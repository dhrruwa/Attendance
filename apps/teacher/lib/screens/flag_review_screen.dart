import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../session_controller.dart';

class FlagReviewScreen extends ConsumerWidget {
  const FlagReviewScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rosterAsync = ref.watch(rosterProvider(sessionId));
    return Scaffold(
      appBar: AppBar(title: const Text('Review flagged')),
      body: rosterAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rows) {
          final flagged =
              rows.where((r) => r.status == AttendanceStatus.flagged).toList();
          if (flagged.isEmpty) {
            return const Center(child: Text('Nothing to review.'));
          }
          return ListView.separated(
            itemCount: flagged.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final a = flagged[i];
              final ev = a.evidence;
              return ExpansionTile(
                leading: const Icon(Icons.flag, color: Colors.orange),
                title: Text(a.studentId),
                subtitle: Text(a.reason ?? 'flagged'),
                childrenPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  _evidenceRow(
                      'Face match', ev?.faceMatchScore.toStringAsFixed(2)),
                  _evidenceRow('Liveness', '${ev?.livenessPassed}'),
                  _evidenceRow('Challenge', ev?.challengeType.name),
                  _evidenceRow('Passive spoof',
                      ev?.passiveSpoofScore?.toStringAsFixed(2)),
                  _evidenceRow('RSSI', '${a.rssi ?? ev?.rssi}'),
                  _evidenceRow('Device', a.deviceId ?? ev?.deviceId),
                  _evidenceRow('Token', a.submittedToken ?? ev?.bleToken),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _review(context, ref, a.id, false),
                        icon: const Icon(Icons.close, color: Colors.red),
                        label: const Text('Reject'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => _review(context, ref, a.id, true),
                        icon: const Icon(Icons.check),
                        label: const Text('Approve'),
                      ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _evidenceRow(String k, String? v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(width: 120, child: Text(k)),
            Expanded(
                child: Text(v ?? '—',
                    style: const TextStyle(fontWeight: FontWeight.w500))),
          ],
        ),
      );

  Future<void> _review(
      BuildContext context, WidgetRef ref, String id, bool approve) async {
    await ref.read(attendanceRepositoryProvider).reviewFlagged(
          attendanceId: id,
          approve: approve,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(approve ? 'Approved' : 'Rejected')),
      );
    }
  }
}
