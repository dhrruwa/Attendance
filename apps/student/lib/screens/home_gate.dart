import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../student_providers.dart';
import 'device_bind_screen.dart';
import 'main_shell.dart';

enum GateState { needsBind, ready }

final gateStateProvider =
    FutureProvider.family<GateState, String>((ref, studentId) async {
  final deviceId = await ref.watch(deviceIdProvider.future);
  final bound = await ref
      .watch(deviceRepositoryProvider)
      .isBoundDevice(userId: studentId, deviceId: deviceId);
  if (!bound) return GateState.needsBind;
  return GateState.ready;
});

/// Routes a signed-in student through first-run device binding, then into the
/// tabbed app. Face enrollment is no longer a gate step — it lives in the
/// Profile tab (the student adds a photo there), and the Mark tab nudges them
/// to Profile if they haven't yet.
class HomeGate extends ConsumerWidget {
  const HomeGate({super.key, required this.student});
  final AppUser student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(gateStateProvider(student.id));
    return gate.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (state) => switch (state) {
        GateState.needsBind => DeviceBindScreen(
            student: student,
            onBound: () => ref.invalidate(gateStateProvider(student.id)),
          ),
        GateState.ready => MainShell(student: student),
      },
    );
  }
}
