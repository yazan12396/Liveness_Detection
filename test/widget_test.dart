import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_test/models/test_record.dart';

void main() {
  TestRecord record(AttemptType type, {required bool judgedReal}) =>
      TestRecord(
        timestamp: DateTime(2026),
        kind: TestKind.passive,
        attemptType: type,
        judgedReal: judgedReal,
        score: 0.5,
        details: '',
      );

  test('detection is correct when real is accepted and spoofs rejected', () {
    expect(record(AttemptType.realFace, judgedReal: true).detectionCorrect,
        isTrue);
    expect(record(AttemptType.realFace, judgedReal: false).detectionCorrect,
        isFalse);
    expect(record(AttemptType.printedPhoto, judgedReal: false).detectionCorrect,
        isTrue);
    expect(record(AttemptType.video, judgedReal: true).detectionCorrect,
        isFalse);
  });

  test('json round trip', () {
    final r = record(AttemptType.screenPhoto, judgedReal: false);
    final back = TestRecord.fromJson(r.toJson());
    expect(back.attemptType, AttemptType.screenPhoto);
    expect(back.kind, TestKind.passive);
    expect(back.judgedReal, isFalse);
    expect(back.camera, CameraSide.front);
  });

  test('rear camera survives round trip; old records default to front', () {
    final r = TestRecord(
      timestamp: DateTime(2026),
      kind: TestKind.active,
      attemptType: AttemptType.video,
      judgedReal: false,
      score: 0,
      details: '',
      camera: CameraSide.rear,
    );
    expect(TestRecord.fromJson(r.toJson()).camera, CameraSide.rear);
    expect(TestRecord.fromJson(r.toJson()..remove('camera')).camera,
        CameraSide.front);
  });
}
