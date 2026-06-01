# Phase 11: Admin Dashboard Security & Efficiency Hardening - Context

**Gathered:** 2026-06-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Harden the admin dashboard layer on 7 identified issues across 3 severity tiers:
- CRITICAL: Unguarded `/admin-dashboard` named route
- SERIOUS: Missing admin UID in `setUserActiveStatus` audit log
- MEDIUM: Fake chart data, N parallel Firestore streams, no pagination/limits, missing `hasError` branches
- MINOR: 3 dead methods in AdminRepository

No new features, no new Firestore schema, no new collections. All changes are confined to `lib/presentation/admin/` and `lib/data/repositories/admin_repository.dart`.

</domain>

<decisions>
## Implementation Decisions

### AdminGuard (D-01 – D-03)
- **D-01:** AdminGuard is a **route wrapper widget** in `lib/main.dart`. The routes map becomes `'/admin-dashboard': (context) => AdminGuard(child: const AdminDashboard())`. AdminGuard is a new StatelessWidget in `lib/presentation/admin/admin_guard.dart`.
- **D-02:** AdminGuard streams `AuthRepository.streamUserProfile(currentUser.uid)` (the same source as `SidebarDrawer`). While the stream is loading, render a full-screen `CircularProgressIndicator`. When resolved, render the child if `isAdmin == true`, or trigger the non-admin flow if `false`.
- **D-03:** Non-admin behavior: show a SnackBar with the message `'Access denied'`, then call `Navigator.pushReplacementNamed(context, '/')` to redirect to home. Do not leave the user on the admin screen even briefly.

### Audit Log — Admin UID (D-04)
- **D-04:** `AdminRepository.setUserActiveStatus(String uid, bool isActive)` reads `FirebaseAuth.instance.currentUser?.uid` internally and adds `'adminUid': adminUid ?? 'unknown'` to the security audit log entry alongside the existing `event`, `details`, and `timestamp` fields. No change to the method signature or call sites.

### TransferVolumeChart Real Data (D-05 – D-06)
- **D-05:** The chart shows **last 7 calendar days**, one data point per day on the X-axis. X-axis range is fixed: today minus 6 days through today, regardless of how many transfers exist. Days with zero transfers plot as `FlSpot(i, 0)`.
- **D-06:** Aggregation is done **in Dart** from the existing `streamTransferLogsDetail()` stream. Filter documents where `loggedAt >= DateTime.now().subtract(const Duration(days: 7))`. Group by `loggedAt.toDate().toLocal()` date (year+month+day), count per group, map to 7 `FlSpot` values. No extra Firestore queries.

### ConnectionNodeMap Stream Consolidation (D-07 – D-09)
- **D-07:** Replace the `StreamBuilder` + per-user `StreamBuilder<Map<String,dynamic>?>` pattern with a **single `FutureBuilder`** that fetches users and their friendship counts in one pass on tab open. No ongoing N listeners.
- **D-08:** Implementation: fetch users via `AdminRepository.fetchUserConnections()` (new `Future`-returning method, `.limit(50)`). For each user UID, fetch accepted friendships from the user's `friendships` subcollection via a single batch approach (loop over user UIDs, collect `Future.wait` on friendship count queries). Combine counts in Dart and render the grid.
- **D-09:** Grid is **capped at 50 users** (`.limit(50)` on the users query). This matches the thesis-scale use case and makes the grid bounded.

### Missing hasError Branches (D-10)
- **D-10:** Add `snapshot.hasError` branch to every `StreamBuilder` in the admin layer that currently checks only `!snapshot.hasData`. Affected widgets: `SecurityPulseFeed`, `UserManagementList`, both stat-card `StreamBuilder`s in `AdminDashboard._buildSummaryCards`, the active-handshakes `StreamBuilder` in `AdminDashboard._buildAnalyticsTab`, and `AdminDashboardScreen`. Error branch shows: `Center(child: Text('Error loading data', style: TextStyle(color: cs.error)))`.

### Dead Method Removal (D-11)
- **D-11:** Remove 3 dead methods from `AdminRepository`: `streamTransferLogs()`, `streamSecurityLogs()`, and `streamActiveHandshakes()` (the `Stream<int>` variant). All 3 are defined but never called. `streamActiveHandshakesDetail()` (used in analytics tab) and `streamTotalTransfers()`/`streamTotalUsers()` (used in stat cards) remain.

