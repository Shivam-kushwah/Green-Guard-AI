import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/dashboard_service.dart';
import '../utils/colors.dart';
import '../utils/risk_colors.dart';

/// Chart pieces for the officer dashboard.
///
/// Two deliberate choices about form:
///
/// * The trend is a real chart because change over time is genuinely hard to
///   read from numbers. It is one series on one axis - never a second y-axis
///   for scans-vs-cases, which is the single most misread chart pattern there
///   is. Rate and volume are shown as separate readouts instead.
///
/// * The ranked breakdowns are laid out as plain widgets rather than a chart
///   library. Bar length already carries the magnitude, and hand-built rows
///   let every bar carry a visible label and value, which a squeezed
///   fl_chart axis does not.

/// Headline number. Not a chart - a single value does not need one.
class StatTile extends StatelessWidget {
  final String value;
  final String label;
  final String? sublabel;
  final Color? accent;
  final IconData? icon;

  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.sublabel,
    this.accent,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 7),
          ],
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.05,
              color: color,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
          if (sublabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                sublabel!,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Daily disease reports over the window.
///
/// One series, one axis. The title names the series, so there is no legend
/// box to read - a legend for a single line is pure noise.
class DiseaseTrendChart extends StatelessWidget {
  final List<DailyCount> data;

  const DiseaseTrendChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.length < 2) {
      return _emptyBox(
        data.isEmpty
            ? 'No scans in this window yet'
            : 'Not enough days of data to draw a trend',
      );
    }

    final spots = <FlSpot>[
      for (var i = 0; i < data.length; i++)
        FlSpot(i.toDouble(), data[i].diseased.toDouble()),
    ];

    final maxY = data
        .map((d) => d.diseased)
        .reduce((a, b) => a > b ? a : b)
        .toDouble();
    // Never a zero-height axis, and leave headroom above the peak.
    final topY = (maxY <= 0 ? 1 : maxY * 1.25).ceilToDouble();

    return SizedBox(
      height: 190,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: topY,
          minX: 0,
          maxX: (data.length - 1).toDouble(),

          // Recessive grid: horizontal only, so it guides the eye to values
          // without competing with the line.
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (topY / 4).clamp(1, double.infinity),
            getDrawingHorizontalLine: (_) => const FlLine(
              color: AppColors.outlineVariant,
              strokeWidth: 0.6,
            ),
          ),
          borderData: FlBorderData(show: false),

          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: (topY / 4).clamp(1, double.infinity),
                getTitlesWidget: (value, _) => Text(
                  value.toInt().toString(),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                // Label roughly five points, whatever the window length -
                // a tick per day collides on a phone.
                interval: (data.length / 5).ceilToDouble(),
                getTitlesWidget: (value, _) {
                  final i = value.toInt();
                  if (i < 0 || i >= data.length) {
                    return const SizedBox.shrink();
                  }
                  final d = data[i].day;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${d.day}/${d.month}',
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.onSurface,
              getTooltipItems: (spots) => spots.map((s) {
                final d = data[s.x.toInt()];
                return LineTooltipItem(
                  '${d.diseased} diseased of ${d.total} scans\n'
                  '${d.day.day}/${d.day.month}',
                  const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }).toList(),
            ),
          ),

          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.25,
              // 2px line, per the mark spec - thin enough to read values off.
              barWidth: 2,
              color: AppColors.primary,
              dotData: FlDotData(
                show: data.length <= 14,
                getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                  radius: 3,
                  color: AppColors.primary,
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.primary.withValues(alpha: 0.10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A ranked horizontal bar row with the label and value always visible.
///
/// Values are direct-labelled rather than left to an axis, which also
/// satisfies the relief rule for the palest steps of the severity ramp.
class RankedBar extends StatelessWidget {
  final String label;
  final String? sublabel;
  final int value;
  final int maxValue;
  final Color color;

  /// Shown after the label - carries the meaning that colour alone must not.
  final String? badge;
  final IconData? badgeIcon;

  const RankedBar({
    super.key,
    required this.label,
    required this.value,
    required this.maxValue,
    required this.color,
    this.sublabel,
    this.badge,
    this.badgeIcon,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = maxValue == 0 ? 0.0 : value / maxValue;

    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: RiskColors.surfaceFor(color),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (badgeIcon != null) ...[
                              Icon(badgeIcon,
                                  size: 9, color: RiskColors.inkOn(color)),
                              const SizedBox(width: 2),
                            ],
                            Text(
                              badge!,
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                                color: RiskColors.inkOn(color),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$value',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
          if (sublabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                sublabel!,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 5),
          // 4px rounded data-end anchored to the baseline, per the mark spec.
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: AppColors.surfaceContainer,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _emptyBox(String message) => Container(
  height: 120,
  alignment: Alignment.center,
  decoration: BoxDecoration(
    color: AppColors.surfaceContainer,
    borderRadius: BorderRadius.circular(12),
  ),
  child: Text(
    message,
    style: const TextStyle(
      fontSize: 12.5,
      color: AppColors.onSurfaceVariant,
    ),
  ),
);
