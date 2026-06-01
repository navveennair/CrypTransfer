---
phase: 11
slug: admin-dashboard-security-efficiency-hardening-fix-critical-u
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-06-02
---

# Phase 11 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Flutter test (flutter_test package) |
| **Config file** | None — uses standard `flutter test` discovery |
| **Quick run command** | `flutter test test/admin/ -x` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~15 seconds (quick), ~60 seconds (full) |

---

## Sampling Rate

- **After every task commit:** Run `flutter analyze` (catches compile errors from deletions/new files instantly)
- **After every plan wave:** Run `flutter test test/admin/ -x`
- **Before `/gsd-verify-work`:** Full suite (`flutter test`) must be green
- **Max feedback latency:** 15 seconds (quick admin suite)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Decision | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|----------|------------|-----------------|-----------|-------------------|-------------|--------|
| 11-W0-01 | 01 | 0 | D-01/D-02/D-03 | — | AdminGuard blocks non-admin navigation | widget | `flutter test test/admin/admin_guard_test.dart -x` | ❌ W0 | ⬜ pending |
| 11-W0-02 | 01 | 0 | D-04 | — | setUserActiveStatus includes adminUid in audit log | unit | `flutter test test/admin/admin_repository_test.dart -x` | ❌ W0 | ⬜ pending |
| 11-W0-03 | 01 | 0 | D-05/D-06 | — | Chart aggregation: zero-padded 7-day window | unit | `flutter test test/admin/chart_aggregation_test.dart -x` | ❌ W0 | ⬜ pending |
| 11-D11 | 01 | 1 | D-11 | — | Dead methods removed; compile succeeds | static | `flutter analyze` | N/A | ⬜ pending |
| 11-D12 | 01 | 1 | D-12 | — | streamTransferLogsDetail/streamSecurityAuditLog/streamAllUsers have .limit() | unit | `flutter test test/admin/admin_repository_test.dart -x` | ❌ W0 | ⬜ pending |
| 11-D04 | 01 | 1 | D-04 | — | adminUid field present in security_audit_log doc | unit | `flutter test test/admin/admin_repository_test.dart -x` | ❌ W0 | ⬜ pending |
| 11-D10 | 01 | 2 | D-10 | — | hasError branches present in all admin StreamBuilders | static | `flutter analyze` + widget test | ❌ W0 | ⬜ pending |
| 11-D06 | 02 | 2 | D-05/D-06 | — | TransferVolumeChart shows real 7-day aggregated data | unit | `flutter test test/admin/chart_aggregation_test.dart -x` | ❌ W0 | ⬜ pending |
| 11-D07 | 02 | 2 | D-07/D-08/D-09 | — | ConnectionNodeMap replaced with FutureBuilder (≤50 users, no N streams) | unit | `flutter test test/admin/admin_repository_test.dart -x` | ❌ W0 | ⬜ pending |
| 11-D01 | 02 | 3 | D-01/D-02/D-03 | CRITICAL | AdminGuard redirects non-admin; allows admin | widget | `flutter test test/admin/admin_guard_test.dart -x` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/admin/admin_guard_test.dart` — widget test stubs for D-01/D-02/D-03 (AdminGuard blocks non-admin, allows admin, shows loading spinner while stream pending)
- [ ] `test/admin/admin_repository_test.dart` — unit test stubs for D-04 (adminUid in audit log, 'unknown' fallback), D-12 (.limit() on streams), D-07/D-08 (fetchUserConnections returns capped list)
- [ ] `test/admin/chart_aggregation_test.dart` — pure Dart unit test stubs for D-05/D-06 (7-day window, zero-padding, old docs filtered, loggedAt null safety)

*Note: zero existing admin test files — all Wave 0 files are new. No framework install needed (flutter_test already configured).*

---

## Manual-Only Verifications

| Behavior | Decision | Why Manual | Test Instructions |
|----------|----------|------------|-------------------|
| AdminGuard SnackBar 'Access denied' shown on redirect | D-03 | SnackBar display requires device/emulator | (1) Sign in as non-admin user (2) Navigate to /admin-dashboard directly (3) Verify SnackBar appears and redirects to HomeScreen |
| ConnectionNodeMap FutureBuilder shows grid on tab open | D-07 | FutureBuilder with Firestore requires live emulator | (1) Sign in as admin (2) Open admin dashboard → Connection Node Map tab (3) Verify grid loads with usernames and connection counts |
| TransferVolumeChart shows real data (not sawtooth) | D-05/D-06 | Chart visual requires device render | (1) Sign in as admin (2) Open admin dashboard → Analytics tab (3) Verify chart reflects actual transfer log dates from last 7 days |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
