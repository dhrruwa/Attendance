class Course {
  const Course({
    required this.id,
    required this.institutionId,
    required this.teacherId,
    required this.name,
    this.code,
    this.createdAt,
  });

  final String id;
  final String institutionId;
  final String teacherId;
  final String name;
  final String? code;
  final DateTime? createdAt;

  factory Course.fromJson(Map<String, dynamic> json) => Course(
        id: json['id'] as String,
        institutionId: json['institution_id'] as String,
        teacherId: json['teacher_id'] as String,
        name: json['name'] as String,
        code: json['code'] as String?,
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'institution_id': institutionId,
        'teacher_id': teacherId,
        'name': name,
        'code': code,
      };
}
