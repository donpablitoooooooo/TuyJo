import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import '../models/location_share.dart';

/// Servizio per gestire la condivisione della posizione in tempo reale
class LocationService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _storage = const FlutterSecureStorage();

  // Stream subscriptions
  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _partnerLocationSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _myLocationSubscription; // Listener per rilevare stop esterno

  // State
  LocationShare? _myLocation;
  LocationShare? _partnerLocation;
  bool _isSharingLocation = false;
  bool _isTrackingPartner = false;
  DateTime? _sharingExpiresAt;
  String? _currentSessionId; // Session ID univoco per ogni condivisione
  String? _locationShareMessageId; // ID del messaggio di location share

  // Getters
  LocationShare? get myLocation => _myLocation;
  LocationShare? get partnerLocation => _partnerLocation;
  String? get currentSessionId => _currentSessionId;
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

      // Genera nuovo session ID univoco per questa condivisione
      _currentSessionId = const Uuid().v4();

      if (kDebugMode) {
        print('🌍 [LOCATION] Starting location sharing for ${duration.inHours}h');
        print('   Session ID: $_currentSessionId');
        print('   Expires at: ${DateTime.now().add(duration)}');
      }

      // IMPORTANTE: Chiudi vecchie sessioni PRIMA di iniziare nuova
      await _closeOldSessions(myUserId, familyChatId);

      // Imposta scadenza
      _sharingExpiresAt = DateTime.now().add(duration);
      _isSharingLocation = true;

      // IMPORTANTE: Ottieni posizione iniziale PRIMA di avviare lo stream
      // Se non riesci ad ottenere GPS, non permettere la condivisione
      if (kDebugMode) print('📍 [LOCATION] Verifico disponibilità GPS...');
      final initialPosition = await getCurrentPosition();

      if (initialPosition == null) {
        if (kDebugMode) print('❌ [LOCATION] GPS non disponibile - impossibile condividere');
        _isSharingLocation = false;
        _currentSessionId = null;
        return false;
      }

      if (kDebugMode) print('✅ [LOCATION] GPS disponibile, avvio condivisione');

      // Salva posizione iniziale
      await _updateMyLocationToFirestore(initialPosition, myUserId, familyChatId);

      // Avvia stream di posizione per aggiornamenti continui
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // Aggiorna ogni 10 metri
        ),
      ).listen((Position position) {
        _updateMyLocationToFirestore(position, myUserId, familyChatId);
      });

      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ [LOCATION] Error starting location sharing: $e');
      _isSharingLocation = false;
      notifyListeners();
      return false;
    }
  }

  /// Imposta l'ID del messaggio di location share
  void setLocationShareMessageId(String messageId) {
    _locationShareMessageId = messageId;
    if (kDebugMode) print('📝 [LOCATION] Message ID set: $messageId');
  }

  /// Ottiene l'ID del messaggio di location share corrente
  String? getLocationShareMessageId() {
    return _locationShareMessageId;
  }

  /// Ferma la condivisione della posizione
  Future<void> stopSharingLocation() async {
    try {
      if (kDebugMode) print('🛑 [LOCATION] Stopping location sharing');

      // Ferma lo stream posizione
      await _positionStreamSubscription?.cancel();
      _positionStreamSubscription = null;

      // Aggiorna Firestore: imposta is_active = false SOLO per ME
      // L'altro utente rileverà tramite listener e fermerà la sua condivisione
      final myUserId = await _getMyUserId();
      final familyChatId = await _getFamilyChatId();

      if (myUserId != null && familyChatId != null) {
        // Marca il MIO documento come inattivo
        await _firestore
            .collection('families')
            .doc(familyChatId)
            .collection('locations')
            .doc(myUserId)
            .update({'is_active': false});

        if (kDebugMode) print('🛑 [LOCATION] Marked my location as inactive');
      }

      _isSharingLocation = false;
      _sharingExpiresAt = null;
      _myLocation = null;
      _currentSessionId = null; // Reset session ID
      _locationShareMessageId = null; // Reset message ID

      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('❌ [LOCATION] Error stopping location sharing: $e');
    }
  }

  /// Inizia a monitorare la posizione del partner
  Future<void> startTrackingPartner() async {
    if (kDebugMode) print('🎯 [LOCATION] startTrackingPartner() CALLED');
    try {
      final familyChatId = await _getFamilyChatId();
      final myUserId = await _getMyUserId();

      if (kDebugMode) {
        print('   familyChatId: ${familyChatId != null ? "✅ ${familyChatId.substring(0, 8)}..." : "❌ NULL"}');
        print('   myUserId: ${myUserId != null ? "✅ ${myUserId.substring(0, 8)}..." : "❌ NULL"}');
      }

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
          .listen((querySnapshot) async {
        if (kDebugMode) {
          print('👀 [LOCATION] Locations snapshot received:');
          print('   Total docs: ${querySnapshot.docs.length}');
          print('   My userId: $myUserId');
          for (var doc in querySnapshot.docs) {
            print('   - Doc ID: ${doc.id} ${doc.id == myUserId ? "(ME)" : "(PARTNER)"}');
          }
        }

        if (querySnapshot.docs.isEmpty) {
          if (kDebugMode) print('❌ [LOCATION] No locations found in collection');
          _partnerLocation = null;
          notifyListeners();
          return;
        }

        // Trova il documento del partner (non il mio)
        QueryDocumentSnapshot<Map<String, dynamic>>? partnerDoc;
        for (var doc in querySnapshot.docs) {
          if (doc.id != myUserId) {
            partnerDoc = doc;
            break;
          }
        }

        if (partnerDoc == null) {
          // Non c'è il partner, solo io
          if (kDebugMode) print('⚠️ [LOCATION] Only my location found, no partner yet');
          _partnerLocation = null;
          notifyListeners();
          return;
        }

        final locationShare = LocationShare.fromFirestore(partnerDoc.id, partnerDoc.data());

        // Verifica se è scaduta o inattiva
        if (locationShare.isExpired || !locationShare.isActive) {
          if (kDebugMode) {
            print('👀 [LOCATION] Partner location expired or inactive');
            print('   _partnerLocation != null: ${_partnerLocation != null}');
            print('   _partnerLocation?.isActive: ${_partnerLocation?.isActive}');
            print('   _isSharingLocation: $_isSharingLocation');
          }

          // Partner ha fermato: se IO sto condividendo, marco anche me come inattivo
          // Ma SOLO se partner ERA attivo prima (evita di fermare all'inizio)
          if (_partnerLocation != null && _partnerLocation!.isActive && _isSharingLocation) {
            if (kDebugMode) print('🛑 [LOCATION] Partner stopped, stopping MY sharing completely');

            // Ferma il position stream (altrimenti continua a scrivere su Firestore!)
            await _positionStreamSubscription?.cancel();
            _positionStreamSubscription = null;

            // Usa myUserId e familyChatId dal contesto esterno (già disponibili)
            try {
              await _firestore
                  .collection('families')
                  .doc(familyChatId)
                  .collection('locations')
                  .doc(myUserId)
                  .update({'is_active': false});

              if (kDebugMode) print('✅ [LOCATION] Marked myself as inactive (partner stopped)');
            } catch (e) {
              if (kDebugMode) print('❌ [LOCATION] Error marking as inactive: $e');
            }

            // Reset stato locale
            _isSharingLocation = false;
            _sharingExpiresAt = null;
            _myLocation = null;
            _currentSessionId = null;
            _locationShareMessageId = null;
          }

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
      }, onError: (error) {
        if (kDebugMode) {
          print('❌ [LOCATION] Firestore listener ERROR:');
          print('   Error: $error');
          print('   This likely means Firestore rules are not deployed yet!');
        }
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

      // ⚠️ TEST: Aggiungi offset di 1km alla latitudine per testare navigazione
      final testLatOffset = 0.009; // circa 1km

      final locationShare = LocationShare(
        id: myUserId,
        userId: myUserId,
        sessionId: _currentSessionId!, // ID univoco sessione
        latitude: position.latitude + testLatOffset, // OFFSET TEST
        longitude: position.longitude,
        accuracy: position.accuracy,
        timestamp: DateTime.now(),
        expiresAt: _sharingExpiresAt!,
        speed: position.speed,
        heading: position.heading,
        isActive: true,
      );

      if (kDebugMode) {
        print('📤 [LOCATION] Writing to Firestore:');
        print('   Path: families/$familyChatId/locations/$myUserId');
        print('   Position REALE: ${position.latitude}, ${position.longitude}');
        print('   Position TEST (+1km): ${position.latitude + testLatOffset}, ${position.longitude}');
      }

      await _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('locations')
          .doc(myUserId)
          .set(locationShare.toJson(), SetOptions(merge: true));

      _myLocation = locationShare;

      if (kDebugMode) {
        print('✅ [LOCATION] Successfully wrote location to Firestore');
        print('   Speed: ${position.speed} m/s, Heading: ${position.heading}°');
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('❌ [LOCATION] Error updating location to Firestore: $e');
    }
  }

  /// Chiude tutte le vecchie sessioni di condivisione (marca come inactive)
  Future<void> _closeOldSessions(String myUserId, String familyChatId) async {
    try {
      if (kDebugMode) print('🔒 [LOCATION] Closing old location sharing sessions...');

      // Ottieni tutti i documenti location dell'utente
      final snapshot = await _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('locations')
          .doc(myUserId)
          .get();

      if (snapshot.exists) {
        // Marca come inactive
        await _firestore
            .collection('families')
            .doc(familyChatId)
            .collection('locations')
            .doc(myUserId)
            .update({'is_active': false});

        if (kDebugMode) print('✅ [LOCATION] Old sessions closed');
      }
    } catch (e) {
      if (kDebugMode) print('❌ [LOCATION] Error closing old sessions: $e');
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
