---
phase: 11
reviewed: 2026-06-08T00:00:00Z
depth: standard
files_reviewed: 11
files_reviewed_list:
  - lib/data/repositories/admin_repository.dart
  - lib/main.dart
  - lib/presentation/admin/admin_dashboard.dart
  - lib/presentation/admin/admin_guard.dart
  - lib/presentation/admin/widgets/connection_node_map.dart
  - lib/presentation/admin/widgets/security_pulse_feed.dart
  - lib/presentation/admin/widgets/transfer_volume_chart.dart
  - lib/presentation/admin/widgets/user_management_list.dart
  - test/admin/admin_guard_test.dart
  - test/admin/admin_repository_test.dart
  - test/admin/chart_aggregation_test.dart
findings:
  critical: 0
  warning: 2
  info: 3
  total: 5
status: issues_found
---

# Phase 11: Code Review Report (Re-review — Post-Fix Verification)

**Reviewed:** 2026-06-08T00:00:00Z
**Depth:** standard
**Files Reviewed:** 11
**Status:** issues_found

## Summary

This re-review verifies that all 7 previously reported issues (CR-01, CR-02, WR-01, WR-03, WR-04, WR-05, and the accepted WR-02 cost doc) were fixed correctly and scans for any regressions introduced by the fix commits (8dbaf19, 4559f5e, 9f2404a, 9e45355, 26cd262, ba73a9c, ebd7126).

**All previously reported issues are confirmed resolved:**

- **CR-01** (`_RevokeButton` error handling): Correctly implemented as a `StatefulWidget` with a `_loading` guard that blocks re-entrant taps, `showDialog` confirmation before revoke, a `catch (e)` block that shows a `SnackBar` with the error text, and `mounted` checks in both the catch and finally blocks. No regression.
- **CR-02** (`AdminGuard` stream lifecycle): Correctly converted to `StatefulWidget`. `_profileStream` is initialised once in `initState`. All navigation is deferred via `addPostFrameCallback` with a `mounted` guard. The null-UID case silently redirects to `'/'` without showing the 'Access denied' SnackBar. No regression.
- **WR-01** (`fetchUserConnections` batch reads): Correctly chunked into sequential batches of 10 via `Future.wait` per batch. The `batchSize = 10` constant is clear. No regression.
- **WR-03** (null timestamp shows '—'): `SecurityPulseFeed` correctly passes `DateTime? timestamp` to `_SecurityLogTile`. The null case renders `'—'` on line 128 via a ternary. No `DateTime.now()` fallback is present. The fix rationale is documented in an inline comment (lines 44–48). No regression.
- **WR-04** (sibling `StreamBuilder`s): `_transferLogsStream` is now a stable field initialised in `initState` (line 30) and referenced by name in `_buildAnalyticsTab`. No regression on the transfer logs stream. The users/transfers summary cards still use nested `StreamBuilder`s (see IN-03 below), which is a pre-existing style concern, not a regression from WR-04's fix.
- **WR-05** (`chart_aggregation_test.dart` real tests): 6 named test cases with concrete assertions are present covering the 7-spot shape, zero-padding, today/boundary index, 8-days-ago exclusion, null-field skip, and multi-transfer accumulation on the same day. The tests are unambiguously real and not stubs. No regression.

Two new warnings and three info items were found. None are regressions from the fix commits; they are pre-existing patterns that were either not in scope for the prior review or are side-effects of the new code paths.

---

## Warnings

### WR-NEW-01: `_buildActiveSessionsList` creates a new Firestore listener on every outer `StreamBuilder` rebuild

**File:** `lib/presentation/admin/admin_dashboard.dart:441`

**Issue:** `_buildActiveSessionsList` is called from `_buildAnalyticsTab`, which is the builder callback of the `_transferLogsStream` `StreamBuilder`. On every emission of `_transferLogsStream`, `_buildAnalyticsTab` is rebuilt, which calls `_buildActiveSessionsList`, which passes `_adminRepo.streamActiveHandshakesDetail()` directly to a new inner `StreamBuilder`. Because `streamActiveHandshakesDetail()` creates a new stream object on every call, the `StreamBuilder` cannot diff it against the previous stream — it opens a new Firestore listener and abandons the old one without cancelling it. Unlike `_transferLogsStream`, this stream is not cached in a `late final` field.

**Fix:** Cache the handshakes stream in `initState` alongside `_transferLogsStream`:

