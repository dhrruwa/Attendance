import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

/// Shows the server's verdict. The device never decides — this simply reflects
/// what `validate_attendance` returned.
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, this.result, this.error});
  final SubmitResult? result;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String title, String detail) =
        _present();
    return Scaffold(
      appBar: AppBar(title: const Text('Result')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 96, color: color),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(detail, textAlign: TextAlign.center),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (IconData, Color, String, String) _present() {
    if (error != null) {
      return (Icons.error_outline, Colors.red, 'Could not submit', error!);
    }
    final r = result;
    if (r == null) {
      return (
        Icons.help_outline,
        Colors.grey,
        'No result',
        'Please try again.'
      );
    }
    return switch (r.status) {
      AttendanceStatus.present => (
          Icons.check_circle,
          Colors.green,
          'Present',
          r.reason,
        ),
      AttendanceStatus.flagged => (
          Icons.flag,
          Colors.orange,
          'Flagged for review',
          r.reason,
        ),
      AttendanceStatus.absent => (
          Icons.cancel,
          Colors.red,
          'Not accepted',
          r.reason,
        ),
    };
  }
}
