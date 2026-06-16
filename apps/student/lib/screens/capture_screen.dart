import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../attendance_submitter.dart';
import '../face/liveness_capture.dart';
import '../permissions.dart';
import 'result_screen.dart';

/// Full mark-attendance flow: randomized active liveness challenge -> on-device
/// face match + spoof score -> BLE scan for token + RSSI -> submit evidence.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen(
      {super.key, required this.student, required this.session});
  final AppUser student;
  final Session session;

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  final LivenessCapture _capture = LivenessCapture();
  late final ChallengeType _challenge =
      ChallengeType.values[Random().nextInt(ChallengeType.values.length)];

  bool _ready = false;
  bool _running = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ok = await StudentPermissions.requestAll();
    if (!ok) {
      setState(() => _error = 'Camera + Bluetooth permissions are required.');
      return;
    }
    await _capture.initialize();
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _start() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      // 1) Run the randomized active challenge on the live camera.
      final result = await _capture.run(_challenge);
      await _capture.dispose();

      // 2) Hand off to the submitter (match + scan + submit). The server decides.
      await ref.read(attendanceSubmitterProvider.notifier).run(
            student: widget.student,
            session: widget.session,
            liveness: result,
          );

      final flow = ref.read(attendanceSubmitterProvider);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            result: flow.result,
            error: flow.error,
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _error = '$e';
        _running = false;
      });
    }
  }

  @override
  void dispose() {
    _capture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(attendanceSubmitterProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mark attendance')),
      body: Column(
        children: [
          Expanded(
            child: _ready && _capture.controller != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(_capture.controller!),
                      Positioned(
                        bottom: 16,
                        left: 16,
                        right: 16,
                        child: ValueListenableBuilder<String>(
                          valueListenable: _capture.message,
                          builder: (_, msg, __) => _banner(msg),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: _error != null
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_error!, textAlign: TextAlign.center))
                        : const CircularProgressIndicator(),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('Challenge: ${_challenge.prompt}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (_running) _flowStatus(flow),
                if (_error != null && _ready)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: (!_ready || _running) ? null : _start,
                  icon: const Icon(Icons.verified_user),
                  label: const Text('Start verification'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _banner(String msg) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(msg,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
      );

  Widget _flowStatus(FlowState flow) {
    final label = switch (flow.step) {
      FlowStep.matching => 'Matching your face…',
      FlowStep.scanning => 'Looking for the classroom beacon…',
      FlowStep.submitting => 'Submitting to server…',
      _ => 'Verifying liveness…',
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}
