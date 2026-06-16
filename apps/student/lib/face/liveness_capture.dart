import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:shared/shared.dart';

import 'camera_input_converter.dart';

class LivenessResult {
  LivenessResult({
    required this.faceCrop,
    required this.challenge,
    required this.challengePassed,
    required this.faceDetected,
  });

  /// Cropped, upright face for embedding + spoof scoring.
  final img.Image faceCrop;
  final ChallengeType challenge;
  final bool challengePassed;
  final bool faceDetected;
}

/// Owns the front camera + ML Kit detector and runs a randomized active liveness
/// challenge against the live stream, then captures a still face crop.
class LivenessCapture {
  LivenessCapture();

  CameraController? _controller;
  CameraDescription? _camera;
  CameraInputConverter? _converter;
  FaceDetector? _detector;
  bool _processing = false;

  /// UI feedback.
  final ValueNotifier<String> message = ValueNotifier('Position your face');
  final ValueNotifier<bool> faceInFrame = ValueNotifier(false);

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  Future<void> initialize() async {
    final cameras = await availableCameras();
    _camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    _controller = CameraController(
      _camera!,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    await _controller!.initialize();
    _converter = CameraInputConverter(_camera!);
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true, // smile + eye-open probabilities
        enableTracking: true,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
  }

  /// Runs the [challenge] against the live stream. Resolves when satisfied, or
  /// times out (challengePassed=false) after [timeout].
  Future<LivenessResult> run(
    ChallengeType challenge, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final completer = Completer<bool>();
    var sawNeutralEyes = false; // for blink: must open before closing

    Future<void> onImage(CameraImage image) async {
      if (_processing || completer.isCompleted) return;
      _processing = true;
      try {
        final input = _converter!.toInputImage(
          image,
          _controller!.value.deviceOrientation,
        );
        if (input == null) return;
        final faces = await _detector!.processImage(input);
        faceInFrame.value = faces.isNotEmpty;
        if (faces.isEmpty) {
          message.value = 'No face detected';
          return;
        }
        if (faces.length > 1) {
          message.value = 'Only one face allowed';
          return;
        }
        final face = faces.first;
        message.value = challenge.prompt;

        final satisfied = switch (challenge) {
          ChallengeType.blink =>
            _checkBlink(face, () => sawNeutralEyes, (v) => sawNeutralEyes = v),
          ChallengeType.smile => (face.smilingProbability ?? 0) > 0.7,
          ChallengeType.turnLeft => (face.headEulerAngleY ?? 0).abs() > 20,
          ChallengeType.turnRight => (face.headEulerAngleY ?? 0).abs() > 20,
        };
        if (satisfied && !completer.isCompleted) {
          completer.complete(true);
        }
      } catch (_) {
        // swallow per-frame errors
      } finally {
        _processing = false;
      }
    }

    await _controller!.startImageStream(onImage);

    bool passed;
    try {
      passed = await completer.future.timeout(timeout, onTimeout: () => false);
    } finally {
      await _safeStopStream();
    }

    final crop = await _captureFaceCrop();
    return LivenessResult(
      faceCrop: crop.faceCrop,
      challenge: challenge,
      challengePassed: passed,
      faceDetected: crop.faceDetected,
    );
  }

  /// One-shot capture used for enrollment: no active challenge, just grab a
  /// still and crop the largest face.
  Future<LivenessResult> captureOnce(
      {ChallengeType tag = ChallengeType.blink}) async {
    await _safeStopStream();
    final crop = await _captureFaceCrop();
    return LivenessResult(
      faceCrop: crop.faceCrop,
      challenge: tag,
      challengePassed: crop.faceDetected,
      faceDetected: crop.faceDetected,
    );
  }

  bool _checkBlink(
    Face face,
    bool Function() sawNeutral,
    void Function(bool) setNeutral,
  ) {
    final left = face.leftEyeOpenProbability ?? 1.0;
    final right = face.rightEyeOpenProbability ?? 1.0;
    if (left > 0.8 && right > 0.8) {
      setNeutral(true);
    }
    final closed = left < 0.2 && right < 0.2;
    return sawNeutral() && closed;
  }

  /// Stops the stream, takes a still, decodes + crops the largest face.
  Future<({img.Image faceCrop, bool faceDetected})> _captureFaceCrop() async {
    final file = await _controller!.takePicture();
    final bytes = await File(file.path).readAsBytes();
    var decoded = img.decodeImage(bytes);
    decoded ??= img.Image(width: 112, height: 112);

    // Detect the face on the still to crop tightly.
    try {
      final still = await _detector!.processImage(
        InputImage.fromFilePath(file.path),
      );
      if (still.isNotEmpty) {
        final box = still.first.boundingBox;
        final x = box.left.clamp(0, decoded.width - 1).toInt();
        final y = box.top.clamp(0, decoded.height - 1).toInt();
        final w = box.width.clamp(1, decoded.width - x).toInt();
        final h = box.height.clamp(1, decoded.height - y).toInt();
        final crop = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
        return (faceCrop: crop, faceDetected: true);
      }
    } catch (_) {/* fall through to center crop */}

    // Fallback: center square crop.
    final side =
        decoded.width < decoded.height ? decoded.width : decoded.height;
    final crop = img.copyCrop(
      decoded,
      x: (decoded.width - side) ~/ 2,
      y: (decoded.height - side) ~/ 2,
      width: side,
      height: side,
    );
    return (faceCrop: crop, faceDetected: false);
  }

  Future<void> _safeStopStream() async {
    try {
      if (_controller?.value.isStreamingImages ?? false) {
        await _controller!.stopImageStream();
      }
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _safeStopStream();
    await _controller?.dispose();
    await _detector?.close();
    _controller = null;
    _detector = null;
  }
}
