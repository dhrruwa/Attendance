/// Runtime configuration for the apps.
///
/// Values are injected at launch via `--dart-define` (see README). We avoid
/// bundling secrets in source. The Supabase anon key is *publishable* (it is
/// gated by Row Level Security), so it is safe to pass via dart-define.
class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
  });

  final String supabaseUrl;
  final String supabaseAnonKey;

  /// Reads configuration from compile-time environment.
  ///
  /// Run with:
  ///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
  factory AppConfig.fromEnvironment() {
    const url = String.fromEnvironment('SUPABASE_URL');
    const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
    return const AppConfig(supabaseUrl: url, supabaseAnonKey: anonKey);
  }

  bool get isValid => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}

/// The single BLE service UUID family used for session discovery.
///
/// The teacher advertises [beaconServiceUuidBase]. The rotating token is NOT
/// embedded in the advertisement (iOS forbids manufacturer/service data in
/// peripheral ads — see README BLE findings); instead it is delivered via a
/// GATT characteristic read after discovery. These constants are the contract
/// shared by both apps and the probe harness.
class BleContract {
  /// Fixed 128-bit service UUID advertised by every active session so students
  /// can discover the teacher. Per-session uniqueness comes from the GATT token,
  /// not the service UUID (keeps iOS foreground advertising within its 28-byte
  /// budget and works in the iOS->Android direction).
  static const String beaconServiceUuid =
      '8e7f1a90-2b6c-4d3e-9f10-a1b2c3d4e5f6';

  /// GATT characteristic (under [beaconServiceUuid]) that returns the current
  /// rotating token as UTF-8 bytes when read by a connected central.
  static const String tokenCharacteristicUuid =
      '8e7f1a91-2b6c-4d3e-9f10-a1b2c3d4e5f6';

  /// Optional characteristic exposing the session id (UTF-8) so a student can
  /// confirm which session they discovered before submitting.
  static const String sessionIdCharacteristicUuid =
      '8e7f1a92-2b6c-4d3e-9f10-a1b2c3d4e5f6';

  /// How often the teacher rotates the token (must match session_tokens cadence).
  static const Duration tokenRotation = Duration(seconds: 5);
}
