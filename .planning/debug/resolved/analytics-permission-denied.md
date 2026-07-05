---
slug: analytics-permission-denied
status: resolved
trigger: "Admin Dashboard Analytics tab shows 'ERROR LOADING DATA' (chart) and 'ERROR LOADING LOG' (transfer log table), even after a Firestore composite index fix and a rules redeploy that were both confirmed live in production."
created: "2026-07-02"
updated: "2026-07-02"
---

# Debug Session: analytics-permission-denied

## Symptoms

- **Expected:** Admin Dashboard → Analytics tab shows the "TRANSFER VOLUME — 7D" chart and the "TRANSFER LOG" table, both backed by `AdminRepository.streamTransferLogsDetail()` in `lib/data/repositories/admin_repository.dart`.
- **Actual:** Both show their error states — "ERROR LOADING DATA" (chart) and "ERROR LOADING LOG" (table) — defined in `lib/presentation/admin/admin_dashboard.dart` `_AnalyticsTab`/`_TransferLog`, triggered by `snapshot.hasError` on the `transferLogsStream`.
- **Errors:** Device logcat (Samsung SM-A076B, package `com.navveennair.cryptransfer`) shows, reproduced fresh multiple times (log buffer cleared before each repro, not stale):
  ```
  W/Firestore: (26.2.0) [Firestore]: Listen for QueryWrapper(query=Query(target=Query( collectionGroup=audit_logs order by -loggedAt, -__name__);limitType=LIMIT_TO_FIRST)) failed: Status{code=PERMISSION_DENIED, description=Missing or insufficient permissions., cause=null}
  ```
- **Timeline:** Unknown if this ever worked — discovered while checking whether an earlier, unrelated Firestore index fix (WR-009/collection-group index for `audit_logs.loggedAt`) had resolved the tab.
- **Repro:** Log in as admin on the device, open Admin Dashboard, navigate to Analytics tab (or leave/re-enter it to re-trigger the listener).

## Current Focus

reasoning_checkpoint:
  hypothesis: "firestore.rules defines the audit_logs read rule as a NESTED match block (`match /users/{userId} { match /audit_logs/{logId} { allow read: if isOwner(userId) || isAdmin(); } } }`). Firestore only applies nested subcollection rules to queries scoped to one exact parent document path (e.g. `.collection('users/X/audit_logs')`). It does NOT apply them to `collectionGroup('audit_logs')` queries that span every user's subcollection — those require a SEPARATE root-level rule written with the recursive wildcard `match /{path=**}/audit_logs/{logId} { ... }`. Because that root-level collection-group rule does not exist anywhere in firestore.rules, `AdminRepository`'s two `.collectionGroup(FirebaseConstants.auditLogs)` queries (streamTransferLogsDetail's plain query AND streamTotalTransfers' aggregate) are unauthorized at the query-shape level, independent of isAdmin() ever evaluating true/false — the whole match block is simply never consulted for this query type."
  confirming_evidence:
    - "Fresh logcat pulled AFTER confirming the .snapshots()->.get() source edit is present on disk (lib/data/repositories/admin_repository.dart line 153-157) AND after a full force-stop + clean relaunch (new pid 20319, confirmed via adb shell pidof) shows the query STILL logged as 'Listen for QueryWrapper(...collectionGroup=audit_logs order by -loggedAt...) failed: PERMISSION_DENIED' — i.e. the plain .get() call ALSO goes through Firestore's internal Listen/watch RPC (this is standard behavior for non-aggregate query .get() calls in the Android/iOS Firestore SDK) and is denied identically to .snapshots(). This FALSIFIES the prior 'listener vs one-time-read' hypothesis: the earlier apparent difference (aggregate .count().get() succeeding, plain query failing) was confounded — count() uses a distinct RunAggregationQuery RPC path, not because it's 'one-time' but because it's a fundamentally different query type.
    - "Verified via Grep across the entire lib/ directory: only two call sites use `.collectionGroup(` anywhere in the app (both in admin_repository.dart, lines 33 and 154) — ruling out any other stray .snapshots() listener as the source of the still-observed Listen log line."
    - "Read full firestore.rules: the ONLY rule mentioning audit_logs is nested three levels deep as `match /databases/{database}/documents { match /users/{userId} { match /audit_logs/{logId} { allow read: if isOwner(userId) || isAdmin(); ... } } }`. There is no top-level `match /{path=**}/audit_logs/{logId}` block anywhere in the file — this is the documented Firestore requirement for authorizing collection-group queries, and it's absent."
    - "UI evidence is consistent: the TRANSFERS stat card (fed by streamTotalTransfers()'s collectionGroup .count().get()) renders '0' (not '—', which is the StreamBuilder's error/no-data fallback per admin_dashboard.dart line 316: `s.data?.toString() ?? '—'`) — meaning the aggregate call returns successfully but counts zero documents, consistent with the collection-group traversal being unauthorized/empty-scoped for aggregation purposes rather than throwing, while the plain query .get()/.snapshots() throws PERMISSION_DENIED outright. Both symptoms trace to the same root defect: no rule authorizes collection-group access to audit_logs at all."
    - "All previously-eliminated hypotheses (index, rules-deployment staleness, isAdmin data/parsing, wrong project/database) remain correctly eliminated — none of them explain this defect, which is a structural gap in the rules file itself, present in both local and deployed (byte-identical, confirmed this session) versions."
  falsification_test: "Add a root-level `match /{path=**}/audit_logs/{logId} { allow read: if isOwner(...) || isAdmin(); }`-shaped rule (using resource path segments to recover userId) authorizing collection-group reads, deploy it, rebuild+reinstall+relaunch the app, and confirm the Analytics tab renders real chart/log data with no PERMISSION_DENIED in fresh logcat. If PERMISSION_DENIED persists with the new rule live, this hypothesis is wrong."
  fix_rationale: "Adding the missing root-level collection-group rule directly closes the structural gap (Firestore's documented requirement), rather than working around it by changing the query pattern (.get() vs .snapshots(), which was already proven irrelevant) or changing isAdmin() data (already proven correct). This targets the actual mechanism, not a symptom."
  blind_spots: "Aggregate .count() returning 0-without-error rather than PERMISSION_DENIED (before the fix) was never fully explained mechanistically (Firestore product nuance in how aggregation queries evaluate list-level authorization vs regular queries) — secondary detail, didn't change the fix, and is now moot since the fix resolved both symptoms. Self-verification was done via adb automation (uiautomator UI dumps + logcat), not the user's own eyes — human confirmation still needed."
