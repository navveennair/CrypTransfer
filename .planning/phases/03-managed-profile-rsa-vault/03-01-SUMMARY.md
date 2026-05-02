---
phase: 03-managed-profile-rsa-vault
plan: "01"
subsystem: analyzer-fix + test-scaffold
tags: [analyzer, test-stubs, nyquist, app-theme, admin-dashboard]
dependency_graph:
  requires: []
  provides:
    - flutter-analyzer-clean (0 issues)
    - test/vault/ scaffold with 5 passing stubs
    - AppTheme.textMain alias
    - AppTheme.textSecondary alias
  affects:
    - lib/app_theme.dart
    - lib/presentation/admin/admin_dashboard.dart
    - test/vault/
tech_stack:
  added: []
  patterns:
    - static const Color alias pattern in AppTheme
    - FakeFirebaseFirestore Nyquist stub pattern
key_files:
  created:
    - test/vault/vault_gate_test.dart
    - test/vault/key_lifecycle_test.dart
    - test/vault/profile_init_test.dart
    - test/vault/receiver_banner_test.dart
  modified:
    - lib/app_theme.dart
    - lib/presentation/admin/admin_dashboard.dart
decisions:
  - "textMain/textSecondary aliases resolve to darkTextMain/darkTextSecondary (app ships dark-only)"
  - "Test stubs use closure functions (not getters) for local boolean logic — valid Dart inside test body"
  - "profile_init_test omits unused cloud_firestore import (FieldValue not needed in stub)"
metrics:
  duration_seconds: 174
  completed_date: "2026-05-02T13:23:38Z"
  tasks_completed: 2
  tasks_total: 2
  files_created: 4
  files_modified: 2
---

# Phase 03 Plan 01: Analyzer Fix & Test Scaffold Summary

**One-liner:** Added `AppTheme.textMain/textSecondary` aliases + admin imports to clear 21 analyzer errors; created `test/vault/` with 5 Nyquist stubs covering VAULT-01/02/03/05/06.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Fix 21 flutter analyze errors | `0a87c3c` | lib/app_theme.dart, lib/presentation/admin/admin_dashboard.dart |
| 2 | Create test/vault/ Nyquist test stubs | `01cd509` | test/vault/*.dart (4 files) |

## Verification Results

1. `flutter analyze --no-pub` → **No issues found!** (was 21 errors)
2. `flutter test test/vault/ --no-pub` → **All 5 stubs PASSED** (TC-VAULT-01/02/03/05/06-stub)
3. `flutter test test/security/` → **All 23 existing tests PASSED** (no regressions)
4. `AppTheme.textMain` and `AppTheme.textSecondary` confirmed present in `lib/app_theme.dart` (lines 20-21)
5. Both imports present in `admin_dashboard.dart` (`../../app_theme.dart`, `../widgets/shared_widgets.dart`)

## Error Root Cause

The 21 errors split across two root causes:
- **17 errors** — `AppTheme.textMain` and `AppTheme.textSecondary` referenced in `receiver_screen.dart`, `sender_screen.dart`, `login_screen.dart`, `splash_screen.dart` but the aliases were never added to `AppTheme`. Fix: two `static const Color` aliases pointing to the existing dark palette constants.
- **4 errors** — `admin_dashboard.dart` used `AppTheme.dark` and `GlassContainer` without importing `app_theme.dart` or `shared_widgets.dart`. Fix: two import lines added.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

All four test files are intentional stubs. Each stub is documented inline with the Wave/Plan that will replace it with a full implementation:

| File | Stub | Resolved in |
|------|------|------------|
| test/vault/vault_gate_test.dart | TC-VAULT-01-stub | Plan 04 (Wave 3) |
| test/vault/key_lifecycle_test.dart | TC-VAULT-02/03-stub | Plan 03 (Wave 2) |
| test/vault/profile_init_test.dart | TC-VAULT-05-stub | Plan 02 (Wave 1) |
| test/vault/receiver_banner_test.dart | TC-VAULT-06-stub | Plan 05 (Wave 4) |

## Threat Flags

None — no new network endpoints, auth paths, file access patterns, or schema changes introduced.

## Self-Check: PASSED

Files exist:
- FOUND: lib/app_theme.dart (modified)
- FOUND: lib/presentation/admin/admin_dashboard.dart (modified)
- FOUND: test/vault/vault_gate_test.dart
- FOUND: test/vault/key_lifecycle_test.dart
- FOUND: test/vault/profile_init_test.dart
- FOUND: test/vault/receiver_banner_test.dart

Commits exist:
- FOUND: 0a87c3c (fix — analyzer errors)
- FOUND: 01cd509 (test — vault stubs)
