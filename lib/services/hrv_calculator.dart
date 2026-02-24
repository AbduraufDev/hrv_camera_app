import 'dart:math';

/// HRV metrics computed from RR intervals.
class HrvMetrics {
  final double heartRate; // bpm
  final double sdnn; // ms
  final double rmssd; // ms
  final double pnn50; // percentage
  final double stressIndex; // Baevsky's stress index
  final String hrvStatus; // "Excellent", "Good", "Fair", "Poor"
  final int validBeats;

  const HrvMetrics({
    required this.heartRate,
    required this.sdnn,
    required this.rmssd,
    required this.pnn50,
    required this.stressIndex,
    required this.hrvStatus,
    required this.validBeats,
  });

  static const empty = HrvMetrics(
    heartRate: 0,
    sdnn: 0,
    rmssd: 0,
    pnn50: 0,
    stressIndex: 0,
    hrvStatus: '--',
    validBeats: 0,
  );
}

/// Computes HRV metrics from detected peak timestamps.
class HrvCalculator {
  final List<double> _rrIntervals = []; // in milliseconds
  final double _sampleRate;

  // Physiological limits for RR intervals
  static const double _minRR = 300; // ms (~200 bpm)
  static const double _maxRR = 1500; // ms (~40 bpm)
  static const double _maxRRChange = 0.20; // 20% beat-to-beat change allowed

  HrvCalculator({double sampleRate = 30.0}) : _sampleRate = sampleRate;

  /// Add RR intervals from detected peak indices.
  /// Returns updated HRV metrics.
  HrvMetrics addPeaks(List<int> peakIndices) {
    if (peakIndices.length < 2) return HrvMetrics.empty;

    // Compute RR intervals from peak indices
    for (int i = 1; i < peakIndices.length; i++) {
      final rrSamples = peakIndices[i] - peakIndices[i - 1];
      final rrMs = (rrSamples / _sampleRate) * 1000.0;

      // Validate physiological plausibility
      if (rrMs >= _minRR && rrMs <= _maxRR) {
        if (_rrIntervals.isNotEmpty) {
          final change =
              (rrMs - _rrIntervals.last).abs() / _rrIntervals.last;
          if (change <= _maxRRChange) {
            _rrIntervals.add(rrMs);
          }
        } else {
          _rrIntervals.add(rrMs);
        }
      }
    }

    // Keep a sliding window of intervals (last ~120 seconds worth)
    while (_rrIntervals.length > 150) {
      _rrIntervals.removeAt(0);
    }

    return computeMetrics();
  }

  /// Compute all HRV metrics from stored RR intervals.
  HrvMetrics computeMetrics() {
    if (_rrIntervals.length < 3) return HrvMetrics.empty;

    final n = _rrIntervals.length;

    // Mean RR and Heart Rate
    final meanRR = _rrIntervals.reduce((a, b) => a + b) / n;
    final heartRate = 60000.0 / meanRR;

    // SDNN: Standard deviation of NN intervals
    final sdnn = _standardDeviation(_rrIntervals, meanRR);

    // RMSSD: Root mean square of successive differences
    double sumSquaredDiff = 0;
    int diffCount = 0;
    final List<double> successiveDiffs = [];
    for (int i = 1; i < n; i++) {
      final diff = _rrIntervals[i] - _rrIntervals[i - 1];
      successiveDiffs.add(diff);
      sumSquaredDiff += diff * diff;
      diffCount++;
    }
    final rmssd = diffCount > 0 ? sqrt(sumSquaredDiff / diffCount) : 0.0;

    // pNN50: Percentage of successive differences > 50ms
    int nn50Count = 0;
    for (final diff in successiveDiffs) {
      if (diff.abs() > 50) nn50Count++;
    }
    final pnn50 =
        successiveDiffs.isNotEmpty ? (nn50Count / successiveDiffs.length) * 100 : 0.0;

    // Baevsky's Stress Index (SI)
    // SI = AMo / (2 * Mo * MxDMn)
    // AMo = amplitude of mode (most common RR interval)
    // Mo = mode (most common RR interval)
    // MxDMn = max RR - min RR
    final stressIndex = _computeStressIndex();

    // HRV Status based on RMSSD
    final hrvStatus = _assessHrvStatus(rmssd, sdnn);

    return HrvMetrics(
      heartRate: heartRate,
      sdnn: sdnn,
      rmssd: rmssd,
      pnn50: pnn50,
      stressIndex: stressIndex,
      hrvStatus: hrvStatus,
      validBeats: n,
    );
  }

  double _standardDeviation(List<double> values, double mean) {
    if (values.length < 2) return 0;
    final sumSq =
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b);
    return sqrt(sumSq / (values.length - 1));
  }

  double _computeStressIndex() {
    if (_rrIntervals.length < 5) return 0;

    // Histogram-based approach
    const binWidth = 50.0; // 50ms bins
    final minRR = _rrIntervals.reduce(min);
    final maxRR = _rrIntervals.reduce(max);
    final mxDMn = maxRR - minRR;

    if (mxDMn < 1) return 0;

    // Build histogram
    final numBins = max(1, ((maxRR - minRR) / binWidth).ceil() + 1);
    final histogram = List<int>.filled(numBins, 0);

    for (final rr in _rrIntervals) {
      final bin = ((rr - minRR) / binWidth).floor().clamp(0, numBins - 1);
      histogram[bin]++;
    }

    // Find mode (most frequent bin)
    int maxCount = 0;
    int modeBin = 0;
    for (int i = 0; i < numBins; i++) {
      if (histogram[i] > maxCount) {
        maxCount = histogram[i];
        modeBin = i;
      }
    }

    final mo = minRR + modeBin * binWidth + binWidth / 2; // mode value
    final amo = (maxCount / _rrIntervals.length) * 100; // amplitude of mode %

    // SI = AMo / (2 * Mo * MxDMn) * 1000
    final si = (amo / (2 * mo / 1000 * mxDMn / 1000));

    return si.clamp(0, 500);
  }

  String _assessHrvStatus(double rmssd, double sdnn) {
    // Based on clinical HRV guidelines
    if (rmssd > 50 && sdnn > 60) return 'Excellent';
    if (rmssd > 30 && sdnn > 40) return 'Good';
    if (rmssd > 20 && sdnn > 25) return 'Fair';
    return 'Poor';
  }

  /// Reset all stored data.
  void reset() {
    _rrIntervals.clear();
  }

  /// Get current RR intervals for external analysis.
  List<double> get rrIntervals => List.unmodifiable(_rrIntervals);
}
