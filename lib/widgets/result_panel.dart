import 'package:flutter/material.dart';

import '../models/test_record.dart';

/// Bottom panel shown once a face test finishes.
class ResultPanel extends StatelessWidget {
  const ResultPanel({
    required this.record,
    required this.onRetry,
    super.key,
  });

  final TestRecord record;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final real = record.judgedReal;
    final correct = record.detectionCorrect;
    final color = real ? Colors.green : Colors.red;
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(real ? Icons.verified_user : Icons.gpp_bad,
                color: color, size: 48),
            const SizedBox(height: 8),
            Text(
              real ? 'النتيجة: وجه حي' : 'النتيجة: مرفوض (تزييف محتمل)',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: color),
            ),
            const SizedBox(height: 4),
            Text('الدرجة: ${(record.score * 100).toStringAsFixed(1)}٪'),
            Text('نوع المحاولة: ${record.attemptType.label}'),
            if (record.details.isNotEmpty)
              Text(record.details, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Chip(
              avatar: Icon(correct ? Icons.check : Icons.close),
              label: Text(correct ? 'كشف صحيح' : 'كشف خاطئ'),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('رجوع'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
