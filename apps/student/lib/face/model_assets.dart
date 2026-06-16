import 'package:flutter/services.dart' show rootBundle;

/// Resolves whether the drop-in model binaries are present in the bundle.
class ModelAssets {
  static const faceModel = 'assets/models/mobilefacenet.tflite';
  static const spoofModel = 'assets/models/antispoof.tflite';

  static Future<bool> _exists(String path) async {
    try {
      await rootBundle.load(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasFaceModel() => _exists(faceModel);
  static Future<bool> hasSpoofModel() => _exists(spoofModel);
}
