// Phase 11 — TransferVolumeChart aggregation logic tests
// Covers: D-05 (7-day fixed window), D-06 (Dart aggregation, local time grouping, null safety)
// Status: Wave 0 stubs — aggregateTransferLogs helper extracted in Plan 03
// Note: Tests reference a top-level aggregateTransferLogs() function to be created in Plan 03.
//       The function takes List<Map<String,dynamic>> docs and DateTime now, returns List<FlSpot>.

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TransferVolumeChart aggregation', () {
    test('produces exactly 7 FlSpot values covering today-6 through today', () {
      // Expected: List<FlSpot> aggregateTransferLogs(List<Map<String,dynamic>> docs, DateTime now)
      // TODO(Phase11-D05-D06): call aggregateTransferLogs(docs, now) where aggregateTransferLogs
      // is a top-level helper function extracted from TransferVolumeChart builder.
      // verify result.length == 7
      // verify result.first.x == 0.0, result.last.x == 6.0
    }, skip: 'aggregateTransferLogs not extracted yet — implemented in Plan 03');

    test('zero-pads days with no transfers as FlSpot(i, 0)', () {
      // Expected: List<FlSpot> aggregateTransferLogs(List<Map<String,dynamic>> docs, DateTime now)
      // TODO(Phase11-D06): pass empty doc list, verify all 7 spots have y == 0
    }, skip: 'aggregateTransferLogs not extracted yet — implemented in Plan 03');

    test('filters out documents with loggedAt older than 7 days', () {
      // Expected: List<FlSpot> aggregateTransferLogs(List<Map<String,dynamic>> docs, DateTime now)
      // TODO(Phase11-D06): pass 2 docs — one from 8 days ago, one from today.
      // verify count: day 6 (today) = 1, day 0 (8 days ago) not counted
    }, skip: 'aggregateTransferLogs not extracted yet — implemented in Plan 03');

    test('handles null loggedAt field without throwing', () {
      // Expected: List<FlSpot> aggregateTransferLogs(List<Map<String,dynamic>> docs, DateTime now)
      // TODO(Phase11-D06): pass a doc with loggedAt: null.
      // verify no exception thrown, null doc is skipped in aggregation
    }, skip: 'aggregateTransferLogs not extracted yet — implemented in Plan 03');
  });
}
