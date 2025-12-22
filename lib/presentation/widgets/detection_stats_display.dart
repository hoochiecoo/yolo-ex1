// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'package:flutter/material.dart';

/// A widget that displays detection statistics (count and FPS)
class DetectionStatsDisplay extends StatelessWidget {
  const DetectionStatsDisplay({
    super.key,
    required this.detectionCount,
    required this.currentFps,
    this.leftElbowAngle,
    this.rightElbowAngle,
    this.debugKeypointCount,
    this.showAngles = false,
  });

  final int detectionCount;
  final double currentFps;
  final double? leftElbowAngle;
  final double? rightElbowAngle;
  final bool showAngles;
  final int? debugKeypointCount;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'DETECTIONS: $detectionCount',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'FPS: ${currentFps.toStringAsFixed(1)}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (showAngles) ...[
            const SizedBox(width: 16),
            Text(
              'L-ELBOW: ${leftElbowAngle?.isNaN == true || leftElbowAngle == null ? '--' : leftElbowAngle!.toStringAsFixed(0)}°',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'R-ELBOW: ${rightElbowAngle?.isNaN == true || rightElbowAngle == null ? '--' : rightElbowAngle!.toStringAsFixed(0)}°',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (debugKeypointCount != null) ...[
              const SizedBox(width: 8),
              Text(
                'KP: $debugKeypointCount',
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
