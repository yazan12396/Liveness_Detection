import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/test_record.dart';
import '../services/history_store.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<TestRecord>? _records;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await HistoryStore.instance.load();
    if (mounted) setState(() => _records = records);
  }

  Future<void> _export() async {
    final records = _records;
    if (records == null || records.isEmpty) return;
    try {
      await HistoryStore.instance.exportCsv(records);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('فشل التصدير: $e')));
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف السجل'),
        content: const Text('سيتم حذف جميع نتائج الاختبارات. متابعة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await HistoryStore.instance.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final records = _records;
    final hasData = records != null && records.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل الاختبارات'),
        actions: [
          IconButton(
            tooltip: 'تصدير CSV',
            onPressed: hasData ? _export : null,
            icon: const Icon(Icons.ios_share),
          ),
          IconButton(
            tooltip: 'حذف السجل',
            onPressed: hasData ? _clear : null,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: records == null
          ? const Center(child: CircularProgressIndicator())
          : records.isEmpty
              ? const Center(child: Text('لا توجد اختبارات بعد'))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _StatsCard(records: records),
                    const SizedBox(height: 8),
                    for (final r in records) _RecordTile(record: r),
                  ],
                ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.records});

  final List<TestRecord> records;

  String _rate(Iterable<TestRecord> rs) {
    final list = rs.toList();
    if (list.isEmpty) return '—';
    final correct = list.where((r) => r.detectionCorrect).length;
    final pct = correct * 100 / list.length;
    return '${pct.toStringAsFixed(0)}٪ ($correct/${list.length})';
  }

  @override
  Widget build(BuildContext context) {
    final bold = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(fontWeight: FontWeight.bold);
    Widget cell(String s, {TextStyle? style}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Text(s, style: style, textAlign: TextAlign.center),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('نسبة نجاح الكشف',
                style: Theme.of(context).textTheme.titleMedium),
            const Text(
              'النجاح = قبول الوجه الحقيقي أو رفض محاولة التزييف',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Table(
              border: TableBorder.all(color: Colors.black12),
              columnWidths: const {0: FlexColumnWidth(1.3)},
              children: [
                TableRow(
                  children: [
                    cell('نوع المحاولة', style: bold),
                    for (final k in TestKind.values)
                      cell(k.label, style: bold),
                    cell('الإجمالي', style: bold),
                  ],
                ),
                for (final t in AttemptType.values)
                  TableRow(
                    children: [
                      cell(t.label, style: bold),
                      for (final k in TestKind.values)
                        cell(_rate(records.where(
                            (r) => r.attemptType == t && r.kind == k))),
                      cell(_rate(records.where((r) => r.attemptType == t))),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});

  final TestRecord record;

  @override
  Widget build(BuildContext context) {
    final r = record;
    return Card(
      child: ListTile(
        leading: Icon(
          r.detectionCorrect ? Icons.check_circle : Icons.cancel,
          color: r.detectionCorrect ? Colors.green : Colors.red,
        ),
        title: Text(
          '${r.kind.label} (${r.camera.label}) • ${r.attemptType.label} → '
          '${r.judgedReal ? 'حي' : 'مرفوض'}',
        ),
        subtitle: Text(
          '${DateFormat('yyyy/MM/dd HH:mm').format(r.timestamp)}\n'
          'الدرجة: ${(r.score * 100).toStringAsFixed(1)}٪ • ${r.details}',
        ),
        isThreeLine: true,
      ),
    );
  }
}
