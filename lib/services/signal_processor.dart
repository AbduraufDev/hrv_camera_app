import 'dart:math';
import 'dart:typed_data';

/// Second-order section (biquad) coefficients for IIR filtering.
class BiquadSection {
  final double b0, b1, b2, a1, a2;
  double x1 = 0, x2 = 0, y1 = 0, y2 = 0;

  BiquadSection(this.b0, this.b1, this.b2, this.a1, this.a2);

  double process(double x) {
    final y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1;
    x1 = x;
    y2 = y1;
    y1 = y;
    return y;
  }

  void reset() {
    x1 = x2 = y1 = y2 = 0;
  }
}

/// Detected peak with sample index and amplitude.
class Peak {
  final int index;
  final double value;
  final double prominence;
  const Peak(this.index, this.value, [this.prominence = 0]);
}

/// Advanced PPG signal processor with adaptive filtering and robust peak detection.
/// Based on research: Aboy++ algorithm and HRVCam methodology.
class SignalProcessor {
  final double _sampleRate;

  // Butterworth bandpass filter sections
  late List<BiquadSection> _bpSections;

  // Smoothing filter for noise reduction
  late List<BiquadSection> _smoothSections;

  // Adaptive parameters
  double _estimatedHR = 70.0; // Initial HR estimate in BPM
  double _adaptiveThreshold = 0.0;

  // Signal buffers for advanced processing
  final List<double> _rawBuffer = [];
  final List<double> _filteredBuffer = [];
  final List<int> _recentPeakIndices = [];

  // Constants based on research
  static const int _windowSize = 300; // 10 seconds at 30 fps
  static const double _minHR = 40.0; // BPM
  static const double _maxHR = 200.0; // BPM
  static const double _refractoryPeriod = 0.25; // 250ms minimum between beats

  // Elgendi parameters (optimized)
  static const double _w1Duration = 0.111; // systolic peak window
  static const double _w2Duration = 0.667; // beat window

  SignalProcessor({double sampleRate = 30.0}) : _sampleRate = sampleRate {
    _initFilters();
  }

  void _initFilters() {
    // Primary bandpass: 0.75-3.5 Hz (45-210 BPM range, optimized)
    _bpSections = _computeButterworthBandpass(0.75, 3.5, _sampleRate, 2);

    // Smoothing lowpass at 8 Hz for noise reduction
    _smoothSections = _computeButterworthLowpass(8.0, _sampleRate);
  }

  /// Compute Butterworth bandpass filter with specified order.
  List<BiquadSection> _computeButterworthBandpass(
      double f1, double f2, double fs, int order) {
    final sections = <BiquadSection>[];
    final wc = sqrt(2 * pi * f1 / fs * 2 * pi * f2 / fs);
    final bw = 2 * pi * f2 / fs - 2 * pi * f1 / fs;

    for (int i = 0; i < order; i++) {
      final angle = pi * (2 * i + 1) / (4 * order) + pi / 2;
      final q = 1 / (2 * cos(angle));
      final alpha = sin(wc) / (2 * q.abs());
      final cosW = cos(wc);

      final a0 = 1 + alpha;
      sections.add(BiquadSection(
        alpha / a0,
        0.0,
        -alpha / a0,
        -2 * cosW / a0,
        (1 - alpha) / a0,
      ));
    }
    return sections;
  }

  /// Compute Butterworth lowpass filter.
  List<BiquadSection> _computeButterworthLowpass(double fc, double fs) {
    final wc = tan(pi * fc / fs);
    final k = wc * wc;
    final q = 0.7071;
    final norm = 1 / (1 + wc / q + k);

    return [
      BiquadSection(
        k * norm,
        2 * k * norm,
        k * norm,
        2 * (k - 1) * norm,
        (1 - wc / q + k) * norm,
      ),
    ];
  }

  /// Process a single raw sample through filters.
  double filter(double sample) {
    // Apply smoothing first
    double smoothed = sample;
    for (final section in _smoothSections) {
      smoothed = section.process(smoothed);
    }

    // Then bandpass
    double filtered = smoothed;
    for (final section in _bpSections) {
      filtered = section.process(filtered);
    }

    _rawBuffer.add(sample);
    _filteredBuffer.add(filtered);

    // Keep buffers manageable
    if (_rawBuffer.length > _windowSize * 2) {
      _rawBuffer.removeRange(0, _windowSize);
      _filteredBuffer.removeRange(0, _windowSize);
    }

    return filtered;
  }

  /// Reset all states.
  void reset() {
    for (final section in _bpSections) {
      section.reset();
    }
    for (final section in _smoothSections) {
      section.reset();
    }
    _rawBuffer.clear();
    _filteredBuffer.clear();
    _recentPeakIndices.clear();
    _estimatedHR = 70.0;
    _adaptiveThreshold = 0.0;
  }

