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

  /// Connects and reads, retrying the WHOLE sequence on transient BLE failures
  /// (`readCharacteristic() returned false`, timeouts, GATT 133) — budget
  /// Android centrals routinely fail the first attempt and succeed on a fresh
  /// connection.
  Future<BeaconReading?> _connectAndRead(ScanResult result) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await _attemptConnectAndRead(result);
      } catch (e) {
        lastError = e;
        try {
          await result.device.disconnect();
        } catch (_) {/* ignore */}
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    }
    if (lastError != null) throw lastError;
    return null;
  }

  Future<BeaconReading?> _attemptConnectAndRead(ScanResult result) async {
    final device = result.device;
    try {
      // A leftover connection from a previous attempt (or a killed app) wedges
      // the Android GATT stack and makes subsequent reads fail. Clear it.
      if (device.isConnected) {
        await device.disconnect();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }

      // License.nonprofit per the FlutterBluePlus license (educational/nonprofit
      // use). Switch to License.commercial if this is deployed for-profit.
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 10),
      );
      // High priority + a settle delay before discovery/reads. Reading too early
      // is the most common cause of `readCharacteristic returned false` and
      // intermittent read timeouts on Android.
      try {
        await device.requestConnectionPriority(
          connectionPriorityRequest: ConnectionPriority.high,
        );
      } catch (_) {/* android-only / best-effort */}
      await Future<void>.delayed(const Duration(milliseconds: 600));

      final services = await device.discoverServices();
      final svc = services.firstWhere(
        (s) => s.uuid == Guid(BleContract.beaconServiceUuid),
        orElse: () => throw StateError('session service not found'),
      );

      String? token;
      String? sessionId;
      for (final c in svc.characteristics) {
        if (c.uuid == Guid(BleContract.tokenCharacteristicUuid)) {
          token = utf8.decode(await _readWithRetry(c));
        } else if (c.uuid == Guid(BleContract.sessionIdCharacteristicUuid)) {
          sessionId = utf8.decode(await _readWithRetry(c));
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

  /// Reads a characteristic, retrying once on a transient timeout — Android's
  /// GATT stack occasionally drops the first read of a freshly-made connection.
  Future<List<int>> _readWithRetry(BluetoothCharacteristic c) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await c.read(timeout: 12);
      } catch (e) {
        if (attempt >= 1) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 400));
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
