import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import 'device_id.dart';
import 'face/face_enrollment.dart';
import 'face/face_matcher.dart';
import 'face/spoof_detector.dart';

/// Stable per-install device id (bound to the account; checked server-side).
final deviceIdProvider = FutureProvider<String>((ref) => DeviceId.get());

/// On-device face embedder (MobileFaceNet, or stub if model asset missing).
final faceMatcherProvider = FutureProvider<FaceMatcher>((ref) async {
  final matcher = await FaceMatcherFactory.create();
  ref.onDispose(matcher.dispose);
  return matcher;
});

/// Passive anti-spoof scorer (MiniFASNet, or stub if model asset missing).
final spoofDetectorProvider = FutureProvider<SpoofDetector>((ref) async {
  final d = await SpoofDetectorFactory.create();
  ref.onDispose(d.dispose);
  return d;
});

/// Offerings (subject × section) the signed-in student belongs to.
final studentOfferingsProvider =
    FutureProvider<List<Offering>>((ref) {
  return ref.watch(offeringRepositoryProvider).offeringsForStudent();
});

/// The currently-open session for an offering, if any.
final openSessionProvider =
    FutureProvider.family<Session?, String>((ref, offeringId) {
  return ref.watch(offeringRepositoryProvider).openSession(offeringId);
});

/// The signed-in student's own attendance row for a session, if any — drives the
/// Marked / Not Marked status on the dashboard. Null means not marked yet.
final myAttendanceProvider = FutureProvider.family<Attendance?,
    ({String sessionId, String studentId})>((ref, key) {
  return ref.watch(attendanceRepositoryProvider).myAttendance(
        sessionId: key.sessionId,
        studentId: key.studentId,
      );
});

/// The signed-in student's full attendance history (Attendance Tracker tab).
final studentAttendanceHistoryProvider =
    FutureProvider.family<List<AttendanceHistoryEntry>, String>(
        (ref, studentId) {
  return ref.watch(attendanceRepositoryProvider).myHistory(studentId);
});

/// Whether the student has enrolled a profile photo (face template) on this
/// device — gates Mark Attendance and drives the Profile "verified" state.
final faceEnrolledProvider =
    FutureProvider.family<bool, String>((ref, studentId) {
  return FaceEnrollment.isEnrolled(studentId);
});

/// The student's latest profile-change request (drives the locked-profile UI).
final profileChangeRequestProvider =
    FutureProvider.family<ProfileChangeRequest?, String>((ref, studentId) {
  return ref.watch(profileRepositoryProvider).latestRequest(studentId);
});
