import 'package:flutter/material.dart';

/// A card displaying a single HRV metric with label, value, and unit.
class MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;

  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    this.color = const Color(0xFFff6b6b),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF16213e),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Status badge showing HRV assessment with color coding.
class HrvStatusBadge extends StatelessWidget {
  final String status;

  const HrvStatusBadge({super.key, required this.status});

  Color get _statusColor {
    switch (status) {
      case 'Excellent':
        return const Color(0xFF4ecdc4);
      case 'Good':
        return const Color(0xFF45b7d1);
      case 'Fair':
        return const Color(0xFFf9ca24);
      case 'Poor':
        return const Color(0xFFff6b6b);
      default:
        return Colors.grey;
    }
  }

  IconData get _statusIcon {
    switch (status) {
      case 'Excellent':
        return Icons.sentiment_very_satisfied;
      case 'Good':
        return Icons.sentiment_satisfied;
      case 'Fair':
        return Icons.sentiment_neutral;
      case 'Poor':
        return Icons.sentiment_dissatisfied;
      default:
        return Icons.remove;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _statusColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: _statusColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon, color: _statusColor, size: 20),
          const SizedBox(width: 8),
          Text(
            status == '--' ? 'Waiting...' : 'HRV: $status',
            style: TextStyle(
              color: _statusColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
