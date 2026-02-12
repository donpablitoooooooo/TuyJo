import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';

/// Servizio WebRTC per chiamate vocali peer-to-peer.
///
/// Flusso:
/// 1. Caller: createOffer() → scrive offer SDP + ICE candidates su Firestore
/// 2. Callee: createAnswer() → legge offer, scrive answer SDP + ICE candidates
/// 3. Entrambi ascoltano ICE candidates del peer remoto
/// 4. Connessione audio diretta P2P stabilita
/// 5. Verifica audio: controlla che i pacchetti RTP fluiscano realmente
class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription? _remoteCandidatesSubscription;
  StreamSubscription? _answerSubscription;

  bool _remoteDescriptionSet = false;

  // Ringback tone
  AudioPlayer? _ringbackPlayer;
  bool _isPlayingRingback = false;

  // Audio verification
  Timer? _audioCheckTimer;
  int _lastBytesReceived = 0;
  int _audioCheckAttempts = 0;
  static const int _maxAudioCheckAttempts = 10; // 10 x 1s = 10 secondi max

  /// Callback quando la connessione WebRTC è stabilita (ICE connected)
  VoidCallback? onConnected;

  /// Callback quando la connessione si chiude
  VoidCallback? onDisconnected;

  /// Callback quando ICE fallisce (P2P non possibile)
  VoidCallback? onConnectionFailed;

  /// Callback quando l'audio è verificato come funzionante
  VoidCallback? onAudioVerified;

  // STUN servers gratuiti di Google per NAT traversal
  final Map<String, dynamic> _rtcConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  /// Inizializza il peer connection e cattura l'audio locale
  Future<void> initialize() async {
    _peerConnection = await createPeerConnection(_rtcConfig);

    // Cattura audio dal microfono (no video)
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });

    // Aggiungi le tracce audio al peer connection
    for (var track in _localStream!.getAudioTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }

    // Ricevi l'audio remoto dal partner
    _peerConnection!.onTrack = (RTCTrackEvent event) {
      if (kDebugMode) print('📞 [WEBRTC] Remote track received: ${event.track.kind}');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        if (kDebugMode) print('📞 [WEBRTC] Remote audio stream active');
      }
    };

    // Monitora lo stato della connessione
    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      if (kDebugMode) print('📞 [WEBRTC] Connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        onConnected?.call();
        // Avvia verifica audio dopo la connessione
        _startAudioVerification();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        if (kDebugMode) print('❌ [WEBRTC] Connection FAILED - P2P non riuscito');
        onConnectionFailed?.call();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
                 state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        onDisconnected?.call();
      }
    };

    // Monitora lo stato ICE separatamente per rilevare fallimenti prima
    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      if (kDebugMode) print('📞 [WEBRTC] ICE state: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        if (kDebugMode) print('❌ [WEBRTC] ICE FAILED - nessun percorso P2P trovato');
        onConnectionFailed?.call();
      }
    };
  }

  /// Avvia la verifica periodica che l'audio stia effettivamente fluendo
  void _startAudioVerification() {
    _audioCheckAttempts = 0;
    _lastBytesReceived = 0;
    _audioCheckTimer?.cancel();

    _audioCheckTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      _audioCheckAttempts++;

      final isFlowing = await _checkAudioFlowing();
      if (isFlowing) {
        if (kDebugMode) print('✅ [WEBRTC] Audio verificato - pacchetti in arrivo');
        timer.cancel();
        onAudioVerified?.call();
        return;
      }

      if (_audioCheckAttempts >= _maxAudioCheckAttempts) {
        if (kDebugMode) print('⚠️ [WEBRTC] Audio NON verificato dopo ${_maxAudioCheckAttempts}s');
        timer.cancel();
        // L'audio non fluisce nonostante la connessione — probabilmente symmetric NAT
        onConnectionFailed?.call();
      }
    });
  }

  /// Controlla se l'audio remoto sta fluendo usando le statistiche WebRTC
  Future<bool> _checkAudioFlowing() async {
    if (_peerConnection == null) return false;

    try {
      final stats = await _peerConnection!.getStats();
      for (var report in stats) {
        // Cerca le statistiche inbound-rtp per la traccia audio
        if (report.type == 'inbound-rtp') {
          final values = report.values;
          final kind = values['kind'] ?? values['mediaType'];
          if (kind == 'audio') {
            final bytesReceived = (values['bytesReceived'] as num?)?.toInt() ?? 0;
            if (kDebugMode) {
              print('📊 [WEBRTC] Audio inbound: bytesReceived=$bytesReceived (prev=$_lastBytesReceived)');
            }
            if (bytesReceived > _lastBytesReceived && _lastBytesReceived > 0) {
              // I bytes crescono → l'audio sta fluendo
              return true;
            }
            _lastBytesReceived = bytesReceived;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('⚠️ [WEBRTC] Error checking audio stats: $e');
    }
    return false;
  }

  // ─── Ringback Tone ───────────────────────────────────────────────

  /// Avvia il tono di ringback (suono che sente il caller mentre aspetta)
  Future<void> startRingback() async {
    if (_isPlayingRingback) return;
    _isPlayingRingback = true;

    try {
      _ringbackPlayer = AudioPlayer();
      // Genera un tono di ringback standard (425Hz, 1s on, 4s off)
      final wavBytes = _generateRingbackWav();
      await _ringbackPlayer!.setReleaseMode(ReleaseMode.loop);
      await _ringbackPlayer!.play(BytesSource(wavBytes));
      await _ringbackPlayer!.setVolume(0.3); // Volume basso
      if (kDebugMode) print('🔔 [WEBRTC] Ringback tone started');
    } catch (e) {
      if (kDebugMode) print('⚠️ [WEBRTC] Error starting ringback: $e');
      _isPlayingRingback = false;
    }
  }

  /// Ferma il tono di ringback
  Future<void> stopRingback() async {
    if (!_isPlayingRingback) return;
    _isPlayingRingback = false;

    try {
      await _ringbackPlayer?.stop();
      await _ringbackPlayer?.dispose();
      _ringbackPlayer = null;
      if (kDebugMode) print('🔕 [WEBRTC] Ringback tone stopped');
    } catch (e) {
      if (kDebugMode) print('⚠️ [WEBRTC] Error stopping ringback: $e');
    }
  }

  /// Genera un file WAV con tono di ringback italiano (425Hz, 1s on, 4s off)
  Uint8List _generateRingbackWav() {
    const sampleRate = 16000;
    const bitsPerSample = 16;
    const numChannels = 1;
    const frequency = 425.0; // Frequenza standard ringback italiano
    const toneMs = 1000; // 1 secondo di tono
    const silenceMs = 4000; // 4 secondi di silenzio
    const totalMs = toneMs + silenceMs;
    final numSamples = (sampleRate * totalMs / 1000).round();

    // Genera campioni PCM
    final samples = Int16List(numSamples);
    final toneSamples = (sampleRate * toneMs / 1000).round();
    for (int i = 0; i < toneSamples; i++) {
      // Sine wave a 425Hz con fade in/out per evitare click
      double envelope = 1.0;
      const fadeMs = 20;
      final fadeSamples = (sampleRate * fadeMs / 1000).round();
      if (i < fadeSamples) {
        envelope = i / fadeSamples; // Fade in
      } else if (i > toneSamples - fadeSamples) {
        envelope = (toneSamples - i) / fadeSamples; // Fade out
      }
      samples[i] = (sin(2 * pi * frequency * i / sampleRate) * 6000 * envelope).round().clamp(-32768, 32767);
    }
    // Il resto (silenzio) è già 0

    // Costruisci header WAV
    final dataSize = numSamples * (bitsPerSample ~/ 8) * numChannels;
    final fileSize = 36 + dataSize;
    final buffer = ByteData(44 + dataSize);

    // RIFF header
    buffer.setUint8(0, 0x52); // 'R'
    buffer.setUint8(1, 0x49); // 'I'
    buffer.setUint8(2, 0x46); // 'F'
    buffer.setUint8(3, 0x46); // 'F'
    buffer.setUint32(4, fileSize, Endian.little);
    buffer.setUint8(8, 0x57);  // 'W'
    buffer.setUint8(9, 0x41);  // 'A'
    buffer.setUint8(10, 0x56); // 'V'
    buffer.setUint8(11, 0x45); // 'E'

    // fmt sub-chunk
    buffer.setUint8(12, 0x66); // 'f'
    buffer.setUint8(13, 0x6D); // 'm'
    buffer.setUint8(14, 0x74); // 't'
    buffer.setUint8(15, 0x20); // ' '
    buffer.setUint32(16, 16, Endian.little); // Sub-chunk size
    buffer.setUint16(20, 1, Endian.little); // PCM format
    buffer.setUint16(22, numChannels, Endian.little);
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * numChannels * (bitsPerSample ~/ 8), Endian.little);
    buffer.setUint16(32, numChannels * (bitsPerSample ~/ 8), Endian.little);
    buffer.setUint16(34, bitsPerSample, Endian.little);

    // data sub-chunk
    buffer.setUint8(36, 0x64); // 'd'
    buffer.setUint8(37, 0x61); // 'a'
    buffer.setUint8(38, 0x74); // 't'
    buffer.setUint8(39, 0x61); // 'a'
    buffer.setUint32(40, dataSize, Endian.little);

    // Scrivi campioni PCM
    for (int i = 0; i < numSamples; i++) {
      buffer.setInt16(44 + i * 2, samples[i], Endian.little);
    }

    return buffer.buffer.asUint8List();
  }

  // ─── Signaling ───────────────────────────────────────────────────

  /// CALLER: Crea offer SDP e scrive su Firestore
  Future<void> createOffer(String familyChatId) async {
    if (_peerConnection == null) return;

    final callDoc = _firestore
        .collection('families')
        .doc(familyChatId)
        .collection('calls')
        .doc('current');

    // Raccogli ICE candidates locali e scrivili su Firestore
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (kDebugMode) print('📞 [WEBRTC] Caller ICE candidate: ${candidate.candidate}');
      callDoc.collection('callerCandidates').add({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    // Crea offer
    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    // Scrivi offer su Firestore
    await callDoc.set({
      'offer': {
        'type': offer.type,
        'sdp': offer.sdp,
      },
    }, SetOptions(merge: true));

    if (kDebugMode) print('📞 [WEBRTC] Offer created and written to Firestore');

    // Ascolta la risposta (answer) del callee
    _answerSubscription = callDoc.snapshots().listen((snapshot) async {
      if (!snapshot.exists) return;
      final data = snapshot.data()!;
      if (data['answer'] != null && !_remoteDescriptionSet) {
        _remoteDescriptionSet = true;
        final answer = RTCSessionDescription(
          data['answer']['sdp'],
          data['answer']['type'],
        );
        await _peerConnection!.setRemoteDescription(answer);
        if (kDebugMode) print('📞 [WEBRTC] Remote answer set');
      }
    });

    // Ascolta ICE candidates del callee
    _remoteCandidatesSubscription = callDoc
        .collection('calleeCandidates')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data()!;
          if (kDebugMode) print('📞 [WEBRTC] Adding callee ICE candidate');
          _peerConnection!.addCandidate(RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          ));
        }
      }
    });
  }

  /// CALLEE: Legge offer e crea answer SDP.
  /// Ritorna true se l'offer è stato trovato e l'answer creato con successo.
  Future<bool> createAnswer(String familyChatId) async {
    if (_peerConnection == null) return false;

    final callDoc = _firestore
        .collection('families')
        .doc(familyChatId)
        .collection('calls')
        .doc('current');

    // Leggi l'offer dal server (bypassa cache locale che potrebbe non avere l'offer)
    DocumentSnapshot<Map<String, dynamic>>? callData;
    for (int attempt = 0; attempt < 5; attempt++) {
      try {
        callData = await callDoc.get(const GetOptions(source: Source.server));
        if (callData.exists && callData.data()?['offer'] != null) break;
      } catch (e) {
        if (kDebugMode) print('⚠️ [WEBRTC] Server read attempt $attempt failed: $e');
      }
      // Offer non ancora scritto dal caller, riprova dopo un breve delay
      if (kDebugMode) print('⏳ [WEBRTC] Offer not found yet, retry ${attempt + 1}/5...');
      await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
    }
    if (callData == null || !callData.exists || callData.data()?['offer'] == null) {
      if (kDebugMode) print('❌ [WEBRTC] No offer found in Firestore after 5 retries');
      return false;
    }

    final offerData = callData.data()!['offer'];
    final offer = RTCSessionDescription(offerData['sdp'], offerData['type']);
    await _peerConnection!.setRemoteDescription(offer);
    _remoteDescriptionSet = true;
    if (kDebugMode) print('📞 [WEBRTC] Remote offer set');

    // Raccogli ICE candidates locali e scrivili su Firestore
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (kDebugMode) print('📞 [WEBRTC] Callee ICE candidate: ${candidate.candidate}');
      callDoc.collection('calleeCandidates').add({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    // Crea answer
    RTCSessionDescription answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    // Scrivi answer su Firestore
    await callDoc.set({
      'answer': {
        'type': answer.type,
        'sdp': answer.sdp,
      },
    }, SetOptions(merge: true));

    if (kDebugMode) print('📞 [WEBRTC] Answer created and written to Firestore');

    // Ascolta ICE candidates del caller
    _remoteCandidatesSubscription = callDoc
        .collection('callerCandidates')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data()!;
          if (kDebugMode) print('📞 [WEBRTC] Adding caller ICE candidate');
          _peerConnection!.addCandidate(RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          ));
        }
      }
    });

    return true;
  }

  /// Mute/unmute il microfono
  void setMicMuted(bool muted) {
    if (_localStream != null) {
      for (var track in _localStream!.getAudioTracks()) {
        track.enabled = !muted;
      }
      if (kDebugMode) print('📞 [WEBRTC] Mic ${muted ? "muted" : "unmuted"}');
    }
  }

  /// Attiva/disattiva altoparlante
  Future<void> setSpeakerOn(bool speakerOn) async {
    if (_localStream != null) {
      for (var track in _localStream!.getAudioTracks()) {
        track.enableSpeakerphone(speakerOn);
      }
      if (kDebugMode) print('📞 [WEBRTC] Speaker ${speakerOn ? "on" : "off"}');
    }
  }

  /// Pulisci ICE candidates e subcollection su Firestore
  Future<void> cleanupFirestore(String familyChatId) async {
    final callDoc = _firestore
        .collection('families')
        .doc(familyChatId)
        .collection('calls')
        .doc('current');

    // Elimina callerCandidates
    final callerCandidates = await callDoc.collection('callerCandidates').get();
    for (var doc in callerCandidates.docs) {
      await doc.reference.delete();
    }

    // Elimina calleeCandidates
    final calleeCandidates = await callDoc.collection('calleeCandidates').get();
    for (var doc in calleeCandidates.docs) {
      await doc.reference.delete();
    }

    // Elimina il documento chiamata
    await callDoc.delete();
  }

  /// Chiudi tutto: connessione, stream, listener, ringback
  Future<void> dispose() async {
    _audioCheckTimer?.cancel();
    _answerSubscription?.cancel();
    _remoteCandidatesSubscription?.cancel();

    // Ferma ringback se attivo
    await stopRingback();

    // Chiudi tracce audio locali
    if (_localStream != null) {
      for (var track in _localStream!.getAudioTracks()) {
        await track.stop();
      }
      await _localStream!.dispose();
      _localStream = null;
    }

    // Chiudi stream remoto
    _remoteStream = null;

    // Chiudi peer connection
    if (_peerConnection != null) {
      await _peerConnection!.close();
      _peerConnection = null;
    }

    _remoteDescriptionSet = false;

    if (kDebugMode) print('📞 [WEBRTC] Disposed');
  }
}
