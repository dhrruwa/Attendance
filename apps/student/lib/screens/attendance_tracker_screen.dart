import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../student_providers.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _fmtDateTime(DateTime dt) {
  final l = dt.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final m = l.minute.toString().padLeft(2, '0');
  final ampm = l.hour < 12 ? 'AM' : 'PM';
  return '${_months[l.month - 1]} ${l.day}, $h:$m $ampm';
}

/// History of the signed-in student's own attendance records (RLS scopes this
/// to their rows only). Shows subject, when it was marked, and the outcome.
class AttendanceTrackerScreen extends ConsumerWidget {
  const AttendanceTrackerScreen({super.key, required this.student});
  final AppUser student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync =
        ref.watch(studentAttendanceHistoryProvider(student.id));
    return historyAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (rows) {
        if (rows.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(studentAttendanceHistoryProvider(student.id)),
            child: ListView(
              children: const [
                SizedBox(height: 120),
                Center(child: Text('No attendance records yet.')),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(studentAttendanceHistoryProvider(student.id)),
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => _HistoryTile(entry: rows[i]),
          ),
        );
      },
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});
  final AttendanceHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (entry.status) {
      AttendanceStatus.present => (Icons.check_circle, Colors.green, 'Present'),
      AttendanceStatus.flagged => (Icons.flag, Colors.orange, 'Under review'),
      AttendanceStatus.absent => (Icons.cancel, Colors.red, 'Absent'),
    };
    final title = entry.courseCode != null
        ? '${entry.courseName} (${entry.courseCode})'
        : entry.courseName;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('Marked: ${_fmtDateTime(entry.markedAt)}'),
      trailing: Text(label, style: TextStyle(color: color)),
    );
  }
}
