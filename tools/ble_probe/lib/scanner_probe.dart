import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'probe_constants.dart';

/// One observation of the advertiser, recording which channel(s) carried the
/// rotating value.
class ProbeObservation {
  ProbeObservation({
    required this.timestamp,
    required this.deviceId,
    required this.rssi,
    this.localNameValue,
    this.manufacturerValue,
    this.gattValue,
  });

  final DateTime timestamp;
  final String deviceId;
  final int rssi;

  /// Value parsed out of the advertised local name ("ATTN-XXXX" -> "XXXX").
  final String? localNameValue;

  /// Value parsed out of manufacturer data, if present (Android advertiser).
  final String? manufacturerValue;

  /// Value read from the GATT characteristic (after connecting).
  final String? gattValue;

  bool get gotLocalName => (localNameValue ?? '').isNotEmpty;
  bool get gotManufacturer => (manufacturerValue ?? '').isNotEmpty;
  bool get gotGatt => (gattValue ?? '').isNotEmpty;
}

/// Student-side probe. Scans for the service UUID, captures RSSI + advertised
/// channels, and (optionally) connects to read the GATT value.
class ScannerProbe {
  ScannerProbe({this.onObservation, this.onLog});
  final void Function(ProbeObservation obs)? onObservation;
  final void Function(String message)? onLog;

  StreamSubscription<List<ScanResult>>? _sub;
  bool _scanning = false;
  bool get isScanning => _scanning;

  void _log(String m) => onLog?.call(m);

  Future<void> start({bool readGatt = true}) async {
    final serviceGuid = Guid(ProbeConstants.serviceUuid);
    await _sub?.cancel();
    _sub = FlutterBluePlus.scanResults.listen((results) async {
      for (final r in results) {
        if (!r.advertisementData.serviceUuids.contains(serviceGuid)) continue;

        final name = r.advertisementData.advName;
        final localNameValue =
            name.startsWith('ATTN-') ? name.substring(5) : null;

        String? mfgValue;
        final mfg = r.advertisementData.manufacturerData;
        final bytes = mfg[ProbeConstants.testManufacturerId];
        if (bytes != null && bytes.isNotEmpty) {
          mfgValue = utf8.decode(bytes, allowMalformed: true);
        }

        String? gattValue;
        if (readGatt) {
          gattValue = await _tryReadGatt(r.device);
        }

        final obs = ProbeObservation(
          timestamp: DateTime.now(),
          deviceId: r.device.remoteId.str,
          rssi: r.rssi,
          localNameValue: localNameValue,
          manufacturerValue: mfgValue,
          gattValue: gattValue,
        );
        onObservation?.call(obs);
        _log(
          'obs rssi=${r.rssi} name=$localNameValue mfg=$mfgValue gatt=$gattValue',
        );
      }
    });

    await FlutterBluePlus.startScan(
      withServices: [serviceGuid],
      continuousUpdates: true,
      androidScanMode: AndroidScanMode.lowLatency,
    );
    _scanning = true;
    _log('Scanning started.');
  }

  Future<String?> _tryReadGatt(BluetoothDevice device) async {
    try {
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 6),
      );
      final services = await device.discoverServices();
      for (final s in services) {
        if (s.uuid != Guid(ProbeConstants.serviceUuid)) continue;
        for (final c in s.characteristics) {
          if (c.uuid == Guid(ProbeConstants.tokenCharUuid)) {
            final v = await c.read();
            return utf8.decode(v, allowMalformed: true);
          }
        }
      }
      return null;
    } catch (e) {
      _log('GATT read failed: $e');
      return null;
    } finally {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    _scanning = false;
    _log('Scanning stopped.');
  }
}
