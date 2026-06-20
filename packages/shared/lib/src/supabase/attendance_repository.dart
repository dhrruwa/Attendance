import 'package:supabase_flutter/supabase_flutter.dart';

import '../evidence/evidence.dart';
import '../models/attendance.dart';
import '../models/enums.dart';

/// Result of submitting an attendance attempt, as returned by the edge function.
class SubmitResult {
  const SubmitResult({
    required this.status,
    required this.reason,
    this.attendanceId,
  });

  final AttendanceStatus status;
  final String reason;
  final String? attendanceId;

  factory SubmitResult.fromJson(Map<String, dynamic> json) => SubmitResult(
        status: AttendanceStatus.fromString(json['status'] as String),
        reason: (json['reason'] as String?) ?? '',
        attendanceId: json['attendance_id'] as String?,
      );
}

/// One row in the student's own attendance history (joined with the session's
/// course for display in the Attendance Tracker).
class AttendanceHistoryEntry {
  const AttendanceHistoryEntry({
    required this.status,
    required this.reason,
    required this.markedAt,
    required this.courseName,
    this.courseCode,
    this.sessionStartedAt,
  });

  final AttendanceStatus status;
  final String reason;
  final DateTime markedAt;
  final String courseName;
  final String? courseCode;
  final DateTime? sessionStartedAt;

  factory AttendanceHistoryEntry.fromJson(Map<String, dynamic> json) {
    final session = (json['session'] as Map?)?.cast<String, dynamic>();
    final course = (session?['course'] as Map?)?.cast<String, dynamic>();
    return AttendanceHistoryEntry(
      status: AttendanceStatus.fromString(json['status'] as String),
      reason: (json['reason'] as String?) ?? '',
      markedAt: DateTime.parse(json['created_at'] as String),
      courseName: (course?['name'] as String?) ?? 'Unknown course',
      courseCode: course?['code'] as String?,
      sessionStartedAt: session?['started_at'] == null
          ? null
          : DateTime.parse(session!['started_at'] as String),
    );
  }
}

class AttendanceRepository {
  AttendanceRepository(this._client);
  final SupabaseClient _client;

  /// Submits the full evidence object to the `validate_attendance` edge function.
  ///
  /// The phone NEVER decides the outcome. The function verifies the session is
  /// open, the token is within its valid window, the device binding matches, and
  /// the evidence shows face-match + liveness passed; it dedupes and writes the
  /// final `attendance` row with status present|flagged. We just relay its verdict.
  Future<SubmitResult> submit({
    required String sessionId,
    required Evidence evidence,
  }) async {
    final res = await _client.functions.invoke(
      'validate_attendance',
      body: {
        'session_id': sessionId,
        'evidence': evidence.toJson(),
      },
    );
    final data = res.data;
    if (data is Map) {
      return SubmitResult.fromJson(data.cast<String, dynamic>());
    }
    throw StateError('Unexpected response from validate_attendance: $data');
  }

  /// The current student's own attendance row for a session (RLS lets a student
  /// read only their own rows).
  Future<Attendance?> myAttendance({
    required String sessionId,
    required String studentId,
  }) async {
    final rows = await _client
        .from('attendance')
        .select()
        .eq('session_id', sessionId)
        .eq('student_id', studentId)
        .limit(1);
    if (rows.isEmpty) return null;
    return Attendance.fromJson(rows.first);
  }

  /// The student's full attendance history, newest first, with the course of
  /// each session joined in for display. RLS limits rows to the caller's own.
  Future<List<AttendanceHistoryEntry>> myHistory(String studentId) async {
    final rows = await _client
        .from('attendance')
        .select('status, reason, created_at, '
            'session:sessions(started_at, course:courses(name, code))')
        .eq('student_id', studentId)
        .order('created_at', ascending: false);
    return rows
        .map((r) =>
            AttendanceHistoryEntry.fromJson((r as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Teacher action: confirm or reject a flagged student after review.
  Future<void> reviewFlagged({
    required String attendanceId,
    required bool approve,
    String? reason,
  }) async {
    await _client.from('attendance').update({
      'status': approve
          ? AttendanceStatus.present.name
          : AttendanceStatus.absent.name,
      'reason':
          reason ?? (approve ? 'approved by teacher' : 'rejected by teacher'),
    }).eq('id', attendanceId);
  }
}
