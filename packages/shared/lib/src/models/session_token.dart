/// A short-lived token for a session. The teacher app rotates through these
/// (~every 5s) and serves the current one over GATT. The server validates that
/// a submitted token exists for the session and that submission time falls
/// within [validFrom, validTo]. This binds attendance to *being there now*.
class SessionToken {
  const SessionToken({
    required this.id,
    required this.sessionId,
    required this.token,
    required this.validFrom,
    required this.validTo,
  });

  final String id;
  final String sessionId;
  final String token;
  final DateTime validFrom;
  final DateTime validTo;

  bool isValidAt(DateTime t) => !t.isBefore(validFrom) && !t.isAfter(validTo);

  factory SessionToken.fromJson(Map<String, dynamic> json) => SessionToken(
        id: json['id'] as String,
        sessionId: json['session_id'] as String,
        token: json['token'] as String,
        validFrom: DateTime.parse(json['valid_from'] as String),
        validTo: DateTime.parse(json['valid_to'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'session_id': sessionId,
        'token': token,
        'valid_from': validFrom.toIso8601String(),
        'valid_to': validTo.toIso8601String(),
      };
}
