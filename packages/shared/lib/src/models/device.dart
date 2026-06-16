/// A device bound to a user. Exactly one active device per user is enforced by
/// a partial unique index server-side (see migration). Device binding is part
/// of the anti-proxy story: a student cannot submit from a phone that is not the
/// one bound to their account.
class Device {
  const Device({
    required this.id,
    required this.userId,
    required this.deviceId,
    required this.active,
    this.platform,
    this.boundAt,
  });

  final String id;
  final String userId;

  /// Stable per-install device identifier (see DeviceIdProvider in apps).
  final String deviceId;
  final bool active;
  final String? platform;
  final DateTime? boundAt;

  factory Device.fromJson(Map<String, dynamic> json) => Device(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        deviceId: json['device_id'] as String,
        active: (json['active'] as bool?) ?? true,
        platform: json['platform'] as String?,
        boundAt: json['bound_at'] == null
            ? null
            : DateTime.parse(json['bound_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'device_id': deviceId,
        'active': active,
        'platform': platform,
      };
}
