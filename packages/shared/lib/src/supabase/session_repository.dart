// hide Session: our domain `Session` model shadows gotrue's auth Session here.
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../ble/session_token_source.dart';
import '../config/app_config.dart';
import '../models/attendance.dart';
import '../models/roster_entry.dart';
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

  /// Opens a session for an OFFERING (subject × section). Tags the room so the
  /// RFID reader can resolve it. Pre-generates the rotating token windows.
  Future<Session> startSessionForOffering({
    required String offeringId,
    required String teacherId,
    String? room,
    Duration duration = const Duration(minutes: 15),
  }) async {
    final now = DateTime.now().toUtc();
    final ends = now.add(duration);
    final sessionRow = await _client
        .from('sessions')
        .insert({
          'offering_id': offeringId,
          'teacher_id': teacherId,
          'status': 'open',
          'started_at': now.toIso8601String(),
          'ends_at': ends.toIso8601String(),
          'beacon_service_uuid': BleContract.beaconServiceUuid,
          if (room != null) 'room': room,
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

  /// Realtime, STUDENT-based roster for [sessionId] (teacher view).
  ///
  /// Backed by Supabase Realtime on `attendance`. Each attendance row is mapped
  /// to the authenticated student account so faculty see names + student codes,
  /// never BLE tokens / device ids / RSSI. Student profiles are looked up once
  /// and cached. RLS lets a teacher read the users rows of students they teach.
  Stream<List<RosterEntry>> watchRoster(String sessionId) {
    final nameCache = <String, ({String name, String? code})>{};
    return _client
        .from('attendance')
        .stream(primaryKey: ['id'])
        .eq('session_id', sessionId)
        .order('created_at')
        .asyncMap((rows) async {
          final atts = rows.map(Attendance.fromJson).toList();
          final missing = atts
              .map((a) => a.studentId)
              .toSet()
              .where((id) => !nameCache.containsKey(id))
              .toList();
          if (missing.isNotEmpty) {
            final users = await _client
                .from('users')
                .select('id, full_name, student_code')
                .inFilter('id', missing);
            for (final u in users) {
              nameCache[u['id'] as String] = (
                name: (u['full_name'] as String?) ?? 'Student',
                code: u['student_code'] as String?,
              );
            }
          }
          return atts.map((a) {
            final s = nameCache[a.studentId];
            return RosterEntry(
              attendanceId: a.id,
              studentId: a.studentId,
              studentName: s?.name ?? 'Student',
              studentCode: s?.code,
              status: a.status,
              markedAt: a.createdAt,
              reason: a.reason,
              faceMatchScore: a.evidence?.faceMatchScore,
              livenessPassed: a.evidence?.livenessPassed,
              challengeType: a.evidence?.challengeType,
            );
          }).toList();
        });
  }
}
