import 'dart:math';

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
  const Peak(this.index, this.value);
}

/// PPG signal processor with Butterworth bandpass filter and Elgendi peak detection.
class SignalProcessor {
  // Butterworth bandpass filter (4th order = 2 biquad sections)
  // Designed for 0.7–4.0 Hz passband at 30 Hz sample rate (heart rate range ~42–240 bpm)
  late List<BiquadSection> _sections;
  final double _sampleRate;

  // Elgendi peak detection parameters
  static const double _w1Duration = 0.111; // systolic peak window (seconds)
  static const double _w2Duration = 0.667; // beat window (seconds)
  static const double _beta = 0.02; // threshold offset

  // Signal quality
  final List<double> _rawBuffer = [];
  static const int _qualityWindowSize = 90; // 3 seconds at 30 fps

  SignalProcessor({double sampleRate = 30.0}) : _sampleRate = sampleRate {
    _initFilter(sampleRate);
  }

  void _initFilter(double fs) {
    _sections = _computeButterworthBandpass(0.7, 4.0, fs);
  }

  /// Compute Butterworth bandpass filter as cascaded biquad sections.
  /// Uses bilinear transform method.
  List<BiquadSection> _computeButterworthBandpass(
      double f1, double f2, double fs) {
    // For a 4th order bandpass (2nd order prototype), we get 4 poles = 2 biquad sections
    // Using cookbook formulas for bandpass biquads

    final w01 = 2 * pi * f1 / fs;
    final w02 = 2 * pi * f2 / fs;
    final wc = sqrt(w01 * w02);

    // Section 1: narrower Q
    final q1 = 0.7071; // 1/sqrt(2) for Butterworth
    final alpha1 = sin(wc) / (2 * q1);
    final cosW = cos(wc);

    final b0_1 = alpha1;
    final b1_1 = 0.0;
    final b2_1 = -alpha1;
    final a0_1 = 1 + alpha1;
    final a1_1 = -2 * cosW;
    final a2_1 = 1 - alpha1;

    // Section 2: wider Q for sharper rolloff
    final q2 = 1.3066; // Second Butterworth pole radius
    final alpha2 = sin(wc) / (2 * q2);

    final b0_2 = alpha2;
    final b1_2 = 0.0;
    final b2_2 = -alpha2;
    final a0_2 = 1 + alpha2;
    final a1_2 = -2 * cosW;
    final a2_2 = 1 - alpha2;

    return [
      BiquadSection(
          b0_1 / a0_1, b1_1 / a0_1, b2_1 / a0_1, a1_1 / a0_1, a2_1 / a0_1),
      BiquadSection(
          b0_2 / a0_2, b1_2 / a0_2, b2_2 / a0_2, a1_2 / a0_2, a2_2 / a0_2),
    ];
  }


  /// Process a single raw sample through the bandpass filter.
  double filter(double sample) {
    double y = sample;
    for (final section in _sections) {
      y = section.process(y);
    }
    return y;
  }

  /// Reset all filter states.
  void reset() {
    for (final section in _sections) {
      section.reset();
    }
    _rawBuffer.clear();
  }

  /// Detect peaks using Elgendi's two moving average method.
  /// Input: filtered PPG signal buffer.
  /// Returns list of peak indices.
  List<Peak> detectPeaks(List<double> signal) {
    if (signal.length < 10) return [];

    final n = signal.length;
    final w1 = max(1, (_w1Duration * _sampleRate).round()); // systolic window
    final w2 = max(1, (_w2Duration * _sampleRate).round()); // beat window

    // Squaring to enhance peaks
    final squared = signal.map((s) => s * s).toList();

    // Moving average with window w1 (peak emphasis)
    final ma1 = _movingAverage(squared, w1);
    // Moving average with window w2 (beat emphasis)
    final ma2 = _movingAverage(squared, w2);

    // Threshold: ma2 + beta offset
    final threshold = ma2.map((v) => v + _beta).toList();

    // Blocks of interest where ma1 > threshold
    final blocks = <List<int>>[];
    int? blockStart;
    for (int i = 0; i < n; i++) {
      if (ma1[i] > threshold[i]) {
        blockStart ??= i;
      } else {
        if (blockStart != null) {
          blocks.add([blockStart, i - 1]);
          blockStart = null;
        }
      }
    }
    if (blockStart != null) {
      blocks.add([blockStart, n - 1]);
    }

    // Find maximum within each block
    final peaks = <Peak>[];
    for (final block in blocks) {
      final start = block[0];
      final end = block[1];
      if (end - start < 2) continue; // skip very narrow blocks

      double maxVal = -double.infinity;
      int maxIdx = start;
      for (int i = start; i <= end; i++) {
        if (signal[i] > maxVal) {
          maxVal = signal[i];
          maxIdx = i;
        }
      }
      peaks.add(Peak(maxIdx, maxVal));
    }

    // Remove peaks that are too close together (refractory period ~300ms)
    final refractorySamples = (0.3 * _sampleRate).round();
    final filtered = <Peak>[];
    for (final peak in peaks) {
      if (filtered.isEmpty ||
          (peak.index - filtered.last.index) >= refractorySamples) {
        filtered.add(peak);
      } else if (peak.value > filtered.last.value) {
        filtered[filtered.length - 1] = peak;
      }
    }

    return filtered;
  }

  /// Compute moving average of given window size.
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

  /// Assess signal quality from raw buffer (0.0 to 1.0).
  /// Based on amplitude consistency, periodicity, and noise level.
  double assessSignalQuality(List<double> rawSignal) {
    if (rawSignal.length < 30) return 0.0;

    // Use last N samples
    final window = rawSignal.length > _qualityWindowSize
        ? rawSignal.sublist(rawSignal.length - _qualityWindowSize)
        : rawSignal;

    // 1. Check amplitude range (should be reasonable for finger-on-camera)
    final minVal = window.reduce(min);
    final maxVal = window.reduce(max);
    final range = maxVal - minVal;

    // Finger on camera typically shows high red channel values with pulsatile variation
    double amplitudeScore;
    if (range < 0.5) {
      amplitudeScore = 0.0; // Too flat, probably no finger
    } else if (range > 50) {
      amplitudeScore = 0.3; // Too noisy
    } else {
      amplitudeScore = min(1.0, range / 15.0);
    }

    // 2. Check mean level (finger on camera = high luminance in red channel)
    final mean = window.reduce((a, b) => a + b) / window.length;
    double levelScore;
    if (mean > 100) {
      levelScore = 1.0; // Good finger coverage
    } else if (mean > 50) {
      levelScore = 0.6;
    } else {
      levelScore = 0.2; // Probably no finger
    }

    // 3. Check signal variance stability (should be relatively stable)
    final halfLen = window.length ~/ 2;
    final firstHalf = window.sublist(0, halfLen);
    final secondHalf = window.sublist(halfLen);
    final var1 = _variance(firstHalf);
    final var2 = _variance(secondHalf);
    final varRatio = var1 > 0 ? min(var1, var2) / max(var1, var2) : 0.0;
    final stabilityScore = varRatio;

    return (amplitudeScore * 0.4 + levelScore * 0.35 + stabilityScore * 0.25)
        .clamp(0.0, 1.0);
  }

  double _variance(List<double> data) {
    if (data.isEmpty) return 0;
    final mean = data.reduce((a, b) => a + b) / data.length;
    return data.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
        data.length;
  }
}
