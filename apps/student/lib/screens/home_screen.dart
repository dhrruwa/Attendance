import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../student_providers.dart';
import 'capture_screen.dart';
import 'main_shell.dart';

String _fmtTime(DateTime? dt) {
  if (dt == null) return '—';
  final l = dt.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final m = l.minute.toString().padLeft(2, '0');
  return '$h:$m ${l.hour < 12 ? 'AM' : 'PM'}';
}

/// Mark-attendance tab: the student's subjects (offerings), with a prominent
/// card for any that has an open session right now.
class MarkTab extends ConsumerWidget {
  const MarkTab({super.key, required this.student});
  final AppUser student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offeringsAsync = ref.watch(studentOfferingsProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${student.fullName}  ·  ${student.studentCode ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
        Expanded(
          child: offeringsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (offerings) {
              if (offerings.isEmpty) {
                return const Center(child: Text('No subjects assigned.'));
              }
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(studentOfferingsProvider);
                  for (final o in offerings) {
                    ref.invalidate(openSessionProvider(o.id));
                  }
                },
                child: ListView(
                  children: [
                    for (final o in offerings)
                      _OfferingCard(student: student, offering: o),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OfferingCard extends ConsumerWidget {
  const _OfferingCard({required this.student, required this.offering});
  final AppUser student;
  final Offering offering;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(openSessionProvider(offering.id));
    return sessionAsync.when(
      loading: () => _shell(const ListTile(
        leading: Icon(Icons.menu_book),
        title: Text('Checking for an active session…'),
      )),
      error: (e, _) => _shell(ListTile(
        leading: const Icon(Icons.menu_book),
        title: Text(offering.subjectName),
        subtitle: Text('Error: $e'),
      )),
      data: (session) => session == null
          ? _inactive()
          : _ActiveSessionCard(
              student: student, offering: offering, session: session),
    );
  }

  Widget _inactive() => _shell(ListTile(
        leading: const Icon(Icons.menu_book_outlined, color: Colors.grey),
        title: Text(offering.subjectName),
        subtitle: Text('${offering.sectionLabel} · No active session'),
      ));

  Widget _shell(Widget child) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: child,
      );
}

class _ActiveSessionCard extends ConsumerWidget {
  const _ActiveSessionCard({
    required this.student,
    required this.offering,
    required this.session,
  });
  final AppUser student;
  final Offering offering;
  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final attKey = (sessionId: session.id, studentId: student.id);
    final att = ref.watch(myAttendanceProvider(attKey)).value;
    final marked = att != null;
    final enrolled = ref.watch(faceEnrolledProvider(student.id)).value ?? false;

    final (statusLabel, statusColor) = switch (att?.status) {
      AttendanceStatus.present => ('Marked · Present', Colors.green),
      AttendanceStatus.flagged => ('Marked · Under review', Colors.orange),
      AttendanceStatus.absent => ('Not present', Colors.red),
      null => ('Not Marked', theme.colorScheme.error),
    };

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      elevation: 3,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.sensors, size: 20),
              const SizedBox(width: 6),
              Text('ACTIVE SESSION',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 8),
            Text(offering.subjectName,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            _line(Icons.tag, 'Subject code', offering.subjectCode ?? '—'),
            _line(Icons.groups, 'Class', offering.sectionLabel),
            if (session.room != null) _line(Icons.room, 'Room', session.room!),
            _line(Icons.schedule, 'Started', _fmtTime(session.startedAt)),
            const SizedBox(height: 10),
            Row(children: [
              Icon(marked ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: statusColor, size: 18),
              const SizedBox(width: 6),
              Text(statusLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: statusColor, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 12),
            SizedBox(
                width: double.infinity,
                child: _actionButton(context, ref, marked, enrolled)),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(
      BuildContext context, WidgetRef ref, bool marked, bool enrolled) {
    if (marked) {
      return FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.done),
        label: const Text('Attendance submitted'),
      );
    }
    if (!enrolled) {
      return FilledButton.icon(
        icon: const Icon(Icons.add_a_photo),
        label: const Text('Add profile photo to mark'),
        onPressed: () => ref.read(selectedTabProvider.notifier).set(2),
      );
    }
    final attKey = (sessionId: session.id, studentId: student.id);
    return FilledButton.icon(
      icon: const Icon(Icons.how_to_reg),
      label: const Text('Mark Attendance'),
      onPressed: () async {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CaptureScreen(student: student, session: session),
        ));
        ref.invalidate(myAttendanceProvider(attKey));
        ref.invalidate(openSessionProvider(offering.id));
        ref.invalidate(studentAttendanceHistoryProvider(student.id));
      },
    );
  }

  Widget _line(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(child: Text(value)),
        ]),
      );
}
