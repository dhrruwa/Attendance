import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ble_peripheral/ble_peripheral.dart';

import 'probe_constants.dart';

/// Teacher-side probe. Advertises a value that rotates every 5s through THREE
/// channels simultaneously so the scanner can report which one survived:
///   (1) local name      -> `ATTN-<value>`
///   (2) manufacturer data (Android only; iOS silently drops it)
///   (3) GATT characteristic read (connect-then-read)
class AdvertiserProbe {
  AdvertiserProbe({this.onLog});
  final void Function(String message)? onLog;

  Timer? _timer;
  int _counter = 0;
  String _value = '';
  bool _initialized = false;
  bool _advertising = false;

  String get currentValue => _value;
  bool get isAdvertising => _advertising;

  void _log(String m) => onLog?.call(m);

  Future<void> initialize() async {
    if (_initialized) return;
    await BlePeripheral.initialize();

    BlePeripheral.setReadRequestCallback(
      (deviceId, characteristicId, offset, value) {
        if (characteristicId.toLowerCase() ==
            ProbeConstants.tokenCharUuid.toLowerCase()) {
          _log('GATT read from $deviceId -> "$_value"');
          return ReadRequestResult(value: utf8.encode(_value));
        }
        return ReadRequestResult(value: utf8.encode(''));
      },
    );

    await BlePeripheral.addService(
      BleService(
        uuid: ProbeConstants.serviceUuid,
        primary: true,
        characteristics: [
          BleCharacteristic(
            uuid: ProbeConstants.tokenCharUuid,
            properties: [CharacteristicProperties.read.index],
            permissions: [AttributePermissions.readable.index],
            value: null,
          ),
        ],
      ),
    );
    _initialized = true;
  }

  Future<void> start() async {
    await initialize();
    await _rotateAndAdvertise();
    _timer = Timer.periodic(ProbeConstants.rotation, (_) async {
      await _rotateAndAdvertise();
    });
    _advertising = true;
    _log('Advertising started.');
  }

  Future<void> _rotateAndAdvertise() async {
    _counter++;
    _value = _counter.toString().padLeft(4, '0');

    // Restart advertising with the new value in local name + manufacturer data.
    if (_advertising) {
      try {
        await BlePeripheral.stopAdvertising();
      } catch (_) {}
    }
    final mfg = Uint8List.fromList(utf8.encode(_value));
    try {
      await BlePeripheral.startAdvertising(
        services: [ProbeConstants.serviceUuid],
        localName: 'ATTN-$_value',
        manufacturerData: ManufacturerData(
          manufacturerId: ProbeConstants.testManufacturerId,
          data: mfg,
        ),
      );
    } on Object catch (e) {
      // iOS will reject manufacturer data — retry with name+service only so the
      // probe still advertises and we learn the platform difference.
      _log(
          'manufacturerData advertise failed ($e); retrying name+service only');
      await BlePeripheral.startAdvertising(
        services: [ProbeConstants.serviceUuid],
        localName: 'ATTN-$_value',
      );
    }
    _log('Rotated -> value=$_value (name+mfg+GATT)');
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    if (_advertising) {
      try {
        await BlePeripheral.stopAdvertising();
      } catch (_) {}
      _advertising = false;
      _log('Advertising stopped.');
    }
  }
}
