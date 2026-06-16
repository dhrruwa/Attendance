import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../device_id.dart';
import '../student_providers.dart';

/// First-run binding of this device to the student's account (one active device
/// per account — a core anti-proxy control).
class DeviceBindScreen extends ConsumerStatefulWidget {
  const DeviceBindScreen(
      {super.key, required this.student, required this.onBound});
  final AppUser student;
  final VoidCallback onBound;

  @override
  ConsumerState<DeviceBindScreen> createState() => _DeviceBindScreenState();
}

class _DeviceBindScreenState extends ConsumerState<DeviceBindScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _bind() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final deviceId = await ref.read(deviceIdProvider.future);
      await ref.read(deviceRepositoryProvider).bindDevice(
            userId: widget.student.id,
            deviceId: deviceId,
            platform: DeviceId.platformLabel(),
          );
      widget.onBound();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bind this device')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.smartphone, size: 64),
            const SizedBox(height: 16),
            Text(
              'Welcome, ${widget.student.fullName}. Bind this phone to your '
              'account. Attendance can then only be submitted from this device.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            FilledButton.icon(
              onPressed: _busy ? null : _bind,
              icon: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.link),
              label: const Text('Bind device'),
            ),
            TextButton(
              onPressed: () async {
                await ref.read(authRepositoryProvider).signOut();
                ref.invalidate(currentUserProvider);
              },
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
