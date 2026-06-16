// hide Session: our domain `Session` model shadows gotrue's auth Session here.
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../models/course.dart';
import '../models/session.dart';

class CourseRepository {
  CourseRepository(this._client);
  final SupabaseClient _client;

  /// Courses taught by [teacherId].
  Future<List<Course>> coursesForTeacher(String teacherId) async {
    final rows = await _client
        .from('courses')
        .select()
        .eq('teacher_id', teacherId)
        .order('name');
    return rows.map(Course.fromJson).toList();
  }

  /// Courses [studentId] is enrolled in (via the `enrollments` join).
  Future<List<Course>> coursesForStudent(String studentId) async {
    final rows = await _client
        .from('enrollments')
        .select('course:courses(*)')
        .eq('student_id', studentId);
    return rows
        .map((r) =>
            Course.fromJson((r['course'] as Map).cast<String, dynamic>()))
        .toList();
  }

  /// The currently-open session for [courseId], if any.
  Future<Session?> openSessionForCourse(String courseId) async {
    final rows = await _client
        .from('sessions')
        .select()
        .eq('course_id', courseId)
        .eq('status', 'open')
        .order('started_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    final s = Session.fromJson(rows.first);
    return s.isOpen ? s : null;
  }
}
