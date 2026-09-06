import 'dart:convert';

import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../logging/app_log.dart';

/// Handles crash-scene photo capture for Gemma 4 vision triage.
///
/// Gemma 4 is multimodal — it analyzes a photo of the crash scene alongside the
/// voice transcript to detect: fire, smoke, trapped persons, vehicle count,
/// damage severity, fluid spills, and road type.
///
/// This is a key Gemma-4-specific capability. No other model in the inference
/// stack supports image analysis.
///
/// ┌──────────────────────────────────────────────────────────────────────────┐
/// │ Usage pattern — bystander explicitly captures scene photo:               │
/// │                                                                          │
/// │   final photo = await CameraTriageService.captureBystanderPhoto();       │
/// │   final result = await aiTriage.triageWithScenePhoto(                    │
/// │     transcript: '...', photo: photo, ...);                               │
/// │                                                                          │
/// │ This replaces the previous "silent auto-capture at SOS trigger" approach │
/// │ which was unreliable: at auto-SOS time, the phone is typically in a      │
/// │ pocket or facing seat fabric, not the scene.                             │
/// │                                                                          │
/// │ Explicit bystander capture = accurate scene photo every time.            │
/// └──────────────────────────────────────────────────────────────────────────┘
class CameraTriageService {
  static final _picker = ImagePicker();

  /// Explicit bystander-initiated scene photo capture.
  ///
  /// Opens the camera for the bystander to frame the crash scene.
  /// Returns [CapturedScenePhoto] with base64 JPEG, or null if:
  ///   • User cancels the camera
  ///   • Camera permission denied
  ///   • Platform is web or desktop
  ///
  /// Called from the bystander flow UI — NOT from auto-SOS trigger.
  static Future<CapturedScenePhoto?> captureBystanderPhoto() async {
    return _pickImage(ImageSource.camera);
  }

  /// Explicit bystander-initiated scene photo selection from gallery.
  static Future<CapturedScenePhoto?> pickPhotoFromGallery() async {
    return _pickImage(ImageSource.gallery);
  }

  static Future<CapturedScenePhoto?> _pickImage(ImageSource source) async {
    try {
      // Ensure permission is granted before invoking the native camera intent.
      final cam = await Permission.camera.status;
      if (!cam.isGranted) {
        final next = await Permission.camera.request();
        if (!next.isGranted) {
          if (next.isPermanentlyDenied) {
            // Best-effort: prompt user to enable camera permission in Settings.
            openAppSettings();
          }
          appLog.w('[CameraTriageService] Camera permission denied');
          return null;
        }
      }

      final photo = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 768,
        imageQuality: 75,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (photo == null) {
        appLog.d('[CameraTriageService] User cancelled image selection');
        return null;
      }

      final bytes = await photo.readAsBytes();
      if (bytes.isEmpty) return null;

      final base64Str = base64Encode(bytes);
      appLog.i(
        '[CameraTriageService] Image selected (${source.name}): '
        '${(bytes.length / 1024).round()} KB',
      );

      return CapturedScenePhoto(
        base64Jpeg: base64Str,
        sizeBytes: bytes.length,
        capturedAt: DateTime.now().toUtc(),
      );
    } on Object catch (e, st) {
      appLog.w(
        '[CameraTriageService] Image selection failed',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  /// Silent camera capture — retained for internal use during onboarding tests.
  ///
  /// NOT called during auto-SOS: at crash trigger time the phone is in a pocket.
  /// Use [captureBystanderPhoto] for explicit user-initiated capture.
  ///
  /// [timeout] — max wait before giving up and returning null.
  static Future<CapturedScenePhoto?> captureScenePhoto({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      final photo = await _picker
          .pickImage(
            source: ImageSource.camera,
            maxWidth: 640,
            maxHeight: 480,
            imageQuality: 60,
            preferredCameraDevice: CameraDevice.rear,
          )
          .timeout(timeout);

      if (photo == null) return null;

      final bytes = await photo.readAsBytes();
      if (bytes.isEmpty) return null;

      final base64Str = base64Encode(bytes);
      return CapturedScenePhoto(
        base64Jpeg: base64Str,
        sizeBytes: bytes.length,
        capturedAt: DateTime.now().toUtc(),
      );
    } on Object catch (e) {
      appLog.d('[CameraTriageService] Silent capture failed: $e');
      return null;
    }
  }
}

/// Crash-scene photo ready for Gemma 4 vision triage.
class CapturedScenePhoto {
  final String base64Jpeg;
  final int sizeBytes;
  final DateTime capturedAt;

  const CapturedScenePhoto({
    required this.base64Jpeg,
    required this.sizeBytes,
    required this.capturedAt,
  });

  int get sizeKb => sizeBytes ~/ 1024;
}
