import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Servizio per gestire il pairing tra dispositivi tramite RSA public keys
/// Architettura RSA-only: ogni dispositivo condivide solo la propria chiave pubblica
class PairingService extends ChangeNotifier {
  final _storage = const FlutterSecureStorage();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pairingStatusSubscription;

  bool _isPaired = false;
  String? _partnerPublicKey;
  bool _familyWasComplete = false; // Traccia se abbiamo mai visto 2 users

  /// Callback invocato quando il partner fa "Elimina Tutto"
  /// Permette al codice chiamante di pulire la cache locale (messaggi + foto)
  Function(String familyChatId)? onPartnerDeletedAll;

  bool get isPaired => _isPaired;
  String? get partnerPublicKey => _partnerPublicKey;

  /// Inizializza il servizio verificando se esiste già un pairing
  /// Il pairing è considerato valido se esiste partner_public_key
  Future<void> initialize() async {
    if (kDebugMode) print('🔍 [PAIRING] initialize() called');

    final partnerPubKey = await _storage.read(key: 'partner_public_key');

    if (kDebugMode) {
      print('🔍 [PAIRING] partner_public_key from storage: ${partnerPubKey != null ? "${partnerPubKey.substring(0, 20)}..." : "NULL (not paired)"}');
    }

    if (partnerPubKey != null) {
      _partnerPublicKey = partnerPubKey;
      // Ottimistico: se c'è la chiave partner, assume paired
      // Il listener correggerà lo stato se userCount < 2
      _isPaired = true;

      if (kDebugMode) {
        print('✅ [PAIRING] Partner public key trovata nello storage');
        print('   Partner public key: ${partnerPubKey.substring(0, 20)}...');
        print('   _isPaired = true (ottimistico, listener correggerà se necessario)');
      }

      notifyListeners();

      // UNPAIR SYNC: Avvia listener per monitorare cambiamenti
      // Il listener imposterà _isPaired = false se userCount < 2
      _startBackgroundUnpairListener();
    } else {
      if (kDebugMode) {
        print('❌ [PAIRING] No pairing found in storage');
        print('   _isPaired = false');
        print('   Show QR code screen to pair');
      }
    }
  }

  /// Ottiene i dati da codificare nel QR code
  /// Include solo la chiave pubblica RSA (SICURO!)
  Future<String> getMyPublicKeyQRData(String myPublicKey) async {
    final qrData = {
      'public_key': myPublicKey,
      'version': '2.0', // Nuova versione architettura RSA-only
    };

    return json.encode(qrData);
  }

