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
