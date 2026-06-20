import 'enums.dart';

/// An attendance-taking window. The teacher opens it (which begins BLE
/// advertising) and closes it. Belongs to an `offering` (subject × section); the
/// legacy `course_id` is kept nullable for old sessions.
class Session {
  const Session({
    required this.id,
    required this.teacherId,
    required this.status,
    required this.startedAt,
    required this.endsAt,
    required this.beaconServiceUuid,
    this.courseId,
    this.offeringId,
    this.room,
  });

  final String id;
  final String? courseId;
  final String? offeringId;
  final String teacherId;
  final SessionStatus status;
  final DateTime startedAt;
  final DateTime endsAt;
  final String beaconServiceUuid;
  final String? room;

  bool get isOpen =>
      status == SessionStatus.open && DateTime.now().isBefore(endsAt);

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        id: json['id'] as String,
        courseId: json['course_id'] as String?,
        offeringId: json['offering_id'] as String?,
        teacherId: json['teacher_id'] as String,
        status: SessionStatus.fromString(json['status'] as String),
        startedAt: DateTime.parse(json['started_at'] as String),
        endsAt: DateTime.parse(json['ends_at'] as String),
        beaconServiceUuid: json['beacon_service_uuid'] as String,
        room: json['room'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'course_id': courseId,
        'offering_id': offeringId,
        'teacher_id': teacherId,
        'status': status.name,
        'started_at': startedAt.toIso8601String(),
        'ends_at': endsAt.toIso8601String(),
        'beacon_service_uuid': beaconServiceUuid,
        'room': room,
      };
}
