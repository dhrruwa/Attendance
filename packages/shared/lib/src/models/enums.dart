/// Role of a user. Maps to the `users.role` enum column in Postgres.
enum UserRole {
  student,
  teacher;

  static UserRole fromString(String value) => UserRole.values
      .firstWhere((r) => r.name == value, orElse: () => UserRole.student);
}

/// Lifecycle of an attendance session. Maps to `sessions.status`.
enum SessionStatus {
  open,
  closed;

  static SessionStatus fromString(String value) => SessionStatus.values
      .firstWhere((s) => s.name == value, orElse: () => SessionStatus.closed);
}

/// Final attendance decision. Set server-side only. Maps to `attendance.status`.
///
/// - [present]: all checks passed.
/// - [flagged]: submitted but something looked off (low RSSI, weak liveness,
///   device mismatch); needs teacher review.
/// - [absent]: never submitted / explicitly rejected.
enum AttendanceStatus {
  present,
  flagged,
  absent;

  static AttendanceStatus fromString(String value) =>
      AttendanceStatus.values.firstWhere((s) => s.name == value,
          orElse: () => AttendanceStatus.absent);
}

/// The randomized active liveness challenge the student must perform.
enum ChallengeType {
  blink,
  turnLeft,
  turnRight,
  smile;

  static ChallengeType fromString(String value) => ChallengeType.values
      .firstWhere((c) => c.name == value, orElse: () => ChallengeType.blink);

  String get prompt => switch (this) {
        ChallengeType.blink => 'Blink slowly',
        ChallengeType.turnLeft => 'Turn your head left',
        ChallengeType.turnRight => 'Turn your head right',
        ChallengeType.smile => 'Smile',
      };
}
