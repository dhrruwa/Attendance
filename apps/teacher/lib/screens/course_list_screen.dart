import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import 'change_requests_screen.dart';
import 'session_screen.dart';

final teacherOfferingsProvider =
    FutureProvider.family<List<Offering>, String>((ref, teacherId) {
  return ref.watch(offeringRepositoryProvider).offeringsForTeacher(teacherId);
});

final todaysOfferingsProvider =
    FutureProvider.family<List<TimetableSlot>, String>((ref, teacherId) {
  return ref.watch(offeringRepositoryProvider).todaysOfferings(teacherId);
});

/// Teacher home: today's scheduled classes (one-tap start) + all classes the
/// teacher handles, grouped by subject. Scales to many subjects × sections.
class CourseListScreen extends ConsumerWidget {
  const CourseListScreen({super.key, required this.teacher});
  final AppUser teacher;

  void _open(BuildContext context, Offering o) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SessionScreen(teacher: teacher, offering: o),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offeringsAsync = ref.watch(teacherOfferingsProvider(teacher.id));
    final todayAsync = ref.watch(todaysOfferingsProvider(teacher.id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('My classes'),
        actions: [
          IconButton(
            tooltip: 'Profile change requests',
            icon: const Icon(Icons.edit_note),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const ChangeRequestsScreen(),
            )),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authRepositoryProvider).signOut();
              ref.invalidate(currentUserProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(teacherOfferingsProvider(teacher.id));
          ref.invalidate(todaysOfferingsProvider(teacher.id));
        },
        child: offeringsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [Center(child: Text('Error: $e'))]),
          data: (offerings) {
            if (offerings.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 120),
                Center(child: Text('No classes assigned.')),
              ]);
            }
            final bySubject = <String, List<Offering>>{};
            for (final o in offerings) {
              bySubject.putIfAbsent(o.subjectName, () => []).add(o);
            }
            return ListView(
              children: [
                _header('Today'),
                ...todayAsync.when(
                  loading: () => [const ListTile(title: Text('Loading…'))],
                  error: (e, _) => [ListTile(title: Text('Error: $e'))],
                  data: (slots) => slots.isEmpty
                      ? [
                          const ListTile(
                            dense: true,
                            title: Text('No classes scheduled today.'),
                          )
                        ]
                      : slots
                          .where((s) => s.offering != null)
                          .map((s) => _TodayTile(
                                slot: s,
                                onTap: () => _open(context, s.offering!),
                              ))
                          .toList(),
                ),
                const Divider(height: 24),
                _header('All my classes'),
                for (final entry in bySubject.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(entry.key,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  for (final o in entry.value)
                    ListTile(
                      leading: const Icon(Icons.groups),
                      title: Text(o.sectionLabel),
                      subtitle: Text([
                        if (o.subjectCode != null) o.subjectCode!,
                        if (o.studentCount != null) '${o.studentCount} students',
                        if (o.room != null) 'Room ${o.room}',
                      ].join('  ·  ')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(context, o),
                    ),
                ],
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
                letterSpacing: 1)),
      );
}

class _TodayTile extends StatelessWidget {
  const _TodayTile({required this.slot, required this.onTap});
  final TimetableSlot slot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final o = slot.offering!;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: ListTile(
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(slot.startHm, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(slot.endHm, style: const TextStyle(fontSize: 12)),
          ],
        ),
        title: Text('${o.subjectName} · ${o.sectionLabel}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(slot.room != null ? 'Room ${slot.room}' : ''),
        trailing: const Icon(Icons.play_circle_fill, color: Colors.indigo),
        onTap: onTap,
      ),
    );
  }
}