  /// Advanced peak detection using Aboy++ methodology.
  List<Peak> detectPeaks(List<double> signal) {
    if (signal.length < 30) return [];

    final n = signal.length;
    final w1 = max(3, (_w1Duration * _sampleRate).round());
    final w2 = max(10, (_w2Duration * _sampleRate).round());

    // Step 1: Compute first derivative for slope detection
    final derivative = List<double>.filled(n, 0);
    for (int i = 1; i < n - 1; i++) {
      derivative[i] = (signal[i + 1] - signal[i - 1]) / 2;
    }

    // Step 2: Square the signal to enhance peaks
    final squared = signal.map((s) => s * s).toList();

    // Step 3: Moving averages (Elgendi method)
    final ma1 = _movingAverage(squared, w1);
    final ma2 = _movingAverage(squared, w2);

    // Step 4: Adaptive threshold based on signal statistics
    final signalStd = _standardDeviation(signal);
    final beta = 0.02 + 0.01 * (signalStd / 10).clamp(0, 1);

    // Step 5: Find blocks of interest
    final blocks = <List<int>>[];
    int? blockStart;
    for (int i = 0; i < n; i++) {
      final threshold = ma2[i] + beta;
      if (ma1[i] > threshold) {
        blockStart ??= i;
      } else {
        if (blockStart != null && (i - blockStart) >= 2) {
          blocks.add([blockStart, i - 1]);
        }
        blockStart = null;
      }
    }
    if (blockStart != null && (n - blockStart) >= 2) {
      blocks.add([blockStart, n - 1]);
    }

    // Step 6: Find peaks with prominence calculation
    final peaks = <Peak>[];
    for (final block in blocks) {
      final start = block[0];
      final end = block[1];

      // Find maximum in block
      double maxVal = -double.infinity;
      int maxIdx = start;
      for (int i = start; i <= end; i++) {
        if (signal[i] > maxVal) {
          maxVal = signal[i];
          maxIdx = i;
        }
      }

      // Calculate prominence
      final leftMin = _findMinInRange(signal, max(0, maxIdx - w2), maxIdx);
      final rightMin = _findMinInRange(signal, maxIdx, min(n - 1, maxIdx + w2));
      final prominence = maxVal - max(leftMin, rightMin);

      // Only add if prominence is significant (25% of average amplitude)
      if (prominence > signalStd * 0.5) {
        peaks.add(Peak(maxIdx, maxVal, prominence));
      }
    }

    // Step 7: Adaptive refractory period based on estimated HR
    final minPeakDistance = (_sampleRate * 60 / _maxHR).round();
    final maxPeakDistance = (_sampleRate * 60 / _minHR).round();
    final expectedDistance = (_sampleRate * 60 / _estimatedHR).round();
    final refractorySamples = max(minPeakDistance, (expectedDistance * 0.6).round());

    // Step 8: Filter peaks by refractory period
    final filtered = <Peak>[];
    for (final peak in peaks) {
      if (filtered.isEmpty) {
        filtered.add(peak);
      } else {
        final distance = peak.index - filtered.last.index;
        if (distance >= refractorySamples) {
          filtered.add(peak);
        } else if (peak.prominence > filtered.last.prominence * 1.2) {
          // Replace if new peak is significantly more prominent
          filtered[filtered.length - 1] = peak;
        }
      }
    }

    // Step 9: Update HR estimate from detected peaks
    if (filtered.length >= 3) {
      final intervals = <double>[];
      for (int i = 1; i < filtered.length; i++) {
        final interval = (filtered[i].index - filtered[i - 1].index) / _sampleRate;
        if (interval > 0.3 && interval < 1.5) {
          intervals.add(interval);
        }
      }
      if (intervals.isNotEmpty) {
        final meanInterval = intervals.reduce((a, b) => a + b) / intervals.length;
        final newHR = 60.0 / meanInterval;
        // Smooth HR estimate
        _estimatedHR = _estimatedHR * 0.7 + newHR * 0.3;
        _estimatedHR = _estimatedHR.clamp(_minHR, _maxHR);
      }
    }

    return filtered;
  }

  /// Detect heart rate using FFT (frequency domain backup method).
  double detectHRByFFT(List<double> signal) {
    if (signal.length < 128) return _estimatedHR;

    // Use power of 2 length for FFT
    final fftSize = _nextPowerOf2(signal.length);
    final paddedSignal = List<double>.filled(fftSize, 0);
    for (int i = 0; i < signal.length; i++) {
      paddedSignal[i] = signal[i];
    }

    // Simple DFT for dominant frequency
    double maxPower = 0;
    double dominantFreq = 1.0;

    final minBin = (fftSize * 0.75 / _sampleRate).round(); // 0.75 Hz = 45 BPM
    final maxBin = (fftSize * 3.5 / _sampleRate).round();  // 3.5 Hz = 210 BPM

    for (int k = minBin; k <= maxBin && k < fftSize ~/ 2; k++) {
      double real = 0, imag = 0;
      for (int n = 0; n < fftSize; n++) {
        final angle = -2 * pi * k * n / fftSize;
        real += paddedSignal[n] * cos(angle);
        imag += paddedSignal[n] * sin(angle);
      }
      final power = real * real + imag * imag;
      if (power > maxPower) {
        maxPower = power;
        dominantFreq = k * _sampleRate / fftSize;
      }
    }

    return dominantFreq * 60; // Convert Hz to BPM
  }

