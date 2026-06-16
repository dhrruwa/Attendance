import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../config/app_config.dart';

/// A discovered teacher beacon plus the freshly read token.
class BeaconReading {
  const BeaconReading({
    required this.deviceId,
    required this.rssi,
    required this.token,
    required this.sessionId,
  });

  final String deviceId;
  final int rssi;
  final String token;
  final String sessionId;
}

/// Student-side BLE central.
///
/// Scans for the fixed session service UUID, captures RSSI from the scan result,
/// then connects and reads the current rotating token (and session id) from the
/// teacher's GATT characteristics. This is the mechanism validated by the probe
/// to survive all four OS combos.
class BleScanner {
  BleScanner();

  StreamSubscription<List<ScanResult>>? _sub;

  /// True if Bluetooth adapter is on.
  Future<bool> isAdapterOn() async {
    final state = await FlutterBluePlus.adapterState.first;
    return state == BluetoothAdapterState.on;
  }

  /// Scans up to [timeout] for the strongest beacon advertising our service
  /// UUID, then connects and reads token + session id. Returns null if none
  /// found. Picks the strongest RSSI to favour the nearest teacher.
  Future<BeaconReading?> findAndRead({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final serviceGuid = Guid(BleContract.beaconServiceUuid);

    ScanResult? best;
    final completer = Completer<void>();

    await _sub?.cancel();
    _sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final advertisesService =
            r.advertisementData.serviceUuids.contains(serviceGuid);
        if (!advertisesService) continue;
        if (best == null || r.rssi > best!.rssi) {
          best = r;
        }
      }
    });

    await FlutterBluePlus.startScan(
      withServices: [serviceGuid],
      timeout: timeout,
    );
    // Wait for the scan to finish (FlutterBluePlus auto-stops after timeout).
    final isScanningSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (!scanning && !completer.isCompleted) completer.complete();
    });
    await completer.future;
    await isScanningSub.cancel();
    await _sub?.cancel();
    _sub = null;

    final target = best;
    if (target == null) return null;

    return _connectAndRead(target);
  }

  Future<BeaconReading?> _connectAndRead(ScanResult result) async {
    final device = result.device;
    try {
      // License.nonprofit per the FlutterBluePlus license (educational/nonprofit
      // use). Switch to License.commercial if this is deployed for-profit.
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 8),
      );
      final services = await device.discoverServices();
      final svc = services.firstWhere(
        (s) => s.uuid == Guid(BleContract.beaconServiceUuid),
        orElse: () => throw StateError('session service not found'),
      );

      String? token;
      String? sessionId;
      for (final c in svc.characteristics) {
        if (c.uuid == Guid(BleContract.tokenCharacteristicUuid)) {
          token = utf8.decode(await c.read());
        } else if (c.uuid == Guid(BleContract.sessionIdCharacteristicUuid)) {
          sessionId = utf8.decode(await c.read());
        }
      }

      if (token == null || token.isEmpty) return null;
      return BeaconReading(
        deviceId: device.remoteId.str,
        rssi: result.rssi,
        token: token,
        sessionId: sessionId ?? '',
      );
    } finally {
      try {
        await device.disconnect();
      } catch (_) {
        /* ignore disconnect errors */
      }
    }
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }
}
