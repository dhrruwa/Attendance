import '../evidence/evidence.dart';
import 'enums.dart';

/// A row in `attendance`. Students INSERT a pending row (status defaults to
/// `flagged` until the edge function rules on it); the **server** sets the final
/// status, reason, rssi mirror, etc. Students cannot read other students' rows
/// (RLS); teachers can read rows for their own sessions only.
class Attendance {
  const Attendance({
    required this.id,
    required this.sessionId,
    required this.studentId,
    required this.status,
    required this.evidence,
    this.submittedToken,
    this.rssi,
    this.deviceId,
    this.reason,
    this.createdAt,
  });

  final String id;
  final String sessionId;
  final String studentId;
  final AttendanceStatus status;
  final Evidence? evidence;

  /// Mirror columns (also inside evidence) kept top-level for fast querying.
  final String? submittedToken;
  final int? rssi;
  final String? deviceId;

  /// Human-readable explanation set by the server (e.g. "rssi too weak").
  final String? reason;
  final DateTime? createdAt;

  factory Attendance.fromJson(Map<String, dynamic> json) => Attendance(
        id: json['id'] as String,
        sessionId: json['session_id'] as String,
        studentId: json['student_id'] as String,
        status: AttendanceStatus.fromString(json['status'] as String),
        evidence: json['evidence'] == null
            ? null
            : Evidence.fromJson(
                (json['evidence'] as Map).cast<String, dynamic>()),
        submittedToken: json['submitted_token'] as String?,
        rssi: (json['rssi'] as num?)?.toInt(),
        deviceId: json['device_id'] as String?,
        reason: json['reason'] as String?,
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'session_id': sessionId,
        'student_id': studentId,
        'status': status.name,
        'evidence': evidence?.toJson(),
        'submitted_token': submittedToken,
        'rssi': rssi,
        'device_id': deviceId,
        'reason': reason,
      };
}
