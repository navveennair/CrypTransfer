# Phase 11: Admin Dashboard Security & Efficiency Hardening - Research

**Researched:** 2026-06-02
**Domain:** Flutter admin dashboard hardening — route guards, audit logging, Firestore stream consolidation, real chart data, pagination
**Confidence:** HIGH (all findings verified by direct codebase inspection)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** AdminGuard is a route wrapper widget in `lib/main.dart`. Routes map becomes `'/admin-dashboard': (context) => AdminGuard(child: const AdminDashboard())`. AdminGuard is a new `StatelessWidget` in `lib/presentation/admin/admin_guard.dart`.
- **D-02:** AdminGuard streams `AuthRepository.streamUserProfile(currentUser.uid)`. Loading state shows full-screen `CircularProgressIndicator`. Resolves to child if `isAdmin == true`, else triggers non-admin flow.
- **D-03:** Non-admin behavior: `SnackBar('Access denied')` then `Navigator.pushReplacementNamed(context, '/')`. No brief admin screen exposure.
- **D-04:** `AdminRepository.setUserActiveStatus(String uid, bool isActive)` reads `FirebaseAuth.instance.currentUser?.uid` internally. Adds `'adminUid': adminUid ?? 'unknown'` to the security audit log entry. No signature change.
- **D-05:** Chart shows last 7 calendar days. X-axis is fixed: today minus 6 days through today. Days with zero transfers plot as `FlSpot(i, 0)`.
- **D-06:** Aggregation done in Dart from existing `streamTransferLogsDetail()`. Filter `loggedAt >= DateTime.now().subtract(Duration(days: 7))`. Group by local date (year+month+day). Map to 7 FlSpot values.
- **D-07:** Replace `StreamBuilder` + per-user `StreamBuilder<Map<String,dynamic>?>` pattern in `ConnectionNodeMap` with a single `FutureBuilder`. No ongoing N listeners.
- **D-08:** New `AdminRepository.fetchUserConnections()` Future method with `.limit(50)`. Loop UIDs with `Future.wait` on friendship count queries. Combine in Dart.
- **D-09:** Grid capped at 50 users (`.limit(50)` on users query).
- **D-10:** Add `snapshot.hasError` branch to every `StreamBuilder` in the admin layer missing it. Error branch: `Center(child: Text('Error loading data', style: TextStyle(color: cs.error)))`.
- **D-11:** Remove 3 dead methods from `AdminRepository`: `streamTransferLogs()`, `streamSecurityLogs()`, `streamActiveHandshakes()` (the `Stream<int>` variant).
- **D-12:** Add `.limit(100)` to `streamTransferLogsDetail()` and `streamSecurityAuditLog()`. Add `.limit(200)` to `streamAllUsers()`.

### Claude's Discretion
- Exact SnackBar duration and animation in AdminGuard non-admin redirect
- Whether to add a "Refresh" button to the ConnectionNodeMap FutureBuilder
- Exact Y-axis padding in the TransferVolumeChart
- Order of fixes within plan waves

### Deferred Ideas (OUT OF SCOPE)
- Real-time ConnectionNodeMap (live per-user connection count updates)
- Pagination UI for admin user list (load more button)
- Cloud Functions for denormalized `connectionCount` field on user doc
</user_constraints>

---

## Summary

Phase 11 is a hardening-only phase — no new collections, no schema changes, no new features. All changes are confined to `lib/presentation/admin/` and `lib/data/repositories/admin_repository.dart`, plus a one-line change in `lib/main.dart` and a new file `lib/presentation/admin/admin_guard.dart`.

The codebase inspection reveals the exact current state of every file to be modified. The 3 dead methods in `AdminRepository` are confirmed dead by grep: `streamTransferLogs()`, `streamSecurityLogs()`, and `streamActiveHandshakes()` (Stream<int> variant) have zero callers outside the repository itself. The N-stream pattern in `ConnectionNodeMap` is confirmed: one outer `StreamBuilder<QuerySnapshot>` spawns one inner `StreamBuilder<Map<String,dynamic>?>` per user (via `_userRepo.streamUserWithFriendships(uid)`), creating N persistent Firestore listeners. The `hasError` audit confirms that only `AdminDashboardScreen` has the pattern; all other admin StreamBuilders are missing it. The `TransferVolumeChart` confirms the fake sawtooth: `FlSpot(i.toDouble(), (i % 5).toDouble() + 1)` for each document regardless of date, plus hardcoded fallback spots. The route `'/admin-dashboard'` maps directly to `AdminDashboard()` with no guard.

