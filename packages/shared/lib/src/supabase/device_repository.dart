import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/device.dart';

/// Manages the one-active-device-per-user binding.
class DeviceRepository {
  DeviceRepository(this._client);
  final SupabaseClient _client;

  /// Returns the active device for [userId], or null if none bound yet.
  Future<Device?> activeDevice(String userId) async {
    final rows = await _client
        .from('devices')
        .select()
        .eq('user_id', userId)
        .eq('active', true)
        .limit(1);
    if (rows.isEmpty) return null;
    return Device.fromJson(rows.first);
  }

  /// Binds [deviceId] to [userId] as the active device on first run.
  ///
  /// If a different active device already exists, this throws — re-binding to a
  /// new phone is an administrative action (anti-proxy: you can't silently
  /// migrate your identity to a friend's phone). The server enforces the
  /// one-active-device invariant via a partial unique index.
  Future<Device> bindDevice({
    required String userId,
    required String deviceId,
    required String platform,
  }) async {
    final existing = await activeDevice(userId);
    if (existing != null) {
      if (existing.deviceId == deviceId) return existing;
      throw StateError(
        'Another device is already bound to this account. Contact your '
        'institution to reset device binding.',
      );
    }
    final row = await _client
        .from('devices')
        .insert({
          'user_id': userId,
          'device_id': deviceId,
          'platform': platform,
          'active': true,
        })
        .select()
        .single();
    return Device.fromJson(row);
  }

  /// Whether [deviceId] is the active bound device for [userId].
  Future<bool> isBoundDevice({
    required String userId,
    required String deviceId,
  }) async {
    final d = await activeDevice(userId);
    return d != null && d.deviceId == deviceId;
  }
}
