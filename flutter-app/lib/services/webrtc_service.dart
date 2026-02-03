import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Servizio WebRTC per chiamate vocali peer-to-peer.
///
/// Flusso:
/// 1. Caller: createOffer() → scrive offer SDP + ICE candidates su Firestore
/// 2. Callee: createAnswer() → legge offer, scrive answer SDP + ICE candidates
/// 3. Entrambi ascoltano ICE candidates del peer remoto
/// 4. Connessione audio diretta P2P stabilita
class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription? _remoteCandidatesSubscription;
  StreamSubscription? _answerSubscription;

  /// Callback quando la connessione è stabilita
  VoidCallback? onConnected;

  /// Callback quando la connessione si chiude
  VoidCallback? onDisconnected;

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

    // Monitora lo stato della connessione
    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      if (kDebugMode) print('📞 [WEBRTC] Connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        onConnected?.call();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
                 state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
                 state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        onDisconnected?.call();
      }
    };

    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      if (kDebugMode) print('📞 [WEBRTC] ICE state: $state');
    };
  }

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
      if (data['answer'] != null && _peerConnection?.getRemoteDescription() == null) {
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
          _peerConnection!.addCandidate(RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          ));
        }
      }
    });
  }

  /// CALLEE: Legge offer e crea answer SDP
  Future<void> createAnswer(String familyChatId) async {
    if (_peerConnection == null) return;

    final callDoc = _firestore
        .collection('families')
        .doc(familyChatId)
        .collection('calls')
        .doc('current');

    // Leggi l'offer dal documento
    final callData = await callDoc.get();
    if (!callData.exists || callData.data()?['offer'] == null) {
      if (kDebugMode) print('❌ [WEBRTC] No offer found in Firestore');
      return;
    }

    final offerData = callData.data()!['offer'];
    final offer = RTCSessionDescription(offerData['sdp'], offerData['type']);
    await _peerConnection!.setRemoteDescription(offer);

    // Raccogli ICE candidates locali e scrivili su Firestore
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
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
          _peerConnection!.addCandidate(RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          ));
        }
      }
    });
  }

  /// Mute/unmute il microfono
  void setMicMuted(bool muted) {
    if (_localStream != null) {
      for (var track in _localStream!.getAudioTracks()) {
        track.enabled = !muted;
      }
    }
  }

  /// Attiva/disattiva altoparlante
  Future<void> setSpeakerOn(bool speakerOn) async {
    if (_localStream != null) {
      for (var track in _localStream!.getAudioTracks()) {
        track.enableSpeakerphone(speakerOn);
      }
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

  /// Chiudi tutto: connessione, stream, listener
  Future<void> dispose() async {
    _answerSubscription?.cancel();
    _remoteCandidatesSubscription?.cancel();

    // Chiudi tracce audio
    if (_localStream != null) {
      for (var track in _localStream!.getAudioTracks()) {
        await track.stop();
      }
      await _localStream!.dispose();
      _localStream = null;
    }

    // Chiudi peer connection
    if (_peerConnection != null) {
      await _peerConnection!.close();
      _peerConnection = null;
    }

    if (kDebugMode) print('📞 [WEBRTC] Disposed');
  }
}
