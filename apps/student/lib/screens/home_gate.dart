import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../face/face_enrollment.dart';
import '../student_providers.dart';
import 'device_bind_screen.dart';
import 'enroll_screen.dart';
import 'home_screen.dart';

enum GateState { needsBind, needsEnroll, ready }

final gateStateProvider =
    FutureProvider.family<GateState, String>((ref, studentId) async {
  final deviceId = await ref.watch(deviceIdProvider.future);
  final bound = await ref
      .watch(deviceRepositoryProvider)
      .isBoundDevice(userId: studentId, deviceId: deviceId);
  if (!bound) return GateState.needsBind;
  if (!await FaceEnrollment.isEnrolled(studentId)) return GateState.needsEnroll;
  return GateState.ready;
});

/// Routes a signed-in student through first-run device binding and face
/// enrollment before reaching the home screen.
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
        GateState.needsEnroll => EnrollScreen(
            student: student,
            onEnrolled: () => ref.invalidate(gateStateProvider(student.id)),
          ),
        GateState.ready => HomeScreen(student: student),
      },
    );
  }
}