**Primary recommendation:** Execute fixes wave by wave — D-11 (dead code removal) first as pure subtraction, then D-12 (limits) as one-line changes, then D-04 (audit log), then D-10 (hasError), then D-05/D-06 (chart), then D-07/D-08/D-09 (stream consolidation), then D-01/D-02/D-03 (AdminGuard, the highest-risk change due to new file and auth stream).

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Route access control (AdminGuard) | Frontend (Flutter route layer) | — | Named routes are resolved in MaterialApp; guard wraps the widget at route resolution time |
| Admin UID in audit log | Data layer (AdminRepository) | — | Repository owns all Firestore writes; UID read from FirebaseAuth inside repo |
| Real chart aggregation | Presentation (TransferVolumeChart widget) | Data layer (streamTransferLogsDetail) | Aggregation logic runs in Dart inside the StreamBuilder builder function; data sourced from existing repo stream |
| Stream consolidation | Presentation (ConnectionNodeMap widget) + Data layer (AdminRepository) | — | New `fetchUserConnections()` Future in repo; FutureBuilder replaces N StreamBuilders in widget |
| Pagination / limits | Data layer (AdminRepository) | — | `.limit()` applied at query level in repository methods |
| hasError branches | Presentation (all admin widgets) | — | StreamBuilder error handling is a widget-layer concern |
| Dead method removal | Data layer (AdminRepository) | — | Pure subtraction in repository file |

---

## Current State Analysis

### File: `lib/main.dart`

Route registration (line 40):
```dart
'/admin-dashboard': (context) => const AdminDashboard(),
```
No guard, no auth check. Any code that has a BuildContext can navigate to this route. `SidebarDrawer` uses `Navigator.pushNamed(context, '/admin-dashboard')` after its own `isAdmin` StreamBuilder check — but the route itself has no enforcement. A user who directly calls `pushNamed('/admin-dashboard')` or uses deep-link bypass reaches the admin screen.

**Change required (D-01):** Wrap with AdminGuard:
```dart
'/admin-dashboard': (context) => AdminGuard(child: const AdminDashboard()),
```

### File: `lib/presentation/admin/admin_guard.dart`

Does not exist yet. Must be created as part of this phase.

**Pattern to replicate** (from `sidebar_drawer.dart` lines 119-137):
```dart
if (user != null)
  StreamBuilder<UserModel?>(
    stream: authRepo.streamUserProfile(user.uid),
    builder: (context, snapshot) {
      final isAdmin = snapshot.data?.isAdmin ?? false;
      if (!isAdmin) return const SizedBox.shrink();
      ...
    },
  ),
```

`AuthRepository.streamUserProfile(String uid)` (verified at `lib/data/repositories/auth_repository.dart:324`) returns `Stream<UserModel?>` from a Firestore doc snapshot. `UserModel.isAdmin` field exists (verified by `user_management_list.dart:55` reading `user.isAdmin`).

**AdminGuard implementation skeleton:**
```dart
class AdminGuard extends StatelessWidget {
  final Widget child;
  const AdminGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final authRepo = AuthRepository();
    final user = authRepo.currentUser;
    if (user == null) {
      // Not logged in — redirect immediately
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, '/');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return StreamBuilder<UserModel?>(
      stream: authRepo.streamUserProfile(user.uid),
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError || snapshot.data?.isAdmin != true) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Access denied')),
            );
            Navigator.pushReplacementNamed(context, '/');
          });
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return child;
      },
    );
  }
}
```
Note: `addPostFrameCallback` is required because `Navigator.pushReplacementNamed` during a build throws. This is the standard Flutter pattern for navigation inside a build method.

### File: `lib/data/repositories/admin_repository.dart`

**Current imports:** `cloud_firestore`, `firebase_constants`, `user_model`. No `firebase_auth` import.

**D-04 requires adding:**
```dart
import 'package:firebase_auth/firebase_auth.dart';
```
Then inside `setUserActiveStatus`:
```dart
final adminUid = FirebaseAuth.instance.currentUser?.uid;
await _db.collection(FirebaseConstants.securityAuditLog).add({
  'event': isActive ? 'ADMIN_USER_RESTORE' : 'ADMIN_USER_REVOKE',
  'details': 'User $uid access status changed to $isActive',
  'adminUid': adminUid ?? 'unknown',
  'timestamp': FieldValue.serverTimestamp(),
});
```

### File: `lib/presentation/admin/widgets/transfer_volume_chart.dart`

