import 'enums.dart';

/// A row in `users`. Identified by Supabase auth uid (`id`). Carries a unique
/// human-facing code (`student_code` for students, `teacher_code` for teachers).
class AppUser {
  const AppUser({
    required this.id,
    required this.institutionId,
    required this.role,
    required this.fullName,
    this.studentCode,
    this.teacherCode,
    this.createdAt,
  });

  final String id;
  final String institutionId;
  final UserRole role;
  final String fullName;
  final String? studentCode;
  final String? teacherCode;
  final DateTime? createdAt;

  /// The code relevant to this user's role.
  String? get code => role == UserRole.teacher ? teacherCode : studentCode;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        institutionId: json['institution_id'] as String,
        role: UserRole.fromString(json['role'] as String),
        fullName: (json['full_name'] as String?) ?? '',
        studentCode: json['student_code'] as String?,
        teacherCode: json['teacher_code'] as String?,
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'institution_id': institutionId,
        'role': role.name,
        'full_name': fullName,
        'student_code': studentCode,
        'teacher_code': teacherCode,
      };
}
