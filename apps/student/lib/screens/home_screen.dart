import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../student_providers.dart';
import 'capture_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.student});
  final AppUser student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coursesAsync = ref.watch(studentCoursesProvider(student.id));
    return Scaffold(
      appBar: AppBar(
        title: const Text('My courses'),
        actions: [
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${student.fullName} (${student.studentCode})'),
            ),
          ),
          Expanded(
            child: coursesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (courses) {
                if (courses.isEmpty) {
                  return const Center(
                      child: Text('Not enrolled in any course.'));
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(studentCoursesProvider(student.id));
                    for (final c in courses) {
                      ref.invalidate(openSessionProvider(c.id));
                    }
                  },
                  child: ListView(
                    children: [
                      for (final c in courses)
                        _CourseCard(student: student, course: c),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseCard extends ConsumerWidget {
  const _CourseCard({required this.student, required this.course});
  final AppUser student;
  final Course course;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(openSessionProvider(course.id));
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: const Icon(Icons.class_),
        title: Text(course.name),
        subtitle: sessionAsync.when(
          loading: () => const Text('Checking for open session…'),
          error: (e, _) => Text('Error: $e'),
          data: (session) => Text(
            session != null ? 'Session open now' : 'No open session',
          ),
        ),
        trailing: sessionAsync.maybeWhen(
          data: (session) => session == null
              ? null
              : FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          CaptureScreen(student: student, session: session),
                    ),
                  ),
                  child: const Text('Mark'),
                ),
          orElse: () => null,
        ),
      ),
    );
  }
}
