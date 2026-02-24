import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/camera_service.dart';
import '../services/signal_processor.dart';
import '../services/hrv_calculator.dart';
import '../widgets/ppg_chart.dart';
import '../widgets/metric_card.dart';

class HrvScreen extends StatefulWidget {
  const HrvScreen({super.key});

  @override
  State<HrvScreen> createState() => _HrvScreenState();
}

class _HrvScreenState extends State<HrvScreen> with TickerProviderStateMixin {
  // Services
  final CameraService _cameraService = CameraService();
  final SignalProcessor _signalProcessor = SignalProcessor(sampleRate: 30);
  final HrvCalculator _hrvCalculator = HrvCalculator(sampleRate: 30);

  // State
  bool _isMeasuring = false;
  bool _cameraReady = false;
  bool _permissionGranted = false;
  double _signalQuality = 0.0;

  // Data buffers
  final List<double> _rawSignal = [];
  final List<double> _filteredSignal = [];
  final List<double> _chartData = [];
  static const int _maxChartPoints = 150;

  // Metrics
  HrvMetrics _metrics = HrvMetrics.empty;

  // Timer
  int _elapsedSeconds = 0;
  Timer? _timer;
  static const int _measurementDuration = 120; // 2 minutes

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Processing control
  int _frameCount = 0;
  static const int _peakDetectionInterval = 30; // run peak detection every 30 frames (~1 second)

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _initCamera();
  }

  Future<void> _initCamera() async {
    // Request camera permission
    final status = await Permission.camera.request();
    if (status.isGranted) {
      setState(() => _permissionGranted = true);
      final ready = await _cameraService.initialize();
      setState(() => _cameraReady = ready);
    } else {
      setState(() => _permissionGranted = false);
    }
  }

  void _startMeasurement() async {
    if (!_cameraReady) return;

    // Reset everything
    _rawSignal.clear();
    _filteredSignal.clear();
    _chartData.clear();
    _signalProcessor.reset();
    _hrvCalculator.reset();
    _frameCount = 0;
    _elapsedSeconds = 0;
    _metrics = HrvMetrics.empty;
    _signalQuality = 0.0;

    setState(() => _isMeasuring = true);

    // Enable wakelock
    await WakelockPlus.enable();

    // Start pulse animation
    _pulseController.repeat(reverse: true);

    // Start camera measurement
    await _cameraService.startMeasurement(_onLuminanceData);

    // Start timer
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _elapsedSeconds++;
      });
      if (_elapsedSeconds >= _measurementDuration) {
        _stopMeasurement();
      }
    });
  }

  void _onLuminanceData(double luminance, DateTime timestamp) {
    if (!_isMeasuring) return;

    _rawSignal.add(luminance);
    _frameCount++;

    // Apply bandpass filter
    final filtered = _signalProcessor.filter(luminance);
    _filteredSignal.add(filtered);

    // Update chart data
    _chartData.add(filtered);
    if (_chartData.length > _maxChartPoints) {
      _chartData.removeAt(0);
    }

    // Assess signal quality periodically
    if (_frameCount % 15 == 0) {
      _signalQuality = _signalProcessor.assessSignalQuality(_rawSignal);
    }

    // Run peak detection periodically
    if (_frameCount % _peakDetectionInterval == 0 && _filteredSignal.length > 60) {
      final peaks = _signalProcessor.detectPeaks(_filteredSignal);
      if (peaks.length >= 2) {
        final peakIndices = peaks.map((p) => p.index).toList();
        _metrics = _hrvCalculator.addPeaks(peakIndices);

        // Update pulse animation speed based on HR
        if (_metrics.heartRate > 0) {
          final bpmDuration = (60000 / _metrics.heartRate).round();
          _pulseController.duration =
              Duration(milliseconds: bpmDuration.clamp(300, 1500));
          if (_pulseController.isAnimating) {
            _pulseController.repeat(reverse: true);
          }
        }
      }
    }

    // Trigger UI update at ~10 fps for smooth chart
    if (_frameCount % 3 == 0) {
      if (mounted) setState(() {});
    }
  }

  void _stopMeasurement() async {
    _timer?.cancel();
    _timer = null;

    await _cameraService.stopMeasurement();
    await WakelockPlus.disable();

    _pulseController.stop();
    _pulseController.reset();

    if (mounted) {
      setState(() => _isMeasuring = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    _cameraService.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: !_permissionGranted
            ? _buildPermissionDenied()
            : !_cameraReady
                ? _buildLoading()
                : _buildMainContent(),
      ),
    );
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.camera_alt_outlined, size: 64, color: Color(0xFFff6b6b)),
            const SizedBox(height: 24),
            const Text(
              'Camera Permission Required',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'This app needs camera access to measure your heart rate and HRV using photoplethysmography (PPG).',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => openAppSettings(),
              icon: const Icon(Icons.settings),
              label: const Text('Open Settings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFff6b6b),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFFff6b6b)),
          SizedBox(height: 16),
          Text('Initializing camera...'),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _buildHeader(),
          const SizedBox(height: 16),

          // PPG Chart
          _buildChartSection(),
          const SizedBox(height: 16),

          // Signal quality & timer
          _buildStatusRow(),
          const SizedBox(height: 16),

          // Metrics grid
          _buildMetricsGrid(),
          const SizedBox(height: 16),

          // HRV Status
          Center(child: HrvStatusBadge(status: _metrics.hrvStatus)),
          const SizedBox(height: 20),

          // Start/Stop button
          _buildControlButton(),
          const SizedBox(height: 12),

          // Instructions
          if (!_isMeasuring) _buildInstructions(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _isMeasuring ? _pulseAnimation.value : 1.0,
              child: child,
            );
          },
          child: const Icon(Icons.favorite, color: Color(0xFFff6b6b), size: 28),
        ),
        const SizedBox(width: 10),
        const Text(
          'HRV Camera',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        const Spacer(),
        if (_isMeasuring && _metrics.heartRate > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFff6b6b).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.favorite, color: Color(0xFFff6b6b), size: 16),
                const SizedBox(width: 6),
                Text(
                  '${_metrics.heartRate.round()} bpm',
                  style: const TextStyle(
                    color: Color(0xFFff6b6b),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildChartSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'PPG Waveform',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            if (_isMeasuring)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _signalQuality > 0.5
                      ? const Color(0xFF4ecdc4)
                      : _signalQuality > 0.25
                          ? const Color(0xFFf9ca24)
                          : const Color(0xFFff6b6b),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (_signalQuality > 0.5
                              ? const Color(0xFF4ecdc4)
                              : const Color(0xFFff6b6b))
                          .withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            if (_isMeasuring) const SizedBox(width: 6),
            if (_isMeasuring)
              Text(
                _signalQuality > 0.5
                    ? 'Good Signal'
                    : _signalQuality > 0.25
                        ? 'Weak Signal'
                        : 'No Signal',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 11,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        PpgChart(
          data: _chartData,
          maxPoints: _maxChartPoints,
          height: 180,
        ),
      ],
    );
  }

  Widget _buildStatusRow() {
    return Row(
      children: [
        // Timer
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF16213e),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.timer_outlined,
                  color: Colors.white.withValues(alpha: 0.6),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  _isMeasuring
                      ? '${_formatTime(_elapsedSeconds)} / ${_formatTime(_measurementDuration)}'
                      : '${_formatTime(_measurementDuration)} total',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Signal quality bar
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF16213e),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.signal_cellular_alt,
                  color: Colors.white.withValues(alpha: 0.6),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _signalQuality,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation(
                        _signalQuality > 0.5
                            ? const Color(0xFF4ecdc4)
                            : _signalQuality > 0.25
                                ? const Color(0xFFf9ca24)
                                : const Color(0xFFff6b6b),
                      ),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(_signalQuality * 100).round()}%',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.7,
      children: [
        MetricCard(
          label: 'SDNN',
          value: _metrics.sdnn > 0 ? _metrics.sdnn.toStringAsFixed(1) : '--',
          unit: 'ms',
          icon: Icons.show_chart,
          color: const Color(0xFF4ecdc4),
        ),
        MetricCard(
          label: 'RMSSD',
          value: _metrics.rmssd > 0 ? _metrics.rmssd.toStringAsFixed(1) : '--',
          unit: 'ms',
          icon: Icons.timeline,
          color: const Color(0xFF45b7d1),
        ),
        MetricCard(
          label: 'pNN50',
          value: _metrics.pnn50 > 0 ? _metrics.pnn50.toStringAsFixed(1) : '--',
          unit: '%',
          icon: Icons.percent,
          color: const Color(0xFFf9ca24),
        ),
        MetricCard(
          label: 'Stress Index',
          value: _metrics.stressIndex > 0
              ? _metrics.stressIndex.toStringAsFixed(0)
              : '--',
          unit: '',
          icon: Icons.psychology,
          color: const Color(0xFFff6b6b),
        ),
      ],
    );
  }

  Widget _buildControlButton() {
    return GestureDetector(
      onTap: _isMeasuring ? _stopMeasurement : _startMeasurement,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _isMeasuring
                ? [const Color(0xFFff4757), const Color(0xFFff6b81)]
                : [const Color(0xFFff6b6b), const Color(0xFFee5a24)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: (_isMeasuring
                      ? const Color(0xFFff4757)
                      : const Color(0xFFff6b6b))
                  .withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isMeasuring ? Icons.stop_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 8),
              Text(
                _isMeasuring ? 'Stop Measurement' : 'Start Measurement',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstructions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16213e).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How to measure:',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          _buildInstruction('1', 'Place your fingertip gently over the back camera and flash'),
          const SizedBox(height: 6),
          _buildInstruction('2', 'Keep still and maintain light pressure'),
          const SizedBox(height: 6),
          _buildInstruction('3', 'Wait for the signal to stabilize (green indicator)'),
          const SizedBox(height: 6),
          _buildInstruction('4', 'Measurement takes 2 minutes for accurate HRV'),
        ],
      ),
    );
  }

  Widget _buildInstruction(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: const Color(0xFFff6b6b).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Color(0xFFff6b6b),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 13,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
