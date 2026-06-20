import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists the enrolled face embedding on-device (privacy-preserving: the raw
/// template never leaves the phone; matching happens locally). Keyed by user id.
///
/// Also stores a small display photo (base64 JPEG) for the Profile screen — this
/// is the reference image the student "verifies" against; at attendance time the
/// live face is matched against the embedding derived from it.
class FaceEnrollment {
  static String _key(String userId) => 'attendance.face_template.$userId';
  static String _photoKey(String userId) => 'attendance.face_photo.$userId';

  static Future<void> save(String userId, List<double> embedding) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(userId), embedding.join(','));
  }

  static Future<List<double>?> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(userId));
    if (raw == null || raw.isEmpty) return null;
    return raw.split(',').map(double.parse).toList();
  }

  static Future<bool> isEnrolled(String userId) async =>
      (await load(userId)) != null;

  /// Stores the reference photo (JPEG bytes) for display.
  static Future<void> savePhoto(String userId, Uint8List jpeg) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_photoKey(userId), base64Encode(jpeg));
  }

  static Future<Uint8List?> loadPhoto(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_photoKey(userId));
    if (raw == null || raw.isEmpty) return null;
    return base64Decode(raw);
  }

  static Future<void> clear(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(userId));
    await prefs.remove(_photoKey(userId));
  }
}
