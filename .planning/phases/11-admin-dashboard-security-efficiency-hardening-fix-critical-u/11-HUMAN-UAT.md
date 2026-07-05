---
status: partial
phase: 11-admin-dashboard-security-efficiency-hardening-fix-critical-u
source: [11-VERIFICATION.md]
started: "2026-06-02"
updated: "2026-07-05"
---

## Current Test

[testing complete — 2/3 passed, 1 issue found]

## Tests

### 1. AdminGuard 'Access denied' SnackBar
expected: Sign in as non-admin user, push `/admin-dashboard` directly. Spinner shows briefly, "Access denied" SnackBar fires within 1 frame, AdminDashboard is never rendered, user is redirected to HomeScreen.
result: pass

### 2. ConnectionNodeMap FutureBuilder grid
expected: Sign in as admin, open NETWORK tab. Grid loads with usernames + connection counts. Refresh button visible in top-right corner. No persistent spinning beyond initial load.
result: issue
reported: "Grid loads usernames, but every user shows status 'ISOLATED' regardless of actual online/connection state — the real-time presence/connection status computation isn't wired up. Separately, the grid does not persist across in-dashboard tab switches: NETWORK -> ANALYTICS -> NETWORK loses the previously loaded state; only a full exit-and-re-enter of the whole Admin Dashboard refreshes it correctly. User does not require live/real-time updates (FutureBuilder-on-demand is acceptable) but expects state to survive a same-session tab switch."
severity: major

### 3. TransferVolumeChart real data
expected: Sign in as admin, open ANALYTICS tab. Chart shows 7 data points with Mon/Tue/Wed/Thu/Fri/Sat/Sun labels on x-axis. No sawtooth/repeating pattern — values reflect actual transfer log counts from the last 7 days.
result: pass
note: "Corroborated by debug_session analytics-permission-denied.md's own on-device verification (2026-07-02): TRANSFER VOLUME — 7D chart confirmed rendering day-of-week bars with real data, TRANSFERS/USERS stat cards showing real counts, zero PERMISSION_DENIED."

## Summary

total: 3
passed: 2
issues: 1
pending: 0
skipped: 0
blocked: 0

## Gaps

- truth: "ConnectionNodeMap reflects real per-user online/connection status and persists its loaded state across in-dashboard tab switches"
  status: failed
  reason: "User reported: every user shows status 'ISOLATED' regardless of actual connection state; grid state is lost when switching NETWORK -> ANALYTICS -> NETWORK within the same dashboard session (requires full exit/re-entry to refresh)."
  severity: major
  test: 2
  root_cause: "Not yet investigated — new finding, not covered by any existing debug session."
  artifacts:
    - path: "lib/presentation/admin/connection_node_map.dart"
      issue: "Status computation defaults to/always returns 'ISOLATED'; FutureBuilder state not preserved across TabBarView tab switches (possibly related to the _networkKey GlobalKey pattern in admin_dashboard.dart)"
  missing:
    - "New debug session needed: investigate ConnectionNodeMap status computation and tab-switch state loss"
  debug_session: null
