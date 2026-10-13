import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Size;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../models/test_record.dart';

typedef FrameHandler = Future<void> Function(CameraImage image);

/// Front or rear camera streaming NV21 frames, plus conversion to ML Kit input.
class FaceCamera {
  /// Last lens the tester chose; new test screens start with it.
  static CameraSide preferredSide = CameraSide.front;

  CameraController? controller;
  CameraSide side = preferredSide;
  late CameraDescription _description;
  bool _processing = false;

  bool get isFront => side == CameraSide.front;

  /// Rotation of the sensor relative to the (portrait-locked) screen. In
  /// portrait this is the ML Kit rotation for both front and rear lenses.
  int get rotation => _description.sensorOrientation;

  Future<void> start(FrameHandler onFrame) async {
    final cameras = await availableCameras();
    final wanted =
        isFront ? CameraLensDirection.front : CameraLensDirection.back;
    _description = cameras.firstWhere(
      (c) => c.lensDirection == wanted,
      orElse: () => cameras.first,
    );
    final c = CameraController(
      _description,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    controller = c;
    await c.initialize();
    await c.startImageStream((image) async {
      // Drop frames while the previous one is still being analysed.
      if (_processing) return;
      _processing = true;
      try {
        await onFrame(image);
      } catch (e, st) {
        debugPrint('frame error: $e\n$st');
      } finally {
        _processing = false;
      }
    });
  }

  Future<void> switchSide(FrameHandler onFrame) async {
    await dispose();
    side = isFront ? CameraSide.rear : CameraSide.front;
    preferredSide = side;
    await start(onFrame);
  }

  /// Briefly lights the rear LED — the screen flash can't reach a subject
  /// in front of the rear camera.
  Future<void> pulseTorch(Duration duration) async {
    final c = controller;
    if (c == null || isFront) return;
    try {
      await c.setFlashMode(FlashMode.torch);
      await Future<void>.delayed(duration);
      await controller?.setFlashMode(FlashMode.off);
    } catch (e) {
      debugPrint('torch error: $e');
    }
  }

  Future<void> dispose() async {
    final c = controller;
    controller = null;
    if (c == null) return;
    if (c.value.isStreamingImages) {
      await c.stopImageStream();
    }
    await c.dispose();
  }

  InputImage? toInputImage(CameraImage image) {
    final rot = InputImageRotationValue.fromRawValue(rotation);
    final format = InputImageFormatValue.fromRawValue(image.format.raw as int);
    if (rot == null || format != InputImageFormat.nv21) return null;
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rot,
        format: InputImageFormat.nv21,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }
}
