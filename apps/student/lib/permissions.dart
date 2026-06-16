import 'package:permission_handler/permission_handler.dart';

/// Requests camera + BLE runtime permissions the student flow needs.
class StudentPermissions {
  static Future<bool> requestCamera() async {
    final s = await Permission.camera.request();
    return s.isGranted;
  }

  static Future<bool> requestBle() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    return !statuses.values.any((s) => s.isPermanentlyDenied);
  }

  static Future<bool> requestAll() async {
    final cam = await requestCamera();
    final ble = await requestBle();
    return cam && ble;
  }
}
