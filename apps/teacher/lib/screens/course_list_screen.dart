import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import 'session_screen.dart';

final teacherCoursesProvider =
    FutureProvider.family<List<Course>, String>((ref, teacherId) {
  return ref.watch(courseRepositoryProvider).coursesForTeacher(teacherId);
});

class CourseListScreen extends ConsumerWidget {
  const CourseListScreen({super.key, required this.teacher});
  final AppUser teacher;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coursesAsync = ref.watch(teacherCoursesProvider(teacher.id));
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
              child: Text('Signed in as ${teacher.fullName} '
                  '(${teacher.teacherCode})'),
            ),
          ),
          Expanded(
            child: coursesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (courses) {
                if (courses.isEmpty) {
                  return const Center(child: Text('No courses assigned.'));
                }
                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(teacherCoursesProvider(teacher.id)),
                  child: ListView.separated(
                    itemCount: courses.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = courses[i];
                      return ListTile(
                        leading: const Icon(Icons.class_),
                        title: Text(c.name),
                        subtitle: Text(c.code ?? ''),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                SessionScreen(teacher: teacher, course: c),
                          ),
                        ),
                      );
                    },
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
