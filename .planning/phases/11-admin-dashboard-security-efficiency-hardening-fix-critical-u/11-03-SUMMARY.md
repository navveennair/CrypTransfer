---
plan: 11-03
phase: 11
status: complete
wave: 2
completed: "2026-06-02"
---

# Plan 11-03: hasError Branches + Real Chart Aggregation — COMPLETE

## What Was Built

Added `snapshot.hasError` branches to all 5 admin StreamBuilders missing them (D-10), and replaced the fake sawtooth `TransferVolumeChart` data with real 7-day Dart aggregation (D-05/D-06).

## Changes

- **admin_dashboard.dart**: Outer `_buildSummaryCards` StreamBuilder — waiting/hasError return Row of two `_SummaryCard(value:'–', color:cs.error)` preserving Row layout; inner uses `userSnap.hasError`; `_buildActiveSessionsList` adds standard waiting/hasError/!hasData order
- **security_pulse_feed.dart**: Standard waiting/hasError/!hasData guard in StreamBuilder — `'Error loading data'` text
- **user_management_list.dart**: Same pattern — `'Error loading data'` text
- **transfer_volume_chart.dart**: `aggregateTransferLogs()` top-level function extracted (7 FlSpot, zero-padded, null-safe Timestamp cast); fake sawtooth removed; bottom axis weekday labels with `reservedSize: 28`; `dart:math` imported for `max()`

## Verification

- `flutter analyze` on all 4 files → No issues found
- `snapshot.hasError` present in `security_pulse_feed.dart` (1 match) ✓
- `snapshot.hasError` present in `user_management_list.dart` (1 match) ✓
- `aggregateTransferLogs` appears twice in `transfer_volume_chart.dart` (definition + call) ✓
- `sawtooth|i % 5|FlSpot(0, 3)` → 0 matches (fake data gone) ✓
- `'Error loading data'` present in 3 files ✓

## Self-Check: PASSED
