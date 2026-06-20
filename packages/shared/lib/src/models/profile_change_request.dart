/// A student's request to edit their locked profile, awaiting teacher approval.
class ProfileChangeRequest {
  const ProfileChangeRequest({
    required this.id,
    required this.studentId,
    required this.status,
    this.reason,
    this.createdAt,
    this.studentName,
    this.studentCode,
  });

  final String id;
  final String studentId;
  final String status; // pending | approved | rejected
  final String? reason;
  final DateTime? createdAt;

  // Joined for the teacher inbox (not stored on the row).
  final String? studentName;
  final String? studentCode;

  bool get isPending => status == 'pending';

  factory ProfileChangeRequest.fromJson(Map<String, dynamic> json) {
    final student = (json['student'] as Map?)?.cast<String, dynamic>();
    return ProfileChangeRequest(
      id: json['id'] as String,
      studentId: json['student_id'] as String,
      status: json['status'] as String,
      reason: json['reason'] as String?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
      studentName: student?['full_name'] as String?,
      studentCode: student?['student_code'] as String?,
    );
  }
}
