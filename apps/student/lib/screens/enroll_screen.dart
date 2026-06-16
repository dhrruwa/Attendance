import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../face/face_enrollment.dart';
import '../face/liveness_capture.dart';
import '../permissions.dart';
import '../student_providers.dart';

/// One-time face enrollment: capture a clear face, compute the embedding, store
/// it locally. Matching at attendance time compares against this template.
class EnrollScreen extends ConsumerStatefulWidget {
  const EnrollScreen(
      {super.key, required this.student, required this.onEnrolled});
  final AppUser student;
  final VoidCallback onEnrolled;

  @override
  ConsumerState<EnrollScreen> createState() => _EnrollScreenState();
}

class _EnrollScreenState extends ConsumerState<EnrollScreen> {
  final LivenessCapture _capture = LivenessCapture();
  bool _ready = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ok = await StudentPermissions.requestCamera();
    if (!ok) {
      setState(() => _error = 'Camera permission is required to enroll.');
      return;
    }
    await _capture.initialize();
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _enroll() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _capture.captureOnce();
      if (!result.faceDetected) {
        throw StateError('No face detected — try again in good lighting.');
      }
      final matcher = await ref.read(faceMatcherProvider.future);
      final embedding = await matcher.embed(result.faceCrop);
      await FaceEnrollment.save(widget.student.id, embedding);
      await _capture.dispose();
      widget.onEnrolled();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _capture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enroll your face')),
      body: Column(
        children: [
          Expanded(
            child: _ready && _capture.controller != null
                ? CameraPreview(_capture.controller!)
                : Center(
                    child: _error != null
                        ? Text(_error!)
                        : const CircularProgressIndicator()),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'Look straight at the camera in good lighting, then capture.',
                  textAlign: TextAlign.center,
                ),
                if (_error != null && _ready)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: (!_ready || _busy) ? null : _enroll,
                  icon: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.camera_alt),
                  label: const Text('Capture & enroll'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
