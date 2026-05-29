import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import '../models/message.dart';
import '../services/chat_service.dart';
import '../services/encryption_service.dart';
import '../services/location_service.dart';
import '../services/pairing_service.dart';

/// Schermata minimal per navigazione verso il partner
class LocationSharingScreen extends StatefulWidget {
  final String expectedSessionId; // Session ID dal messaggio
  final bool isSender; // true se l'utente corrente è il mittente del messaggio
  final String mode; // 'live' o 'static'
  final double? initialLatitude; // Coordinate iniziali del sender (dal messaggio E2E)
  final double? initialLongitude;

  const LocationSharingScreen({
    Key? key,
    required this.expectedSessionId,
    this.isSender = false,
    this.mode = 'live',
    this.initialLatitude,
    this.initialLongitude,
  }) : super(key: key);

  @override
  State<LocationSharingScreen> createState() => _LocationSharingScreenState();
}

class _LocationSharingScreenState extends State<LocationSharingScreen> {
  double? _heading; // Direzione corrente dalla bussola (0-360°)
  StreamSubscription<CompassEvent>? _compassSubscription;
  Timer? _compassRetryTimer;
  Timer? _positionUpdateTimer; // Timer per aggiornare la posizione
  int _compassRetryCount = 0;
  Position? _myPosition; // Posizione corrente dell'utente (locale, non condivisa)