```dart
// _AdminDashboardState — add field
late final Stream<QuerySnapshot> _handshakesStream;

@override
void initState() {
  super.initState();
  _tabController = TabController(length: 4, vsync: this);
  _tabController.addListener(_onTabChanged);
  _transferLogsStream = _adminRepo.streamTransferLogsDetail();
  _handshakesStream = _adminRepo.streamActiveHandshakesDetail(); // add
}

// _buildActiveSessionsList — use the cached field
return StreamBuilder<QuerySnapshot>(
  stream: _handshakesStream, // was: _adminRepo.streamActiveHandshakesDetail()
  ...
);
```

---

### WR-NEW-02: `AdminGuard` State C fires 'Access denied' SnackBar + `pushReplacementNamed` on every Firestore re-emission

**File:** `lib/presentation/admin/admin_guard.dart:71-84`

**Issue:** State C is entered whenever `snapshot.data?.isAdmin != true`. Because `_profileStream` is a live Firestore stream, it can emit multiple times before navigation completes (e.g., on network reconnect, or when any field on the user document changes). Each emission schedules a fresh `addPostFrameCallback` that shows the 'Access denied' SnackBar and calls `pushReplacementNamed`. If the stream emits twice before the frame boundary, the user sees the SnackBar twice and `pushReplacementNamed` is called twice, which can leave a duplicate route on the stack depending on the navigator implementation.

**Fix:** Add a `_redirecting` bool guard to `_AdminGuardState` to ensure the redirect fires at most once per guard lifecycle:

```dart
class _AdminGuardState extends State<AdminGuard> {
  final _authRepo = AuthRepository();
  Stream<UserModel?>? _profileStream;
  bool _redirecting = false; // add

  // In the StreamBuilder builder, State C:
  if (snapshot.hasError || snapshot.data?.isAdmin != true) {
    if (!_redirecting) {
      _redirecting = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Access denied'), duration: Duration(seconds: 3)),
          );
          Navigator.pushReplacementNamed(context, '/');
        }
      });
    }
    return _loadingScaffold(context);
  }
```

---

## Info

### IN-01: `admin_guard_test.dart` and `admin_repository_test.dart` have only empty TODO stubs — no assertions

**Files:** `test/admin/admin_guard_test.dart:19-36`, `test/admin/admin_repository_test.dart:20-48`

**Issue:** All 8 test cases in these two files have empty bodies. They register named test cases but assert nothing, so they pass vacuously. The blocking issue is that `AdminGuard` and `AdminRepository` instantiate their dependencies internally (`AuthRepository()`, `FirebaseAuth.instance`) rather than accepting injectable parameters. The TODO comments correctly identify this but it means zero automated coverage for the security-critical guard redirect and the `adminUid` audit log field.

**Fix:** Add an optional `AuthRepository? authRepo` constructor parameter to `AdminGuard` (matching the `FirebaseFirestore? db` pattern already used in `AdminRepository`), and add `firebase_auth_mocks` to `dev_dependencies`. Then implement the three guard test cases and the two audit-log test cases — they are straightforward widget/unit tests once injection is possible.

---

### IN-02: `SecurityPulseFeed` holds a mutable repository field on a `StatelessWidget`

**File:** `lib/presentation/admin/widgets/security_pulse_feed.dart:8`

**Issue:** `final _adminRepo = AdminRepository()` is declared as an instance field on a `StatelessWidget`. `StatelessWidget` instances can be discarded and recreated by the framework at any time (e.g., hot reload, parent rebuild that changes the widget type). When that happens, the old `StreamBuilder` subscription is abandoned and a new one is opened. In practice the widget is stable in the `TabBarView`, but the pattern is inconsistent with `ConnectionNodeMap` and `UserManagementList`, which correctly use `StatefulWidget` + `initState` for the same reason.

**Fix:** Convert `SecurityPulseFeed` to a `StatefulWidget` and initialise the repository in `initState`, consistent with the rest of the admin widget layer.

---

### IN-03: `_buildActiveSessionsList` reads `fromUsername`/`toUsername` — fields that do not exist in the `handshakes` data model

**File:** `lib/presentation/admin/admin_dashboard.dart:479`

**Issue:** The active handshakes row displays `@${data['fromUsername'] ?? '...'} → @${data['toUsername'] ?? '...'}`. Per the CLAUDE.md data model and `FirebaseConstants`, `handshakes` documents contain `{receiverId, senderId, publicKey, status}` — not username fields. Both labels will always render as `@...` (the null fallback). This makes the "ACTIVE HANDSHAKES" panel display no useful information to the admin.

**Fix:** Either enrich the handshake document at write time with `senderUsername`/`receiverUsername` fields, or resolve usernames from the `users` collection at read time. As a minimum, fall through to the UID for readability:

```dart
'@${data['senderUsername'] ?? data['senderId'] ?? '?'} → @${data['receiverUsername'] ?? data['receiverId'] ?? '?'}'
```

---

_Reviewed: 2026-06-08T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
