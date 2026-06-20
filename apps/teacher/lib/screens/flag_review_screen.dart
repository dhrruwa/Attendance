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
              final e = flagged[i];
              final srn =
                  e.studentCode != null ? 'SRN: ${e.studentCode}' : null;
              return ExpansionTile(
                leading: const Icon(Icons.flag, color: Colors.orange),
                title: Text(e.studentName,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text([
                  if (srn != null) srn,
                  e.reason ?? 'flagged',
                ].join('  ·  ')),
                childrenPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  // Human-meaningful verification signals only — no BLE token,
                  // device id, MAC, UUID or RSSI is ever shown to faculty.
                  _evidenceRow(
                      'Face match', e.faceMatchScore?.toStringAsFixed(2)),
                  _evidenceRow('Liveness',
                      e.livenessPassed == null ? null : '${e.livenessPassed}'),
                  _evidenceRow('Challenge', e.challengeType?.name),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () =>
                            _review(context, ref, e.attendanceId, false),
                        icon: const Icon(Icons.close, color: Colors.red),
                        label: const Text('Reject'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () =>
                            _review(context, ref, e.attendanceId, true),
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
