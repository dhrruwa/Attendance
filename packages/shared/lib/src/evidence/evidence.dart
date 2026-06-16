import '../models/enums.dart';

/// The full evidence object submitted with an attendance attempt and stored in
/// `attendance.evidence` (jsonb). The **server** reads this to decide
/// present/flagged — the phone only reports observations, it never decides.
///
/// Includes live placeholders for `wifi_bssid`, `geo`, and `attestation` so the
/// server-side policy can tighten over time without a schema migration.
class Evidence {
  const Evidence({
    required this.faceMatchScore,
    required this.livenessPassed,
    required this.challengeType,
    required this.bleToken,
    required this.rssi,
    required this.deviceId,
    this.passiveSpoofScore,
    this.challengePassed = true,
    this.faceModelVersion,
    this.wifiBssid,
    this.geo,
    this.attestation,
    this.capturedAt,
  });

  /// Cosine similarity (0..1) between the live embedding and the enrolled one.
  final double faceMatchScore;

  /// Combined liveness verdict (passive model AND active challenge).
  final bool livenessPassed;

  /// Which randomized active challenge was issued this attempt.
  final ChallengeType challengeType;

  /// Token read from the teacher's GATT characteristic at submission time.
  final String bleToken;

  /// Signal strength of the discovered beacon (dBm, negative). Proximity proxy.
  final int rssi;

  /// Stable per-install device id; server checks it against the bound device.
  final String deviceId;

  /// Passive anti-spoof model score (0..1; higher = more likely live). Null if
  /// the model asset is not yet installed (stub mode).
  final double? passiveSpoofScore;

  /// Whether the active challenge (blink/turn/smile) was satisfied.
  final bool challengePassed;

  /// Version tag of the face-match model, for auditability across upgrades.
  final String? faceModelVersion;

  // ---- Placeholders for future server-side policy tightening ----
  final String? wifiBssid;
  final GeoPoint? geo;
  final AttestationInfo? attestation;

  final DateTime? capturedAt;

  Map<String, dynamic> toJson() => {
        'face_match_score': faceMatchScore,
        'liveness_passed': livenessPassed,
        'challenge_type': challengeType.name,
        'challenge_passed': challengePassed,
        'passive_spoof_score': passiveSpoofScore,
        'ble_token': bleToken,
        'rssi': rssi,
        'device_id': deviceId,
        'face_model_version': faceModelVersion,
        'wifi_bssid': wifiBssid,
        'geo': geo?.toJson(),
        'attestation': attestation?.toJson(),
        'captured_at': (capturedAt)?.toIso8601String(),
      };

  factory Evidence.fromJson(Map<String, dynamic> json) => Evidence(
        faceMatchScore: (json['face_match_score'] as num).toDouble(),
        livenessPassed: json['liveness_passed'] as bool,
        challengeType:
            ChallengeType.fromString(json['challenge_type'] as String),
        challengePassed: (json['challenge_passed'] as bool?) ?? true,
        passiveSpoofScore: (json['passive_spoof_score'] as num?)?.toDouble(),
        bleToken: json['ble_token'] as String,
        rssi: (json['rssi'] as num).toInt(),
        deviceId: json['device_id'] as String,
        faceModelVersion: json['face_model_version'] as String?,
        wifiBssid: json['wifi_bssid'] as String?,
        geo: json['geo'] == null
            ? null
            : GeoPoint.fromJson(json['geo'] as Map<String, dynamic>),
        attestation: json['attestation'] == null
            ? null
            : AttestationInfo.fromJson(
                json['attestation'] as Map<String, dynamic>),
        capturedAt: json['captured_at'] == null
            ? null
            : DateTime.parse(json['captured_at'] as String),
      );
}

class GeoPoint {
  const GeoPoint({required this.lat, required this.lng, this.accuracy});
  final double lat;
  final double lng;
  final double? accuracy;

  Map<String, dynamic> toJson() =>
      {'lat': lat, 'lng': lng, 'accuracy': accuracy};

  factory GeoPoint.fromJson(Map<String, dynamic> json) => GeoPoint(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        accuracy: (json['accuracy'] as num?)?.toDouble(),
      );
}

/// Placeholder for Play Integrity / App Attest results.
class AttestationInfo {
  const AttestationInfo({required this.platform, this.verdict, this.token});
  final String platform;
  final String? verdict;
  final String? token;

  Map<String, dynamic> toJson() =>
      {'platform': platform, 'verdict': verdict, 'token': token};

  factory AttestationInfo.fromJson(Map<String, dynamic> json) =>
      AttestationInfo(
        platform: json['platform'] as String,
        verdict: json['verdict'] as String?,
        token: json['token'] as String?,
      );
}
