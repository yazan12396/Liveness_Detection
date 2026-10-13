import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:passive_liveness/passive_liveness.dart';

import '../models/test_record.dart';
import '../services/face_camera.dart';
import '../services/history_store.dart';
import '../widgets/result_panel.dart';

const int _sampleCount = 12;
const double _realRatioToPass = 0.6;

const _statusLabels = {
  LivenessStatus.real: 'حقيقي',
  LivenessStatus.spoof: 'تزييف',
  LivenessStatus.tooFar: 'اقترب من الكاميرا',
  LivenessStatus.tooClose: 'ابتعد قليلاً عن الكاميرا',
  LivenessStatus.invalidAspectRatio: 'أبعاد الوجه غير طبيعية',
  LivenessStatus.printSpoof: 'تزييف مطبوع',
  LivenessStatus.screenReplaySpoof: 'إعادة عرض من شاشة',
};

const _positionStatuses = {
  LivenessStatus.tooFar,
  LivenessStatus.tooClose,
  LivenessStatus.invalidAspectRatio,
};

class PassiveLivenessScreen extends StatefulWidget {
  const PassiveLivenessScreen({required this.attemptType, super.key});

  final AttemptType attemptType;

  @override
  State<PassiveLivenessScreen> createState() => _PassiveLivenessScreenState();
}

class _PassiveLivenessScreenState extends State<PassiveLivenessScreen> {
  final _camera = FaceCamera();
  final _faceDetector = FaceDetector(
    options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast),
  );
  final _liveness = PassiveLivenessDetector();
  static const _flashDuration = Duration(milliseconds: 300);
  final _flash = LivenessFlashController(flashDuration: _flashDuration);

  final List<LivenessResult> _samples = [];
  LivenessResult? _last;
  String _hint = 'جارٍ تحميل النموذج…';
  String? _error;
  TestRecord? _result;
  bool _switching = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _liveness.initialize();
      await _camera.start(_onFrame);
      if (mounted) setState(() => _hint = 'ضع وجهك داخل الإطار');
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذّر التشغيل: $e');
    }
  }

  @override
  void dispose() {
    _camera.dispose();
    _faceDetector.close();
    _liveness.dispose();
    _flash.dispose();
    super.dispose();
  }

  void _retry() {
    _liveness.resetEma();
    setState(() {
      _samples.clear();
      _last = null;
      _result = null;
      _hint = 'ضع وجهك داخل الإطار';
    });
  }

  /// Switching lens restarts the test so a record never mixes both cameras.
  Future<void> _switchCamera() async {
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
    if (_result != null || _switching || !_liveness.isInitialized) return;
    final input = _camera.toInputImage(image);
    if (input == null) return;

    final faces = await _faceDetector.processImage(input);
    if (!mounted || _result != null) return;
    if (faces.length != 1) {
      setState(() => _hint =
          faces.isEmpty ? 'لا يوجد وجه' : 'يجب أن يظهر وجه واحد فقط');
      return;
    }

    // ML Kit's box is in upright (rotated) space; the package maps it back to
    // the raw sensor buffer using the rotation on Android.
    final result = await _liveness.detectLivenessFromCameraImage(
      image,
      boundingBox: FaceBoundingBox.fromRect(faces.first.boundingBox),
      rotation: _camera.rotation,
    );
    if (!mounted || _result != null) return;

    if (_positionStatuses.contains(result.status)) {
      setState(() {
        _last = result;
        _hint = _statusLabels[result.status]!;
      });
      return;
    }

    _samples.add(result);
    // Flash at the start and halfway through so frames are captured both with
    // and without the extra screen light on the face.
    if (_samples.length == 1 || _samples.length == _sampleCount ~/ 2) {
      if (_camera.isFront) {
        _flash.triggerFlash();
      } else {
        _camera.pulseTorch(_flashDuration);
      }
    }
    setState(() {
      _last = result;
      _hint = 'ثبّت وجهك… جارٍ التحليل';
    });
    if (_samples.length >= _sampleCount) await _finish();
  }

  Future<void> _finish() async {
    final realCount = _samples.where((r) => r.isReal).length;
    final ratio = realCount / _samples.length;
    final meanScore =
        _samples.map((r) => r.realScore).reduce((a, b) => a + b) /
            _samples.length;
    final judgedReal = ratio >= _realRatioToPass;

    final counts = <LivenessStatus, int>{};
    for (final r in _samples.where((r) => !r.isReal)) {
      counts.update(r.status, (v) => v + 1, ifAbsent: () => 1);
    }
    final topSpoof = counts.isEmpty
        ? null
        : (counts.entries.toList()..sort((a, b) => b.value - a.value))
            .first
            .key;

    final record = TestRecord(
      timestamp: DateTime.now(),
      kind: TestKind.passive,
      attemptType: widget.attemptType,
      camera: _camera.side,
      judgedReal: judgedReal,
      score: meanScore,
      details: 'إطارات حقيقية $realCount/${_samples.length}'
          '${topSpoof == null ? '' : ' — أكثر حالة رفض: ${topSpoof.name}'}',
    );
    setState(() => _result = record);
    await HistoryStore.instance.add(record);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _camera.controller;
    final last = _last;

    return AdaptiveScreenFlashOverlay(
      controller: _flash,
      child: Scaffold(
        appBar: AppBar(
          title: Text('الكشف السلبي — ${widget.attemptType.label}'),
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
                  if (_result == null)
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
                              Text(
                                _hint,
                                style:
                                    Theme.of(context).textTheme.titleLarge,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: _samples.length / _sampleCount,
                              ),
                              const SizedBox(height: 8),
                              if (last != null)
                                Text(
                                  'الحالة: ${_statusLabels[last.status]} • '
                                  'realScore: ${last.realScore.toStringAsFixed(3)}',
                                ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: ResultPanel(record: _result!, onRetry: _retry),
                    ),
                ],
              ),
      ),
    );
  }
}
