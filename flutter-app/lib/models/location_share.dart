import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/encryption_service.dart';

/// Modello per la condivisione della posizione in tempo reale
class LocationShare {
  final String id;
  final String userId; // deviceId di chi condivide la posizione
  final String sessionId; // ID univoco della sessione di condivisione
  final double latitude;
  final double longitude;
  final double accuracy; // Precisione in metri
  final DateTime timestamp; // Ultimo aggiornamento posizione
  final DateTime expiresAt; // Quando scade la condivisione (1h o 8h)
  final double? speed; // Velocità in m/s (opzionale)
  final double? heading; // Direzione in gradi (0-360) - 0 = Nord
  final bool isActive; // Se la condivisione è ancora attiva

  LocationShare({
    required this.id,
    required this.userId,
    required this.sessionId,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
    required this.expiresAt,
    this.speed,
    this.heading,
    this.isActive = true,
  });

  /// Factory per creare da Firestore
  factory LocationShare.fromFirestore(String docId, Map<String, dynamic> data) {
    // Timestamp può essere Timestamp Firestore o int (secondi)
    DateTime parseTimestamp(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is Timestamp) return value.toDate();
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value * 1000);
      return DateTime.now();
    }

    // ExpiresAt può essere Timestamp o String ISO8601
    DateTime parseExpiresAt(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.parse(value);
      return DateTime.now();
    }

    return LocationShare(
      id: docId,
      userId: data['user_id'] ?? '',
      sessionId: data['session_id'] ?? '',
      latitude: (data['latitude'] ?? 0.0).toDouble(),
      longitude: (data['longitude'] ?? 0.0).toDouble(),
      accuracy: (data['accuracy'] ?? 0.0).toDouble(),
      timestamp: parseTimestamp(data['timestamp']),
      expiresAt: parseExpiresAt(data['expires_at']),
      speed: data['speed'] != null ? (data['speed'] as num).toDouble() : null,
      heading: data['heading'] != null ? (data['heading'] as num).toDouble() : null,
      isActive: data['is_active'] ?? true,
    );
  }

  /// Factory per creare da Firestore con coordinate cifrate (AES-256)
  /// Decifra encrypted_location usando la chiave di sessione
  factory LocationShare.fromEncryptedFirestore(
    String docId,
    Map<String, dynamic> data,
    String locationKeyBase64,
    EncryptionService encryptionService,
  ) {
    // Timestamp può essere Timestamp Firestore o int (secondi)
    DateTime parseTimestamp(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is Timestamp) return value.toDate();
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value * 1000);
      return DateTime.now();
    }

    // ExpiresAt può essere Timestamp o String ISO8601
    DateTime parseExpiresAt(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.parse(value);
      return DateTime.now();
    }

    // Decifra le coordinate
    final decrypted = encryptionService.decryptLocationData(
      data['encrypted_location'] as String,
      data['location_iv'] as String,
      locationKeyBase64,
    );

    return LocationShare(
      id: docId,
      userId: data['user_id'] ?? '',
      sessionId: data['session_id'] ?? '',
      latitude: (decrypted['lat'] ?? 0.0).toDouble(),
      longitude: (decrypted['lng'] ?? 0.0).toDouble(),
      accuracy: (decrypted['acc'] ?? 0.0).toDouble(),
      timestamp: parseTimestamp(data['timestamp']),
      expiresAt: parseExpiresAt(data['expires_at']),
      speed: decrypted['spd'] != null ? (decrypted['spd'] as num).toDouble() : null,
      heading: decrypted['hdg'] != null ? (decrypted['hdg'] as num).toDouble() : null,
      isActive: data['is_active'] ?? true,
    );
  }

  /// Factory per creare da JSON
  factory LocationShare.fromJson(Map<String, dynamic> json) {
    return LocationShare(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      sessionId: json['session_id'] ?? '',
      latitude: (json['latitude'] ?? 0.0).toDouble(),
      longitude: (json['longitude'] ?? 0.0).toDouble(),
      accuracy: (json['accuracy'] ?? 0.0).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
      expiresAt: DateTime.parse(json['expires_at'] ?? DateTime.now().toIso8601String()),
      speed: json['speed'] != null ? (json['speed'] as num).toDouble() : null,
      heading: json['heading'] != null ? (json['heading'] as num).toDouble() : null,
      isActive: json['is_active'] ?? true,
    );
  }

  /// Converte in Map per Firestore
  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'session_id': sessionId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'timestamp': Timestamp.fromDate(timestamp),
      'expires_at': Timestamp.fromDate(expiresAt),
      if (speed != null) 'speed': speed,
      if (heading != null) 'heading': heading,
      'is_active': isActive,
    };
  }

  /// Verifica se la condivisione è scaduta
  bool get isExpired {
    return DateTime.now().isAfter(expiresAt);
  }

  /// Copia con campi modificati
  LocationShare copyWith({
    String? id,
    String? userId,
    String? sessionId,
    double? latitude,
    double? longitude,
    double? accuracy,
    DateTime? timestamp,
    DateTime? expiresAt,
    double? speed,
    double? heading,
    bool? isActive,
  }) {
    return LocationShare(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      sessionId: sessionId ?? this.sessionId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      timestamp: timestamp ?? this.timestamp,
      expiresAt: expiresAt ?? this.expiresAt,
      speed: speed ?? this.speed,
      heading: heading ?? this.heading,
      isActive: isActive ?? this.isActive,
    );
  }
}
