import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile_change_request.dart';

/// Profile change-request workflow: a student asks to edit their locked profile;
/// a teacher approves (which opens a one-shot edit window server-side) or rejects.
class ProfileRepository {
  ProfileRepository(this._client);
  final SupabaseClient _client;

  /// Student: submit a request to edit their locked profile.
  Future<void> requestChange({
    required String studentId,
    String? reason,
  }) async {
    await _client.from('profile_change_requests').insert({
      'student_id': studentId,
      'reason': reason,
    });
  }

  /// Student: their most recent request (to show "pending" / "approved" state).
  Future<ProfileChangeRequest?> latestRequest(String studentId) async {
    final rows = await _client
        .from('profile_change_requests')
        .select()
        .eq('student_id', studentId)
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return ProfileChangeRequest.fromJson(rows.first);
  }

  /// Teacher: pending requests from students they teach (RLS scopes the rows),
  /// newest first, with the student's name/code joined in.
  Future<List<ProfileChangeRequest>> pendingRequests() async {
    final rows = await _client
        .from('profile_change_requests')
        .select('id, student_id, status, reason, created_at, '
            'student:users!profile_change_requests_student_id_fkey'
            '(full_name, student_code)')
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return rows
        .map((r) => ProfileChangeRequest.fromJson(
            (r as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Teacher: approve or reject a request via the edge function (service role
  /// flips the student's edit window). Throws on failure.
  Future<void> resolve({
    required String requestId,
    required bool approve,
  }) async {
    final res = await _client.functions.invoke(
      'resolve_change_request',
      body: {'request_id': requestId, 'approve': approve},
    );
    final data = res.data;
    if (data is Map && data['error'] != null) {
      throw StateError(data['error'].toString());
    }
  }
}
