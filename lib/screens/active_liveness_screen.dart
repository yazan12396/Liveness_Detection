import 'dart:async';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../models/test_record.dart';
import '../services/face_camera.dart';
import '../services/history_store.dart';
import '../widgets/result_panel.dart';

enum Challenge {
  lookLeft('انظر يساراً', Icons.west),
  lookRight('انظر يميناً', Icons.east),
  blink('ارمش', Icons.remove_red_eye_outlined),
  smile('ابتسم', Icons.sentiment_satisfied_alt);

  const Challenge(this.label, this.icon);
  final String label;
  final IconData icon;
}

// ML Kit: positive headEulerAngleY = face turned toward the right side of the
// (unmirrored) front-camera image, i.e. the user's own left.
const double _yawTurned = 25;
const double _yawNeutral = 12;
const double _eyeOpen = 0.7;
const double _eyeClosed = 0.25;
const double _smiling = 0.8;
const double _notSmiling = 0.3;
const Duration _challengeTimeout = Duration(seconds: 8);
const int _challengeCount = 3;

class ActiveLivenessScreen extends StatefulWidget {
  const ActiveLivenessScreen({required this.attemptType, super.key});

  final AttemptType attemptType;

  @override
  State<ActiveLivenessScreen> createState() => _ActiveLivenessScreenState();
}

class _ActiveLivenessScreenState extends State<ActiveLivenessScreen> {
  final _camera = FaceCamera();
  final _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.25,
    ),
  );

  late List<Challenge> _challenges;
  int _index = 0;

  /// The neutral pose for the current challenge has been seen; the action only
  /// counts after that, so a static smile / turned photo can't pass instantly.
  bool _armed = false;
  DateTime? _deadline;
  Timer? _timer;
  String _hint = 'جارٍ تشغيل الكاميرا…';
  String? _error;
  TestRecord? _result;
  bool _switching = false;

  @override
  void initState() {
    super.initState();
    _reset();
    _camera.start(_onFrame).then((_) {
      if (mounted) setState(_startChallenge);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = 'تعذّر تشغيل الكاميرا: $e');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _camera.dispose();
    _detector.close();
    super.dispose();
  }

  void _reset() {
    _challenges = (List.of(Challenge.values)..shuffle(Random()))
        .take(_challengeCount)
        .toList();
    _index = 0;
    _result = null;
  }

  void _startChallenge() {
    _armed = false;
    _hint = 'ضع وجهك داخل الإطار';
    _deadline = DateTime.now().add(_challengeTimeout);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || _result != null) return;
      if (DateTime.now().isAfter(_deadline!)) {
        _finish(timedOut: true);
      } else {
        setState(() {}); // refresh countdown
      }
    });
  }

  void _retry() {
    setState(() {
      _reset();
      _startChallenge();
    });
  }

  /// Switching lens restarts the test so a record never mixes both cameras.
  Future<void> _switchCamera() async {
    _timer?.cancel();
    setState(() => _switching = true);
    try {
      await _camera.switchSide(_onFrame);
      if (mounted) _retry();
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذّر تبديل الكاميرا: $e');
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_result != null || _deadline == null || _switching) return;
    final input = _camera.toInputImage(image);
    if (input == null) return;
    final faces = await _detector.processImage(input);
    if (!mounted || _result != null) return;

    if (faces.isEmpty) {
      setState(() => _hint = 'لا يوجد وجه');
      return;
    }
    if (faces.length > 1) {
      setState(() => _hint = 'يجب أن يظهر وجه واحد فقط');
      return;
    }
    _evaluate(faces.first);
  }

  void _evaluate(Face face) {
    final yaw = face.headEulerAngleY ?? 0;
    final left = face.leftEyeOpenProbability;
    final right = face.rightEyeOpenProbability;
    final smile = face.smilingProbability;
    final challenge = _challenges[_index];

    bool neutral;
    bool done;
    switch (challenge) {
      case Challenge.lookLeft:
        neutral = yaw.abs() < _yawNeutral;
        done = yaw > _yawTurned;
      case Challenge.lookRight:
        neutral = yaw.abs() < _yawNeutral;
        done = yaw < -_yawTurned;
      case Challenge.blink:
        if (left == null || right == null) return;
        neutral = left > _eyeOpen && right > _eyeOpen;
        done = left < _eyeClosed && right < _eyeClosed;
      case Challenge.smile:
        if (smile == null) return;
        neutral = smile < _notSmiling;
        done = smile > _smiling;
    }

    if (!_armed) {
      setState(() {
        _armed = neutral;
        _hint = neutral ? challenge.label : 'انظر مباشرة للكاميرا بوجه محايد';
      });
      return;
    }
    if (done) {
      if (_index + 1 >= _challenges.length) {
        _finish(timedOut: false);
      } else {
        setState(() {
          _index++;
          _startChallenge();
        });
      }
    } else {
      setState(() => _hint = challenge.label);
    }
  }

  Future<void> _finish({required bool timedOut}) async {
    _timer?.cancel();
    final completed = timedOut ? _index : _challenges.length;
    final passed = completed == _challenges.length;
    final order = _challenges.map((c) => c.label).join('، ');
    final record = TestRecord(
      timestamp: DateTime.now(),
      kind: TestKind.active,
      attemptType: widget.attemptType,
      camera: _camera.side,
      judgedReal: passed,
      score: completed / _challenges.length,
      details: passed
          ? 'اكتملت التحديات: $order'
          : 'اكتمل $completed/${_challenges.length} — انتهت مهلة «${_challenges[_index].label}»',
    );
    setState(() => _result = record);
    await HistoryStore.instance.add(record);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _camera.controller;
    final remaining = _deadline == null
        ? 0
        : (_deadline!.difference(DateTime.now()).inMilliseconds / 1000)
            .clamp(0, 99)
            .ceil();

    return Scaffold(
      appBar: AppBar(
        title: Text('الكشف النشط — ${widget.attemptType.label}'),
        actions: [
          IconButton(
            tooltip: _camera.isFront
                ? 'التبديل إلى الكاميرا الخلفية'
                : 'التبديل إلى الكاميرا الأمامية',
            onPressed: _switching ? null : _switchCamera,
            icon: const Icon(Icons.cameraswitch),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : Stack(
              children: [
                if (controller != null && controller.value.isInitialized)
                  Center(child: CameraPreview(controller))
                else
                  const Center(child: CircularProgressIndicator()),
                if (_result == null) ...[
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: _ChallengeProgress(
                      challenges: _challenges,
                      index: _index,
                    ),
                  ),
                  Positioned(
                    bottom: 24,
                    left: 16,
                    right: 16,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_challenges[_index].icon, size: 40),
                            Text(
                              _hint,
                              style: Theme.of(context).textTheme.headlineSmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text('الوقت المتبقي: $remaining ث'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ] else
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: ResultPanel(record: _result!, onRetry: _retry),
                  ),
              ],
            ),
    );
  }
}

class _ChallengeProgress extends StatelessWidget {
  const _ChallengeProgress({required this.challenges, required this.index});

  final List<Challenge> challenges;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        for (var i = 0; i < challenges.length; i++)
          Chip(
              avatar: Icon(
                i < index ? Icons.check_circle : challenges[i].icon,
                color: i < index ? Colors.green : null,
              ),
              label: Text(challenges[i].label),
              backgroundColor: i == index
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
          ),
      ],
    );
  }
}
