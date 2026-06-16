/// Shared constants for the probe. These mirror the production BleContract so
/// the probe exercises the exact UUIDs the apps will use.
class ProbeConstants {
  static const String serviceUuid = '8e7f1a90-2b6c-4d3e-9f10-a1b2c3d4e5f6';
  static const String tokenCharUuid = '8e7f1a91-2b6c-4d3e-9f10-a1b2c3d4e5f6';

  /// Manufacturer id used when testing manufacturer-data advertising on Android.
  /// 0xFFFF is the "test" company id reserved for internal use.
  static const int testManufacturerId = 0xFFFF;

  /// Rotation cadence for the probe value.
  static const Duration rotation = Duration(seconds: 5);
}
