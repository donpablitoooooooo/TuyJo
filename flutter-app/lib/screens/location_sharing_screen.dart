import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/location_service.dart';
import '../generated/l10n/app_localizations.dart';

/// Schermata per visualizzare la posizione del partner con frecce direzionali
class LocationSharingScreen extends StatefulWidget {
  const LocationSharingScreen({Key? key}) : super(key: key);

  @override
  State<LocationSharingScreen> createState() => _LocationSharingScreenState();
}

class _LocationSharingScreenState extends State<LocationSharingScreen> {
  double? _heading; // Direzione della bussola (0-360)
  StreamSubscription<CompassEvent>? _compassSubscription;

  @override
  void initState() {
    super.initState();
    _startCompass();

    // Avvia tracking del partner E ottieni la mia posizione per calcolare distanza
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final locationService = Provider.of<LocationService>(context, listen: false);
      locationService.startTrackingPartner();

      // Ottieni la mia posizione corrente per calcolare distanza
      await locationService.getCurrentPosition();
    });
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    super.dispose();
  }

  /// Avvia il compass stream
  void _startCompass() {
    _compassSubscription = FlutterCompass.events?.listen((CompassEvent event) {
      if (mounted) {
        setState(() {
          _heading = event.heading;
        });
      }
    });
  }

  /// Apre le mappe native con le indicazioni
  Future<void> _openMaps(double lat, double lon) async {
    final url = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon';
    final uri = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossibile aprire le mappe')),
        );
      }
    }
  }

  /// Calcola l'opacità della freccia basandosi sull'allineamento
  /// Ritorna 1.0 se perfettamente allineato, diminuisce man mano che si allontana
  double _calculateArrowOpacity(double targetBearing, double currentHeading) {
    // Calcola differenza angolare (normalizzata -180 a +180)
    double diff = ((targetBearing - currentHeading + 180) % 360) - 180;
    double absDiff = diff.abs();

    // Se perfettamente allineato (±5°), opacità = 1.0
    // Se completamente disallineato (180°), opacità = 0.2
    if (absDiff <= 5) {
      return 1.0;
    } else if (absDiff >= 180) {
      return 0.2;
    } else {
      // Interpolazione lineare tra 1.0 e 0.2
      return 1.0 - (absDiff / 180.0) * 0.8;
    }
  }

  /// Formatta la distanza in modo leggibile
  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toInt()} m';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
  }

  /// Formatta il tempo trascorso
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

    // Debug: verifica quando il widget rebuilda e quali valori ha
    print('🔄 [UI] LocationSharingScreen rebuild:');
    print('   partnerLocation: ${partnerLocation != null ? "✅ FOUND (${partnerLocation.latitude}, ${partnerLocation.longitude})" : "❌ NULL"}');
    print('   myLocation: ${myLocation != null ? "✅ FOUND" : "❌ NULL"}');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          'Posizione Partner',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: IconThemeData(color: Colors.white),
        actions: [
          // Bottone per aprire le mappe
          if (partnerLocation != null)
            IconButton(
              icon: Icon(Icons.map, color: Colors.white),
              onPressed: () => _openMaps(
                partnerLocation.latitude,
                partnerLocation.longitude,
              ),
            ),
        ],
      ),
      body: partnerLocation == null
          ? _buildWaitingView()
          : _buildNavigationView(partnerLocation, myLocation),
    );
  }

  /// Vista quando non c'è posizione del partner
  Widget _buildWaitingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Colors.tealAccent,
              strokeWidth: 3,
            ),
            SizedBox(height: 30),
            Icon(Icons.location_searching, size: 60, color: Colors.white54),
            SizedBox(height: 20),
            Text(
              'In attesa della posizione del partner...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 12),
            Text(
              'Il partner deve avere il GPS attivo e la condivisione in corso',
              style: TextStyle(color: Colors.white54, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Vista principale con navigazione
  Widget _buildNavigationView(partnerLocation, myLocation) {
    // Calcola distanza e direzione solo se ho anche la mia posizione
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

    return Column(
      children: [
        // Top: Marker direzionale (indica dove andare)
        SizedBox(height: 40),
        if (targetBearing != null && _heading != null)
          _buildDirectionMarker(targetBearing, _heading!),

        // Center: Grande freccia (indica direzione corrente)
        Expanded(
          child: Center(
            child: _heading != null && targetBearing != null
                ? _buildDirectionArrow(targetBearing, _heading!)
                : _buildCompassWarning(),
          ),
        ),

        // Bottom: Info distanza e timestamp
        _buildInfoPanel(distance, partnerLocation.timestamp),
        SizedBox(height: 40),
      ],
    );
  }

  /// Marker in alto che indica la direzione da seguire
  Widget _buildDirectionMarker(double targetBearing, double currentHeading) {
    // Calcola rotazione relativa
    double rotation = (targetBearing - currentHeading) * math.pi / 180;

    return Column(
      children: [
        Transform.rotate(
          angle: rotation,
          child: Icon(
            Icons.navigation,
            size: 60,
            color: Colors.tealAccent,
          ),
        ),
        SizedBox(height: 8),
        Text(
          '${targetBearing.toInt()}°',
          style: TextStyle(
            color: Colors.tealAccent,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// Grande freccia centrale che mostra la direzione di movimento
  Widget _buildDirectionArrow(double targetBearing, double currentHeading) {
    double opacity = _calculateArrowOpacity(targetBearing, currentHeading);

    // Calcola rotazione (punta sempre verso l'alto = nord)
    double rotation = -currentHeading * math.pi / 180;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedOpacity(
          duration: Duration(milliseconds: 300),
          opacity: opacity,
          child: Transform.rotate(
            angle: rotation,
            child: Icon(
              Icons.arrow_upward,
              size: 200,
              color: Colors.white,
            ),
          ),
        ),
        SizedBox(height: 20),
        Text(
          opacity > 0.8 ? 'Direzione corretta!' : 'Gira verso la freccia verde',
          style: TextStyle(
            color: opacity > 0.8 ? Colors.green : Colors.orange,
            fontSize: 18,
            fontWeight: FontWeight.bold,
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
        Icon(Icons.explore_off, size: 80, color: Colors.orange),
        SizedBox(height: 20),
        Text(
          'Bussola non disponibile',
          style: TextStyle(color: Colors.orange, fontSize: 18),
        ),
        SizedBox(height: 10),
        Text(
          'Muovi il telefono per calibrare',
          style: TextStyle(color: Colors.white54, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// Pannello info in basso con distanza e timestamp
  Widget _buildInfoPanel(double? distance, DateTime timestamp) {
    return Container(
      padding: EdgeInsets.all(20),
      margin: EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          if (distance != null) ...[
            Text(
              _formatDistance(distance),
              style: TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 5),
            Text(
              'distanza',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
            SizedBox(height: 15),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.access_time, color: Colors.white54, size: 16),
              SizedBox(width: 5),
              Text(
                _formatTimestamp(timestamp),
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
