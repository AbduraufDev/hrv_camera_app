import 'dart:math';

/// HRV metrics computed from RR intervals.
class HrvMetrics {
  final double heartRate; // bpm
  final double sdnn; // ms
  final double rmssd; // ms
  final double pnn50; // percentage
  final double stressIndex; // Baevsky's stress index
  final double amo50; // Amplitude of mode (%)
  final String hrvStatus; // "Excellent", "Good", "Fair", "Poor"
  final int validBeats;
  final double sdsd; // Standard deviation of successive differences
  final double cvRR; // Coefficient of variation

  const HrvMetrics({
    required this.heartRate,
    required this.sdnn,
    required this.rmssd,
    required this.pnn50,
    required this.stressIndex,
    required this.amo50,
    required this.hrvStatus,
    required this.validBeats,
    required this.sdsd,
    required this.cvRR,
  });

  static const empty = HrvMetrics(
    heartRate: 0,
    sdnn: 0,
    rmssd: 0,
    pnn50: 0,
    stressIndex: 0,
    amo50: 0,
    hrvStatus: '--',
    validBeats: 0,
    sdsd: 0,
    cvRR: 0,
  );
}

/// Advanced HRV calculator with improved RR interval validation.
/// Based on research guidelines for camera-based PPG.
class HrvCalculator {
  final List<double> _rrIntervals = []; // in milliseconds
  final List<int> _peakTimestamps = []; // for temporal analysis
  final double _sampleRate;

  // Physiological limits (relaxed for better HRV capture)
  static const double _minRR = 300; // ms (~200 bpm)
  static const double _maxRR = 1800; // ms (~33 bpm)
  static const double _maxRRChange = 0.50; // 50% beat-to-beat change (allow natural variability)
  static const double _ectopicThreshold = 0.35; // 35% for ectopic beat detection

  // Outlier detection
  final List<double> _recentRR = [];
  static const int _outlierWindowSize = 5;

  HrvCalculator({double sampleRate = 30.0}) : _sampleRate = sampleRate;

  /// Add RR intervals from detected peak indices with advanced validation.
  HrvMetrics addPeaks(List<int> peakIndices) {
    if (peakIndices.length < 2) return HrvMetrics.empty;

    // Compute RR intervals
    final newIntervals = <double>[];
    for (int i = 1; i < peakIndices.length; i++) {
      final rrSamples = peakIndices[i] - peakIndices[i - 1];
      final rrMs = (rrSamples / _sampleRate) * 1000.0;
      newIntervals.add(rrMs);
    }

    // Validate and add intervals
    for (final rrMs in newIntervals) {
      if (_isValidRRInterval(rrMs)) {
        _rrIntervals.add(rrMs);
        _updateRecentRR(rrMs);
      }
    }

    // Apply outlier removal
    _removeOutliers();

    // Keep sliding window (60 seconds worth of data for 1-minute measurement)
    while (_rrIntervals.length > 120) {
      _rrIntervals.removeAt(0);
    }

    return computeMetrics();
  }

  /// Validate RR interval using relaxed criteria for better HRV capture.
  bool _isValidRRInterval(double rrMs) {
    // Basic physiological range only
    if (rrMs < _minRR || rrMs > _maxRR) return false;

    // Check against recent intervals - but be lenient
    if (_recentRR.length >= 3) {
      final medianRR = _median(_recentRR);
      final change = (rrMs - medianRR).abs() / medianRR;

      // Only reject extreme outliers (>50% change from median)
      if (change > _maxRRChange) {
        return false;
      }
    }

    return true;
  }

  void _updateRecentRR(double rrMs) {
    _recentRR.add(rrMs);
    if (_recentRR.length > _outlierWindowSize) {
      _recentRR.removeAt(0);
    }
  }

  /// Remove statistical outliers using IQR method (relaxed).
  void _removeOutliers() {
    if (_rrIntervals.length < 15) return;

    final sorted = List<double>.from(_rrIntervals)..sort();
    final q1 = sorted[(sorted.length * 0.25).floor()];
    final q3 = sorted[(sorted.length * 0.75).floor()];
    final iqr = q3 - q1;
    // Use 2.5 * IQR instead of 1.5 to keep more variability
    final lowerBound = q1 - 2.5 * iqr;
    final upperBound = q3 + 2.5 * iqr;

    _rrIntervals.removeWhere((rr) => rr < lowerBound || rr > upperBound);
  }

