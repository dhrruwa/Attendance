import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

/// State of an active (or attempted) attendance session on the teacher device.
class TeacherSessionState {
  const TeacherSessionState({
    this.session,
    this.currentToken,
    this.advertising = false,
    this.error,
    this.starting = false,
  });

  final Session? session;
  final String? currentToken;
  final bool advertising;
  final bool starting;
  final String? error;

  bool get isActive => session != null && advertising;

  TeacherSessionState copyWith({
    Session? session,
    String? currentToken,
    bool? advertising,
    bool? starting,
    String? error,
    bool clearError = false,
    bool clearSession = false,
  }) =>
      TeacherSessionState(
        session: clearSession ? null : (session ?? this.session),
        currentToken: currentToken ?? this.currentToken,
        advertising: advertising ?? this.advertising,
        starting: starting ?? this.starting,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Orchestrates: create session -> load token windows -> advertise (GATT) ->
/// rotate the served token every ~5s -> end session.
class TeacherSessionController extends Notifier<TeacherSessionState> {
  final BleAdvertiser _advertiser = BleAdvertiser();
  SessionTokenSource? _tokenSource;
  Timer? _rotationTimer;

  @override
  TeacherSessionState build() {
    ref.onDispose(_cleanup);
    return const TeacherSessionState();
  }

  Future<void> start({
    required String courseId,
    required String teacherId,
    Duration duration = const Duration(minutes: 15),
  }) async {
    state = state.copyWith(starting: true, clearError: true);
    try {
      final repo = ref.read(sessionRepositoryProvider);

      // Pre-flight: peripheral/advertising must be supported.
      if (!await _advertiser.isSupported()) {
        throw StateError(
          'BLE advertising is not supported / Bluetooth is off on this device.',
        );
      }

      final session = await repo.startSession(
        courseId: courseId,
        teacherId: teacherId,
        duration: duration,
      );
      _tokenSource = await repo.tokenSource(session.id);

      final initial = _tokenSource!.currentToken(DateTime.now().toUtc());
      await _advertiser.start(
        sessionId: session.id,
        initialToken: initial?.token ?? '',
      );

      _rotationTimer = Timer.periodic(BleContract.tokenRotation, (_) {
        final t = _tokenSource?.currentToken(DateTime.now().toUtc());
        if (t != null) {
          _advertiser.currentToken = t.token;
          state = state.copyWith(currentToken: t.token);
        }
      });

      state = state.copyWith(
        session: session,
        currentToken: initial?.token ?? '',
        advertising: true,
        starting: false,
      );
    } catch (e) {
      await _cleanup();
      state = TeacherSessionState(error: '$e');
    }
  }

  Future<void> end() async {
    final session = state.session;
    try {
      if (session != null) {
        await ref.read(sessionRepositoryProvider).endSession(session.id);
      }
    } finally {
      await _cleanup();
      state = const TeacherSessionState();
    }
  }

  Future<void> _cleanup() async {
    _rotationTimer?.cancel();
    _rotationTimer = null;
    _tokenSource = null;
    await _advertiser.stop();
  }
}

final teacherSessionControllerProvider =
    NotifierProvider<TeacherSessionController, TeacherSessionState>(
  TeacherSessionController.new,
);

/// Realtime roster for the active session.
final rosterProvider =
    StreamProvider.family<List<Attendance>, String>((ref, sessionId) {
  return ref.watch(sessionRepositoryProvider).watchRoster(sessionId);
});