**Current fake data implementation (lines 28-45):**
```dart
final docs = snapshot.data!.docs.reversed.toList();
final spots = <FlSpot>[];

for (int i = 0; i < docs.length; i++) {
  // Mocking a trend line based on index if data is sparse
  spots.add(FlSpot(i.toDouble(), (i % 5).toDouble() + 1));  // ← FAKE SAWTOOTH
}

if (spots.isEmpty) {
  spots.addAll([
    const FlSpot(0, 3), const FlSpot(1, 4), const FlSpot(2, 2),
    const FlSpot(3, 5), const FlSpot(4, 3),  // ← HARDCODED FALLBACK
  ]);
}
```

**Real aggregation needed (D-05, D-06):** Filter by `loggedAt >= 7 days ago`, group by `(year, month, day)`, count per day, map to exactly 7 `FlSpot` values with X = 0..6 (0 = oldest, 6 = today).

`loggedAt` field type: confirmed as `FieldValue.serverTimestamp()` → stored as Firestore `Timestamp`. Cast via `(data['loggedAt'] as Timestamp?)?.toDate()`.

**Real aggregation implementation:**
```dart
final now = DateTime.now();
final today = DateTime(now.year, now.month, now.day);
final cutoff = today.subtract(const Duration(days: 6));

// Build a map: dayIndex (0=oldest, 6=today) → count
final Map<int, int> countsByDay = {for (int i = 0; i < 7; i++) i: 0};

for (final doc in snapshot.data!.docs) {
  final data = doc.data() as Map<String, dynamic>;
  final ts = (data['loggedAt'] as Timestamp?)?.toDate();
  if (ts == null) continue;
  final local = ts.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  if (day.isBefore(cutoff)) continue;
  final idx = day.difference(cutoff).inDays;
  if (idx >= 0 && idx < 7) countsByDay[idx] = (countsByDay[idx] ?? 0) + 1;
}

final spots = [for (int i = 0; i < 7; i++) FlSpot(i.toDouble(), countsByDay[i]!.toDouble())];
```

**fl_chart version:** 0.70.2 (verified from pubspec.lock). `FlSpot`, `LineChart`, `LineChartData`, `LineChartBarData`, `BarAreaData`, `FlGridData`, `FlTitlesData`, `FlBorderData`, `FlDotData` are all currently used — no API changes needed for this fix.

**X-axis labels (D-05):** The decision says X-axis range is fixed but does not require labels. Current chart has `titlesData: const FlTitlesData(show: false)`. Adding day labels is Claude's discretion. Recommended: add bottom titles showing abbreviated day names (Mon, Tue, ...) using `SideTitles(showTitles: true, getTitlesWidget: ...)` for clarity.

### File: `lib/presentation/admin/widgets/connection_node_map.dart`

**Current N-stream pattern (confirmed):**
- Outer `StreamBuilder<QuerySnapshot>` on `_adminRepo.streamUserConnections()` (line 15)
- For each user doc in the snapshot, an inner `StreamBuilder<Map<String,dynamic>?>` on `_userRepo.streamUserWithFriendships(uid)` (line 36)
- `streamUserWithFriendships` (verified in `user_repository.dart:36`) uses `.asyncMap()` which performs a get() query per tick — creating N persistent listeners + N get() calls on every outer snapshot update

**What `streamUserWithFriendships` does:**
```dart
Stream<Map<String, dynamic>?> streamUserWithFriendships(String userId) {
  return _db.collection(FirebaseConstants.users).doc(userId).snapshots()
    .asyncMap((userDoc) async {
      // For EVERY snapshot: runs a friendships .get() query
      final friendships = await _db.collection(users).doc(userId)
          .collection(friendships).where('status', isEqualTo: 'accepted').get();
      userData['friendships'] = friendships.docs...;
      return userData;
    });
}
```
With N users, this creates: N Firestore listeners (user doc snapshots) + N get() calls per outer update. At scale, this is a significant read amplification problem.

**D-07/D-08 replacement:** `FutureBuilder` that calls `AdminRepository.fetchUserConnections()`. New method:
```dart
Future<List<Map<String, dynamic>>> fetchUserConnections() async {
  final usersSnap = await _db.collection(FirebaseConstants.users)
      .limit(50).get();

  final futures = usersSnap.docs.map((userDoc) async {
    final uid = userDoc.id;
    final friendships = await _db
        .collection(FirebaseConstants.users)
        .doc(uid)
        .collection(FirebaseConstants.friendships)
        .where('status', isEqualTo: 'accepted')
        .get();
    return {
      'uid': uid,
      'username': userDoc.data()['username'] as String? ?? '',
      'connectionCount': friendships.size,
    };
  }).toList();

  return Future.wait(futures);
}
```
This runs exactly once per tab open (or manual refresh), performs `1 + N` reads total (where N <= 50), and creates zero persistent listeners.