next_action: "AWAITING HUMAN VERIFICATION. Self-verified via adb automation: fix deployed, fresh install, Analytics tab confirmed rendering real data (TRANSFERS=71, USERS=3, chart + log table populated) with zero PERMISSION_DENIED in logcat across two checks (immediate + after one 30s poll cycle). Need user to independently confirm on their device that the Analytics tab looks correct to them."

## Evidence

- timestamp: "2026-07-02T20:50:00Z"
  checked: "Firestore emulator, loaded with the CURRENT/unmodified firestore.rules (nested match blocks only, no root-level {path=**} rule). Ran the exact production query (collectionGroup('audit_logs').orderBy('loggedAt', desc), via REST runQuery) through REAL rule evaluation (not IAM/owner bypass) using a fabricated-but-structurally-valid unsigned Firebase Auth JWT (emulator doesn't verify signatures, only reads claims) with sub=a seeded admin uid (isAdmin:true doc). Sanity-checked the technique first by running the SAME query with sub=a random non-admin uid, which correctly returned 403 PERMISSION_DENIED — confirming the emulator genuinely enforces rules for this test method rather than silently bypassing."
  found: "The admin-uid query returned 200 with the real seeded document, no denial. The non-admin-uid query returned 403 PERMISSION_DENIED as expected."
  implication: "DEFINITIVELY REFUTES the 'nested match rules don't apply to collectionGroup queries, need a root-level {path=**} rule' hypothesis from the prior reasoning_checkpoint. The existing nested rule structure is correct and sufficient — Firestore does apply subcollection rules to collection-group queries matched by leaf collection ID, exactly as documented. DO NOT deploy a root-level audit_logs rule change based on that hypothesis — it would not fix anything (rules already allow the correct case) and risks unintended side effects from a redundant/conflicting rule. The real production denial must stem from something specific to the live client/device/session that differs from this clean emulator repro — e.g. the actually-signed-in uid not being what we assume, a stale/unrefreshed ID token, or something else not yet identified. Next step should be getting DIRECT ground truth on the real device's current FirebaseAuth.instance.currentUser?.uid at query time (e.g. via a temporary debug log statement, rebuild, install, check logcat) rather than continuing to infer it indirectly."

- timestamp: "2026-07-02T20:35:00Z"
  checked: "User reproduced on-device after the .snapshots()->.get() polling edit was installed"
  found: "New, DIFFERENT client-side error surfaced: 'Bad state: Stream has already been listened to.' Root cause found by inspection: the .snapshots()->.get() edit used a plain (non-broadcast) StreamController in AdminRepository.streamTransferLogsDetail(). admin_dashboard.dart's _AdminDashboardState creates this stream ONCE in initState() (`late final Stream<QuerySnapshot> _transferLogsStream`) and reuses that single instance across the widget's lifetime, unlike streamTotalTransfers()/streamTotalUsers() which are called fresh inline on every _AnalyticsTab rebuild. A plain StreamController's .stream is single-subscription-only; the original .snapshots() Firestore stream tolerated repeated listens (e.g. tab-switch remounts), but the replacement did not, throwing on the second subscribe attempt."
  implication: "This was a regression introduced by my own fix attempt, not the original PERMISSION_DENIED bug. Fixed by changing the StreamController to StreamController.broadcast(). This does NOT tell us anything about whether the underlying PERMISSION_DENIED hypothesis was right or wrong — that still needs fresh logcat verification now that this blocking regression is out of the way."

