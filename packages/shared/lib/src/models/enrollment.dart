class Enrollment {
  const Enrollment({
    required this.id,
    required this.courseId,
    required this.studentId,
    this.createdAt,
  });

  final String id;
  final String courseId;
  final String studentId;
  final DateTime? createdAt;

  factory Enrollment.fromJson(Map<String, dynamic> json) => Enrollment(
        id: json['id'] as String,
        courseId: json['course_id'] as String,
        studentId: json['student_id'] as String,
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'course_id': courseId,
        'student_id': studentId,
      };
}
