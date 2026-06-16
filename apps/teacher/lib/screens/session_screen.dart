import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared/shared.dart';

import '../session_controller.dart';
import 'flag_review_screen.dart';

class SessionScreen extends ConsumerStatefulWidget {
  const SessionScreen({super.key, required this.teacher, required this.course});
  final AppUser teacher;
  final Course course;

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  Future<void> _ensurePermissions() async {
    await [
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.locationWhenInUse,
    ].request();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(teacherSessionControllerProvider);
    final controller = ref.read(teacherSessionControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course.name),
        actions: [
          if (state.isActive)
            TextButton.icon(
              onPressed: () async {
                await controller.end();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Session ended.')),
                  );
                }
              },
              icon: const Icon(Icons.stop_circle, color: Colors.white),
              label: const Text('End', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: state.isActive ? _activeView(state) : _startView(state, controller),
    );
  }

  Widget _startView(
      TeacherSessionState state, TeacherSessionController controller) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_tethering, size: 64),
          const SizedBox(height: 16),
          Text(
            'Start an attendance session for ${widget.course.name}. '
            'Your phone will advertise a rotating token over BLE for students '
            'in the room to capture. Keep this screen in the foreground.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(state.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          FilledButton.icon(
            onPressed: state.starting
                ? null
                : () async {
                    await _ensurePermissions();
                    await controller.start(
                      courseId: widget.course.id,
                      teacherId: widget.teacher.id,
                    );
                  },
            icon: state.starting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow),
            label: const Text('Start session'),
          ),
        ],
      ),
    );
  }

  Widget _activeView(TeacherSessionState state) {
    final session = state.session!;
    final rosterAsync = ref.watch(rosterProvider(session.id));

    return Column(
      children: [
        Card(
          margin: const EdgeInsets.all(12),
          color: Colors.teal.shade50,
          child: ListTile(
            leading: const Icon(Icons.podcasts, color: Colors.teal),
            title: const Text('Advertising token (rotates ~5s)'),
            subtitle: Text(
              state.currentToken ?? '—',
              style: const TextStyle(fontSize: 24, letterSpacing: 2),
            ),
            trailing: IconButton(
              tooltip: 'Review flagged',
              icon: const Icon(Icons.flag),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FlagReviewScreen(sessionId: session.id),
                ),
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Live roster',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
        Expanded(
          child: rosterAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (rows) {
              if (rows.isEmpty) {
                return const Center(child: Text('No submissions yet.'));
              }
              return ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => _RosterTile(att: rows[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RosterTile extends StatelessWidget {
  const _RosterTile({required this.att});
  final Attendance att;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (att.status) {
      AttendanceStatus.present => (Icons.check_circle, Colors.green, 'Present'),
      AttendanceStatus.flagged => (Icons.flag, Colors.orange, 'Flagged'),
      AttendanceStatus.absent => (Icons.cancel, Colors.red, 'Absent'),
    };
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(att.studentId),
      subtitle: Text(att.reason ?? label),
      trailing: Text('RSSI ${att.rssi ?? '—'}'),
    );
  }
}
