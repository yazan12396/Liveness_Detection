import 'package:flutter/material.dart';

import '../models/test_record.dart';
import '../widgets/attempt_type_picker.dart';
import 'active_liveness_screen.dart';
import 'document_scan_screen.dart';
import 'history_screen.dart';
import 'passive_liveness_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _startFaceTest(BuildContext context, TestKind kind) async {
    final attempt = await pickAttemptType(context);
    if (attempt == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => switch (kind) {
          TestKind.active => ActiveLivenessScreen(attemptType: attempt),
          TestKind.passive => PassiveLivenessScreen(attemptType: attempt),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Liveness Detection')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _MenuCard(
            icon: Icons.gesture,
            title: 'الكشف النشط (Active Liveness)',
            subtitle: '3 تحديات عشوائية: التفات، رمش، ابتسامة',
            onTap: () => _startFaceTest(context, TestKind.active),
          ),
          _MenuCard(
            icon: Icons.face_retouching_natural,
            title: 'الكشف السلبي (Passive Liveness)',
            subtitle: 'تحليل الإطار بنموذج مضاد للتزييف مع وميض الشاشة',
            onTap: () => _startFaceTest(context, TestKind.passive),
          ),
          _MenuCard(
            icon: Icons.badge_outlined,
            title: 'تصوير الهوية (Document Capture)',
            subtitle: 'ماسح المستندات من ML Kit',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DocumentScanScreen(),
              ),
            ),
          ),
          _MenuCard(
            icon: Icons.history,
            title: 'سجل الاختبارات (Test Log)',
            subtitle: 'نسب نجاح الكشف لكل نوع وتصدير CSV',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const HistoryScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leading: Icon(icon, size: 36),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_left),
        onTap: onTap,
      ),
    );
  }
}
