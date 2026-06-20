import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import 'attendance_tracker_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';

/// Which bottom-nav tab is selected. A Notifier so any tab can switch tabs
/// (e.g. the Mark tab nudging an un-enrolled student to Profile). StateProvider
/// is not exported by default in Riverpod 3.x, so we use a tiny Notifier.
class _SelectedTab extends Notifier<int> {
  @override
  int build() => 0;
  void set(int i) => state = i;
}

final selectedTabProvider = NotifierProvider<_SelectedTab, int>(_SelectedTab.new);

/// The signed-in student's main app: Mark Attendance · Attendance Tracker ·
/// Profile, behind a bottom navigation bar.
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.student});
  final AppUser student;

  static const _titles = ['Mark Attendance', 'Attendance Tracker', 'Profile'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(selectedTabProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[index]),
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
      body: IndexedStack(
        index: index,
        children: [
          MarkTab(student: student),
          AttendanceTrackerScreen(student: student),
          ProfileScreen(student: student),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) =>
            ref.read(selectedTabProvider.notifier).set(i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.how_to_reg_outlined),
              selectedIcon: Icon(Icons.how_to_reg),
              label: 'Mark'),
          NavigationDestination(
              icon: Icon(Icons.fact_check_outlined),
              selectedIcon: Icon(Icons.fact_check),
              label: 'Tracker'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile'),
        ],
      ),
    );
  }
}
