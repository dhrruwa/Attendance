import 'dart:async';
import 'dart:math';

import '../config/app_config.dart';
import '../models/session_token.dart';

/// Pure, testable rotating-token logic.
///
/// The teacher app uses this to know which token to serve over GATT *right now*.
/// Tokens are pre-generated server-side (`session_tokens`) and streamed to the
/// teacher; the teacher serves whichever one is currently valid. If the teacher
/// is briefly offline we can also self-generate deterministic fallbacks, but the
/// authoritative list lives on the server and is what `validate_attendance` checks.
class SessionTokenSource {
  SessionTokenSource(this._tokens);

  /// Pre-generated tokens for the session, ordered by validFrom.
  final List<SessionToken> _tokens;

  /// Returns the token whose validity window contains [now], or null.
  SessionToken? currentToken(DateTime now) {
    for (final t in _tokens) {
      if (t.isValidAt(now)) return t;
    }
    return null;
  }

  /// Emits the current token every [BleContract.tokenRotation], so the teacher's
  /// GATT read callback always returns a fresh value.
  Stream<SessionToken?> rotations({
    required Stream<DateTime> clock,
  }) =>
      clock.map(currentToken);
}

/// Generates the opaque token strings stored in `session_tokens`. Used by the
/// teacher app when opening a session to seed the server (the server can also
/// generate these; we keep one implementation here so the format is shared).
class TokenGenerator {
  TokenGenerator([Random? random]) : _random = random ?? Random.secure();
  final Random _random;

  static const _alphabet =
      'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no ambiguous chars

  /// A short, high-entropy token (default 8 chars ~ 40 bits).
  String generate([int length = 8]) => List.generate(
        length,
        (_) => _alphabet[_random.nextInt(_alphabet.length)],
      ).join();

  /// Builds a contiguous chain of token windows covering [from] .. [from+span],
  /// each lasting [BleContract.tokenRotation]. The window is widened slightly on
  /// validTo to tolerate clock skew between teacher and student.
  List<Map<String, dynamic>> buildTokenWindows({
    required String sessionId,
    required DateTime from,
    required Duration span,
    Duration skewGrace = const Duration(seconds: 3),
  }) {
    final rotation = BleContract.tokenRotation;
    final count = (span.inMilliseconds / rotation.inMilliseconds).ceil();
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < count; i++) {
      final validFrom = from.add(rotation * i);
      final validTo = validFrom.add(rotation).add(skewGrace);
      out.add({
        'session_id': sessionId,
        'token': generate(),
        'valid_from': validFrom.toUtc().toIso8601String(),
        'valid_to': validTo.toUtc().toIso8601String(),
      });
    }
    return out;
  }
}

/// A simple periodic clock used to drive rotations. Exposed so tests can inject
/// a fake clock.
Stream<DateTime> periodicClock(Duration interval) =>
    Stream<DateTime>.periodic(interval, (_) => DateTime.now());
