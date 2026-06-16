// hide Session: our domain `Session` model shadows gotrue's auth Session here.
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../ble/session_token_source.dart';
import '../config/app_config.dart';
import '../models/attendance.dart';
import '../models/session.dart';
import '../models/session_token.dart';

class SessionRepository {
  SessionRepository(this._client);
  final SupabaseClient _client;

  final TokenGenerator _tokenGenerator = TokenGenerator();

  /// Opens a new session for [courseId] and pre-generates the rotating token
  /// windows covering its lifetime. Returns the created session.
  Future<Session> startSession({
    required String courseId,
    required String teacherId,
    Duration duration = const Duration(minutes: 15),
  }) async {
    final now = DateTime.now().toUtc();
    final ends = now.add(duration);

    final sessionRow = await _client
        .from('sessions')
        .insert({
          'course_id': courseId,
          'teacher_id': teacherId,
          'status': 'open',
          'started_at': now.toIso8601String(),
          'ends_at': ends.toIso8601String(),
          'beacon_service_uuid': BleContract.beaconServiceUuid,
        })
        .select()
        .single();
    final session = Session.fromJson(sessionRow);

    final windows = _tokenGenerator.buildTokenWindows(
      sessionId: session.id,
      from: now,
      span: duration,
    );
    await _client.from('session_tokens').insert(windows);

    return session;
  }

  /// Closes a session (stops counting attendance server-side via status check).
  Future<void> endSession(String sessionId) async {
    await _client
        .from('sessions')
        .update({'status': 'closed'}).eq('id', sessionId);
  }

  /// All token windows for a session, ordered, so the teacher app can serve the
  /// current one over GATT. Wrapped in [SessionTokenSource].
  Future<SessionTokenSource> tokenSource(String sessionId) async {
    final rows = await _client
        .from('session_tokens')
        .select()
        .eq('session_id', sessionId)
        .order('valid_from');
    final tokens = rows.map(SessionToken.fromJson).toList();
    return SessionTokenSource(tokens);
  }

  /// Realtime stream of attendance rows for [sessionId] (teacher roster).
  /// Backed by Supabase Realtime on the `attendance` table.
  Stream<List<Attendance>> watchRoster(String sessionId) {
    return _client
        .from('attendance')
        .stream(primaryKey: ['id'])
        .eq('session_id', sessionId)
        .order('created_at')
        .map((rows) => rows.map(Attendance.fromJson).toList());
  }

  /// One-shot roster fetch (e.g. on screen open before realtime warms up).
  Future<List<Attendance>> roster(String sessionId) async {
    final rows = await _client
        .from('attendance')
        .select()
        .eq('session_id', sessionId)
        .order('created_at');
    return rows.map(Attendance.fromJson).toList();
  }
}
