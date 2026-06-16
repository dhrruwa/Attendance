import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import 'face/face_enrollment.dart';
import 'face/face_matcher.dart';
import 'face/liveness_capture.dart';
import 'student_providers.dart';

/// Steps surfaced to the UI as the flow runs.
enum FlowStep { idle, matching, scanning, submitting, done, error }

class FlowState {
  const FlowState({
    this.step = FlowStep.idle,
    this.message = '',
    this.result,
    this.error,
  });
  final FlowStep step;
  final String message;
  final SubmitResult? result;
  final String? error;

  FlowState copy({
    FlowStep? step,
    String? message,
    SubmitResult? result,
    String? error,
  }) =>
      FlowState(
        step: step ?? this.step,
        message: message ?? this.message,
        result: result ?? this.result,
        error: error ?? this.error,
      );
}

/// Takes a completed [LivenessResult], does on-device face match + spoof score,
/// scans for the session beacon (token + RSSI), assembles the evidence object,
/// and submits it to `validate_attendance`. The device decides NOTHING — it
/// reports observations; the server rules present/flagged.
class AttendanceSubmitter extends Notifier<FlowState> {
  @override
  FlowState build() => const FlowState();

  Future<void> run({
    required AppUser student,
    required Session session,
    required LivenessResult liveness,
  }) async {
    try {
      // 1. Face match (on device).
      state = const FlowState(
          step: FlowStep.matching, message: 'Matching your face…');
      final matcher = await ref.read(faceMatcherProvider.future);
      final spoofDetector = await ref.read(spoofDetectorProvider.future);
      final deviceId = await ref.read(deviceIdProvider.future);

      final enrolled = await FaceEnrollment.load(student.id);
      if (enrolled == null) {
        throw StateError('No enrolled face template. Please enroll first.');
      }
      final liveEmbedding = await matcher.embed(liveness.faceCrop);
      final faceMatchScore = cosineSimilarity(liveEmbedding, enrolled);
      final spoofScore = await spoofDetector.score(liveness.faceCrop);

      // Local liveness verdict (server re-checks authoritatively).
      final livenessPassed = liveness.challengePassed &&
          liveness.faceDetected &&
          (spoofDetector.isStub || spoofScore >= 0.7);

      // 2. Scan for the beacon, read token + RSSI.
      state = state.copy(
          step: FlowStep.scanning,
          message: 'Looking for the classroom beacon…');
      await _ensureBluetoothOn();
      final scanner = BleScanner();
      final reading = await scanner.findAndRead();
      await scanner.dispose();
      if (reading == null) {
        throw StateError(
          'Could not find the session beacon. Are you in the classroom with '
          'Bluetooth on?',
        );
      }

      // 3. Build evidence + submit.
      state = state.copy(
          step: FlowStep.submitting, message: 'Submitting to server…');
      final evidence = Evidence(
        faceMatchScore: faceMatchScore,
        livenessPassed: livenessPassed,
        challengeType: liveness.challenge,
        challengePassed: liveness.challengePassed,
        passiveSpoofScore: spoofDetector.isStub ? null : spoofScore,
        bleToken: reading.token,
        rssi: reading.rssi,
        deviceId: deviceId,
        faceModelVersion: matcher.modelVersion,
        capturedAt: DateTime.now().toUtc(),
      );

      final result = await ref.read(attendanceRepositoryProvider).submit(
            sessionId: session.id,
            evidence: evidence,
          );
      state = FlowState(step: FlowStep.done, result: result);
    } catch (e) {
      state = FlowState(step: FlowStep.error, error: '$e');
    }
  }

  Future<void> _ensureBluetoothOn() async {
    final state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      throw StateError('Bluetooth is off. Turn it on and try again.');
    }
  }
}

final attendanceSubmitterProvider =
    NotifierProvider<AttendanceSubmitter, FlowState>(AttendanceSubmitter.new);