  double _median(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length % 2 == 0) {
      return (sorted[mid - 1] + sorted[mid]) / 2;
    }
    return sorted[mid];
  }

  /// Compute all HRV metrics with enhanced algorithms.
  HrvMetrics computeMetrics() {
    if (_rrIntervals.length < 5) return HrvMetrics.empty;

    final n = _rrIntervals.length;

    // Mean RR and Heart Rate
    final meanRR = _rrIntervals.reduce((a, b) => a + b) / n;
    final heartRate = 60000.0 / meanRR;

    // SDNN: Standard deviation of NN intervals
    final sdnn = _standardDeviation(_rrIntervals, meanRR);

    // CV (Coefficient of Variation)
    final cvRR = (sdnn / meanRR) * 100;

    // Successive differences
    final successiveDiffs = <double>[];
    for (int i = 1; i < n; i++) {
      successiveDiffs.add(_rrIntervals[i] - _rrIntervals[i - 1]);
    }

    // RMSSD: Root mean square of successive differences
    double sumSquaredDiff = 0;
    for (final diff in successiveDiffs) {
      sumSquaredDiff += diff * diff;
    }
    final rmssd = successiveDiffs.isNotEmpty
        ? sqrt(sumSquaredDiff / successiveDiffs.length)
        : 0.0;

    // SDSD: Standard deviation of successive differences
    final sdsd = successiveDiffs.isNotEmpty
        ? _standardDeviation(successiveDiffs,
            successiveDiffs.reduce((a, b) => a + b) / successiveDiffs.length)
        : 0.0;

    // pNN50: Percentage of successive differences > 50ms
    int nn50Count = 0;
    for (final diff in successiveDiffs) {
      if (diff.abs() > 50) nn50Count++;
    }
    final pnn50 = successiveDiffs.isNotEmpty
        ? (nn50Count / successiveDiffs.length) * 100
        : 0.0;

    // Baevsky's Stress Index and AMo50
    final stressResult = _computeStressIndexAdvanced();
    final stressIndex = stressResult['si'] ?? 0.0;
    final amo50 = stressResult['amo'] ?? 0.0;

    // HRV Status
    final hrvStatus = _assessHrvStatus(rmssd, sdnn, stressIndex);

    return HrvMetrics(
      heartRate: heartRate,
      sdnn: sdnn,
      rmssd: rmssd,
      pnn50: pnn50,
      stressIndex: stressIndex,
      amo50: amo50,
      hrvStatus: hrvStatus,
      validBeats: n,
      sdsd: sdsd,
      cvRR: cvRR,
    );
  }

  double _standardDeviation(List<double> values, double mean) {
    if (values.length < 2) return 0;
    final sumSq = values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b);
    return sqrt(sumSq / (values.length - 1));
  }

  /// Advanced Baevsky Stress Index calculation with proper histogram.
  Map<String, double> _computeStressIndexAdvanced() {
    if (_rrIntervals.length < 10) return {'si': 0.0, 'amo': 0.0};

    const double binWidth = 50.0; // 50ms bins (standard)
    final minRR = _rrIntervals.reduce(min);
    final maxRR = _rrIntervals.reduce(max);
    final mxDMn = maxRR - minRR; // Variation range

    if (mxDMn < 10) return {'si': 0.0, 'amo': 0.0};

    // Build histogram
    final numBins = max(1, ((maxRR - minRR) / binWidth).ceil() + 1);
    final histogram = List<int>.filled(numBins, 0);

    for (final rr in _rrIntervals) {
      final bin = ((rr - minRR) / binWidth).floor().clamp(0, numBins - 1);
      histogram[bin]++;
    }

    // Find mode
    int maxCount = 0;
    int modeBin = 0;
    for (int i = 0; i < numBins; i++) {
      if (histogram[i] > maxCount) {
        maxCount = histogram[i];
        modeBin = i;
      }
    }

    // Mode value (center of bin)
    final mo = minRR + modeBin * binWidth + binWidth / 2;

    // AMo: Amplitude of mode as percentage
    final amo = (maxCount / _rrIntervals.length) * 100;

    // Stress Index: SI = AMo% / (2 × Mo × MxDMn)
    // Mo in seconds, MxDMn in seconds
    final si = (amo / (2 * (mo / 1000) * (mxDMn / 1000)));

    return {
      'si': si.clamp(0, 1000),
      'amo': amo,
    };
  }

  /// Assess HRV status with multiple parameters.
  String _assessHrvStatus(double rmssd, double sdnn, double stressIndex) {
    // Scoring based on clinical guidelines
    int score = 0;

    // RMSSD scoring (parasympathetic indicator)
    if (rmssd > 50) score += 3;
    else if (rmssd > 30) score += 2;
    else if (rmssd > 20) score += 1;

    // SDNN scoring (overall HRV)
    if (sdnn > 100) score += 3;
    else if (sdnn > 50) score += 2;
    else if (sdnn > 30) score += 1;

    // Stress Index scoring (inverse)
    if (stressIndex < 100) score += 2;
    else if (stressIndex < 200) score += 1;
    else if (stressIndex > 400) score -= 1;

    // Final assessment
    if (score >= 6) return 'Excellent';
    if (score >= 4) return 'Good';
    if (score >= 2) return 'Fair';
    return 'Poor';
  }

  /// Reset all stored data.
  void reset() {
    _rrIntervals.clear();
    _peakTimestamps.clear();
    _recentRR.clear();
  }

  /// Get current RR intervals for external analysis.
  List<double> get rrIntervals => List.unmodifiable(_rrIntervals);

  /// Get number of valid beats collected.
  int get beatCount => _rrIntervals.length;
}
