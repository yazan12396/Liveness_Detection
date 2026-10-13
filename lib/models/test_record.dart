/// What the tester actually presented to the camera.
enum AttemptType {
  realFace('وجه حقيقي'),
  printedPhoto('صورة مطبوعة'),
  screenPhoto('صورة على شاشة'),
  video('فيديو');

  const AttemptType(this.label);
  final String label;

  /// A correct detection means: real face accepted, anything else rejected.
  bool get isGenuine => this == AttemptType.realFace;
}

enum TestKind {
  active('نشط'),
  passive('سلبي');

  const TestKind(this.label);
  final String label;
}

enum CameraSide {
  front('أمامية'),
  rear('خلفية');

  const CameraSide(this.label);
  final String label;
}

class TestRecord {
  const TestRecord({
    required this.timestamp,
    required this.kind,
    required this.attemptType,
    required this.judgedReal,
    required this.score,
    required this.details,
    this.camera = CameraSide.front,
  });

  factory TestRecord.fromJson(Map<String, dynamic> json) => TestRecord(
        timestamp: DateTime.parse(json['timestamp'] as String),
        kind: TestKind.values.byName(json['kind'] as String),
        attemptType: AttemptType.values.byName(json['attemptType'] as String),
        judgedReal: json['judgedReal'] as bool,
        score: (json['score'] as num).toDouble(),
        details: json['details'] as String? ?? '',
        // Records saved before the camera switch existed were front-only.
        camera: CameraSide.values.byName(json['camera'] as String? ?? 'front'),
      );

  final DateTime timestamp;
  final TestKind kind;
  final AttemptType attemptType;

  /// Whether the detector judged the subject to be a live person.
  final bool judgedReal;

  /// 0..1 — passive: mean realScore; active: fraction of challenges completed.
  final double score;
  final String details;
  final CameraSide camera;

  /// Did the detector reach the right verdict for this attempt type?
  bool get detectionCorrect => judgedReal == attemptType.isGenuine;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'kind': kind.name,
        'attemptType': attemptType.name,
        'judgedReal': judgedReal,
        'score': score,
        'details': details,
        'camera': camera.name,
      };
}