  /// Importa la chiave pubblica del partner da QR code scansionato
  Future<bool> importPartnerPublicKeyFromQR(String qrData) async {
    try {
      if (kDebugMode) {
        print('🔍 DEBUG QR Data:');
        print('   QR Length: ${qrData.length}');
        print('   QR First 100: ${qrData.substring(0, qrData.length > 100 ? 100 : qrData.length)}');
      }

      final data = json.decode(qrData) as Map<String, dynamic>;

      final partnerPublicKey = data['public_key'] as String?;

      if (partnerPublicKey == null) {
        if (kDebugMode) print('Invalid QR data: missing public_key');
        return false;
      }

      if (kDebugMode) {
        print('🔍 DEBUG Partner Public Key from QR:');
        print('   Length: ${partnerPublicKey.length}');
        print('   First 50: ${partnerPublicKey.substring(0, partnerPublicKey.length > 50 ? 50 : partnerPublicKey.length)}');
        print('   Last 50: ${partnerPublicKey.substring(partnerPublicKey.length > 50 ? partnerPublicKey.length - 50 : 0)}');
      }

      // Salva chiave pubblica del partner
      if (kDebugMode) print('💾 [PAIRING] Saving partner_public_key to secure storage...');
      await _storage.write(key: 'partner_public_key', value: partnerPublicKey);

      // Verifica che sia stata salvata correttamente
      final savedKey = await _storage.read(key: 'partner_public_key');
      if (kDebugMode) {
        print('✅ [PAIRING] Verification: key saved = ${savedKey != null}');
        if (savedKey != null) {
          print('   Saved key matches: ${savedKey == partnerPublicKey}');
        }
      }

      // IMPORTANTE: Ferma il vecchio listener prima di cambiare familyChatId
      // Altrimenti rimane un listener attivo sulla vecchia famiglia che può causare unpair
      stopListeningToPairingStatus();
      _familyWasComplete = false; // Reset per il nuovo pairing

      // NON impostare _isPaired = true qui! Verrà impostato dal listener quando userCount >= 2
      _partnerPublicKey = partnerPublicKey;
      notifyListeners();

      if (kDebugMode) {
        print('✅ [PAIRING] Partner public key imported successfully');
        print('   Partner key: ${partnerPublicKey.substring(0, 20)}...');
        print('   _isPaired sarà true quando entrambi avranno completato il pairing');
      }

      // IMPORTANTE: Prima di creare il mio documento, pulisci solo le famiglie COMPLETE dal pairing precedente
      // Se userCount == 1, potrebbe essere il partner che sta facendo pairing contemporaneamente, NON eliminare!
      final myUserId = await getMyUserId();
      final myPublicKey = await _storage.read(key: 'rsa_public_key');
      final familyChatId = await getFamilyChatId();

      if (myUserId != null && familyChatId != null && myPublicKey != null) {
        // Controlla se ci sono documenti vecchi nella famiglia
        final existingDocs = await _firestore
            .collection('families')
            .doc(familyChatId)
            .collection('users')
            .get();

        // Elimina SOLO se userCount >= 2 (famiglia completa dal pairing precedente)
        if (existingDocs.docs.length >= 2) {
          if (kDebugMode) {
            print('⚠️ [PAIRING] Trovata famiglia completa vecchia (${existingDocs.docs.length} documenti)');
            print('   Elimino famiglia vecchia prima di creare nuovo pairing...');
          }

          // Elimina tutti i documenti vecchi
          for (var doc in existingDocs.docs) {
            await _firestore
                .collection('families')
                .doc(familyChatId)
                .collection('users')
                .doc(doc.id)
                .delete();
            if (kDebugMode) print('   🗑️ Eliminato documento vecchio: ${doc.id.substring(0, 10)}...');
          }

          if (kDebugMode) print('   ✅ Famiglia vecchia eliminata, pairing pulito');
        } else if (existingDocs.docs.length == 1) {
          if (kDebugMode) print('   ℹ️ [PAIRING] Trovato 1 documento (probabilmente il partner sta facendo pairing), lo tengo');
        }

        // Ora crea il MIO documento pulito
        await _firestore
            .collection('families')
            .doc(familyChatId)
            .collection('users')
            .doc(myUserId)
            .set({
          'paired_at': FieldValue.serverTimestamp(),
          'my_public_key': myPublicKey,
          'partner_public_key': partnerPublicKey,
        });
        if (kDebugMode) print('✅ [PAIRING] Created my user document in family: $myUserId');

        // Signal that we scanned this partner's QR code
        await signalQRScanned(partnerPublicKey);
      }

      // Avvia il listener per monitorare lo stato della famiglia
      _startBackgroundUnpairListener();

      return true;
    } catch (e) {
      if (kDebugMode) print('Error importing partner public key: $e');
      return false;
    }
  }

  /// Reset del pairing (elimina partner)
  /// Rimuove anche il documento dalla collezione users su Firestore
  /// così l'altro telefono vede il cambiamento e fa auto-unpair
  Future<void> resetPairing() async {
    try {
      // Prima rimuovi il documento users da Firestore se esiste
      final chatId = await getFamilyChatId();
      final myUserId = await getMyUserId();

      if (chatId != null && myUserId != null) {
        if (kDebugMode) print('🗑️ [PAIRING] Removing my user document from Firestore...');

        await _firestore
            .collection('families')
            .doc(chatId)
            .collection('users')
            .doc(myUserId)
            .delete();

        if (kDebugMode) print('✅ [PAIRING] User document removed from Firestore');
      }
    } catch (e) {
      if (kDebugMode) print('⚠️ [PAIRING] Error removing user document: $e');
      // Continua comunque con il reset locale
    }

    // Poi elimina i dati locali
    await _storage.delete(key: 'partner_public_key');

    _isPaired = false;
    _partnerPublicKey = null;
    notifyListeners();

    if (kDebugMode) print('✅ [PAIRING] Pairing reset completed');
  }

