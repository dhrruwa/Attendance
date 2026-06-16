import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'model_assets.dart';

/// Passive anti-spoofing: scores how likely the captured face is a live person
/// vs a photo/screen replay, from a single frame. Production path: MiniFASNet
/// TFLite (80×80×3 → softmax; class 1 = real). Falls back to a permissive stub
/// when the model is absent (the active challenge still guards liveness).
abstract class SpoofDetector {
  /// 0..1, higher = more likely live.
  Future<double> score(img.Image faceCrop);
  bool get isStub;
  void dispose() {}
}

class SpoofDetectorFactory {
  static Future<SpoofDetector> create() async {
    if (await ModelAssets.hasSpoofModel()) {
      try {
        final interpreter = await Interpreter.fromAsset(ModelAssets.spoofModel);
        return TfliteSpoofDetector(interpreter);
      } catch (_) {
        return StubSpoofDetector();
      }
    }
    return StubSpoofDetector();
  }
}

class TfliteSpoofDetector implements SpoofDetector {
  TfliteSpoofDetector(this._interpreter);
  final Interpreter _interpreter;
  static const int _size = 80;

  @override
  bool get isStub => false;

  @override
  Future<double> score(img.Image faceCrop) async {
    final resized = img.copyResize(faceCrop, width: _size, height: _size);
    final input = List.generate(
      1,
      (_) => List.generate(
        _size,
        (y) => List.generate(_size, (x) {
          final p = resized.getPixel(x, y);
          return [p.r / 255.0, p.g / 255.0, p.b / 255.0];
        }),
      ),
    );
    // MiniFASNet outputs 3 logits/probs: [fake_2d, real, fake_3d] (varies by
    // export). We treat index 1 as the "real" class — adjust if your export
    // differs (see assets/models/README.md).
    final output = List.generate(1, (_) => List.filled(3, 0.0));
    _interpreter.run(input, output);
    final probs = _softmax(output[0]);
    return probs[1].clamp(0.0, 1.0);
  }

  @override
  void dispose() => _interpreter.close();

  List<double> _softmax(List<double> logits) {
    final maxL = logits.reduce((a, b) => a > b ? a : b);
    final exps = logits.map((l) => math.exp(l - maxL)).toList();
    final sum = exps.fold<double>(0, (a, b) => a + b);
    return exps.map((e) => e / sum).toList();
  }
}

/// Permissive placeholder — returns a high "live" score so the pipeline runs.
/// Liveness still depends on the randomized active challenge until the real
/// MiniFASNet model is dropped in.
class StubSpoofDetector implements SpoofDetector {
  @override
  bool get isStub => true;

  @override
  Future<double> score(img.Image faceCrop) async => 0.9;

  @override
  void dispose() {}
}
