import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:shared/shared.dart';

import '../face/face_enrollment.dart';
import '../face/liveness_capture.dart';
import '../permissions.dart';
import '../student_providers.dart';

/// Profile tab. The student sets their name / phone / college id and a photo
/// used to verify their identity at attendance time. After the first save the
/// profile LOCKS — changing it (including the photo) needs a teacher to approve
/// a change request, which opens a one-shot edit window (enforced server-side).
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, required this.student});
  final AppUser student;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.student.fullName);
  late final TextEditingController _phone =
      TextEditingController(text: widget.student.phone ?? '');
  late final TextEditingController _college =
      TextEditingController(text: widget.student.collegeId ?? '');

  bool _saving = false;
  int _photoNonce = 0;

  bool get _canEdit => widget.student.canEditProfile;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _college.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(authRepositoryProvider).updateProfile(
            uid: widget.student.id,
            fullName: _name.text.trim(),
            phone: _phone.text.trim(),
            collegeId: _college.text.trim(),
          );
      ref.invalidate(currentUserProvider);
      ref.invalidate(profileChangeRequestProvider(widget.student.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved & locked.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestChange() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RequestChangeDialog(),
    );
    if (reason == null) return; // cancelled
    try {
      await ref.read(profileRepositoryProvider).requestChange(
            studentId: widget.student.id,
            reason: reason.trim().isEmpty ? null : reason.trim(),
          );
      ref.invalidate(profileChangeRequestProvider(widget.student.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Change request sent to your teacher.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send request: $e')),
        );
      }
    }
  }

  Future<void> _capturePhoto() async {
    final result = await Navigator.of(context).push<LivenessResult>(
      MaterialPageRoute(builder: (_) => const _PhotoCaptureScreen()),
    );
    if (result == null) return;
    if (!result.faceDetected) {
      _toast('No face detected — try again in good lighting.');
      return;
    }
    try {
      final matcher = await ref.read(faceMatcherProvider.future);
      final embedding = await matcher.embed(result.faceCrop);
      await FaceEnrollment.save(widget.student.id, embedding);
      final jpeg = img.encodeJpg(
        img.copyResize(result.faceCrop, width: 256, height: 256),
        quality: 80,
      );
      await FaceEnrollment.savePhoto(
          widget.student.id, Uint8List.fromList(jpeg));
      ref.invalidate(faceEnrolledProvider(widget.student.id));
      if (mounted) {
        setState(() => _photoNonce++);
        _toast('Photo saved & face enrolled.');
      }
    } catch (e) {
      _toast('Could not process photo: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.student;
    final canEdit = _canEdit;
    final reqAsync = ref.watch(profileChangeRequestProvider(s.id));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PhotoSection(
          studentId: s.id,
          nonce: _photoNonce,
          onCapture: canEdit ? _capturePhoto : null,
        ),
        const SizedBox(height: 16),
        _statusBanner(s, canEdit, reqAsync),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          enabled: canEdit,
          decoration: const InputDecoration(
            labelText: 'Full name',
            prefixIcon: Icon(Icons.badge_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          enabled: canEdit,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone number',
            prefixIcon: Icon(Icons.phone_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _college,
          enabled: canEdit,
          decoration: const InputDecoration(
            labelText: 'College ID',
            prefixIcon: Icon(Icons.school_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        // USN/SRN is account identity — never editable from the app.
        TextField(
          enabled: false,
          controller: TextEditingController(text: s.studentCode ?? ''),
          decoration: const InputDecoration(
            labelText: 'USN / SRN (locked)',
            prefixIcon: Icon(Icons.tag),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        if (canEdit)
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: Text(s.profileLocked ? 'Save changes' : 'Save profile'),
          )
        else
          _requestArea(reqAsync),
      ],
    );
  }

  Widget _statusBanner(
      AppUser s, bool canEdit, AsyncValue<ProfileChangeRequest?> reqAsync) {
    if (!s.profileLocked) {
      return _banner(
        Colors.blue,
        Icons.info_outline,
        'Fill in your details and add a photo, then Save. After saving, your '
        'profile locks and changes need teacher approval.',
      );
    }
    if (s.editAllowed) {
      return _banner(
        Colors.green,
        Icons.lock_open,
        'A teacher approved your request. Make your changes and Save — the '
        'profile re-locks afterwards.',
      );
    }
    return _banner(
      Colors.orange,
      Icons.lock_outline,
      'Your profile is locked. To change anything, request approval from your '
      'teacher.',
    );
  }

  Widget _requestArea(AsyncValue<ProfileChangeRequest?> reqAsync) {
    final pending = reqAsync.value?.isPending ?? false;
    if (pending) {
      return _banner(
        Colors.orange,
        Icons.hourglass_top,
        'Change request pending — waiting for your teacher to approve.',
      );
    }
    return OutlinedButton.icon(
      onPressed: _requestChange,
      icon: const Icon(Icons.edit_note),
      label: const Text('Request profile change'),
    );
  }

  Widget _banner(Color color, IconData icon, String text) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

class _RequestChangeDialog extends StatefulWidget {
  const _RequestChangeDialog();
  @override
  State<_RequestChangeDialog> createState() => _RequestChangeDialogState();
}

class _RequestChangeDialogState extends State<_RequestChangeDialog> {
  final _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Request profile change'),
      content: TextField(
        controller: _reason,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'Why do you need to change your profile? (optional)',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _reason.text),
          child: const Text('Send request'),
        ),
      ],
    );
  }
}

class _PhotoSection extends StatelessWidget {
  const _PhotoSection({
    required this.studentId,
    required this.nonce,
    required this.onCapture,
  });
  final String studentId;
  final int nonce;
  final VoidCallback? onCapture;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FutureBuilder<Uint8List?>(
          key: ValueKey(nonce),
          future: FaceEnrollment.loadPhoto(studentId),
          builder: (_, snap) {
            final bytes = snap.data;
            return CircleAvatar(
              radius: 56,
              backgroundColor: Colors.grey.shade300,
              backgroundImage: bytes != null ? MemoryImage(bytes) : null,
              child: bytes == null
                  ? const Icon(Icons.person, size: 56, color: Colors.white)
                  : null,
            );
          },
        ),
        const SizedBox(height: 8),
        FutureBuilder<bool>(
          key: ValueKey('enrolled-$nonce'),
          future: FaceEnrollment.isEnrolled(studentId),
          builder: (_, snap) {
            final enrolled = snap.data ?? false;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(enrolled ? Icons.verified : Icons.info_outline,
                    size: 16, color: enrolled ? Colors.green : Colors.orange),
                const SizedBox(width: 4),
                Text(
                  enrolled
                      ? 'Face enrolled — used to verify attendance'
                      : 'No photo yet — add one to mark attendance',
                  style:
                      TextStyle(color: enrolled ? Colors.green : Colors.orange),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          // Disabled when the profile is locked (photo locks too).
          onPressed: onCapture,
          icon: const Icon(Icons.camera_alt),
          label: const Text('Capture / update photo'),
        ),
      ],
    );
  }
}

/// Camera screen that captures one clear face still and returns it.
class _PhotoCaptureScreen extends StatefulWidget {
  const _PhotoCaptureScreen();
  @override
  State<_PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends State<_PhotoCaptureScreen> {
  final LivenessCapture _capture = LivenessCapture();
  bool _ready = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ok = await StudentPermissions.requestCamera();
    if (!ok) {
      setState(() => _error = 'Camera permission is required.');
      return;
    }
    await _capture.initialize();
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _shoot() async {
    setState(() => _busy = true);
    try {
      final result = await _capture.captureOnce();
      await _capture.dispose();
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  void dispose() {
    _capture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile photo')),
      body: Column(
        children: [
          Expanded(
            child: _ready && _capture.controller != null
                ? CameraPreview(_capture.controller!)
                : Center(
                    child: _error != null
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_error!, textAlign: TextAlign.center))
                        : const CircularProgressIndicator(),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'Look straight at the camera in good lighting, then capture.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: (!_ready || _busy) ? null : _shoot,
                  icon: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.camera_alt),
                  label: const Text('Capture'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
