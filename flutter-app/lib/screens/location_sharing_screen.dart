import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/location_service.dart';

/// Schermata minimal per navigazione verso il partner
class LocationSharingScreen extends StatefulWidget {
  const LocationSharingScreen({Key? key}) : super(key: key);

  @override
  State<LocationSharingScreen> createState() => _LocationSharingScreenState();
}

class _LocationSharingScreenState extends State<LocationSharingScreen> {
  double? _heading; // Direzione corrente dalla bussola (0-360°)
  StreamSubscription<CompassEvent>? _compassSubscription;
  Timer? _compassRetryTimer;
  int _compassRetryCount = 0;

  @override
  void initState() {
    super.initState();
    _startCompass();

    // Avvia tracking del partner e ottieni la mia posizione
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final locationService = Provider.of<LocationService>(context, listen: false);
      locationService.startTrackingPartner();
      await locationService.getCurrentPosition();
    });
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
      print('🧭 [COMPASS] Stream disponibile, avvio listener');
      _compassSubscription = compassStream.listen(
        (CompassEvent event) {
          if (mounted) {
            if (event.heading != null) {
              print('🧭 [COMPASS] Heading ricevuto: ${event.heading}°');
              setState(() {
                _heading = event.heading;
              });
            } else {
              print('🧭 [COMPASS] Evento ricevuto ma heading è NULL');
            }
          }
        },
        onError: (error) {
          print('❌ [COMPASS] ERRORE nel listener: $error');
        },
        cancelOnError: false,
      );
      // Annulla il retry timer se la bussola è disponibile
      _compassRetryTimer?.cancel();
      _compassRetryTimer = null;
    } else {
      // Stream non disponibile, riprova ogni secondo
      _compassRetryCount++;
      print('🧭 [COMPASS] Stream è NULL, retry #$_compassRetryCount');

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
          if (partnerLocation != null)
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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF3BA8B0), // Teal app
              Color(0xFF145A60), // Teal scuro app
            ],
          ),
        ),
        child: partnerLocation == null
            ? _buildWaitingView()
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

  /// Vista principale di navigazione
  Widget _buildNavigationView(BuildContext context, partnerLocation, myLocation) {
    // Calcola distanza e direzione verso il partner
    double? distance;
    double? targetBearing;

    if (myLocation != null) {
      final locationService = Provider.of<LocationService>(context, listen: false);
      distance = locationService.calculateDistance(
        myLocation.latitude,
        myLocation.longitude,
        partnerLocation.latitude,
        partnerLocation.longitude,
      );
      targetBearing = locationService.calculateBearing(
        myLocation.latitude,
        myLocation.longitude,
        partnerLocation.latitude,
        partnerLocation.longitude,
      );
    }

    return SafeArea(
      child: Column(
        children: [
          SizedBox(height: 60),

          // PUNTO FISSO IN ALTO = DESTINAZIONE
          _buildDestinationPoint(),

          SizedBox(height: 80),

          // FRECCIA CHE RUOTA = DIREZIONE IN CUI STO ANDANDO
          Expanded(
            child: Center(
              child: _heading != null && targetBearing != null
                  ? _buildNavigationArrow(targetBearing, _heading!)
                  : _buildCompassWarning(),
            ),
          ),

          // INFO: DISTANZA E TIMESTAMP
          if (distance != null)
            _buildInfoPanel(distance, partnerLocation.timestamp),

          SizedBox(height: 40),
        ],
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

  /// Warning se la bussola non è disponibile
  Widget _buildCompassWarning() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Loading indicator animato
        SizedBox(
          width: 80,
          height: 80,
          child: CircularProgressIndicator(
            color: Colors.white38,
            strokeWidth: 2,
          ),
        ),
        SizedBox(height: 30),
        Text(
          'Calibrazione bussola...',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w300,
            letterSpacing: 1.2,
          ),
        ),
        SizedBox(height: 12),
        Text(
          'Muovi il telefono a forma di 8',
          style: TextStyle(
            color: Colors.white60,
            fontSize: 14,
            fontWeight: FontWeight.w300,
          ),
        ),
        if (_compassRetryCount > 5) ...[
          SizedBox(height: 20),
          Text(
            'Tentativo ${_compassRetryCount}...',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 12,
              fontWeight: FontWeight.w300,
            ),
          ),
        ],
      ],
    );
  }

  /// Pannello info minimal in basso
  Widget _buildInfoPanel(double distance, DateTime timestamp) {
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
          Text(
            _formatDistance(distance),
            style: TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.w200,
              letterSpacing: 2,
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
