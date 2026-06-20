import 'enums.dart';

/// A teacher-facing roster row.
///
/// Carries the STUDENT's identity + attendance status only. It deliberately
/// exposes no BLE token, device id, MAC address, UUID, or RSSI — those are used
/// purely server-side for verification and must never reach the faculty UI.
/// The optional verification fields below (face/liveness/challenge) are
/// human-meaningful signals shown only on the flag-review screen so a teacher
/// can adjudicate a flagged student; they are not device identifiers.
class RosterEntry {
  const RosterEntry({
    required this.attendanceId,
    required this.studentId,
    required this.studentName,
    required this.status,
    this.studentCode,
    this.markedAt,
    this.reason,
    this.faceMatchScore,
    this.livenessPassed,
    this.challengeType,
  });

  final String attendanceId;

  /// Internal only — used to scope review actions. Never displayed.
  final String studentId;

  final String studentName;
  final String? studentCode; // SRN / USN / student id
  final AttendanceStatus status;
  final DateTime? markedAt;
  final String? reason;

  // Verification evidence for flag review (NOT identifiers).
  final double? faceMatchScore;
  final bool? livenessPassed;
  final ChallengeType? challengeType;
}
