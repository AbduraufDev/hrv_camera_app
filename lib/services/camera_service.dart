import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Callback with extracted luminance value (red channel average).
typedef LuminanceCallback = void Function(double luminance, DateTime timestamp);

/// Manages camera lifecycle, torch, and frame processing for PPG measurement.
class CameraService {
  CameraController? _controller;
  bool _isProcessing = false;
  bool _isTorchOn = false;
  bool _isStreaming = false;
  LuminanceCallback? _onLuminance;

  // Frame rate control
  DateTime _lastFrameTime = DateTime.now();
  static const int _targetFps = 30;
  static const Duration _minFrameInterval =
      Duration(milliseconds: 1000 ~/ _targetFps);

  /// Whether the camera is initialized and ready.
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  /// The camera controller for preview display.
  CameraController? get controller => _controller;

  /// Initialize the back camera with lowest resolution for speed.
  Future<bool> initialize() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return false;

      // Use the back camera
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        backCamera,
        ResolutionPreset.low, // Low res = faster processing
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();

      // Lock exposure and focus for stable readings
      try {
        await _controller!.setExposureMode(ExposureMode.locked);
      } catch (_) {}
      try {
        await _controller!.setFocusMode(FocusMode.locked);
      } catch (_) {}

      return true;
    } catch (e) {
      debugPrint('Camera init error: $e');
      return false;
    }
  }

  /// Start image stream and torch for PPG measurement.
  Future<void> startMeasurement(LuminanceCallback onLuminance) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    _onLuminance = onLuminance;

    // Turn on torch
    try {
      await _controller!.setFlashMode(FlashMode.torch);
      _isTorchOn = true;
    } catch (e) {
      debugPrint('Torch error: $e');
    }

    // Start image stream
    if (!_isStreaming) {
      await _controller!.startImageStream(_processFrame);
      _isStreaming = true;
    }
  }

  /// Process each camera frame to extract luminance.
  void _processFrame(CameraImage image) {
    if (_isProcessing || _onLuminance == null) return;

    // Frame rate limiting
    final now = DateTime.now();
    if (now.difference(_lastFrameTime) < _minFrameInterval) return;
    _lastFrameTime = now;

    _isProcessing = true;

    try {
      final luminance = _extractRedChannel(image);
      _onLuminance!(luminance, now);
    } catch (e) {
      debugPrint('Frame processing error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Extract average red channel value from camera image.
  /// For YUV420: Y plane gives luminance; for PPG with torch, red dominates.
  /// We use center region for best signal quality.
  double _extractRedChannel(CameraImage image) {
    final plane = image.planes[0]; // Y plane (luminance)
    final bytes = plane.bytes;
    final width = image.width;
    final height = image.height;
    final rowStride = plane.bytesPerRow;

    // Sample from center 50% of the image for better SNR
    final startX = width ~/ 4;
    final endX = (width * 3) ~/ 4;
    final startY = height ~/ 4;
    final endY = (height * 3) ~/ 4;

    double sum = 0;
    int count = 0;

    // Sample every 2nd pixel for speed while maintaining accuracy
    for (int y = startY; y < endY; y += 2) {
      for (int x = startX; x < endX; x += 2) {
        final index = y * rowStride + x;
        if (index < bytes.length) {
          sum += bytes[index];
          count++;
        }
      }
    }

    return count > 0 ? sum / count : 0;
  }

  /// Stop the image stream and torch.
  Future<void> stopMeasurement() async {
    if (_isStreaming && _controller != null) {
      try {
        await _controller!.stopImageStream();
      } catch (_) {}
      _isStreaming = false;
    }

    if (_isTorchOn && _controller != null) {
      try {
        await _controller!.setFlashMode(FlashMode.off);
      } catch (_) {}
      _isTorchOn = false;
    }

    _onLuminance = null;
  }

  /// Dispose camera resources.
  Future<void> dispose() async {
    await stopMeasurement();
    await _controller?.dispose();
    _controller = null;
  }
}
