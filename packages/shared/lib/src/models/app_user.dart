import 'enums.dart';

/// A row in `users`. Identified by Supabase auth uid (`id`). Carries a unique
/// human-facing code (`student_code` for students, `teacher_code` for teachers)
/// plus editable profile fields (phone, college_id).
class AppUser {
  const AppUser({
    required this.id,
    required this.institutionId,
    required this.role,
    required this.fullName,
    this.studentCode,
    this.teacherCode,
    this.phone,
    this.collegeId,
    this.profileLocked = false,
    this.editAllowed = false,
    this.createdAt,
  });

  final String id;
  final String institutionId;
  final UserRole role;
  final String fullName;
  final String? studentCode;
  final String? teacherCode;

  /// Editable profile fields (Profile tab).
  final String? phone;
  final String? collegeId;

  /// Locked after first save; only a teacher-approved request reopens editing.
  final bool profileLocked;

  /// True while a teacher-granted edit window is open (one save, then re-locks).
  final bool editAllowed;
  final DateTime? createdAt;

  /// Whether the student can edit locked profile fields right now.
  bool get canEditProfile => !profileLocked || editAllowed;

  /// The code relevant to this user's role (USN/SRN for students).
  String? get code => role == UserRole.teacher ? teacherCode : studentCode;

  AppUser copyWith({
    String? fullName,
    String? phone,
    String? collegeId,
  }) =>
      AppUser(
        id: id,
        institutionId: institutionId,
        role: role,
        fullName: fullName ?? this.fullName,
        studentCode: studentCode,
        teacherCode: teacherCode,
        phone: phone ?? this.phone,
        collegeId: collegeId ?? this.collegeId,
        createdAt: createdAt,
      );

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        institutionId: json['institution_id'] as String,
        role: UserRole.fromString(json['role'] as String),
        fullName: (json['full_name'] as String?) ?? '',
        studentCode: json['student_code'] as String?,
        teacherCode: json['teacher_code'] as String?,
        phone: json['phone'] as String?,
        collegeId: json['college_id'] as String?,
        profileLocked: (json['profile_locked'] as bool?) ?? false,
        editAllowed: (json['edit_allowed'] as bool?) ?? false,
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
        'phone': phone,
        'college_id': collegeId,
      };
}
