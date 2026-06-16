import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  group('TokenGenerator', () {
    test('generates tokens of requested length from the safe alphabet', () {
      final gen = TokenGenerator(Random(42));
      final t = gen.generate(8);
      expect(t.length, 8);
      expect(RegExp(r'^[A-Z2-9]+$').hasMatch(t), isTrue);
      expect(t.contains('0'), isFalse); // ambiguous chars excluded
      expect(t.contains('1'), isFalse);
    });

    test('buildTokenWindows covers the full span with contiguous windows', () {
      final gen = TokenGenerator(Random(1));
      final from = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final windows = gen.buildTokenWindows(
        sessionId: 's1',
        from: from,
        span: const Duration(seconds: 30),
      );
      // 30s / 5s rotation = 6 windows.
      expect(windows.length, 6);
      expect(windows.first['session_id'], 's1');
      // First window starts at `from`.
      expect(windows.first['valid_from'], from.toIso8601String());
    });
  });

  group('SessionTokenSource', () {
    test('currentToken returns the window containing now (with skew grace)',
        () {
      final from = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final tokens = [
        SessionToken(
          id: 't0',
          sessionId: 's1',
          token: 'AAAA',
          validFrom: from,
          validTo: from.add(const Duration(seconds: 8)),
        ),
        SessionToken(
          id: 't1',
          sessionId: 's1',
          token: 'BBBB',
          validFrom: from.add(const Duration(seconds: 5)),
          validTo: from.add(const Duration(seconds: 13)),
        ),
      ];
      final src = SessionTokenSource(tokens);
      expect(src.currentToken(from.add(const Duration(seconds: 2)))?.token,
          'AAAA');
      expect(src.currentToken(from.add(const Duration(seconds: 20))), isNull);
    });
  });

  group('Evidence', () {
    test('round-trips through json including placeholders', () {
      final e = Evidence(
        faceMatchScore: 0.91,
        livenessPassed: true,
        challengeType: ChallengeType.blink,
        bleToken: 'ABCD2345',
        rssi: -62,
        deviceId: 'dev-123',
        passiveSpoofScore: 0.97,
        geo: const GeoPoint(lat: 1.0, lng: 2.0, accuracy: 5),
      );
      final back = Evidence.fromJson(e.toJson());
      expect(back.faceMatchScore, 0.91);
      expect(back.challengeType, ChallengeType.blink);
      expect(back.rssi, -62);
      expect(back.geo?.lat, 1.0);
    });
  });
}
