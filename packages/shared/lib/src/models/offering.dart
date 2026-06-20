/// A subject in the catalog (reusable across sections).
class Subject {
  const Subject({required this.id, required this.name, this.code});
  final String id;
  final String name;
  final String? code;

  // id tolerant: embeds (subjects(code,name)) may omit it.
  factory Subject.fromJson(Map<String, dynamic> j) => Subject(
        id: (j['id'] as String?) ?? '',
        name: (j['name'] as String?) ?? 'Subject',
        code: j['code'] as String?,
      );
}

/// A student cohort (e.g. "CSE-A", semester 6).
class Section {
  const Section({required this.id, required this.name, this.semester, this.dept});
  final String id;
  final String name;
  final int? semester;
  final String? dept;

  /// "6th sem CSE-A"
  String get label {
    final sem = semester != null ? '${_ordinal(semester!)} sem ' : '';
    return '$sem$name';
  }

  // id tolerant: embeds (sections(name,semester,...)) may omit it.
  factory Section.fromJson(Map<String, dynamic> j) => Section(
        id: (j['id'] as String?) ?? '',
        name: (j['name'] as String?) ?? 'Section',
        semester: (j['semester'] as num?)?.toInt(),
        dept: j['dept'] as String?,
      );
}

String _ordinal(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}

/// A teacher teaching a subject to a section in a room — the unit attendance is
/// taken against. Carries joined subject + section for display.
class Offering {
  const Offering({
    required this.id,
    required this.subjectId,
    required this.sectionId,
    required this.teacherId,
    this.room,
    this.subject,
    this.section,
    this.studentCount,
  });

  final String id;
  final String subjectId;
  final String sectionId;
  final String teacherId;
  final String? room;
  final Subject? subject;
  final Section? section;
  final int? studentCount;

  String get subjectName => subject?.name ?? 'Subject';
  String? get subjectCode => subject?.code;
  String get sectionLabel => section?.label ?? 'Section';

  factory Offering.fromJson(Map<String, dynamic> j) {
    final subj = (j['subject'] as Map?)?.cast<String, dynamic>();
    final sec = (j['section'] as Map?)?.cast<String, dynamic>();
    return Offering(
      id: j['id'] as String,
      subjectId: j['subject_id'] as String,
      sectionId: j['section_id'] as String,
      teacherId: j['teacher_id'] as String,
      room: j['room'] as String?,
      subject: subj == null ? null : Subject.fromJson(subj),
      section: sec == null ? null : Section.fromJson(sec),
      studentCount: (j['student_count'] as num?)?.toInt(),
    );
  }
}

/// A weekly timetable slot for an offering.
class TimetableSlot {
  const TimetableSlot({
    required this.id,
    required this.offeringId,
    required this.weekday,
    required this.startTime,
    required this.endTime,
    this.room,
    this.offering,
  });

  final String id;
  final String offeringId;
  final int weekday; // 1=Mon..7=Sun
  final String startTime; // "09:00:00"
  final String endTime;
  final String? room;
  final Offering? offering;

  /// "09:00"
  String get startHm => startTime.length >= 5 ? startTime.substring(0, 5) : startTime;
  String get endHm => endTime.length >= 5 ? endTime.substring(0, 5) : endTime;

  factory TimetableSlot.fromJson(Map<String, dynamic> j) {
    final off = (j['offering'] as Map?)?.cast<String, dynamic>();
    return TimetableSlot(
      id: j['id'] as String,
      offeringId: j['offering_id'] as String,
      weekday: (j['weekday'] as num).toInt(),
      startTime: j['start_time'] as String,
      endTime: j['end_time'] as String,
      room: j['room'] as String?,
      offering: off == null ? null : Offering.fromJson(off),
    );
  }
}
