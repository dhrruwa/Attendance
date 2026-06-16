import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// A stable, per-install device identifier.
///
/// Generated once and persisted in shared preferences. This is what gets bound
/// to the user account (one active device per user) and submitted in the
/// evidence; the server checks it against the bound device. Reinstalling the app
/// rotates it, which forces a re-bind — an intentional anti-proxy friction.
class DeviceId {
  static const _key = 'attendance.device_id';

  static Future<String> get() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_key);
    if (id == null) {
      id = _generate();
      await prefs.setString(_key, id);
    }
    return id;
  }

  static String platformLabel() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return Platform.operatingSystem;
  }

  static String _generate() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
