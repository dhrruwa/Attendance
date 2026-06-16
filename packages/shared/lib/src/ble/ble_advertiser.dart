import 'dart:async';
import 'dart:convert';

import 'package:ble_peripheral/ble_peripheral.dart';

import '../config/app_config.dart';

/// Teacher-side BLE peripheral.
///
/// Per the Step-One findings (see README), the rotating token is NOT placed in
/// the advertisement payload — iOS rejects manufacturer/service data in
/// foreground ads and the iOS->Android ad-discovery path is unreliable. Instead:
///   1. Advertise a FIXED service UUID so any student (Android or iOS) can find
///      the teacher and measure RSSI.
///   2. Expose the *current* rotating token via a readable GATT characteristic.
///      The student connects and reads it. This works in all four OS combos.
///
/// Designed for FOREGROUND use only (iOS does not advertise reliably in the
/// background, and the local name is dropped there).
class BleAdvertiser {
  BleAdvertiser();

  String _currentToken = '';
  String _sessionId = '';
  bool _initialized = false;
  bool _advertising = false;

  bool get isAdvertising => _advertising;

  /// The token currently served to readers. Update this on every rotation.
  set currentToken(String value) => _currentToken = value;
  String get currentToken => _currentToken;

  /// Initializes the peripheral stack and registers the GATT service + read
  /// callback. Idempotent.
  Future<void> initialize() async {
    if (_initialized) return;
    await BlePeripheral.initialize();

    // Serve the current token / session id dynamically on each read.
    BlePeripheral.setReadRequestCallback(
      (deviceId, characteristicId, offset, value) {
        final id = characteristicId.toLowerCase();
        if (id == BleContract.tokenCharacteristicUuid.toLowerCase()) {
          return ReadRequestResult(value: utf8.encode(_currentToken));
        }
        if (id == BleContract.sessionIdCharacteristicUuid.toLowerCase()) {
          return ReadRequestResult(value: utf8.encode(_sessionId));
        }
        return ReadRequestResult(value: utf8.encode(''));
      },
    );

    await BlePeripheral.addService(
      BleService(
        uuid: BleContract.beaconServiceUuid,
        primary: true,
        characteristics: [
          BleCharacteristic(
            uuid: BleContract.tokenCharacteristicUuid,
            properties: [CharacteristicProperties.read.index],
            permissions: [AttributePermissions.readable.index],
            value: null,
          ),
          BleCharacteristic(
            uuid: BleContract.sessionIdCharacteristicUuid,
            properties: [CharacteristicProperties.read.index],
            permissions: [AttributePermissions.readable.index],
            value: null,
          ),
        ],
      ),
    );
    _initialized = true;
  }

  /// Starts advertising the session. Call [initialize] first.
  Future<void> start({
    required String sessionId,
    required String initialToken,
  }) async {
    await initialize();
    _sessionId = sessionId;
    _currentToken = initialToken;
    await BlePeripheral.startAdvertising(
      services: [BleContract.beaconServiceUuid],
      // Short local name kept under the iOS foreground ad budget; not relied on
      // for correctness, only as a human-readable hint during debugging.
      localName: 'attend',
    );
    _advertising = true;
  }

  Future<void> stop() async {
    if (!_advertising) return;
    await BlePeripheral.stopAdvertising();
    _advertising = false;
  }

  /// Whether the BLE adapter is powered on / advertising is supported.
  Future<bool> isSupported() async {
    try {
      return await BlePeripheral.isSupported();
    } catch (_) {
      return false;
    }
  }
}
