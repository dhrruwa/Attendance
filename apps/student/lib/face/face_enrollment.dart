import 'package:shared_preferences/shared_preferences.dart';

/// Persists the enrolled face embedding on-device (privacy-preserving: the raw
/// template never leaves the phone; matching happens locally). Keyed by user id.
class FaceEnrollment {
  static String _key(String userId) => 'attendance.face_template.$userId';

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

  static Future<void> clear(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(userId));
  }
}
