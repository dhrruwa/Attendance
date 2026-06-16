import 'package:permission_handler/permission_handler.dart';

/// Requests the runtime permissions BLE needs on Android 12+ and iOS.
class BlePermissions {
  static Future<bool> request() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    // On iOS only bluetooth is relevant; missing Android-only perms resolve as
    // granted/limited. Treat as success if none are permanently denied.
    return !statuses.values.any((s) => s.isPermanentlyDenied);
  }
}
