import 'package:flutter_test/flutter_test.dart';
import 'package:private_messaging/services/webrtc_service.dart';

const _sdp = 'v=0\r\n'
    'o=- 1 2 IN IP4 127.0.0.1\r\n'
    's=-\r\n'
    'm=audio 9 UDP/TLS/RTP/SAVPF 111 63 9 0 8\r\n'
    'a=rtpmap:111 opus/48000/2\r\n'
    'a=rtcp-fb:111 transport-cc\r\n'
    'a=fmtp:111 minptime=10;useinbandfec=1\r\n'
    'a=rtpmap:63 red/48000/2\r\n'
    'a=rtpmap:9 G722/8000\r\n';

void main() {
  group('tuneOpusSdp', () {
    test('merges tuning params into the existing opus fmtp line', () {
      final out = WebRTCService.tuneOpusSdp(_sdp);
      final fmtp = out.split('\r\n').firstWhere((l) => l.startsWith('a=fmtp:111 '));
      expect(fmtp, contains('useinbandfec=1'));
      expect(fmtp, contains('stereo=0'));
      expect(fmtp, contains('sprop-stereo=0'));
      expect(fmtp, contains('maxaveragebitrate=40000'));
      expect(fmtp, contains('maxplaybackrate=48000'));
      expect(fmtp, contains('usedtx=0'));
      expect(fmtp, contains('minptime=10'));
      // only one fmtp line for opus, other codecs untouched
      expect(out.split('\r\n').where((l) => l.startsWith('a=fmtp:111 ')).length, 1);
      expect(out, contains('a=rtpmap:9 G722/8000'));
      expect(out.contains('\r\n'), isTrue);
    });

    test('adds an fmtp line when opus has none', () {
      final sdp = _sdp.replaceFirst('a=fmtp:111 minptime=10;useinbandfec=1\r\n', '');
      final out = WebRTCService.tuneOpusSdp(sdp);
      final lines = out.split('\r\n');
      final idx = lines.indexOf('a=rtpmap:111 opus/48000/2');
      expect(lines[idx + 1], startsWith('a=fmtp:111 '));
      expect(lines[idx + 1], contains('useinbandfec=1'));
    });

    test('leaves SDP without opus untouched', () {
      const sdp = 'v=0\r\nm=audio 9 RTP/AVP 0\r\na=rtpmap:0 PCMU/8000\r\n';
      expect(WebRTCService.tuneOpusSdp(sdp), sdp);
    });
  });

  group('CallStats.quality', () {
    test('classifies by loss, rtt and jitter', () {
      expect(const CallStats().quality, CallQuality.unknown);
      expect(const CallStats(rttMs: 80, jitterMs: 10, lossPercent: 0.5).quality, CallQuality.good);
      expect(const CallStats(rttMs: 300, jitterMs: 10).quality, CallQuality.fair);
      expect(const CallStats(rttMs: 80, jitterMs: 10, lossPercent: 12).quality, CallQuality.poor);
    });
  });
}
