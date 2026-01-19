import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import '../models/location_share.dart';

/// Servizio per gestire la condivisione della posizione in tempo reale
class LocationService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _storage = const FlutterSecureStorage();

  // Stream subscriptions
  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _partnerLocationSubscription;

  // State
  LocationShare? _myLocation;
  LocationShare? _partnerLocation;
  bool _isSharingLocation = false;
  bool _isTrackingPartner = false;
  DateTime? _sharingExpiresAt;

  // Getters
  LocationShare? get myLocation => _myLocation;
  LocationShare? get partnerLocation => _partnerLocation;
  bool get isSharingLocation => _isSharingLocation;
  bool get isTrackingPartner => _isTrackingPartner;
  DateTime? get sharingExpiresAt => _sharingExpiresAt;

  /// Verifica se la condivisione è scaduta
  bool get isSharingExpired {
    if (_sharingExpiresAt == null) return true;
    return DateTime.now().isAfter(_sharingExpiresAt!);
  }

  /// Calcola distanza in metri tra due posizioni
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  /// Calcola bearing (direzione) in gradi tra due posizioni (0-360)
  /// 0 = Nord, 90 = Est, 180 = Sud, 270 = Ovest
  double calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.bearingBetween(lat1, lon1, lat2, lon2);
  }

  /// Verifica e richiede permessi di localizzazione
  Future<bool> requestLocationPermission() async {
    try {
      if (kDebugMode) print('🔍 [LOCATION] Checking location permissions...');

      // Verifica se i servizi di localizzazione sono abilitati
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (kDebugMode) print('   GPS enabled: $serviceEnabled');

      if (!serviceEnabled) {
        if (kDebugMode) print('❌ [LOCATION] Location services are disabled - user needs to enable GPS');
        return false;
      }

      // Verifica permessi
      LocationPermission permission = await Geolocator.checkPermission();
      if (kDebugMode) print('   Current permission: $permission');

      if (permission == LocationPermission.denied) {
        if (kDebugMode) print('   Requesting permission...');
        permission = await Geolocator.requestPermission();
        if (kDebugMode) print('   Permission result: $permission');

        if (permission == LocationPermission.denied) {
          if (kDebugMode) print('❌ [LOCATION] Location permissions are denied');
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (kDebugMode) print('❌ [LOCATION] Location permissions are permanently denied - user needs to enable in settings');
        return false;
      }

      if (kDebugMode) print('✅ [LOCATION] Location permissions granted: $permission');
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ [LOCATION] Error requesting permission: $e');
      return false;
    }
  }

  /// Ottiene la posizione corrente
  Future<Position?> getCurrentPosition() async {
    try {
      final hasPermission = await requestLocationPermission();
      if (!hasPermission) return null;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (kDebugMode) {
        print('✅ [LOCATION] Current position: ${position.latitude}, ${position.longitude}');
        print('   Accuracy: ${position.accuracy}m');
      }

      return position;
    } catch (e) {
      if (kDebugMode) print('❌ [LOCATION] Error getting position: $e');
      return null;
    }
  }

  /// Inizia a condividere la posizione per una durata specificata
  /// duration: Duration.hours(1) o Duration.hours(8)
  Future<bool> startSharingLocation(Duration duration) async {
    try {
      if (kDebugMode) print('🌍 [LOCATION] Attempting to start location sharing...');

      final hasPermission = await requestLocationPermission();
      if (!hasPermission) {
        if (kDebugMode) print('❌ [LOCATION] Cannot start sharing: no permission');
        return false;
      }

      if (kDebugMode) print('✅ [LOCATION] Permissions OK, checking pairing...');

      // Ottieni deviceId e familyChatId
      final myUserId = await _getMyUserId();
      final familyChatId = await _getFamilyChatId();

      if (kDebugMode) {
        print('   myUserId: ${myUserId != null ? "✅ ${myUserId.substring(0, 8)}..." : "❌ NULL"}');
        print('   familyChatId: ${familyChatId != null ? "✅ ${familyChatId.substring(0, 8)}..." : "❌ NULL"}');
      }

      if (myUserId == null || familyChatId == null) {
        if (kDebugMode) {
          print('❌ [LOCATION] Cannot start sharing: not paired or missing data');
          print('   myUserId is null: ${myUserId == null}');
          print('   familyChatId is null: ${familyChatId == null}');
        }
        return false;
      }

      // Imposta scadenza
      _sharingExpiresAt = DateTime.now().add(duration);
      _isSharingLocation = true;

      if (kDebugMode) {
        print('🌍 [LOCATION] Starting location sharing for ${duration.inHours}h');
        print('   Expires at: $_sharingExpiresAt');
      }

      // Avvia stream di posizione
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // Aggiorna ogni 10 metri
        ),
      ).listen((Position position) {
        _updateMyLocationToFirestore(position, myUserId, familyChatId);
      });

      // Ottieni e salva posizione iniziale immediatamente
      final initialPosition = await getCurrentPosition();
      if (initialPosition != null) {
        await _updateMyLocationToFirestore(initialPosition, myUserId, familyChatId);
      }

      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ [LOCATION] Error starting location sharing: $e');
      _isSharingLocation = false;
      notifyListeners();
      return false;
    }
  }

  /// Ferma la condivisione della posizione
  Future<void> stopSharingLocation() async {
    try {
      if (kDebugMode) print('🛑 [LOCATION] Stopping location sharing');

      // Ferma lo stream
      await _positionStreamSubscription?.cancel();
      _positionStreamSubscription = null;

      // Aggiorna Firestore: imposta is_active = false
      final myUserId = await _getMyUserId();
      final familyChatId = await _getFamilyChatId();

      if (myUserId != null && familyChatId != null) {
        await _firestore
            .collection('families')
            .doc(familyChatId)
            .collection('locations')
            .doc(myUserId)
            .update({'is_active': false});
      }

      _isSharingLocation = false;
      _sharingExpiresAt = null;
      _myLocation = null;

      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('❌ [LOCATION] Error stopping location sharing: $e');
    }
  }

  /// Inizia a monitorare la posizione del partner
  Future<void> startTrackingPartner() async {
    try {
      final familyChatId = await _getFamilyChatId();
      final myUserId = await _getMyUserId();

      if (familyChatId == null || myUserId == null) {
        if (kDebugMode) print('❌ [LOCATION] Cannot track partner: not paired');
        return;
      }

      // Cancella subscription esistente se presente
      if (_partnerLocationSubscription != null) {
        if (kDebugMode) print('👀 [LOCATION] Canceling existing partner tracking subscription');
        await _partnerLocationSubscription?.cancel();
        _partnerLocationSubscription = null;
      }

      if (kDebugMode) print('👀 [LOCATION] Starting to track partner location');

      _isTrackingPartner = true;

      // Ascolta la collection locations per il partner
      _partnerLocationSubscription = _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('locations')
          .snapshots()
          .listen((querySnapshot) {
        if (querySnapshot.docs.isEmpty) {
          if (kDebugMode) print('👀 [LOCATION] No partner location found');
          _partnerLocation = null;
          notifyListeners();
          return;
        }

        // Trova il documento del partner (non il mio)
        final partnerDoc = querySnapshot.docs.firstWhere(
          (doc) => doc.id != myUserId,
          orElse: () => querySnapshot.docs.first, // fallback
        );

        if (partnerDoc.id == myUserId) {
          // Non c'è il partner, solo io
          if (kDebugMode) print('👀 [LOCATION] Only my location found, no partner');
          _partnerLocation = null;
          notifyListeners();
          return;
        }

        final locationShare = LocationShare.fromFirestore(partnerDoc.id, partnerDoc.data());

        // Verifica se è scaduta
        if (locationShare.isExpired || !locationShare.isActive) {
          if (kDebugMode) print('👀 [LOCATION] Partner location expired or inactive');
          _partnerLocation = null;
        } else {
          if (kDebugMode) {
            print('👀 [LOCATION] Partner location updated:');
            print('   Position: ${locationShare.latitude}, ${locationShare.longitude}');
            print('   Timestamp: ${locationShare.timestamp}');
            print('   Expires: ${locationShare.expiresAt}');
          }
          _partnerLocation = locationShare;
        }

        notifyListeners();
      });

      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('❌ [LOCATION] Error tracking partner: $e');
    }
  }

  /// Ferma il monitoraggio della posizione del partner
  Future<void> stopTrackingPartner() async {
    try {
      if (kDebugMode) print('🛑 [LOCATION] Stopping partner tracking');

      await _partnerLocationSubscription?.cancel();
      _partnerLocationSubscription = null;

      _isTrackingPartner = false;
      _partnerLocation = null;

      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('❌ [LOCATION] Error stopping partner tracking: $e');
    }
  }

  /// Aggiorna la mia posizione su Firestore
  Future<void> _updateMyLocationToFirestore(
    Position position,
    String myUserId,
    String familyChatId,
  ) async {
    try {
      // Verifica se è scaduta
      if (isSharingExpired) {
        if (kDebugMode) print('⏰ [LOCATION] Sharing expired, stopping');
        await stopSharingLocation();
        return;
      }

      final locationShare = LocationShare(
        id: myUserId,
        userId: myUserId,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        timestamp: DateTime.now(),
        expiresAt: _sharingExpiresAt!,
        speed: position.speed,
        heading: position.heading,
        isActive: true,
      );

      await _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('locations')
          .doc(myUserId)
          .set(locationShare.toJson(), SetOptions(merge: true));

      _myLocation = locationShare;

      if (kDebugMode) {
        print('📍 [LOCATION] Updated my location to Firestore');
        print('   Position: ${position.latitude}, ${position.longitude}');
        print('   Speed: ${position.speed} m/s, Heading: ${position.heading}°');
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('❌ [LOCATION] Error updating location to Firestore: $e');
    }
  }

  /// Helper: ottiene il deviceId corrente
  Future<String?> _getMyUserId() async {
    try {
      // userId = SHA-256(rsa_public_key) - stesso algoritmo di PairingService
      final myPublicKey = await _storage.read(key: 'rsa_public_key');
      if (myPublicKey == null) {
        if (kDebugMode) print('❌ [LOCATION] rsa_public_key not found in storage');
        return null;
      }

      final bytes = utf8.encode(myPublicKey);
      final digest = sha256.convert(bytes);
      final userId = digest.toString();

      if (kDebugMode) print('   Calculated userId: ${userId.substring(0, 8)}...');
      return userId;
    } catch (e) {
      if (kDebugMode) print('❌ [LOCATION] Error getting userId: $e');
      return null;
    }
  }

  /// Helper: ottiene il familyChatId corrente
  Future<String?> _getFamilyChatId() async {
    try {
      final myPublicKey = await _storage.read(key: 'rsa_public_key');
      final partnerPublicKey = await _storage.read(key: 'partner_public_key');

      if (kDebugMode) {
        print('   myPublicKey found: ${myPublicKey != null}');
        print('   partnerPublicKey found: ${partnerPublicKey != null}');
      }

      if (myPublicKey == null || partnerPublicKey == null) {
        if (kDebugMode) print('❌ [LOCATION] Missing public keys in storage');
        return null;
      }

      // Calcola familyChatId (stesso algoritmo di pairing_service)
      final keys = [myPublicKey, partnerPublicKey]..sort();
      final concatenated = keys.join('|');
      final bytes = utf8.encode(concatenated);
      final hash = sha256.convert(bytes);
      final familyChatId = hash.toString();

      if (kDebugMode) print('   Calculated familyChatId: ${familyChatId.substring(0, 8)}...');
      return familyChatId;
    } catch (e) {
      if (kDebugMode) print('❌ [LOCATION] Error calculating familyChatId: $e');
      return null;
    }
  }

  /// Pulisce tutte le risorse
  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _partnerLocationSubscription?.cancel();
    super.dispose();
  }
}