### Pagination / Limits (D-12)
- **D-12:** Add `.limit(100)` to `streamTransferLogsDetail()` and `streamSecurityAuditLog()` (used by `AdminDashboardScreen` and `SecurityPulseFeed`). Add `.limit(200)` to `streamAllUsers()`. These are admin-facing streams where showing all docs is unnecessary and unbounded at scale. Connection node map already capped at 50 (D-09).

### Claude's Discretion
- Exact `SnackBar` duration and animation in AdminGuard non-admin redirect
- Whether to add a "Refresh" button to the ConnectionNodeMap FutureBuilder (acceptable either way)
- Exact Y-axis padding in the TransferVolumeChart
- Order of fixes within plan waves

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Admin layer files (read before any changes)
- `lib/presentation/admin/admin_dashboard.dart` — Main dashboard with tab controller and analytics tab
- `lib/presentation/admin/admin_dashboard_screen.dart` — Transfer logs screen
- `lib/presentation/admin/widgets/connection_node_map.dart` — N-stream issue to fix
- `lib/presentation/admin/widgets/security_pulse_feed.dart` — Missing hasError
- `lib/presentation/admin/widgets/transfer_volume_chart.dart` — Fake data to replace
- `lib/presentation/admin/widgets/user_management_list.dart` — Missing hasError + setUserActiveStatus call
- `lib/data/repositories/admin_repository.dart` — Dead methods, setUserActiveStatus, new methods needed

### Existing patterns to follow
- `lib/presentation/home/sidebar_drawer.dart` — Reference for `AuthRepository.streamUserProfile(uid)` isAdmin check pattern (lines 118–135)
- `lib/data/repositories/user_repository.dart` — `streamUserWithFriendships()` to be REPLACED (no longer called after D-07)
- `lib/presentation/widgets/shared_widgets.dart` — `GlassContainer` for AdminGuard error states if needed

### Route registration
- `lib/main.dart` — Route map where AdminGuard wrapper is added (only file changed for D-01)

### Security audit log schema
- `lib/data/repositories/admin_repository.dart` `setUserActiveStatus()` — current log fields: `event`, `details`, `timestamp`. Add `adminUid` (D-04).

### No external specs
No external ADRs or design docs for this phase — all requirements are captured in the decisions above and the ROADMAP.md phase description.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `AuthRepository.streamUserProfile(uid)`: Already used in `SidebarDrawer` for isAdmin check — reuse identical pattern in AdminGuard
- `GlassContainer`: Available from `shared_widgets.dart` — AdminGuard loading/error states can use it for consistency
- `fl_chart` package: Already imported in `transfer_volume_chart.dart` — no new dependency needed for real chart data
- `FirebaseAuth.instance.currentUser`: Available in any repository class — use for admin UID in D-04

### Established Patterns
- isAdmin streaming: `StreamBuilder<UserModel?>` on `authRepo.streamUserProfile(uid)` with `snapshot.data?.isAdmin ?? false` — see `sidebar_drawer.dart:121–135`
- hasError pattern: `if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}', style: TextStyle(color: cs.error)));` — already present in `admin_dashboard_screen.dart:44–48`; replicate this pattern in all other StreamBuilders
- Repository constructor injection: `AdminRepository({FirebaseFirestore? db})` — preserve this pattern when adding new methods

### Integration Points
- `main.dart` routes map: Only change is wrapping `AdminDashboard()` with `AdminGuard(child: AdminDashboard())`
- `AdminRepository`: Add `fetchUserConnections()` (Future), modify `setUserActiveStatus()` to read admin UID internally
- `ConnectionNodeMap`: Replace `_userRepo.streamUserWithFriendships(uid)` inner StreamBuilders with FutureBuilder approach — `UserRepository.streamUserWithFriendships` will become unused after this phase

</code_context>

<specifics>
## Specific Ideas

- AdminGuard SnackBar message: `'Access denied'` (short, clear)
- TransferVolumeChart X-axis: fixed 7-day window (always shows last 7 days even if 0 transfers on some days)
- ConnectionNodeMap grid: capped at 50 users, FutureBuilder with a manual refresh mechanism if user wants it

</specifics>

<deferred>
## Deferred Ideas

- Real-time ConnectionNodeMap (live per-user connection count updates) — accepted as out of scope; snapshot-on-load is sufficient for thesis demo
- Pagination UI for admin user list (load more button) — current approach is `.limit(200)` cap; full pagination is a future concern
- Cloud Functions for denormalized `connectionCount` field on user doc — over-engineered for current scale

</deferred>

---

*Phase: 11-admin-dashboard-security-efficiency-hardening-fix-critical-u*
*Context gathered: 2026-06-02*
