import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user.dart';
import '../models/enums.dart';

/// Authentication + profile loading.
///
/// Login model (per project decision): users authenticate with Supabase
/// email/password. The human-facing `student_code` / `teacher_code` is a unique
/// column on `users`; the UI collects the code for display/validation but the
/// actual credential is email+password. We verify the signed-in user's role and
/// code match what was entered.
class AuthRepository {
  AuthRepository(this._client);
  final SupabaseClient _client;

  Session? get currentSession => _client.auth.currentSession;
  User? get currentAuthUser => _client.auth.currentUser;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Signs in with email + password, then loads the `users` profile row and
  /// asserts it matches [expectedRole] and (if provided) [expectedCode].
  Future<AppUser> signIn({
    required String email,
    required String password,
    required UserRole expectedRole,
    String? expectedCode,
  }) async {
    final res = await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    final uid = res.user?.id;
    if (uid == null) {
      throw const AuthException('Sign-in failed: no user returned.');
    }
    final profile = await loadProfile(uid);
    if (profile.role != expectedRole) {
      await signOut();
      throw AuthException(
        'This account is not a ${expectedRole.name} account.',
      );
    }
    if (expectedCode != null &&
        expectedCode.isNotEmpty &&
        profile.code?.toUpperCase() != expectedCode.trim().toUpperCase()) {
      await signOut();
      throw const AuthException('The code does not match this account.');
    }
    return profile;
  }

  Future<AppUser> loadProfile(String uid) async {
    final row = await _client.from('users').select().eq('id', uid).single();
    return AppUser.fromJson(row);
  }

  Future<AppUser?> loadCurrentProfile() async {
    final uid = currentAuthUser?.id;
    if (uid == null) return null;
    return loadProfile(uid);
  }

  Future<void> signOut() => _client.auth.signOut();
}
