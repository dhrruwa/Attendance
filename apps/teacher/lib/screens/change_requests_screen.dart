import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

/// Pending profile-change requests from students this teacher teaches. RLS
/// scopes the rows; approving calls the edge function which opens the student's
/// one-shot edit window.
final pendingRequestsProvider =
    FutureProvider<List<ProfileChangeRequest>>((ref) {
  return ref.watch(profileRepositoryProvider).pendingRequests();
});

class ChangeRequestsScreen extends ConsumerWidget {
  const ChangeRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(pendingRequestsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile change requests')),
      body: requestsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (requests) {
          if (requests.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(pendingRequestsProvider),
              child: ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('No pending requests.')),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(pendingRequestsProvider),
            child: ListView.separated(
              itemCount: requests.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _RequestTile(request: requests[i]),
            ),
          );
        },
      ),
    );
  }
}

class _RequestTile extends ConsumerStatefulWidget {
  const _RequestTile({required this.request});
  final ProfileChangeRequest request;

  @override
  ConsumerState<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends ConsumerState<_RequestTile> {
  bool _busy = false;

  Future<void> _resolve(bool approve) async {
    setState(() => _busy = true);
    try {
      await ref.read(profileRepositoryProvider).resolve(
            requestId: widget.request.id,
            approve: approve,
          );
      ref.invalidate(pendingRequestsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(approve
                  ? 'Approved — the student can now edit once.'
                  : 'Request rejected.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final who = r.studentCode != null
        ? '${r.studentName ?? 'Student'}  ·  ${r.studentCode}'
        : (r.studentName ?? 'Student');
    return ListTile(
      leading: const Icon(Icons.edit_note),
      title: Text(who, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(r.reason?.isNotEmpty == true
          ? r.reason!
          : 'No reason provided'),
      trailing: _busy
          ? const SizedBox(
              height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Reject',
                  icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: () => _resolve(false),
                ),
                IconButton(
                  tooltip: 'Approve',
                  icon: const Icon(Icons.check, color: Colors.green),
                  onPressed: () => _resolve(true),
                ),
              ],
            ),
    );
  }
}
