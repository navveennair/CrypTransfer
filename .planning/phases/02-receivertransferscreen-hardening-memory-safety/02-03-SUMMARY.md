---
phase: 02-receivertransferscreen-hardening-memory-safety
plan: "03"
subsystem: security-ux
tags: [security, kill-switch, gap-closure, flutter, snackbar, null-guard]
dependency_graph:
  requires: []
  provides: [WIPE-02-closed, MEM-01-closed]
  affects:
    - lib/presentation/receiver/receiver_transfer_screen.dart
    - lib/presentation/sender/sender_screen.dart
tech_stack:
  added: []
  patterns:
    - ScaffoldMessenger.showSnackBar before Navigator.popUntil for kill-switch UX feedback
    - kIsWeb + file.path null guard for cloud URI safety in FilePicker flow
key_files:
  created: []
  modified:
    - lib/presentation/receiver/receiver_transfer_screen.dart
    - lib/presentation/sender/sender_screen.dart
decisions:
  - "SnackBar placed before popUntil so ScaffoldMessenger of current context is still accessible; after popUntil the queued SnackBar surfaces on ReceiverScreen"
  - "null-path guard extracts result.files.first to local variable so the setState closure references the guarded value, not the raw list accessor"
metrics:
  duration: "2m 32s"
  completed: "2026-04-20T03:00:18Z"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 2
---

# Phase 02 Plan 03: Gap Closure — WIPE-02 SnackBar and MEM-01 Null-Path Guard Summary

Kill-switch UX feedback and cloud URI null-path guard added to close two verified gaps from the phase 02 verification report: `ReceiverTransferScreen` now shows a SnackBar before popping on session termination, and `SenderScreen._pickFile` guards against cloud URI picks that produce a null path on Android.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| GAP-01 | Add kill-switch SnackBar in ReceiverTransferScreen._onSessionStateChanged | bb1d54e | receiver_transfer_screen.dart |
| GAP-03 | Add null-path cloud URI guard in SenderScreen._pickFile | dd09ee8 | sender_screen.dart |

## What Was Built

### GAP-01 — Kill-switch SnackBar (WIPE-02 closure)

`_onSessionStateChanged` in `ReceiverTransferScreen` previously called `wipeAll()` and `Navigator.popUntil` without any user-visible feedback. When the app was backgrounded mid-decrypt, the screen would silently pop back to the first route. Three lines were added:

```dart
ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(content: Text('Transfer cancelled — session wiped')),
);
```

The SnackBar is queued before `popUntil` executes so it surfaces on the `ReceiverScreen` after navigation completes.

### GAP-03 — Null-path cloud URI guard (MEM-01 closure)

`_pickFile` in `SenderScreen` applied `withData: kIsWeb` to the `FilePicker` call (correct) but had no guard for the Android cloud-URI case where `file.path == null` AND `file.bytes == null`. This caused `TransferService.resolve` to throw `StateError: Bad state: no path and no bytes` displayed as "Encryption failed: Bad state: …". The fix:

1. Extracts `result.files.first` to a local `file` variable.
2. Adds `if (!kIsWeb && file.path == null)` guard — shows the friendly SnackBar "This file type isn't supported — try saving it locally first." and returns early.
3. `setState` now references the guarded local `file` variable instead of `result.files.first`.

`kIsWeb` was already imported via `package:flutter/foundation.dart` — no new imports needed.

## Deviations from Plan

None — plan executed exactly as written.

## Verification Results

All plan verification checks passed:

```
grep "Transfer cancelled — session wiped" receiver_transfer_screen.dart  → 1 match (line 109)
grep "showSnackBar" receiver_transfer_screen.dart                         → 1 match (line 108)
grep "!kIsWeb && file.path == null" sender_screen.dart                   → 1 match (line 156)
grep "This file type isn't supported" sender_screen.dart                  → 1 match (line 160)
grep "withData: kIsWeb" sender_screen.dart                               → 1 match (line 153)
flutter analyze --no-fatal-infos (both files)                            → No issues found
```

showSnackBar (line 108) appears before popUntil (line 111) — ordering correct.

## Known Stubs

None.

## Threat Flags

None — changes are purely UX feedback and defensive guards with no new network surface, auth paths, or schema changes.

## Self-Check: PASSED

- `lib/presentation/receiver/receiver_transfer_screen.dart` — modified, contains "Transfer cancelled — session wiped"
- `lib/presentation/sender/sender_screen.dart` — modified, contains "!kIsWeb && file.path == null"
- Commit bb1d54e exists: `fix(02-03): show SnackBar before popUntil in _onSessionStateChanged`
- Commit dd09ee8 exists: `fix(02-03): guard null-path cloud URI picks in SenderScreen._pickFile`
