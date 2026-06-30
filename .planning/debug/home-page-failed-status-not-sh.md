---
status: resolved
trigger: "Home Page is not updated with 'Failed' status, red bar white font, if either sender or receiver clicks on 'Abort & Destroy'"
created: 2026-06-04
updated: 2026-06-04
---

## Symptoms

- **Expected**: When sender or receiver clicks "Abort & Destroy", the Home Page transfer history shows the transfer with a "Failed" status — red bar, white font
- **Actual**: Home Page transfer history does not reflect "Failed" status after abort — either shows wrong status or no entry at all
- **Screens involved**: ReceiverTransferScreen abort dialog, DecryptScreen abort dialog, SenderTransferScreen abort → Home Page recent transfers list

## Current Focus

- hypothesis: CONFIRMED AND FIXED
- next_action: none

## Evidence

- `TransferRepository.writeConnectionLostAuditLog()` (line 350-388): writes `status: 'connection_lost'` to `users/{uid}/audit_logs`.
- `TransferRepository.writeAbortAuditLog()` (line 254-299): writes `status: 'aborted'` — only called from sender stale-key path (pre-transfer), NOT from Abort & Destroy.
- All three abort paths (`ReceiverTransferScreen`, `DecryptScreen`, `SenderTransferScreen`) call `writeConnectionLostAuditLog` → write `status: 'connection_lost'`.
- `HomeScreen._transferStatusBadge()` (before fix): only checked `status == 'aborted'` — `'connection_lost'` fell through to default Sent/Received badge.
- `HomeScreen` ListView itemBuilder (before fix): icon/color override also only checked `data['status'] == 'aborted'`.

## Eliminated

- Status written to wrong collection: eliminated — `writeConnectionLostAuditLog` correctly writes to `users/{uid}/audit_logs`.
- Missing audit log entry: eliminated — all abort paths call `writeConnectionLostAuditLog`.
- Query filtering out aborted: eliminated — `streamRecentTransfers` has no status filter.

## Resolution

- root_cause: All Abort & Destroy paths write `status: 'connection_lost'` to the audit log, but HomeScreen only checked `status == 'aborted'` in both `_transferStatusBadge()` and the ListView itemBuilder — the string mismatch meant aborted entries showed as Sent/Received.
- fix: Added `_isFailedStatus(String status)` helper in `home_screen.dart` that returns true for `'aborted'`, `'connection_lost'`, or `'failed'`. Replaced all four hardcoded `== 'aborted'` checks (3 in itemBuilder, 1 in `_transferStatusBadge`) with calls to this helper. `flutter analyze` passes with no issues.
- files_changed: lib/presentation/home/home_screen.dart