  int _nextPowerOf2(int n) {
    int power = 1;
    while (power < n) power *= 2;
    return power;
  }

  double _findMinInRange(List<double> signal, int start, int end) {
    double minVal = double.infinity;
    for (int i = start; i <= end && i < signal.length; i++) {
      if (signal[i] < minVal) minVal = signal[i];
    }
    return minVal;
  }

  List<double> _movingAverage(List<double> data, int windowSize) {
    final n = data.length;
    final result = List<double>.filled(n, 0);
    double sum = 0;

    for (int i = 0; i < n; i++) {
      sum += data[i];
      if (i >= windowSize) {
        sum -= data[i - windowSize];
      }
      final count = min(i + 1, windowSize);
      result[i] = sum / count;
    }

    return result;
  }

  double _standardDeviation(List<double> data) {
    if (data.length < 2) return 0;
    final mean = data.reduce((a, b) => a + b) / data.length;
    final sumSq = data.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b);
    return sqrt(sumSq / (data.length - 1));
  }

  /// Advanced signal quality assessment.
  double assessSignalQuality(List<double> rawSignal) {
    if (rawSignal.length < 60) return 0.0;

    final window = rawSignal.length > 90
        ? rawSignal.sublist(rawSignal.length - 90)
        : rawSignal;

    // 1. Amplitude range check
    final minVal = window.reduce(min);
    final maxVal = window.reduce(max);
    final range = maxVal - minVal;

    double amplitudeScore;
    if (range < 1.0) {
      amplitudeScore = 0.0;
    } else if (range > 100) {
      amplitudeScore = 0.2;
    } else {
      amplitudeScore = (range / 20.0).clamp(0.0, 1.0);
    }

    // 2. Mean luminance check (finger coverage)
    final mean = window.reduce((a, b) => a + b) / window.length;
    double levelScore;
    if (mean > 150) {
      levelScore = 1.0;
    } else if (mean > 100) {
      levelScore = 0.8;
    } else if (mean > 50) {
      levelScore = 0.5;
    } else {
      levelScore = 0.1;
    }

    // 3. Periodicity check using autocorrelation
    final periodicityScore = _assessPeriodicity(window);

    // 4. Stability check
    final halfLen = window.length ~/ 2;
    final var1 = _variance(window.sublist(0, halfLen));
    final var2 = _variance(window.sublist(halfLen));
    final stabilityScore = var1 > 0 && var2 > 0
        ? (min(var1, var2) / max(var1, var2)).clamp(0.0, 1.0)
        : 0.0;

    // Weighted combination
    return (amplitudeScore * 0.25 +
            levelScore * 0.25 +
            periodicityScore * 0.35 +
            stabilityScore * 0.15).clamp(0.0, 1.0);
  }

  /// Assess signal periodicity using simplified autocorrelation.
  double _assessPeriodicity(List<double> signal) {
    if (signal.length < 60) return 0.0;

    final n = signal.length;
    final mean = signal.reduce((a, b) => a + b) / n;
    final centered = signal.map((x) => x - mean).toList();

    // Check for periodicity at expected heart rate intervals
    final minLag = (_sampleRate * 0.4).round(); // 150 BPM max
    final maxLag = (_sampleRate * 1.2).round(); // 50 BPM min

    double maxCorr = 0;
    double variance = centered.map((x) => x * x).reduce((a, b) => a + b);

    if (variance < 0.01) return 0.0;

    for (int lag = minLag; lag <= maxLag && lag < n ~/ 2; lag++) {
      double corr = 0;
      for (int i = 0; i < n - lag; i++) {
        corr += centered[i] * centered[i + lag];
      }
      corr /= variance;
      if (corr > maxCorr) maxCorr = corr;
    }

    return maxCorr.clamp(0.0, 1.0);
  }

  double _variance(List<double> data) {
    if (data.isEmpty) return 0;
    final mean = data.reduce((a, b) => a + b) / data.length;
    return data.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / data.length;
  }

  /// Get current estimated heart rate.
  double get estimatedHR => _estimatedHR;

  /// Get filtered signal buffer for analysis.
  List<double> get filteredBuffer => List.unmodifiable(_filteredBuffer);
}
