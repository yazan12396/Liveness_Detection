import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/test_record.dart';

class HistoryStore {
  HistoryStore._();
  static final HistoryStore instance = HistoryStore._();

  static const _key = 'test_records_v1';

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  Future<List<TestRecord>> load() async {
    final raw = await _prefs.getStringList(_key) ?? const [];
    return raw
        .map((s) => TestRecord.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  Future<void> add(TestRecord record) async {
    final raw = await _prefs.getStringList(_key) ?? <String>[];
    await _prefs.setStringList(_key, [...raw, jsonEncode(record.toJson())]);
  }

  Future<void> clear() => _prefs.remove(_key);

  /// Writes all records to a CSV file and opens the system share sheet.
  Future<void> exportCsv(List<TestRecord> records) async {
    final fmt = DateFormat('yyyy-MM-dd HH:mm:ss', 'en');
    final rows = <List<String>>[
      [
        'timestamp',
        'test_kind',
        'camera',
        'attempt_type',
        'judged_real',
        'detection_correct',
        'score',
        'details',
      ],
      for (final r in records)
        [
          fmt.format(r.timestamp),
          r.kind.name,
          r.camera.name,
          r.attemptType.name,
          r.judgedReal.toString(),
          r.detectionCorrect.toString(),
          r.score.toStringAsFixed(4),
          r.details,
        ],
    ];
    // UTF-8 BOM so Excel renders Arabic details correctly.
    final csv = '${String.fromCharCode(0xFEFF)}${rows.map((r) => r.map(_escape).join(',')).join('\r\n')}';

    final dir = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmmss', 'en').format(DateTime.now());
    final file = File('${dir.path}/liveness_log_$stamp.csv');
    await file.writeAsString(csv, encoding: utf8);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'سجل اختبارات الحيوية',
      ),
    );
  }

  static String _escape(String v) {
    if (v.contains(RegExp(r'[",\r\n]'))) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }
}
