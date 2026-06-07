// Phase 11 — TransferVolumeChart aggregation logic tests
// Covers: D-05 (7-day fixed window), D-06 (Dart aggregation, local time grouping, null safety)
// aggregateTransferLogs is a pure-Dart top-level function — no Firebase mocking needed.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptransfer/presentation/admin/widgets/transfer_volume_chart.dart';

void main() {
  // Fixed reference point: 2026-06-08 (Monday)
  final now = DateTime(2026, 6, 8, 12, 0, 0);

  Map<String, dynamic> docWithLoggedAt(DateTime dt) => {
        'loggedAt': Timestamp.fromDate(dt),
      };

  group('TransferVolumeChart aggregation', () {
    test('produces exactly 7 FlSpot values covering today-6 through today', () {
      final spots = aggregateTransferLogs([], now);
      expect(spots.length, 7);
      expect(spots.first.x, 0.0);
      expect(spots.last.x, 6.0);
    });

    test('zero-pads days with no transfers as FlSpot(i, 0)', () {
      final spots = aggregateTransferLogs([], now);
      for (final spot in spots) {
        expect(spot.y, 0.0, reason: 'Day ${spot.x.toInt()} should have 0 transfers');
      }
    });

    test('counts a transfer on today (index 6)', () {
      final docs = [docWithLoggedAt(DateTime(2026, 6, 8, 10, 0, 0))];
      final spots = aggregateTransferLogs(docs, now);
      expect(spots[6].y, 1.0);
    });

    test('counts a transfer on 6 days ago (index 0)', () {
      // 6 days before 2026-06-08 = 2026-06-02
      final docs = [docWithLoggedAt(DateTime(2026, 6, 2, 8, 0, 0))];
      final spots = aggregateTransferLogs(docs, now);
      expect(spots[0].y, 1.0);
    });

    test('filters out documents with loggedAt older than 7 days', () {
      // 8 days ago — should be excluded
      final docs = [
        docWithLoggedAt(DateTime(2026, 5, 31, 8, 0, 0)), // 8 days ago
        docWithLoggedAt(DateTime(2026, 6, 8, 10, 0, 0)), // today
      ];
      final spots = aggregateTransferLogs(docs, now);
      // Only the today entry counts
      expect(spots[6].y, 1.0);
      // 8-days-ago is outside the window — all earlier days are 0
      expect(spots[0].y, 0.0);
    });

    test('handles null loggedAt field without throwing', () {
      final docs = [
        {'loggedAt': null},
        docWithLoggedAt(DateTime(2026, 6, 8, 10, 0, 0)),
      ];
      expect(() => aggregateTransferLogs(docs, now), returnsNormally);
      final spots = aggregateTransferLogs(docs, now);
      // Null doc is skipped; today still counts
      expect(spots[6].y, 1.0);
    });

    test('accumulates multiple transfers on the same day', () {
      final docs = [
        docWithLoggedAt(DateTime(2026, 6, 8, 9, 0, 0)),
        docWithLoggedAt(DateTime(2026, 6, 8, 14, 0, 0)),
        docWithLoggedAt(DateTime(2026, 6, 8, 22, 0, 0)),
      ];
      final spots = aggregateTransferLogs(docs, now);
      expect(spots[6].y, 3.0);
    });
  });
}
