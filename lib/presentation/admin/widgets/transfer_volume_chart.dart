import 'dart:math' show max;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../data/repositories/admin_repository.dart';

/// Aggregates transfer log documents into a 7-day count array.
/// Returns exactly 7 FlSpot values: X=0 (today-6 days) through X=6 (today).
/// Days with no transfers are zero-padded.
/// Expects each doc map to have a 'loggedAt' Timestamp field (nullable).
List<FlSpot> aggregateTransferLogs(List<Map<String, dynamic>> docs, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final cutoff = today.subtract(const Duration(days: 6));

  final Map<int, int> countsByDay = {for (int i = 0; i < 7; i++) i: 0};

  for (final data in docs) {
    final ts = (data['loggedAt'] as Timestamp?)?.toDate();
    if (ts == null) continue;
    final local = ts.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    if (day.isBefore(cutoff)) continue;
    final idx = day.difference(cutoff).inDays;
    if (idx >= 0 && idx < 7) {
      countsByDay[idx] = (countsByDay[idx] ?? 0) + 1;
    }
  }

  return [
    for (int i = 0; i < 7; i++)
      FlSpot(i.toDouble(), countsByDay[i]!.toDouble()),
  ];
}

class TransferVolumeChart extends StatelessWidget {
  final _adminRepo = AdminRepository();

  TransferVolumeChart({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: 200,
      padding: const EdgeInsets.fromLTRB(16, 24, 24, 16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outline),
      ),
      child: StreamBuilder<QuerySnapshot>(
        stream: _adminRepo.streamTransferLogsDetail(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error loading data',
                style: TextStyle(color: cs.error),
              ),
            );
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data!.docs
              .map((d) => d.data() as Map<String, dynamic>)
              .toList();
          final spots = aggregateTransferLogs(docs, DateTime.now());
          final yMax = max(
            spots.map((s) => s.y).reduce(max),
            1.0,
          ) + 1;

          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final cutoff = today.subtract(const Duration(days: 6));

          return LineChart(
            LineChartData(
              maxY: yMax,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                show: true,
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (value, meta) {
                      final day = cutoff.add(Duration(days: value.toInt()));
                      const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                      final label = labels[day.weekday - 1];
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.5),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: cs.primary,
                  barWidth: 4,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [
                        cs.primary.withValues(alpha: 0.3),
                        cs.primary.withValues(alpha: 0.0),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
