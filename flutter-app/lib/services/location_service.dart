import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import '../models/location_share.dart';
import 'encryption_service.dart';

/// Servizio per gestire la condivisione della posizione in tempo reale
class LocationService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _storage = const FlutterSecureStorage();
  final EncryptionService _encryptionService;

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
  String? _locationKey; // Chiave AES-256 per cifrare/decifrare coordinate GPS

  // Getters
  LocationShare? get myLocation => _myLocation;
  LocationShare? get partnerLocation => _partnerLocation;
  String? get currentSessionId => _currentSessionId;
  String? get locationKey => _locationKey; // Espone la chiave per il recipient
  bool get isSharingLocation => _isSharingLocation;
  bool get isTrackingPartner => _isTrackingPartner;
  DateTime? get sharingExpiresAt => _sharingExpiresAt;

  LocationService(this._encryptionService);

  // Chiavi SharedPreferences per persistenza stato condivisione
  static const String _prefSessionId = 'location_sharing_session_id';
  static const String _prefExpiresAt = 'location_sharing_expires_at';
  static const String _prefActive = 'location_sharing_active';
  static const String _prefLocationKey = 'location_sharing_key';

  /// Pre-imposta sessione e stato attivo prima di mandare il messaggio Firestore,
  /// così la UI mostra subito la condivisione come attiva.
  void prepareSession(String sessionId, Duration duration) {
    _currentSessionId = sessionId;
    _isSharingLocation = true;
    _sharingExpiresAt = DateTime.now().add(duration);
    _persistSharingState();
    notifyListeners();
  }

  /// Imposta la chiave AES per cifrare/decifrare le coordinate GPS.
  /// Chiamato dal sender dopo sendLocationShare() e dal receiver dopo aver decodificato il messaggio.
  void setLocationKey(String key) {
    _locationKey = key;
    _persistSharingState();
    if (kDebugMode) print('🔐 [LOCATION] Location encryption key set');
  }

  /// Imposta la posizione iniziale del partner dalle coordinate nel messaggio E2E.
  /// Usato quando B apre la schermata: ha subito le coordinate di A senza aspettare Firestore.
  /// Verrà sovrascritto dagli aggiornamenti real-time di Firestore quando arrivano.
  void setInitialPartnerLocation(double latitude, double longitude, String sessionId) {
    if (_partnerLocation != null) return; // Firestore ha già dati, non sovrascrivere
    _partnerLocation = LocationShare(
      id: 'initial',
      userId: '',
      sessionId: sessionId,
      latitude: latitude,
      longitude: longitude,
      accuracy: 0,
      timestamp: DateTime.now(),
      expiresAt: DateTime.now().add(Duration(hours: 8)),
      isActive: true,
    );
    notifyListeners();
    if (kDebugMode) print('📍 [LOCATION] Initial partner location set from E2E message: $latitude, $longitude');
  }

  /// Salva stato condivisione su SharedPreferences (sopravvive a restart app)
  Future<void> _persistSharingState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_isSharingLocation && _currentSessionId != null && _sharingExpiresAt != null) {
        await prefs.setString(_prefSessionId, _currentSessionId!);
        await prefs.setString(_prefExpiresAt, _sharingExpiresAt!.toIso8601String());
        await prefs.setBool(_prefActive, true);
        // Salva location key in Secure Storage (non SharedPreferences!)
        if (_locationKey != null) {
          await _storage.write(key: _prefLocationKey, value: _locationKey!);
        }
      } else {
        await _clearPersistedSharingState();
      }
    } catch (e) {
      if (kDebugMode) print('❌ [LOCATION] Error persisting sharing state: $e');
    }
  }

  /// Cancella stato condivisione persistito
  Future<void> _clearPersistedSharingState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefSessionId);
      await prefs.remove(_prefExpiresAt);
      await prefs.remove(_prefActive);
      await _storage.delete(key: _prefLocationKey);
    } catch (e) {
      if (kDebugMode) print('❌ [LOCATION] Error clearing persisted state: $e');
    }
  }

  /// Ripristina stato condivisione da SharedPreferences (chiamato all'avvio app).
  /// Se la sessione non è scaduta, ripristina stato e riavvia GPS.
  Future<void> restoreSessionIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final active = prefs.getBool(_prefActive) ?? false;
      if (!active) return;

      final sessionId = prefs.getString(_prefSessionId);
      final expiresAtStr = prefs.getString(_prefExpiresAt);
      if (sessionId == null || expiresAtStr == null) return;

      final expiresAt = DateTime.parse(expiresAtStr);
      if (DateTime.now().isAfter(expiresAt)) {
        // Scaduta → pulisci
        if (kDebugMode) print('⏰ [LOCATION] Persisted session expired, clearing');
        await _clearPersistedSharingState();
        return;
      }

      // Ripristina stato in memoria
      _currentSessionId = sessionId;
      _isSharingLocation = true;
      _sharingExpiresAt = expiresAt;

      // Ripristina location key da Secure Storage
      _locationKey = await _storage.read(key: _prefLocationKey);

      if (kDebugMode) {
        print('🔄 [LOCATION] Restored sharing session: $sessionId');
        print('   Expires at: $expiresAt');
        print('   Location key restored: ${_locationKey != null}');
      }

      notifyListeners();

      // Riavvia GPS stream
      final remaining = expiresAt.difference(DateTime.now());
      if (remaining.inSeconds > 0) {
        startSharingLocation(remaining, sessionId: sessionId);
      }
    } catch (e) {
      if (kDebugMode) print('❌ [LOCATION] Error restoring session: $e');
    }
  }

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
  Future<bool> startSharingLocation(Duration duration, {String? sessionId}) async {
    // Se sessionId è fornito, prepareSession() è già stato chiamato e il messaggio
    // è già su Firestore. Non resettare lo stato se qualcosa fallisce.
    final hasPreparedSession = sessionId != null;

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

      if (myUserId == null || familyChatId == null) {
        if (kDebugMode) print('❌ [LOCATION] Cannot start sharing: not paired or missing data');
        return false;
      }

      // Usa session ID esterno se fornito, altrimenti genera nuovo
      _currentSessionId = sessionId ?? const Uuid().v4();

      if (kDebugMode) {
        print('🌍 [LOCATION] Starting location sharing for ${duration.inHours}h');
        print('   Session ID: $_currentSessionId');
      }

      // IMPORTANTE: Chiudi vecchie sessioni PRIMA di iniziare nuova
      await _closeOldSessions(myUserId, familyChatId);

      // Imposta scadenza
      _sharingExpiresAt = DateTime.now().add(duration);
      _isSharingLocation = true;

      // Ottieni posizione iniziale
      if (kDebugMode) print('📍 [LOCATION] Verifico disponibilità GPS...');
      final initialPosition = await getCurrentPosition();

      if (initialPosition == null) {
        if (kDebugMode) print('⚠️ [LOCATION] GPS non disponibile al momento');
        if (!hasPreparedSession) {
          // Nessun messaggio ancora → resetta stato
          _isSharingLocation = false;
          _currentSessionId = null;
        } else {
          // Messaggio già inviato → tieni lo stato attivo, il GPS stream proverà dopo
          if (kDebugMode) print('   Messaggio già su Firestore, mantengo stato attivo');
        }
        // Avvia comunque lo stream: quando il GPS diventa disponibile, aggiornerà
        _positionStreamSubscription = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen((Position position) {
          _updateMyLocationToFirestore(position, myUserId, familyChatId);
        });
        notifyListeners();
        return hasPreparedSession; // true se il messaggio esiste già
      }

      if (kDebugMode) print('✅ [LOCATION] GPS disponibile, avvio condivisione');

      // Salva posizione iniziale
      await _updateMyLocationToFirestore(initialPosition, myUserId, familyChatId);

      // Avvia stream di posizione per aggiornamenti continui
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((Position position) {
        _updateMyLocationToFirestore(position, myUserId, familyChatId);
      });

      _persistSharingState();
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ [LOCATION] Error starting location sharing: $e');
      if (!hasPreparedSession) {
        _isSharingLocation = false;
        _currentSessionId = null;
        _clearPersistedSharingState();
      }
      notifyListeners();
      return hasPreparedSession;
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
      _currentSessionId = null;
      _locationShareMessageId = null;
      _locationKey = null;
      await _clearPersistedSharingState();

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

        // Decifra le coordinate se i dati sono cifrati
        final partnerData = partnerDoc.data();
        final LocationShare locationShare;
        if (partnerData.containsKey('encrypted_location') && _locationKey != null) {
          locationShare = LocationShare.fromEncryptedFirestore(
            partnerDoc.id,
            partnerData,
            _locationKey!,
            _encryptionService,
          );
          if (kDebugMode) print('🔐 [LOCATION] Decrypted partner coordinates');
        } else {
          // Fallback: dati non cifrati (compatibilità con vecchie sessioni)
          locationShare = LocationShare.fromFirestore(partnerDoc.id, partnerData);
          if (kDebugMode && partnerData.containsKey('encrypted_location')) {
            print('⚠️ [LOCATION] Encrypted data found but no location key available');
          }
        }

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
            _locationKey = null;
            _clearPersistedSharingState();
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

  /// Aggiorna la mia posizione su Firestore (coordinate cifrate con AES-256)
  Future<void> _updateMyLocationToFirestore(
    Position position,
    String myUserId,
    String familyChatId,
  ) async {
    try {
      // IMPORTANTE: verifica se sto ancora condividendo (evita race condition)
      if (!_isSharingLocation) {
        if (kDebugMode) print('🛑 [LOCATION] Not sharing anymore, skipping Firestore write');
        return;
      }

      // Verifica se è scaduta
      if (isSharingExpired) {
        if (kDebugMode) print('⏰ [LOCATION] Sharing expired, stopping');
        await stopSharingLocation();
        return;
      }

      final locationShare = LocationShare(
        id: myUserId,
        userId: myUserId,
        sessionId: _currentSessionId!, // ID univoco sessione
        latitude: position.latitude,
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
        print('   Position: ${position.latitude}, ${position.longitude}');
      }

      // Cifra le coordinate sensibili se la chiave è disponibile
      final Map<String, dynamic> firestoreData;
      if (_locationKey != null) {
        final sensitiveFields = {
          'lat': position.latitude,
          'lng': position.longitude,
          'acc': position.accuracy,
          if (position.speed >= 0) 'spd': position.speed,
          if (position.heading >= 0) 'hdg': position.heading,
        };

        final encrypted = _encryptionService.encryptLocationData(sensitiveFields, _locationKey!);

        firestoreData = {
          'user_id': myUserId,
          'session_id': _currentSessionId!,
          'encrypted_location': encrypted['data'],
          'location_iv': encrypted['iv'],
          'timestamp': Timestamp.fromDate(DateTime.now()),
          'expires_at': Timestamp.fromDate(_sharingExpiresAt!),
          'is_active': true,
        };

        if (kDebugMode) print('🔐 [LOCATION] Coordinates encrypted before Firestore write');
      } else {
        // Fallback senza cifratura (non dovrebbe succedere, ma safe)
        firestoreData = locationShare.toJson();
        if (kDebugMode) print('⚠️ [LOCATION] No location key - writing unencrypted (fallback)');
      }

      // set() SENZA merge: sovrascrive il documento intero,
      // così non restano campi in chiaro (lat/lng/accuracy) da sessioni precedenti
      await _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('locations')
          .doc(myUserId)
          .set(firestoreData);

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