**Optional refresh button (Claude's discretion):** A `FloatingActionButton` or `IconButton` in the `FutureBuilder` error/completed state that calls `setState(() { _futureConnections = widget._adminRepo.fetchUserConnections(); })` is the standard FutureBuilder refresh pattern.

### StreamBuilder hasError Audit

**Locations confirmed by codebase inspection:**

| Widget / Location | Stream | Has hasError? | Action (D-10) |
|---|---|---|---|
| `AdminDashboardScreen` (line 42) | `streamTransferLogsDetail()` | YES | No change |
| `AdminDashboard._buildSummaryCards` (outer, line 133) | `streamTotalTransfers()` | NO | Add hasError |
| `AdminDashboard._buildSummaryCards` (inner, line 147) | `streamTotalUsers()` | NO | Add hasError |
| `AdminDashboard._buildActiveSessionsList` (line 166) | `streamActiveHandshakesDetail()` | NO | Add hasError |
| `SecurityPulseFeed` (line 15) | `streamSecurityAuditLog()` | NO | Add hasError |
| `UserManagementList` (line 15) | `streamAllUsers()` | NO | Add hasError |
| `TransferVolumeChart` (line 23) | `streamTransferLogsDetail()` | NO | Add hasError |
| `ConnectionNodeMap` (line 15) — outer | `streamUserConnections()` | NO | Replaced by FutureBuilder (D-07) |

**Existing pattern in AdminDashboardScreen (lines 42-48) to replicate:**
```dart
if (snapshot.hasError) {
  return Center(
    child: Text(
      'Error: ${snapshot.error}',
      style: TextStyle(color: cs.error),
    ),
  );
}
```
D-10 specifies a slightly simplified version: `'Error loading data'` (no error detail). This is appropriate for admin widgets where error details may leak internal info.

**Note on stat card StreamBuilders:** The outer `_buildSummaryCards` StreamBuilder wraps a `Row` containing the inner StreamBuilder. Adding `hasError` to the outer means returning a full-width error widget, which would collapse the Row. Recommendation: add `hasError` to both inner and outer, each returning a `_SummaryCard` with value `'–'` and error color, keeping the Row layout intact. This is Claude's discretion since D-10 says "shows `Center(child: Text('Error loading data', ...))`" — the planner should decide whether to follow literally or adapt for layout.

---

## Dead Method Verification

Three methods confirmed dead by grep (zero callers in `lib/` outside the repository file itself):

| Method | Signature | Confirmed Dead? |
|---|---|---|
| `streamTransferLogs()` | `Stream<QuerySnapshot<Map<String,dynamic>>>` | YES — no callers found. `streamTransferLogsDetail()` is the live variant used by `AdminDashboardScreen` and `TransferVolumeChart`. |
| `streamSecurityLogs()` | `Stream<QuerySnapshot<Map<String,dynamic>>>` | YES — no callers found. `streamSecurityAuditLog()` is the live variant used by `SecurityPulseFeed`. |
| `streamActiveHandshakes()` | `Stream<int>` | YES — no callers found. `streamActiveHandshakesDetail()` (returns `QuerySnapshot`) is the live variant used by `AdminDashboard._buildActiveSessionsList`. |

Grep confirms: the only references to `streamTransferLogs`, `streamSecurityLogs`, and `streamActiveHandshakes` in `lib/` are the method definitions in `admin_repository.dart` itself. The naming pattern is clear: the `*Detail()` variants replaced the simpler `Stream<int>` / unlimted-snapshot variants.

**Live methods to keep (must not be removed):**
- `streamTotalTransfers()` — used in `AdminDashboard._buildSummaryCards`
- `streamTotalUsers()` — used in `AdminDashboard._buildSummaryCards`
- `streamAllUsers()` — used in `UserManagementList`
- `streamActiveHandshakesDetail()` — used in `AdminDashboard._buildActiveSessionsList`
- `streamUserConnections()` — used in `ConnectionNodeMap` (will become unused after D-07, but should remain until D-07 is implemented in the same wave or removed together)
- `streamSecurityAuditLog()` — used in `SecurityPulseFeed`
- `streamTransferLogsDetail()` — used in `AdminDashboardScreen` and `TransferVolumeChart`
- `setUserActiveStatus()` — used in `UserManagementList._RevokeButton`

**Note on `streamUserConnections()`:** After D-07 replaces `ConnectionNodeMap`'s outer StreamBuilder with a FutureBuilder calling `fetchUserConnections()`, the `streamUserConnections()` method becomes unused. The planner should remove it in the same wave as D-07, or flag it as a D-11 companion removal.

---

## Stream Pattern Analysis (ConnectionNodeMap)

**Current widget structure:**
```
ConnectionNodeMap (StatelessWidget)
  ├── _adminRepo = AdminRepository()
  ├── _userRepo = UserRepository()
  └── build()
        └── StreamBuilder<QuerySnapshot>             ← 1 stream: users collection
              ├── loading: CircularProgressIndicator
              └── data: GridView.builder
                    └── [for each user i]
                          StreamBuilder<Map<String,dynamic>?>   ← N streams: one per user
                            stream: _userRepo.streamUserWithFriendships(uid)
                            └── _NodeTile(connectionCount: connCount)
```

**Problem:** With U users, this creates U+1 persistent Firestore listeners. Each inner listener also performs a `get()` query on every outer snapshot update (because `asyncMap` re-executes the async function on each emission). This is both an efficiency and cost concern.

**Replacement pattern (D-07/D-08):**
```
ConnectionNodeMap (StatefulWidget — needs FutureBuilder state management)
  ├── _adminRepo = AdminRepository()
  ├── _futureConnections: Future<List<Map<String,dynamic>>>
  └── initState() → _futureConnections = _adminRepo.fetchUserConnections()
  └── build()
        └── FutureBuilder<List<Map<String,dynamic>>>
              ├── waiting: CircularProgressIndicator
              ├── error: Center(Text('Error loading data'))
              └── data: GridView.builder
                    └── [for each record]
                          _NodeTile(username, connectionCount)
```

Note: `ConnectionNodeMap` needs to become a `StatefulWidget` to hold the `_futureConnections` field and support optional refresh. The current version is a `StatelessWidget`.

---

## Route Registration

**Current (`lib/main.dart` line 40):**
```dart
'/admin-dashboard': (context) => const AdminDashboard(),
```

**Required change (D-01):**
```dart
'/admin-dashboard': (context) => AdminGuard(child: const AdminDashboard()),
```

`AdminDashboard` has `const AdminDashboard({super.key})` constructor. `AdminGuard` wraps it as a non-const widget (because AdminGuard contains a StreamBuilder), so the `const` keyword is removed from the route expression.

**AdminGuard file location:** `lib/presentation/admin/admin_guard.dart` (new file).

**Required imports in `main.dart`:**
```dart
import 'presentation/admin/admin_guard.dart';
```

---

## Implementation Notes per Decision

### D-01 to D-03: AdminGuard

- New file: `lib/presentation/admin/admin_guard.dart`
- Import in `lib/main.dart`
- `AuthRepository` is already a dependency-injectable class; AdminGuard instantiates it directly (matching the `SidebarDrawer` pattern)
- `authRepo.currentUser` (returns `firebase_auth.User?`) is the gating null check before streaming
- The redirect must use `addPostFrameCallback` to avoid "setState during build" errors
- `Navigator.pushReplacementNamed(context, '/')` navigates to home (the `home:` property is `SplashScreen`, which handles auth state and routes to HomeScreen)

### D-04: Admin UID in Audit Log

- `firebase_auth` is already a dependency in `pubspec.yaml` (version ^6.3.0, lock 6.x)
- `AdminRepository` does not currently import `firebase_auth` — must add `import 'package:firebase_auth/firebase_auth.dart';`
- Use `FirebaseAuth.instance.currentUser?.uid` directly (not via `AuthRepository`) to avoid circular dependency
- Fallback to `'unknown'` if `currentUser` is null (edge case: admin session expired mid-action)
- The `securityAuditLog` collection is `FirebaseConstants.securityAuditLog = 'security_audit_log'` (verified)

### D-05 to D-06: Real Chart Data

- `loggedAt` field in `transfer_logs` is `FieldValue.serverTimestamp()` → cast as `(data['loggedAt'] as Timestamp?)?.toDate()`
- `transfer_logs` contains documents from both `TransferLogService` (start-of-transfer) and `TransferRepository.writeAuditLog` / `writeFinalAuditLog` — both use `loggedAt` key
- The 7-day window uses **local** time (`ts.toLocal()`) not UTC, per D-06
- X-axis index 0 = `today - 6 days`, index 6 = today
- Y-axis max should be dynamic (computed from `countsByDay.values.reduce(max)`) with a minimum of 1 to avoid a flat zero line
- `fl_chart 0.70.2`: `SideTitles` for bottom axis uses `getTitlesWidget: (value, meta) => Text(label)` — this is the current API (not deprecated `getTextStyles`)

### D-07 to D-09: ConnectionNodeMap FutureBuilder

- `ConnectionNodeMap` must change from `StatelessWidget` to `StatefulWidget` (FutureBuilder needs state)
- `fetchUserConnections()` queries `users` (limit 50) then friendship subcollections with `Future.wait`
- The friendship subcollection is `users/{uid}/friendships` with `status == 'accepted'` — matches `FirebaseConstants.friendships = 'friendships'` and `UserRepository.streamUserWithFriendships` pattern
- After this change, `_userRepo` field in `ConnectionNodeMap` becomes unused (remove it)
- `streamUserConnections()` in `AdminRepository` becomes unused — can be removed with D-11 or as a companion removal

### D-10: hasError Branches

- Standard error widget per D-10: `Center(child: Text('Error loading data', style: TextStyle(color: cs.error)))`
- Wrap in `Scaffold` for widgets that are full-tab (SecurityPulseFeed, UserManagementList) vs inline `Container` for sub-widgets (stat cards, chart)
- For `_buildSummaryCards` outer StreamBuilder: returning `Center(...)` would collapse the Row; returning a `Row` with two `_SummaryCard(value: '–')` error placeholders maintains layout — this is Claude's discretion
- Placement: `hasError` check goes AFTER `connectionState == waiting` and BEFORE `!snapshot.hasData` (standard Flutter ordering)

### D-11: Dead Method Removal

Simple deletion. Three method blocks to remove from `admin_repository.dart`:
1. Lines 17-22: `Stream<int> streamActiveHandshakes()` block
2. Lines 48-51: `Stream<QuerySnapshot> streamTransferLogs()` block  
3. Lines 53-56: `Stream<QuerySnapshot> streamSecurityLogs()` block

No callers to update.

### D-12: Pagination / Limits

Three one-line changes in `admin_repository.dart`:

```dart
// streamTransferLogsDetail: add .limit(100)
Stream<QuerySnapshot<Map<String, dynamic>>> streamTransferLogsDetail() {
  return _db.collection(FirebaseConstants.transferLogs)
      .orderBy('loggedAt', descending: true)
      .limit(100)      // ← ADD
      .snapshots();
}

// streamSecurityAuditLog: add .limit(100)
Stream<QuerySnapshot<Map<String, dynamic>>> streamSecurityAuditLog() {
  return _db.collection(FirebaseConstants.securityAuditLog)
      .orderBy('timestamp', descending: true)
      .limit(100)      // ← ADD
      .snapshots();
}

// streamAllUsers: add .limit(200)
Stream<List<UserModel>> streamAllUsers() => _db
    .collection(FirebaseConstants.users)
    .limit(200)        // ← ADD
    .snapshots()
    .map((s) => s.docs.map((d) => UserModel.fromDoc(d)).toList());
```

Note: Adding `.limit()` after `.orderBy()` is valid. Adding `.limit()` without `.orderBy()` on `streamAllUsers` is also valid (Firestore applies a default ordering by document ID in this case).

---

## Architecture Patterns

### AdminGuard Pattern (follows SidebarDrawer isAdmin check)

```
MaterialApp routes
  └── '/admin-dashboard'
        └── AdminGuard (StatelessWidget)
              └── StreamBuilder<UserModel?>(authRepo.streamUserProfile(uid))
                    ├── loading → Scaffold + CircularProgressIndicator
                    ├── error / isAdmin==false → addPostFrameCallback → pushReplacementNamed('/') + SnackBar
                    └── isAdmin==true → child (AdminDashboard)
```

### FutureBuilder Refresh Pattern (ConnectionNodeMap)

```dart
class ConnectionNodeMap extends StatefulWidget { ... }

class _ConnectionNodeMapState extends State<ConnectionNodeMap> {
  late Future<List<Map<String, dynamic>>> _futureConnections;
  final _adminRepo = AdminRepository();

  @override
  void initState() {
    super.initState();
    _futureConnections = _adminRepo.fetchUserConnections();
  }

  void _refresh() => setState(() {
    _futureConnections = _adminRepo.fetchUserConnections();
  });
  ...
}
```

---

## Test Coverage

**Existing test files that reference admin functionality:** None found (grep confirmed zero test files reference "admin").

**Current test baseline:** 107-108 tests passing (from STATE.md).

**Phase 11 impact on existing tests:** Zero — no existing test files cover admin. Existing tests test auth, encryption, session, handshake, role assignment, security, navigation, and stale key logic.

**Nyquist validation requirement** (nyquist_validation: true in config.json): New tests are required for this phase.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Flutter test (flutter_test package) |
| Config file | None — uses standard `flutter test` discovery |
| Quick run command | `flutter test test/admin/ -x` |
| Full suite command | `flutter test` |

### Phase Requirements to Test Map

| Decision | Behavior | Test Type | Automated Command | File Exists? |
|----------|----------|-----------|-------------------|-------------|
| D-01/D-02/D-03 | AdminGuard blocks non-admin users | Widget test | `flutter test test/admin/admin_guard_test.dart -x` | No — Wave 0 |
| D-01/D-02/D-03 | AdminGuard allows admin users | Widget test | `flutter test test/admin/admin_guard_test.dart -x` | No — Wave 0 |
| D-01/D-02/D-03 | AdminGuard shows loading state while stream pending | Widget test | `flutter test test/admin/admin_guard_test.dart -x` | No — Wave 0 |
| D-04 | setUserActiveStatus includes adminUid in audit log | Unit test | `flutter test test/admin/admin_repository_test.dart -x` | No — Wave 0 |
| D-04 | setUserActiveStatus fallback to 'unknown' when no user | Unit test | `flutter test test/admin/admin_repository_test.dart -x` | No — Wave 0 |
| D-05/D-06 | Chart aggregation: zero-padded 7-day window | Unit test | `flutter test test/admin/chart_aggregation_test.dart -x` | No — Wave 0 |
| D-05/D-06 | Chart aggregation: filters docs older than 7 days | Unit test | `flutter test test/admin/chart_aggregation_test.dart -x` | No — Wave 0 |
| D-11 | Dead methods removed (compile check) | Static analysis | `flutter analyze` | N/A (analyze, not test) |
| D-12 | streamTransferLogsDetail has .limit(100) | Unit test | `flutter test test/admin/admin_repository_test.dart -x` | No — Wave 0 |

### Sampling Rate
- Per task commit: `flutter analyze` (fast, catches compile errors from deletions)
- Per wave merge: `flutter test test/admin/ -x`
- Phase gate: full `flutter test` suite green before verification

### Wave 0 Gaps

- [ ] `test/admin/admin_guard_test.dart` — covers D-01/D-02/D-03 (AdminGuard widget tests)
- [ ] `test/admin/admin_repository_test.dart` — covers D-04, D-11 deletion check, D-12 limit verification
- [ ] `test/admin/chart_aggregation_test.dart` — covers D-05/D-06 aggregation logic (pure Dart unit tests, no Firebase needed)

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Auth guard pattern | Custom session check logic | `AuthRepository.streamUserProfile(uid)` + `UserModel.isAdmin` | Already used in `SidebarDrawer` — identical pattern |
| Timestamp grouping | Custom date parsing | `Timestamp.toDate().toLocal()` + `DateTime(y,m,d)` equality | Standard Dart DateTime; `.difference().inDays` for index |
| Parallel async reads | Sequential `await` loop | `Future.wait(futures)` | Runs N friendship queries concurrently instead of serially |
| Chart data points | Custom chart library | `fl_chart 0.70.2` (already installed) | Already imported; no new dependency |

---

## Common Pitfalls

### Pitfall 1: Navigator inside build()
**What goes wrong:** Calling `Navigator.pushReplacementNamed` directly inside `StreamBuilder`'s builder function throws "setState called during build."
**Why it happens:** Flutter disallows navigation during the widget build phase.
**How to avoid:** Use `WidgetsBinding.instance.addPostFrameCallback((_) { ... })` to defer navigation to after the current frame.
**Warning signs:** `FlutterError: setState called during build` in the debug console.

### Pitfall 2: FutureBuilder rebuilds on every parent rebuild
**What goes wrong:** If `fetchUserConnections()` is called inline in `build()` rather than stored in a `Future` field, the FutureBuilder re-triggers the Future on every rebuild, causing N reads per rebuild.
**How to avoid:** Store the Future in `initState()` and only reassign via `setState()` on explicit refresh.
**Warning signs:** Network tab shows repeated identical reads; `initState` not overridden on ConnectionNodeMap.

### Pitfall 3: Timestamp null / type cast failure
**What goes wrong:** `data['loggedAt'] as Timestamp` throws if the field is null (during the serverTimestamp() write window, the field may not be present in the local snapshot yet).
**How to avoid:** Always null-check: `(data['loggedAt'] as Timestamp?)?.toDate()`. Skip null documents in aggregation.
**Warning signs:** `type 'Null' is not a subtype of type 'Timestamp'` crash in chart build.

### Pitfall 4: hasError placement order
**What goes wrong:** Checking `!snapshot.hasData` before `snapshot.hasError` means error states that also have no data fall through to the loading spinner, hiding the error.
**How to avoid:** Standard order: (1) `connectionState == waiting`, (2) `hasError`, (3) `!hasData`, (4) data access.
**Warning signs:** Firestore permission errors silently show a spinner forever.

### Pitfall 5: streamUserConnections() left in place after D-07
**What goes wrong:** After ConnectionNodeMap switches to FutureBuilder, `streamUserConnections()` in AdminRepository becomes a dead method. If left in place it creates confusion. If removed without checking callers first, compilation fails.
**How to avoid:** Verify zero callers before removing; remove in the same wave as D-07.

---

## Environment Availability

Step 2.6: SKIPPED — this phase is code/config-only changes within an existing Flutter project. No new external dependencies are introduced. `firebase_auth` (already a direct dependency), `fl_chart 0.70.2` (already installed), and `cloud_firestore` (already installed) are the only packages touched.

---

## Sources

### Primary (HIGH confidence — direct codebase inspection)
- `lib/main.dart` — route registration confirmed (line 40)
- `lib/data/repositories/admin_repository.dart` — all method signatures, dead method confirmation
- `lib/presentation/admin/admin_dashboard.dart` — StreamBuilder locations, missing hasError
- `lib/presentation/admin/admin_dashboard_screen.dart` — existing hasError pattern (lines 42-48)
- `lib/presentation/admin/widgets/connection_node_map.dart` — N-stream pattern confirmed
- `lib/presentation/admin/widgets/security_pulse_feed.dart` — missing hasError confirmed
- `lib/presentation/admin/widgets/transfer_volume_chart.dart` — fake sawtooth confirmed (line 34)
- `lib/presentation/admin/widgets/user_management_list.dart` — missing hasError confirmed
- `lib/presentation/home/sidebar_drawer.dart` — `streamUserProfile` + `isAdmin` pattern (lines 119-137)
- `lib/data/repositories/auth_repository.dart` — `streamUserProfile(String uid)` signature (line 324)
- `lib/data/repositories/user_repository.dart` — `streamUserWithFriendships` (lines 36-60)
- `lib/core/constants/firebase_constants.dart` — collection name constants
- `pubspec.yaml` + `pubspec.lock` — `fl_chart: ^0.70.2`, resolved to `0.70.2`
- `.planning/config.json` — `nyquist_validation: true`
- grep results — zero admin test files; zero callers of dead methods

### Secondary (MEDIUM confidence — design decisions)
- `11-CONTEXT.md` decisions D-01 through D-12 — user-locked implementation choices

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `streamUserConnections()` is also dead after D-07 and should be removed alongside D-11 dead methods | Dead Method Verification | Low risk: if left in place it compiles fine but is unused dead code |
| A2 | Friendship subcollection for D-08 uses `FirebaseConstants.friendships = 'friendships'` with `status == 'accepted'` filter, matching `UserRepository.streamUserWithFriendships` | Implementation Notes D-07-D-09 | Low risk: both confirmed from codebase; mismatch would cause zero connection counts |

**All other claims verified by direct file inspection.**

---

## Open Questions

1. **`_buildSummaryCards` hasError layout**
   - What we know: D-10 says "Error branch shows `Center(child: Text('Error loading data', ...))`" 
   - What's unclear: The outer StreamBuilder returns a `Row` — returning a `Center` widget collapses the row to a single error widget. The inner StreamBuilder is nested inside the Row.
   - Recommendation: Return a `Row` of two `_SummaryCard(value: '–', color: cs.error)` for the outer error case; return a single `_SummaryCard(value: '–')` for the inner error case. Planner should confirm this interpretation.

2. **`streamUserConnections()` removal scope**
   - What we know: This method becomes unused after D-07 but was not listed in D-11's removal list
   - What's unclear: Should it be removed in D-11's wave or D-07's wave?
   - Recommendation: Remove it in the same wave as D-07 to keep the codebase clean.

3. **AdminGuard `const AdminDashboard()` vs non-const**
   - What we know: `AdminDashboard({super.key})` is a const constructor; `AdminGuard` is not const
   - What's unclear: The routes map entry would need to be `AdminGuard(child: const AdminDashboard())` (non-const wrapper, const child)
   - Recommendation: Confirmed safe pattern — `const` applied to `AdminDashboard()` child is fine; the outer `AdminGuard(...)` call is non-const as expected.

---

## Metadata

**Confidence breakdown:**
- Current state analysis: HIGH — all files read directly
- Dead method verification: HIGH — grep confirmed zero callers
- Stream pattern analysis: HIGH — code read and confirmed
- hasError audit: HIGH — all admin widgets read
- Implementation notes: HIGH — code patterns verified against existing codebase
- Test coverage: HIGH — grep confirmed zero admin test files

**Research date:** 2026-06-02
**Valid until:** 2026-07-02 (stable codebase; only changes from this phase itself would invalidate)