  @override
  void initState() {
    super.initState();
    _startCompass();

    // Avvia tracking del partner e ottieni la mia posizione
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final locationService = Provider.of<LocationService>(context, listen: false);

      // Se abbiamo coordinate iniziali dal messaggio E2E, usale subito
      // così B può navigare senza aspettare che A sia online
      if (widget.initialLatitude != null && widget.initialLongitude != null) {
        locationService.setInitialPartnerLocation(
          widget.initialLatitude!,
          widget.initialLongitude!,
          widget.expectedSessionId,
        );
      }

      locationService.startTrackingPartner();

      // Ottieni la mia posizione corrente subito
      _updateMyPosition();

      // Aggiorna posizione ogni 5 secondi
      _positionUpdateTimer = Timer.periodic(Duration(seconds: 5), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        _updateMyPosition();
      });
    });
  }

  Future<void> _updateMyPosition() async {
    final locationService = Provider.of<LocationService>(context, listen: false);
    final position = await locationService.getCurrentPosition();
    if (mounted && position != null) {
      setState(() {
        _myPosition = position;
      });

      // Se sono il destinatario (non mittente), condividi la mia posizione
      // così il mittente può vedere la distanza
      // MA solo se la condivisione è ancora attiva (partner non ha fermato)
      if (!widget.isSender) {
        final partnerLocation = locationService.partnerLocation;
        final isPartnerActive = partnerLocation != null &&
            partnerLocation.isActive &&
            partnerLocation.sessionId == widget.expectedSessionId;

        if (isPartnerActive) {
          await _shareMyPositionWithPartner(position);
        } else {
          // Partner ha fermato o sessione terminata - ferma la condivisione
          if (kDebugMode) print('🛑 [RECIPIENT] Partner stopped, stopping my position share');
          await _stopSharingMyPosition();
          _positionUpdateTimer?.cancel(); // Ferma il timer
        }
      }
    }
  }

  /// Condivide la posizione del destinatario con il mittente (solo per destinatario)
  /// Le coordinate vengono cifrate con la stessa chiave AES della sessione
  Future<void> _shareMyPositionWithPartner(Position position) async {
    try {
      final pairingService = Provider.of<PairingService>(context, listen: false);
      final encryptionService = Provider.of<EncryptionService>(context, listen: false);
      final locationService = Provider.of<LocationService>(context, listen: false);

      final familyChatId = await pairingService.getFamilyChatId();
      final myPublicKey = await encryptionService.getPublicKey();

      if (familyChatId == null || myPublicKey == null) {
        if (kDebugMode) print('❌ [RECIPIENT] Cannot share position: familyChatId or publicKey null');
        return;
      }

      // Calcola userId da public key
      final myUserId = sha256.convert(utf8.encode(myPublicKey)).toString();

      final now = DateTime.now();

      if (kDebugMode) {
        print('📍 [RECIPIENT] Sharing my position with partner:');
        print('   Position: ${position.latitude}, ${position.longitude}');
        print('   FamilyChatId: ${familyChatId.substring(0, 8)}...');
        print('   MyUserId: ${myUserId.substring(0, 8)}...');
        print('   SessionId: ${widget.expectedSessionId}');
      }

      // Cifra le coordinate sensibili se la chiave è disponibile
      final locationKey = locationService.locationKey;
      final Map<String, dynamic> firestoreData;

      if (locationKey != null) {
        final sensitiveFields = {
          'lat': position.latitude,
          'lng': position.longitude,
          'acc': position.accuracy,
          if (position.speed >= 0) 'spd': position.speed,
          if (position.heading >= 0) 'hdg': position.heading,
        };

        final encrypted = encryptionService.encryptLocationData(sensitiveFields, locationKey);

        firestoreData = {
          'encrypted_location': encrypted['data'],
          'location_iv': encrypted['iv'],
          'timestamp': Timestamp.fromDate(now),
          'expires_at': now.add(Duration(minutes: 5)).toIso8601String(),
          'session_id': widget.expectedSessionId,
          'is_active': true,
          'user_id': myUserId,
        };

        if (kDebugMode) print('🔐 [RECIPIENT] Coordinates encrypted before Firestore write');
      } else {
        // Fallback senza cifratura (compatibilità)
        firestoreData = {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
          'timestamp': Timestamp.fromDate(now),
          'expires_at': now.add(Duration(minutes: 5)).toIso8601String(),
          'session_id': widget.expectedSessionId,
          'is_active': true,
          'speed': position.speed,
          'heading': position.heading,
          'user_id': myUserId,
        };
        if (kDebugMode) print('⚠️ [RECIPIENT] No location key - writing unencrypted (fallback)');
      }

      // set() SENZA merge: sovrascrive il documento intero,
      // così non restano campi in chiaro da sessioni precedenti
      await FirebaseFirestore.instance
          .collection('families')
          .doc(familyChatId)
          .collection('locations')
          .doc(myUserId)
          .set(firestoreData);

      if (kDebugMode) print('✅ [RECIPIENT] Position shared successfully');
    } catch (e) {
      if (kDebugMode) print('❌ [RECIPIENT] Error sharing position with partner: $e');
    }
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    _compassRetryTimer?.cancel();
    _positionUpdateTimer?.cancel(); // Cancella il timer posizione

    // Se sono il destinatario, ferma la condivisione della mia posizione
    if (!widget.isSender) {
      _stopSharingMyPosition();
    }

    super.dispose();
  }

  /// Ferma la condivisione della posizione del destinatario (cleanup)
  Future<void> _stopSharingMyPosition() async {
    try {
      final pairingService = Provider.of<PairingService>(context, listen: false);
      final encryptionService = Provider.of<EncryptionService>(context, listen: false);

      final familyChatId = await pairingService.getFamilyChatId();
      final myPublicKey = await encryptionService.getPublicKey();

      if (familyChatId == null || myPublicKey == null) return;

      final myUserId = sha256.convert(utf8.encode(myPublicKey)).toString();

      // Ferma la condivisione su Firestore
      await FirebaseFirestore.instance
          .collection('families')
          .doc(familyChatId)
          .collection('locations')
          .doc(myUserId)
          .update({'is_active': false});

      if (kDebugMode) print('🛑 [RECIPIENT] Stopped sharing my position');
    } catch (e) {
      if (kDebugMode) print('❌ [RECIPIENT] Error stopping position share: $e');
    }
  }

  void _startCompass() {
    // Prova a ottenere lo stream della bussola
    final compassStream = FlutterCompass.events;

    if (compassStream != null) {
      _compassSubscription = compassStream.listen(
        (CompassEvent event) {
          if (mounted && event.heading != null) {
            setState(() {
              _heading = event.heading;
            });
          }
        },
        cancelOnError: false,
      );
      // Annulla il retry timer se la bussola è disponibile
      _compassRetryTimer?.cancel();
      _compassRetryTimer = null;
    } else {
      // Stream non disponibile, riprova ogni secondo
      _compassRetryCount++;

      if (_compassRetryTimer == null) {
        _compassRetryTimer = Timer.periodic(Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          _startCompass();
        });
      }
    }
  }

  /// Apre Google Maps con le indicazioni
  Future<void> _openMaps(double lat, double lon) async {
    final url = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon';
    final uri = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Calcola opacità della freccia basandosi sull'allineamento con destinazione
  /// 1.0 = perfettamente allineato, 0.2 = direzione opposta
  String _formatDistance(double meters) {
    final l10n = AppLocalizations.of(context)!;
    if (meters < 1000) {
      return l10n.locationShareDistanceMeters(meters.toInt());
    } else {
      return l10n.locationShareDistanceKm((meters / 1000).toStringAsFixed(1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locationService = Provider.of<LocationService>(context);
    final partnerLocation = locationService.partnerLocation;
    final myLocation = locationService.myLocation;

    // Condivisione attiva fino a: stop manuale o scadenza temporale
    final bool hasStopAction = false; // Lo stop è gestito dalla chat (action message)
    final bool isExpired = locationService.sharingExpiresAt != null &&
        DateTime.now().isAfter(locationService.sharingExpiresAt!);

    final bool isTerminated = widget.isSender
        ? (!locationService.isSharingLocation || isExpired)
        : (partnerLocation != null && !partnerLocation.isActive) || isExpired;

    // Colore sfondo: grigio se terminata, teal se attiva
    final backgroundColor = isTerminated
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.grey.shade600,
              Colors.grey.shade800,
            ],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF3BA8B0), // Teal app
              Color(0xFF145A60), // Teal scuro app
            ],
          );

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (partnerLocation != null && !isTerminated)
            IconButton(
              icon: Icon(Icons.map_outlined, color: Colors.white),
              onPressed: () => _openMaps(
                partnerLocation.latitude,
                partnerLocation.longitude,
              ),
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: backgroundColor),
        child: isTerminated
            ? _buildTerminatedView()
            : _buildActiveView(partnerLocation, myLocation),
      ),
    );
  }

  /// Decide quale vista mostrare in base a mode (live/static) e ruolo (sender/receiver).
  /// Live: il sender ha la frecciona per navigare verso il partner.
  /// Static: il receiver ha la frecciona per raggiungere il sender.
  Widget _buildActiveView(partnerLocation, myLocation) {
    if (partnerLocation == null) {
      return _buildWaitingView();
    }

    // Chi vede la frecciona (navigazione)?
    // Live: il sender naviga verso il partner → sender ha freccia
    // Static: il receiver naviga verso il sender → receiver ha freccia
    final bool showBigArrow = (widget.mode == 'live' && widget.isSender) ||
        (widget.mode == 'static' && !widget.isSender);

    return _buildNavigationView(context, partnerLocation, myLocation,
        showBigArrow: showBigArrow);
  }

  /// Vista di attesa
  Widget _buildWaitingView() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.location_on, size: 80, color: Colors.white70),
          SizedBox(height: 40),
          Text(
            l10n.locationShareWaitingPartner,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w300,
              letterSpacing: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Vista condivisione terminata (sfondo grigio)
  Widget _buildTerminatedView() {
    final l10n = AppLocalizations.of(context)!;
    final locationService = Provider.of<LocationService>(context);
    final partnerLocation = locationService.partnerLocation;

    // Calcola distanza se entrambe le posizioni sono disponibili
    double? distance;
    if (_myPosition != null && partnerLocation != null) {
      distance = locationService.calculateDistance(
        _myPosition!.latitude,
        _myPosition!.longitude,
        partnerLocation.latitude,
        partnerLocation.longitude,
      );
    }

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.location_off,
                      size: 100,
                      color: Colors.white70,
                    ),
                    SizedBox(height: 40),
                    Text(
                      l10n.locationShareEnded,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w200,
                        letterSpacing: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 20),
                    Text(
                      l10n.locationShareEndedDescription,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 40),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.grey.shade700,
                        padding: EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        l10n.locationShareBackToChat,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Box distanza in basso (se disponibile)
          if (distance != null)
            _buildDistancePanel(distance, null, DateTime.now()),

          SizedBox(height: 40),
        ],
      ),
    );
  }

  /// Vista principale di navigazione
  Widget _buildNavigationView(BuildContext context, partnerLocation, myLocation,
      {bool showBigArrow = false}) {
    final locationService = Provider.of<LocationService>(context, listen: false);

    // Calcola distanza e direzione verso il partner usando _myPosition locale
    double? distance;
    double? targetBearing;

    // Calcola distanza solo se entrambe le posizioni sono disponibili
    if (_myPosition != null && partnerLocation != null) {
      distance = locationService.calculateDistance(
        _myPosition!.latitude,
        _myPosition!.longitude,
        partnerLocation.latitude,
        partnerLocation.longitude,
      );

      targetBearing = locationService.calculateBearing(
        _myPosition!.latitude,
        _myPosition!.longitude,
        partnerLocation.latitude,
        partnerLocation.longitude,
      );
    }

    return SafeArea(
      child: Column(
        children: [
          SizedBox(height: 60),

          // Chi ha la freccia grande vede il target in alto
          if (showBigArrow) _buildDestinationPoint(),

          SizedBox(height: showBigArrow ? 80 : 0),

          // Frecciona grande per chi naviga, radar per chi aspetta
          if (showBigArrow) ...[
            _buildReceiverView(targetBearing),
          ] else ...[
            _buildRadarView(distance, targetBearing, partnerLocation?.heading),
          ],

          SizedBox(height: 40),

          // Box distanza in basso con pin + timestamp + STOP
          _buildDistancePanel(
            distance ?? 0,
            partnerLocation?.timestamp,
            locationService.sharingExpiresAt ?? DateTime.now(),
          ),

          SizedBox(height: 40),
        ],
      ),
    );
  }

  /// Vista radar per il mittente (cerchi concentrici con freccia partner)
  Widget _buildRadarView(double? distance, double? targetBearing, double? partnerHeading) {
    // Fallback: se non abbiamo heading del mittente, usa Nord fisso (0°)
    final myHeading = _heading ?? 0.0;

    // Calcola offset radiale in base alla distanza
    // A 1km o più: freccia sul bordo (140px dal centro)
    // Vicino: freccia al centro (0px)
    double radialOffset = 0;
    if (distance != null) {
      const maxDistance = 1000.0; // 1 km in metri
      const maxRadius = 140.0; // Raggio del cerchio grande

      if (distance >= maxDistance) {
        radialOffset = maxRadius; // Sul bordo
      } else {
        // Interpola linearmente: 0m -> 0px, 1000m -> 140px
        radialOffset = (distance / maxDistance) * maxRadius;
      }
    }

    // Converti bearing in radianti e calcola offset x,y della POSIZIONE della freccia
    double offsetX = 0;
    double offsetY = 0;
    if (targetBearing != null) {
      final angleRad = (targetBearing - myHeading) * math.pi / 180;
      offsetX = radialOffset * math.sin(angleRad);
      offsetY = -radialOffset * math.cos(angleRad); // -Y perché lo schermo ha Y invertito
    }

    // Calcola rotazione freccia in base a dove sta andando il partner
    // IMPORTANTE: La freccia deve ruotare RELATIVAMENTE alla sua posizione radiale!
    // Formula: partnerHeading - targetBearing
    // - Se va verso mittente (opposto): differenza ~180° → punta al centro ✓
    // - Se va lontano (stesso verso): differenza ~0° → punta verso esterno ✓
    double arrowRotation = 0;
    if (partnerHeading != null && partnerHeading >= 0 && targetBearing != null) {
      // Rotazione RELATIVA alla posizione sul radar
      arrowRotation = (partnerHeading - targetBearing) * math.pi / 180;
    } else if (targetBearing != null) {
      // Fallback: punta verso il mittente (180° dalla sua posizione radiale)
      arrowRotation = math.pi; // 180° rispetto alla radiale
    }

    // LOG DETTAGLIATO PER DEBUG
    if (kDebugMode) {
      print('🎯 [RADAR] ========================================');
      print('   Distance: ${distance?.toStringAsFixed(1)} m');
      print('   RadialOffset: ${radialOffset.toStringAsFixed(1)} px');
      print('   MyHeading (mittente): ${myHeading.toStringAsFixed(1)}° ${_heading == null ? "(Nord fisso)" : ""}');
      print('   PartnerHeading (destinatario): ${partnerHeading?.toStringAsFixed(1) ?? "null"}°');
      print('   TargetBearing (dove si trova): ${targetBearing?.toStringAsFixed(1) ?? "null"}°');
      if (partnerHeading != null && targetBearing != null) {
        print('   Differenza: ${(partnerHeading - targetBearing).toStringAsFixed(1)}°');
      }
      print('   ArrowRotation: ${(arrowRotation * 180 / math.pi).toStringAsFixed(1)}° (${partnerHeading != null && partnerHeading >= 0 && targetBearing != null ? "heading-bearing" : "fallback 180°"})');
      print('   Position (x,y): (${offsetX.toStringAsFixed(1)}, ${offsetY.toStringAsFixed(1)})');
      print('==========================================');
    }

    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // "N" in alto per indicare il Nord
          Text(
            'N',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 2.0,
            ),
          ),
          SizedBox(height: 20),

          // Radar con freccia
          Center(
            child: Stack(
              clipBehavior: Clip.none, // Permette overflow per frecce sui bordi
              alignment: Alignment.center,
              children: [
                // Cerchi concentrici (radar)
                Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                ),
                Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                ),

                // Freccia del partner che si muove verso il centro - PIÙ PICCOLA
                // La POSIZIONE dipende da targetBearing (dove si trova)
                // La ROTAZIONE dipende da partnerHeading (dove sta andando)
                if (targetBearing != null)
                  Transform.translate(
                    offset: Offset(offsetX, offsetY),
                    child: Transform.rotate(
                      angle: arrowRotation,
                      child: Icon(
                        Icons.navigation,
                        size: 60,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  // Nessuna posizione partner disponibile
                  Icon(
                    Icons.navigation,
                    size: 60,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Vista per il destinatario (solo freccia grossa)
  Widget _buildReceiverView(double? targetBearing) {
    // Calcola opacità basandosi sull'allineamento
    double opacity = 1.0;
    if (_heading != null && targetBearing != null) {
      double diff = ((targetBearing - _heading!) + 180) % 360 - 180;
      double absDiff = diff.abs();

      if (absDiff <= 5) {
        opacity = 1.0; // Perfettamente allineato - SOLIDO
      } else if (absDiff >= 170) {
        opacity = 0.15; // Direzione opposta - MOLTO SFUMATO
      } else {
        opacity = 1.0 - (absDiff / 170.0) * 0.85; // Graduale
      }
    } else {
      opacity = 0.5; // Bussola non disponibile
    }

    return Expanded(
      child: Center(
        child: _heading != null && targetBearing != null
            ? AnimatedOpacity(
                duration: Duration(milliseconds: 200),
                opacity: opacity,
                child: Transform.rotate(
                  alignment: Alignment.center,
                  angle: (targetBearing - _heading!) * math.pi / 180,
                  child: Icon(
                    Icons.navigation,
                    size: 280,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              )
            : Icon(
                Icons.navigation,
                size: 280,
                color: Colors.white.withValues(alpha: 0.5),
              ),
      ),
    );
  }

  /// Pannello distanza con pin + timestamp + STOP
  Widget _buildDistancePanel(double distance, DateTime? timestamp, DateTime expiresAt) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 32),
      padding: EdgeInsets.symmetric(vertical: 24, horizontal: 32),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Distanza grande
          Text(
            _formatDistance(distance),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.w200,
              letterSpacing: 2.0,
            ),
          ),

          SizedBox(height: 16),

          // Pin icon + timestamp + STOP in una riga
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pin icon
              Icon(
                Icons.location_on,
                color: Colors.white60,
                size: 16,
              ),
              SizedBox(width: 6),

              // Timestamp (se disponibile)
              if (timestamp != null) ...[
                Text(
                  _formatTimestamp(timestamp),
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(width: 16),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // RIMOSSO: STOP button - si interrompe solo dalla chat

  /// Punto fisso in alto che rappresenta la destinazione (partner)
  /// Cerchi concentrici piccoli che indicano la destinazione
  Widget _buildDestinationPoint() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Cerchio esterno
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
        ),
        // Cerchio interno
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.7),
              width: 2,
            ),
          ),
        ),
      ],
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inSeconds < 60) {
      return l10n.locationShareTimeAgoSeconds(diff.inSeconds);
    } else if (diff.inMinutes < 60) {
      return l10n.locationShareTimeAgoMinutes(diff.inMinutes);
    } else {
      return l10n.locationShareTimeAgoHours(diff.inHours);
    }
  }

}