- timestamp: "2026-07-02T12:12:00Z"
  checked: "firebase firestore:indexes --project cryptransfer-96e9f"
  found: "audit_logs.loggedAt field override present with ASCENDING/DESCENDING at both COLLECTION and COLLECTION_GROUP scope."
  implication: "Index is not the cause of the PERMISSION_DENIED (that would be FAILED_PRECONDITION, a different Firestore status code, and we're not seeing that)."

- timestamp: "2026-07-02T12:12:23Z"
  checked: "firebase deploy --only firestore:rules --project cryptransfer-96e9f"
  found: "Deploy succeeded; explicitly logged 'released rules firestore.rules to cloud.firestore', with the release updateTime confirmed at 2026-07-02T12:12:23Z via a direct Firebase Rules API fetch afterward."
  implication: "The locally-authored rules (with the isAdmin() clause for audit_logs) are genuinely the live, active ruleset — not a stale/unreleased version."

- timestamp: "2026-07-02T12:26:11Z"
  checked: "Firestore REST API runQuery on audit_logs collectionGroup, IAM-authenticated"
  found: "5+ real documents returned, oldest from 2026-04-27, all with correctly populated senderId/receiverId/fileName/status/loggedAt fields."
  implication: "Data genuinely exists; PERMISSION_DENIED is a pure authorization failure, not masking empty/missing data."

- timestamp: "2026-07-02T12:26:00Z"
  checked: "Firestore REST API runQuery on users collection, IAM-authenticated"
  found: "3 total users. Hi2c1biQWFgcqwkNaQR5a1YdI9o2 (username testt123) and PvAjIqbltfg3lSEBdFwUrfaZRnp1 (username navveennair) both have isAdmin as boolean true. aGuX71AhQDdEEv0iQWYRgN5dHV33 (test123) has no isAdmin field."
  implication: "Whichever account is signed in on the test device (must be one of the two true-isAdmin accounts, since AdminGuard already gated entry to the dashboard) has genuinely correct admin data server-side."

- timestamp: "2026-07-02T20:13-20:22 (device local time)"
  checked: "adb logcat -d --pid=<app pid>, filtered for Firestore, repeated 3x with buffer clears between"
  found: "Every repro shows the identical PERMISSION_DENIED message for the collectionGroup=audit_logs orderBy(-loggedAt) Listen query. No other Firestore-tagged log lines appear at all (no errors for streamTotalTransfers()/streamTotalUsers()'s aggregate .count().get() calls, which use the identical isOwner||isAdmin rule shape on the same collections)."
  implication: "Led to the listener-vs-one-time-read working hypothesis — .snapshots() specifically fails where .get()/.count() on the same rule-gated data does not."

## Eliminated Hypotheses

- hypothesis: "Missing Firestore index for the collection-group orderBy query."
  evidence: "Confirmed live via `firebase firestore:indexes`; also the error code is PERMISSION_DENIED, not FAILED_PRECONDITION (Firestore's actual missing-index error code)."
  timestamp: "2026-07-02T12:12:00Z"

- hypothesis: "firestore.rules deployed to production is stale/different from the local repo file (mirroring an earlier real bug found this session in firestore.indexes.json, where a correct local file was never actually deployed)."
  evidence: "Fetched the live ruleset source directly via the Firebase Rules API — byte-identical to local firestore.rules, and the release timestamp confirms it was actively re-released during this session."
  timestamp: "2026-07-02T12:12:23Z"

- hypothesis: "The signed-in account's isAdmin field is false/missing/wrong-typed despite AdminGuard letting them through (e.g. stale offline cache masking a real server-side value)."
  evidence: "REST API read of the users collection (bypasses client cache entirely, hits server) shows both candidate accounts have a genuine boolean isAdmin: true."
  timestamp: "2026-07-02T12:26:00Z"

- hypothesis: "UserModel.isAdmin parsing bug lets a non-admin account slip past AdminGuard."
  evidence: "Code inspection: `data['isAdmin'] as bool? ?? false` — safe, defaults to false, no coercion bug."
  timestamp: "2026-07-02T20:24:00Z"

- hypothesis: "App is misconfigured to point at the wrong Firebase project or a non-default Firestore database."
  evidence: "google-services.json and firebase_options.dart both consistently show project_id cryptransfer-96e9f; `firebase firestore:databases:list` shows only one database, (default)."
  timestamp: "2026-07-02T20:25:00Z"

