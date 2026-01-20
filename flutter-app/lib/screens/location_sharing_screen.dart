import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/location_service.dart';

/// Schermata minimal per navigazione verso il partner
class LocationSharingScreen extends StatefulWidget {
  final String expectedSessionId; // Session ID dal messaggio
  final bool isSender; // true se l'utente corrente è il mittente del messaggio

  const LocationSharingScreen({
    Key? key,
    required this.expectedSessionId,
    this.isSender = false,
  }) : super(key: key);

  @override
  State<LocationSharingScreen> createState() => _LocationSharingScreenState();
}

class _LocationSharingScreenState extends State<LocationSharingScreen> {
  double? _heading; // Direzione corrente dalla bussola (0-360°)
  StreamSubscription<CompassEvent>? _compassSubscription;
  Timer? _compassRetryTimer;
  int _compassRetryCount = 0;
  Position? _myPosition; // Posizione corrente dell'utente (locale, non condivisa)

  @override
  void initState() {
    super.initState();
    _startCompass();

    // Avvia tracking del partner e ottieni la mia posizione
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final locationService = Provider.of<LocationService>(context, listen: false);
      locationService.startTrackingPartner();

      // Ottieni la mia posizione corrente
      _updateMyPosition();

      // Aggiorna posizione ogni 5 secondi
      Timer.periodic(Duration(seconds: 5), (timer) {
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
    }
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    _compassRetryTimer?.cancel();
    super.dispose();
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
  double _calculateArrowOpacity(double targetBearing, double currentHeading) {
    double diff = ((targetBearing - currentHeading + 180) % 360) - 180;
    double absDiff = diff.abs();

    if (absDiff <= 5) {
      return 1.0; // Perfettamente allineato
    } else if (absDiff >= 170) {
      return 0.15; // Direzione opposta
    } else {
      return 1.0 - (absDiff / 170.0) * 0.85;
    }
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toInt()} m';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s fa';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m fa';
    } else {
      return '${diff.inHours}h fa';
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationService = Provider.of<LocationService>(context);
    final partnerLocation = locationService.partnerLocation;
    final myLocation = locationService.myLocation;

    // VERIFICA SESSION ID: se partner ha sessionId diverso, sessione terminata
    // NOTA: Se l'utente è il mittente (sta aprendo la propria condivisione),
    // non verifichiamo il sessionId perché potrebbe aver riavviato la condivisione
    final bool isSessionValid = widget.isSender || (partnerLocation != null &&
        partnerLocation.sessionId == widget.expectedSessionId);

    // Verifica se la condivisione è terminata
    // - Sessione non valida (sessionId diverso)
    // - Partner location null e non siamo in attesa iniziale
    final bool isTerminated = !isSessionValid ||
        (partnerLocation == null && !widget.isSender && locationService.isTrackingPartner);

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
          if (partnerLocation != null && isSessionValid && !widget.isSender)
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
            ? _buildTerminatedView() // Condivisione terminata
            : partnerLocation == null
                ? _buildWaitingView() // In attesa della posizione del partner
                : _buildNavigationView(context, partnerLocation, myLocation),
      ),
    );
  }

  /// Vista di attesa
  Widget _buildWaitingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2,
          ),
          SizedBox(height: 40),
          Icon(Icons.location_searching, size: 80, color: Colors.white38),
          SizedBox(height: 24),
          Text(
            'In attesa...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w300,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  /// Vista condivisione terminata (sfondo grigio)
  Widget _buildTerminatedView() {
    return Center(
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
              'Condivisione terminata',
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
              'La condivisione della posizione è stata interrotta',
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
                'Torna alla chat',
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
    );
  }

  /// Vista principale di navigazione
  Widget _buildNavigationView(BuildContext context, partnerLocation, myLocation) {
    // Calcola distanza e direzione verso il partner usando _myPosition locale
    double? distance;
    double? targetBearing;

    if (_myPosition != null) {
      final locationService = Provider.of<LocationService>(context, listen: false);
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

          // Se è il mittente, mostra solo messaggio statico
          // Se è il destinatario, mostra punto destinazione + freccia
          if (widget.isSender) ...[
            // MITTENTE: messaggio statico
            _buildSenderView(partnerLocation.expiresAt),
          ] else ...[
            // DESTINATARIO: punto fisso in alto + freccia navigazione
            _buildDestinationPoint(),

            SizedBox(height: 80),

            // FRECCIA o CERCHIO
            Expanded(
              child: Center(
                child: _heading != null && targetBearing != null
                    ? _buildNavigationArrow(targetBearing, _heading!) // Freccia che ruota
                    : _buildStaticCircle(), // Cerchio fisso se bussola non disponibile
              ),
            ),
          ],

          // INFO: DISTANZA E TIMESTAMP (sempre visibile per entrambi)
          _buildInfoPanel(distance, partnerLocation.timestamp, _myPosition == null),

          SizedBox(height: 40),
        ],
      ),
    );
  }

  /// Vista per il mittente (chi condivide)
  Widget _buildSenderView(DateTime expiresAt) {
    final timeFormat = DateFormat('HH:mm');
    final expiresAtFormatted = timeFormat.format(expiresAt);

    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.share_location,
              size: 80,
              color: Colors.white.withOpacity(0.9),
            ),
            SizedBox(height: 40),
            Text(
              'Stai condividendo la\ntua posizione fino alle',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 20,
                fontWeight: FontWeight.w300,
                height: 1.4,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 16),
            Text(
              expiresAtFormatted,
              style: TextStyle(
                color: Colors.white,
                fontSize: 48,
                fontWeight: FontWeight.w200,
                letterSpacing: 2.0,
              ),
            ),
            SizedBox(height: 60),
            ElevatedButton.icon(
              onPressed: () async {
                final locationService = Provider.of<LocationService>(context, listen: false);
                await locationService.stopSharingLocation();
                if (mounted) {
                  Navigator.pop(context);
                }
              },
              icon: Icon(Icons.stop_circle_outlined, size: 24),
              label: Text(
                'Interrompi condivisione',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Color(0xFF3BA8B0),
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Punto fisso in alto che rappresenta la destinazione (partner)
  Widget _buildDestinationPoint() {
    return Column(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.white.withOpacity(0.5),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
        ),
        SizedBox(height: 12),
        Text(
          'Destinazione',
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
            fontWeight: FontWeight.w300,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  /// Freccia di navigazione che ruota in base alla direzione
  Widget _buildNavigationArrow(double targetBearing, double currentHeading) {
    // Calcola opacità basandosi sull'allineamento
    double opacity = _calculateArrowOpacity(targetBearing, currentHeading);

    // Rotazione: la freccia punta nella direzione in cui sto andando
    // Quando sono allineato con la destinazione, punta verso l'alto (verso il punto)
    double rotationAngle = (targetBearing - currentHeading) * math.pi / 180;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedOpacity(
          duration: Duration(milliseconds: 200),
          opacity: opacity,
          child: Transform.rotate(
            angle: rotationAngle,
            child: Icon(
              Icons.navigation,
              size: 140,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 40),
        AnimatedOpacity(
          duration: Duration(milliseconds: 300),
          opacity: opacity > 0.8 ? 1.0 : 0.4,
          child: Text(
            opacity > 0.8 ? 'Direzione corretta' : 'Allineati con la destinazione',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w300,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ],
    );
  }

  /// Cerchio fisso quando la bussola non è disponibile
  Widget _buildStaticCircle() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.3),
            border: Border.all(
              color: Colors.white,
              width: 3,
            ),
          ),
          child: Center(
            child: Icon(
              Icons.explore_off,
              size: 60,
              color: Colors.white,
            ),
          ),
        ),
        SizedBox(height: 40),
        Text(
          'Bussola non disponibile',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w300,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  /// Pannello info minimal in basso
  Widget _buildInfoPanel(double? distance, DateTime timestamp, bool gpsUnavailable) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 32),
      padding: EdgeInsets.symmetric(vertical: 24, horizontal: 32),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Distanza o messaggio GPS non disponibile
          Text(
            gpsUnavailable ? 'GPS non disponibile' : (distance != null ? _formatDistance(distance) : '---'),
            style: TextStyle(
              color: Colors.white,
              fontSize: gpsUnavailable ? 24 : 48,
              fontWeight: FontWeight.w200,
              letterSpacing: gpsUnavailable ? 1.0 : 2.0,
            ),
          ),
          SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.access_time, color: Colors.white60, size: 16),
              SizedBox(width: 8),
              Text(
                'Aggiornato ${_formatTimestamp(timestamp)}',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
