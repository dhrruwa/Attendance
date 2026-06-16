import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user.dart';
import '../supabase/attendance_repository.dart';
import '../supabase/auth_repository.dart';
import '../supabase/course_repository.dart';
import '../supabase/device_repository.dart';
import '../supabase/session_repository.dart';
import '../supabase/supabase_init.dart';

/// The initialized Supabase client. Apps must initialize Supabase before reading.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return SupabaseInit.client;
});

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);

final deviceRepositoryProvider = Provider<DeviceRepository>(
  (ref) => DeviceRepository(ref.watch(supabaseClientProvider)),
);

final courseRepositoryProvider = Provider<CourseRepository>(
  (ref) => CourseRepository(ref.watch(supabaseClientProvider)),
);

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepository(ref.watch(supabaseClientProvider)),
);

final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => AttendanceRepository(ref.watch(supabaseClientProvider)),
);

/// Emits Supabase auth state changes (sign-in / sign-out / token refresh).
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

/// The signed-in app user profile (null when signed out). Recomputes on auth
/// changes.
final currentUserProvider = FutureProvider<AppUser?>((ref) async {
  // Re-run whenever auth state changes.
  ref.watch(authStateProvider);
  final repo = ref.watch(authRepositoryProvider);
  if (repo.currentAuthUser == null) return null;
  return repo.loadCurrentProfile();
});
