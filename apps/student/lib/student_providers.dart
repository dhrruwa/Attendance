import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import 'device_id.dart';
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

/// Courses the signed-in student is enrolled in.
final studentCoursesProvider =
    FutureProvider.family<List<Course>, String>((ref, studentId) {
  return ref.watch(courseRepositoryProvider).coursesForStudent(studentId);
});

/// The currently-open session for a course, if any.
final openSessionProvider =
    FutureProvider.family<Session?, String>((ref, courseId) {
  return ref.watch(courseRepositoryProvider).openSessionForCourse(courseId);
});
