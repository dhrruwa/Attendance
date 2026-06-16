import 'enums.dart';

/// An attendance-taking window for a course. The teacher opens it (which begins
/// BLE advertising) and closes it. `beacon_service_uuid` lets the schema support
/// per-session UUIDs later; today every session uses [BleContract.beaconServiceUuid].
class Session {
  const Session({
    required this.id,
    required this.courseId,
    required this.teacherId,
    required this.status,
    required this.startedAt,
    required this.endsAt,
    required this.beaconServiceUuid,
  });

  final String id;
  final String courseId;
  final String teacherId;
  final SessionStatus status;
  final DateTime startedAt;
  final DateTime endsAt;
  final String beaconServiceUuid;

  bool get isOpen =>
      status == SessionStatus.open && DateTime.now().isBefore(endsAt);

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        id: json['id'] as String,
        courseId: json['course_id'] as String,
        teacherId: json['teacher_id'] as String,
        status: SessionStatus.fromString(json['status'] as String),
        startedAt: DateTime.parse(json['started_at'] as String),
        endsAt: DateTime.parse(json['ends_at'] as String),
        beaconServiceUuid: json['beacon_service_uuid'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'course_id': courseId,
        'teacher_id': teacherId,
        'status': status.name,
        'started_at': startedAt.toIso8601String(),
        'ends_at': endsAt.toIso8601String(),
        'beacon_service_uuid': beaconServiceUuid,
      };
}