  /// Calcola l'ID utente del partner basato sulla sua chiave pubblica
  Future<String?> getPartnerId() async {
    if (_partnerPublicKey == null) return null;

    // userId = SHA-256(publicKey)
    final bytes = utf8.encode(_partnerPublicKey!);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Ottiene l'ID dell'utente corrente basato sulla propria chiave pubblica
  Future<String?> getMyUserId() async {
    final myPublicKey = await _storage.read(key: 'rsa_public_key');
    if (myPublicKey == null) return null;

    // userId = SHA-256(publicKey)
    final bytes = utf8.encode(myPublicKey);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Salva la chiave pubblica dell'utente corrente
  Future<void> saveMyPublicKey(String publicKey) async {
    await _storage.write(key: 'rsa_public_key', value: publicKey);
  }

  /// Alias per resetPairing (per compatibilità)
  Future<void> clearPairing() async {
    await resetPairing();
  }

  /// Calcola l'ID della chat condivisa tra i due utenti
  /// family_chat_id = SHA-256(sorted([myPublicKey, partnerPublicKey]))
  /// Questo garantisce che entrambi gli utenti calcolino lo stesso ID
  Future<String?> getFamilyChatId() async {
    final myPublicKey = await _storage.read(key: 'rsa_public_key');
    final partnerPublicKey = _partnerPublicKey;

    if (myPublicKey == null || partnerPublicKey == null) return null;

    // Sort per garantire stesso ID da entrambe le parti
    final keys = [myPublicKey, partnerPublicKey]..sort();
    final combined = keys.join('|');

    // family_chat_id = SHA-256(combined sorted keys)
    final bytes = utf8.encode(combined);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Avvia manualmente il background listener
  /// Da chiamare DOPO che i token FCM sono stati salvati su Firestore
  void startBackgroundUnpairListener() {
    _startBackgroundUnpairListener();
  }

  /// Ferma il listener del pairing status
  void stopListeningToPairingStatus() {
    _pairingStatusSubscription?.cancel();
    _pairingStatusSubscription = null;
    if (kDebugMode) print('🔇 Stopped listening to pairing status');
  }

  /// Background listener che ascolta SEMPRE unpair del partner
  /// Basato sullo STATO della famiglia (collezione users) invece che su eventi
  void _startBackgroundUnpairListener() async {
    final chatId = await getFamilyChatId();
    if (chatId == null) {
      if (kDebugMode) print('⚠️ No chatId, cannot listen to pairing status');
      return;
    }

    final myUserId = await getMyUserId();
    if (myUserId == null) {
      if (kDebugMode) print('⚠️ No userId, cannot listen to pairing status');
      return;
    }

    if (kDebugMode) print('🎧 Background unpair listener (state-based) started for chat: ${chatId.substring(0, 10)}...');

    // STATE-BASED: Ascolta la collezione /users invece di pairing_status
    _pairingStatusSubscription = _firestore
        .collection('families')
        .doc(chatId)
        .collection('users')
        .snapshots()
        .listen(
      (snapshot) async {
      final userCount = snapshot.docs.length;

      if (kDebugMode) {
        print('👥 [PAIRING] Family users count: $userCount');
        print('   chatId: ${chatId.substring(0, 10)}...');
        print('   myUserId: ${myUserId.substring(0, 10)}...');
        print('   _partnerPublicKey: ${_partnerPublicKey != null ? "YES" : "NULL"}');
        print('   Current _isPaired: $_isPaired');
      }

      // LOGICA ROBUSTA: isPaired = true SOLO se:
      // 1. userCount == 2
      // 2. Entrambi i documenti hanno chiavi valide che si corrispondono
      bool keysAreValid = false;
      bool familyIsCorrupted = false;

      // Verifica le chiavi SOLO se userCount >= 2
      if (userCount >= 2) {
        try {
          final myDocList = snapshot.docs.where((doc) => doc.id == myUserId).toList();

          if (myDocList.isNotEmpty) {
            final myDoc = myDocList.first;
            final myDocData = myDoc.data();
            final myDocPartnerKey = myDocData?['partner_public_key'] as String?;
            final myDocPublicKey = myDocData?['my_public_key'] as String?;

            // Controlla se il partner ha richiesto la cancellazione della cache
            final deleteCacheRequested = myDocData?['delete_cache_requested'] as bool?;
            if (deleteCacheRequested == true) {
              if (kDebugMode) print('🗑️ [PAIRING] Partner requested cache deletion, cleaning up...');

              // Importa i servizi necessari (assumendo che siano disponibili via Provider o altro)
              // Per ora triggeriamo unpair completo che include pulizia cache
              try {
                // Rimuovi il flag
                await _firestore
                    .collection('families')
                    .doc(chatId)
                    .collection('users')
                    .doc(myUserId)
                    .update({'delete_cache_requested': FieldValue.delete()});

                // Triggera pulizia: unpair + cache locale
                await _storage.delete(key: 'partner_public_key');
                _isPaired = false;
                _partnerPublicKey = null;
                _familyWasComplete = false;
                stopListeningToPairingStatus();
                notifyListeners();

                // Invoca il callback per pulire la cache (messaggi + foto)
                if (onPartnerDeletedAll != null) {
                  if (kDebugMode) print('🧹 [PAIRING] Invoking onPartnerDeletedAll callback...');
                  onPartnerDeletedAll!(chatId);
                }

                if (kDebugMode) print('✅ [PAIRING] Cache deletion completed (triggered by partner)');
                return; // Esci dal listener
              } catch (e) {
                if (kDebugMode) print('❌ [PAIRING] Error processing cache deletion: $e');
              }
            }

            // Trova il documento del partner
            final partnerDocs = snapshot.docs.where((doc) => doc.id != myUserId).toList();

            if (partnerDocs.isNotEmpty) {
              final partnerDoc = partnerDocs.first;
              final partnerDocData = partnerDoc.data();
              final partnerDocPartnerKey = partnerDocData?['partner_public_key'] as String?;
              final partnerDocPublicKey = partnerDocData?['my_public_key'] as String?;

              if (kDebugMode) {
                print('   Verifico chiavi incrociate:');
                print('     - Mio doc ha partner_public_key: ${myDocPartnerKey != null ? "YES" : "NO"}');
                print('     - Partner doc ha partner_public_key: ${partnerDocPartnerKey != null ? "YES" : "NO"}');
                print('     - _partnerPublicKey in cache: ${_partnerPublicKey != null ? "YES" : "NO"}');
              }

              // Verifica che le chiavi si corrispondano
              final myKeysMatch = myDocPartnerKey != null &&
                                   myDocPartnerKey == partnerDocPublicKey;

              final partnerKeysMatch = partnerDocPartnerKey != null &&
                                        partnerDocPartnerKey == myDocPublicKey;

              final cacheMatches = _partnerPublicKey != null &&
                                    _partnerPublicKey == partnerDocPublicKey;

              keysAreValid = myKeysMatch && partnerKeysMatch && cacheMatches;

              if (!keysAreValid) {
                familyIsCorrupted = true;
                if (kDebugMode) {
                  print('   ⚠️ FAMIGLIA CORROTTA RILEVATA:');
                  print('     - Mie chiavi corrispondono: $myKeysMatch');
                  print('     - Chiavi partner corrispondono: $partnerKeysMatch');
                  print('     - Cache corrisponde: $cacheMatches');
                }
              }

              if (kDebugMode) print('     - Famiglia valida: $keysAreValid');
            } else {
              if (kDebugMode) print('   ⚠️ Partner document not found (userCount=2 ma solo 1 doc?)');
              familyIsCorrupted = true;
            }
          } else {
            if (kDebugMode) print('   ⚠️ My document not found in family users');
            familyIsCorrupted = true;
          }
        } catch (e) {
          if (kDebugMode) print('   ⚠️ Error checking keys: $e');
          familyIsCorrupted = true;
        }
      } else {
        // userCount < 2: pairing iniziale in corso, non verificare le chiavi
        if (kDebugMode && _partnerPublicKey != null) {
          print('   ⏳ Pairing in corso, chiavi non verificate (aspettando partner...)');
        }
      }

      // Se la famiglia è corrotta, puliscila completamente
      if (familyIsCorrupted && userCount >= 2) {
        if (kDebugMode) print('   🗑️ Pulizia famiglia corrotta in corso...');

        try {
          // Elimina TUTTI i documenti users
          for (var doc in snapshot.docs) {
            await _firestore
                .collection('families')
                .doc(chatId)
                .collection('users')
                .doc(doc.id)
                .delete();
            if (kDebugMode) print('     - Eliminato documento: ${doc.id.substring(0, 10)}...');
          }

          // Elimina la chiave partner locale
          await _storage.delete(key: 'partner_public_key');
          _partnerPublicKey = null;
          _isPaired = false;
          _familyWasComplete = false;
          notifyListeners();

          if (kDebugMode) print('   ✅ Famiglia corrotta pulita, entrambi i telefoni ora unpaired');
        } catch (e) {
          if (kDebugMode) print('   ❌ Errore durante pulizia: $e');
        }

        return; // Esci dal listener
      }

      final shouldBePaired = userCount >= 2 && _partnerPublicKey != null && keysAreValid;

      if (kDebugMode) {
        if (userCount < 2) {
          print('   shouldBePaired: $shouldBePaired (aspettando partner, userCount: $userCount/2)');
        } else {
          print('   shouldBePaired: $shouldBePaired (userCount: 2, has partner key: ${_partnerPublicKey != null}, keys valid: $keysAreValid)');
        }
      }

      if (_isPaired != shouldBePaired) {
        _isPaired = shouldBePaired;
        notifyListeners();
        if (kDebugMode) print('🔄 [PAIRING] isPaired aggiornato da ${!shouldBePaired} a $shouldBePaired → notifyListeners() chiamato');
      } else {
        if (kDebugMode) print('   isPaired già corretto ($_isPaired), nessun cambio');
      }

      // Traccia quando la famiglia diventa completa (2 users)
      if (userCount == 2) {
        if (!_familyWasComplete) {
          _familyWasComplete = true;
          if (kDebugMode) print('✅ Famiglia completa: 2 utenti presenti');
        }
      }

      // Fai unpair completo (rimuovi chiave partner) SOLO se eravamo completi e ora non lo siamo più
      if (userCount < 2 && _partnerPublicKey != null && _familyWasComplete) {
        // Verifica che IO sia ancora presente (potrei essere l'unico rimasto)
        final iAmPresent = snapshot.docs.any((doc) => doc.id == myUserId);

        if (iAmPresent && userCount == 1) {
          // Solo io presente → partner ha fatto unpair
          if (kDebugMode) {
            print('⚠️ [PAIRING] Partner unpaired detected!');
            print('   User count: $userCount (only me)');
            print('   Family was complete: $_familyWasComplete');
            print('   Triggering auto-unpair...');
          }

          // Verifica se il partner ha fatto "Elimina Tutto" controllando i messaggi
          bool partnerDeletedAll = false;
          try {
            final messagesSnapshot = await _firestore
                .collection('families')
                .doc(chatId)
                .collection('messages')
                .limit(1)
                .get();

            partnerDeletedAll = messagesSnapshot.docs.isEmpty;

            if (kDebugMode) {
              if (partnerDeletedAll) {
                print('🗑️ [PAIRING] Partner deleted all messages (Elimina Tutto)');
              } else {
                print('💾 [PAIRING] Messages still exist (Cambio Telefono)');
              }
            }
          } catch (e) {
            if (kDebugMode) print('⚠️ [PAIRING] Error checking messages: $e');
          }

          // Elimina anche il MIO documento users da Firestore
          try {
            await _firestore
                .collection('families')
                .doc(chatId)
                .collection('users')
                .doc(myUserId)
                .delete();
            if (kDebugMode) print('🗑️ [PAIRING] Removed my user document from Firestore');
          } catch (e) {
            if (kDebugMode) print('⚠️ [PAIRING] Error removing my document: $e');
          }

          // Fai unpair locale
          await _storage.delete(key: 'partner_public_key');
          _isPaired = false;
          _partnerPublicKey = null;
          _familyWasComplete = false; // Reset per il prossimo pairing

          // Ferma il listener
          stopListeningToPairingStatus();

          // Notifica i listener (Provider)
          notifyListeners();

          // Se il partner ha fatto "Elimina Tutto", invoca il callback per pulire cache
          if (partnerDeletedAll && onPartnerDeletedAll != null) {
            if (kDebugMode) print('🧹 [PAIRING] Invoking onPartnerDeletedAll callback...');
            onPartnerDeletedAll!(chatId);
          }

          if (kDebugMode) print('✅ [PAIRING] Auto-unpair completed (partner left)');
        } else if (!iAmPresent && userCount == 0) {
          // Nessuno presente → famiglia vuota
          if (kDebugMode) {
            print('⚠️ [PAIRING] Family empty detected!');
            print('   User count: 0');
            print('   Triggering auto-unpair...');
          }

          await _storage.delete(key: 'partner_public_key');
          _isPaired = false;
          _partnerPublicKey = null;
          _familyWasComplete = false; // Reset per il prossimo pairing
          stopListeningToPairingStatus();
          notifyListeners();

          if (kDebugMode) print('✅ [PAIRING] Auto-unpair completed (family empty)');
        }
      } else if (userCount < 2 && !_familyWasComplete && kDebugMode) {
        // Pairing iniziale in corso - aspettiamo il partner
        print('⏳ Pairing in corso, aspettando il partner... ($userCount/2 users)');
      }
    },
    onError: (error) {
      // 🔧 FIX: NON fare unpair in caso di errori di connessione!
      // Gli errori sono normali quando l'app è offline
      if (kDebugMode) {
        print('⚠️ [PAIRING] Listener error (probably offline): $error');
        print('   Keeping paired status unchanged (offline resilience)');
        print('   _isPaired still = $_isPaired');
      }
      // Mantieni _isPaired e _partnerPublicKey invariati
    },
  );
  }

  /// Signals that we scanned someone's QR code
  /// Writes to pairing_signals/{SHA256(partnerPublicKey)}
  Future<void> signalQRScanned(String partnerPublicKey) async {
    final keyHash = sha256.convert(utf8.encode(partnerPublicKey)).toString();
    await _firestore.collection('pairing_signals').doc(keyHash).set({
      'scanned_at': FieldValue.serverTimestamp(),
    });
    if (kDebugMode) print('📡 [PAIRING] Signaled QR scanned for: ${keyHash.substring(0, 10)}...');
  }

  /// Listens for when our QR code gets scanned by the partner
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>> listenForMyQRScanned(
    String myPublicKey,
    void Function() onScanned,
  ) {
    final keyHash = sha256.convert(utf8.encode(myPublicKey)).toString();
    if (kDebugMode) print('👁️ [PAIRING] Listening for QR scan signal on: ${keyHash.substring(0, 10)}...');
    return _firestore.collection('pairing_signals').doc(keyHash).snapshots().listen(
      (snapshot) {
        if (snapshot.exists) {
          if (kDebugMode) print('🔔 [PAIRING] My QR was scanned by partner!');
          onScanned();
        }
      },
    );
  }

  /// Cleans up the pairing signal after pairing is complete
  Future<void> cleanupPairingSignal(String publicKey) async {
    final keyHash = sha256.convert(utf8.encode(publicKey)).toString();
    try {
      await _firestore.collection('pairing_signals').doc(keyHash).delete();
      if (kDebugMode) print('🧹 [PAIRING] Cleaned up pairing signal: ${keyHash.substring(0, 10)}...');
    } catch (e) {
      if (kDebugMode) print('⚠️ [PAIRING] Error cleaning up signal: $e');
    }
  }

  @override
  void dispose() {
    stopListeningToPairingStatus();
    super.dispose();
  }
}
