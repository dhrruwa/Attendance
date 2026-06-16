import 'dart:math';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'model_assets.dart';

/// Computes a face embedding from a cropped, aligned face image.
///
/// Production path: MobileFaceNet TFLite (112×112×3 → 192-d). If the model asset
/// is absent the factory returns [StubFaceMatcher] so the app still runs; the
/// evidence is tagged with [modelVersion] so the server can tell stub from real.
abstract class FaceMatcher {
  String get modelVersion;
  Future<List<double>> embed(img.Image faceCrop);
  void dispose() {}
}

class FaceMatcherFactory {
  static Future<FaceMatcher> create() async {
    if (await ModelAssets.hasFaceModel()) {
      try {
        final interpreter = await Interpreter.fromAsset(ModelAssets.faceModel);
        return TfliteFaceMatcher(interpreter);
      } catch (_) {
        return StubFaceMatcher();
      }
    }
    return StubFaceMatcher();
  }
}

class TfliteFaceMatcher implements FaceMatcher {
  TfliteFaceMatcher(this._interpreter);
  final Interpreter _interpreter;

  static const int _size = 112;
  static const int _embeddingDim = 192;

  @override
  String get modelVersion => 'mobilefacenet-tflite';

  @override
  Future<List<double>> embed(img.Image faceCrop) async {
    final resized = img.copyResize(faceCrop, width: _size, height: _size);

    // [1, 112, 112, 3] float32 normalized to [-1, 1].
    final input = List.generate(
      1,
      (_) => List.generate(
        _size,
        (y) => List.generate(_size, (x) {
          final p = resized.getPixel(x, y);
          return [
            (p.r - 127.5) / 127.5,
            (p.g - 127.5) / 127.5,
            (p.b - 127.5) / 127.5,
          ];
        }),
      ),
    );

    final output = List.generate(1, (_) => List.filled(_embeddingDim, 0.0));
    _interpreter.run(input, output);
    return _l2normalize(output[0]);
  }

  @override
  void dispose() => _interpreter.close();
}

/// Deterministic placeholder embedding derived from a downscaled grayscale
/// signature of the image. Stable for the same face crop, different across
/// faces — enough for the pipeline to run before real models are dropped in.
class StubFaceMatcher implements FaceMatcher {
  @override
  String get modelVersion => 'stub';

  @override
  Future<List<double>> embed(img.Image faceCrop) async {
    const dim = 64;
    final small = img.copyResize(
      img.grayscale(faceCrop),
      width: 8,
      height: 8,
    );
    final vec = List<double>.filled(dim, 0);
    var i = 0;
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        vec[i++] = small.getPixel(x, y).luminanceNormalized.toDouble();
      }
    }
    return _l2normalize(vec);
  }

  @override
  void dispose() {}
}

List<double> _l2normalize(List<double> v) {
  var norm = 0.0;
  for (final x in v) {
    norm += x * x;
  }
  norm = sqrt(norm);
  if (norm == 0) return v;
  return v.map((x) => x / norm).toList();
}

/// Cosine similarity of two L2-normalized embeddings, mapped to [0, 1].
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) return 0;
  var dot = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
  }
  // a, b are unit vectors, so dot is in [-1, 1]; rescale to [0, 1].
  return ((dot + 1) / 2).clamp(0.0, 1.0);
}