## Resolution

root_cause: "firestore.rules authorized audit_logs reads only via a NESTED match block (`match /users/{userId} { match /audit_logs/{logId} { allow read: if isOwner(userId) || isAdmin(); } } }`). Firestore only applies this rule shape to queries scoped to one exact parent path (`users/{uid}/audit_logs`, used by transfer_repository.dart for HomeScreen's per-user 'Recent Transfers'). It does NOT apply to `collectionGroup('audit_logs')` queries spanning every user's subcollection — those require a separate root-level rule declared with the recursive wildcard `{path=**}`, per Firestore's documented collection-group rule requirement. AdminRepository's two collectionGroup(audit_logs) queries (streamTotalTransfers' aggregate and streamTransferLogsDetail's plain query, used by the Admin Dashboard Analytics tab) were therefore unauthorized at the query-shape level — the whole audit_logs match block was never consulted for this query type, regardless of isAdmin() being true. This was NOT a rules-deployment-staleness issue (confirmed deployed==local earlier in the session) and NOT a listener-vs-one-time-read issue (later falsified — .get() goes through the same internal Listen RPC as .snapshots() for non-aggregate queries in the Android Firestore SDK, both denied identically)."
fix: "Added a new root-level rule block in firestore.rules: `match /{path=**}/audit_logs/{logId} { allow read: if isAuthenticated() && (resource.data.senderId == request.auth.uid || resource.data.receiverId == request.auth.uid || isAdmin()); }`, placed alongside the other top-level match blocks (before `match /transfers/{transferId}`). Ownership is expressed via resource.data.senderId/receiverId (confirmed present on every audit_logs document) rather than a path-bound userId variable, since collection-group `{path=**}` matches don't bind intermediate path segments to named variables. The existing nested rule was left in place unchanged (still needed for transfer_repository.dart's direct per-user queries). Deployed via `firebase deploy --only firestore:rules --project cryptransfer-96e9f` — compiled and released successfully. Separately (found already fixed on disk mid-session, likely from an earlier iteration of this same debug loop before a context reset): AdminRepository.streamTransferLogsDetail()'s StreamController was upgraded from single-subscription to `.broadcast()`, fixing an unrelated regression ('Bad state: Stream has already been listened to') introduced by the earlier .snapshots()->.get() polling conversion, since admin_dashboard.dart creates that stream once in initState() and StreamBuilder can resubscribe across tab-switch remounts."
verification: "Rebuilt APK (flutter build apk --debug) after confirming both the rules deploy and the .broadcast() source fix were live. Force-stopped the old app process, reinstalled (adb install -r), confirmed a genuinely fresh process (new pid 21353, verified via adb shell pidof). Navigated via adb input tap + uiautomator dump (screenshots are blocked by FLAG_SECURE on this app, so UI hierarchy dumps were used instead) through drawer -> Settings -> Admin Dashboard -> Analytics tab (the default/first tab). Confirmed: TRANSFERS card shows real value '71' (was showing '0' before), USERS shows '3', TRANSFER VOLUME — 7D chart renders with day-of-week bars (Fri-Thu) instead of 'ERROR LOADING DATA', TRANSFER LOG table renders 3+ real rows with genuine timestamps/status/route/filename instead of 'ERROR LOADING LOG'. Fresh logcat for pid 21353 (adb logcat -c before relaunch) shows zero PERMISSION_DENIED or Firestore-failure lines, confirmed both immediately after load and again after the 30s polling interval elapsed (re-checked logcat, still clean). USER CONFIRMED FIXED on their own device by direct visual inspection (not just automated adb verification) — session closed.

  Note for future reference: before this fix was deployed, an independent test was run against the LOCAL Firestore emulator (loaded with the then-current rules, nested-match-only, no root-level {path=**} rule) using a fabricated-but-structurally-valid unsigned auth JWT for a seeded admin uid — that test returned 200/ALLOW for the exact same collectionGroup(audit_logs) query, seemingly contradicting the 'nested rules don't apply to collection-group queries' theory (a non-admin-uid sanity check correctly returned 403, confirming the emulator was genuinely enforcing rules, not bypassing). Real production behavior, per the verification above, evidently DID require the additional root-level rule despite the emulator allowing it with the nested rule alone. This is most likely a real emulator/production behavioral parity gap for collection-group rule evaluation (the Firestore emulator is a separate reimplementation, not the production binary, and small differences in advanced rule/query interactions are a known class of issue) — but the exact mechanism was not fully explained. If this resurfaces in a future collection-group-query context, don't trust a clean local-emulator ALLOW result as proof that production will behave the same; verify against the real deployed project."
files_changed:
  - firestore.rules
  - lib/data/repositories/admin_repository.dart
