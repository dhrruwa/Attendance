// hide Session: our domain Session shadows gotrue's auth Session here.
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../models/offering.dart';
import '../models/session.dart';

/// Offerings (subject × section × teacher) + timetable access.
class OfferingRepository {
  OfferingRepository(this._client);
  final SupabaseClient _client;

  // Count goes through sections (section_students FK is to sections, not
  // offerings — PostgREST can't embed it directly under offerings).
  static const _sel = '*, subject:subjects(code,name), '
      'section:sections(name,semester,dept,section_students(count))';

  /// All offerings a teacher teaches, with subject + section + student count.
  Future<List<Offering>> offeringsForTeacher(String teacherId) async {
    final rows = await _client
        .from('offerings')
        .select(_sel)
        .eq('teacher_id', teacherId);
    return rows.map(_withCount).toList();
  }

  /// Offerings the signed-in student belongs to (RLS limits rows to their
  /// sections).
  Future<List<Offering>> offeringsForStudent() async {
    final rows = await _client.from('offerings').select(_sel);
    return rows
        .map((r) => Offering.fromJson((r as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Today's scheduled offerings for a teacher (by ISO weekday), time-ordered.
  Future<List<TimetableSlot>> todaysOfferings(String teacherId) async {
    final weekday = _isoWeekday(DateTime.now());
    final rows = await _client
        .from('timetable')
        .select('*, offering:offerings!inner($_sel)')
        .eq('weekday', weekday)
        .eq('offering.teacher_id', teacherId)
        .order('start_time');
    return rows
        .map((r) => TimetableSlot.fromJson((r as Map).cast<String, dynamic>()))
        .toList();
  }

  /// The currently-open session for an offering, if any.
  Future<Session?> openSession(String offeringId) async {
    final rows = await _client
        .from('sessions')
        .select()
        .eq('offering_id', offeringId)
        .eq('status', 'open')
        .order('started_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return Session.fromJson(rows.first);
  }

  Offering _withCount(dynamic r) {
    final m = (r as Map).cast<String, dynamic>();
    // section.section_students(count) -> [{count: N}]
    final sec = (m['section'] as Map?)?.cast<String, dynamic>();
    final ssl = sec?['section_students'] as List?;
    final cnt = (ssl != null && ssl.isNotEmpty)
        ? (ssl.first as Map)['count'] as int?
        : null;
    m['student_count'] = cnt;
    return Offering.fromJson(m);
  }

  static int _isoWeekday(DateTime d) => d.weekday; // Dart: Mon=1..Sun=7
}
