---
slug: b-missing-handshake-request
status: resolved
trigger: "user B is not receiving neutral handshake request when user A sends one"
created: "2026-06-22"
updated: "2026-07-05"
---

# Debug Session: b-missing-handshake-request

## Symptoms

- **Expected:** When user A sends a neutral handshake (connection) request targeting user B, user B should see the incoming request appear in their UI in real time.
- **Actual:** Nothing appears in user B's UI at all — the incoming request is never shown.
- **Errors:** None observed. Completely silent — no console errors, no crash, no visible Firestore permission-denied or other error.
- **Repro:** User A sends a connection/handshake request to user B (e.g. via search/connect flow). User B's incoming requests view never reflects it.
- **Timeline:** Regression — this flow worked before and broke recently. Recent related commits: `3f436fe fix(handshake): add missing role-conflict guard to selectSenderHandshake`, and uncommitted changes to `rules-tests/neutral_handshakes.test.mjs` are present on this branch (fix/critical-security-and-debt).

## Current Focus

hypothesis: "Firestore security rule for neutral_handshakes list query (partnerId==self && status==pending) is denying the recipient's streamIncomingPending() listen, OR a missing/empty composite index is silently failing the listen."
test: "Run rules-tests/neutral_handshakes.test.mjs (HAND-09-5/6) against firestore.rules via emulator to directly observe ALLOW/DENY for the list query shape used by streamIncomingPending()."
expecting: "If rule denies: assertSucceeds(getDocs(q)) fails in test HAND-09-5. If rule is fine: test passes, ruling out rules as cause."
next_action: "Run firebase emulator-backed mocha rules tests for neutral_handshakes and observe pass/fail."

## Evidence

- timestamp: "2026-06-22T00:00:00Z"
  checked: "commit 3f436fe diff (lib/data/repositories/key_repository.dart) — the 'role-conflict guard' commit named in context_notes"
  found: "This guard is in KeyRepository.selectSenderHandshake, which writes to the SESSION-layer 'handshakes' collection (transfer key-exchange), not the CONNECTION-layer 'neutral_handshakes' collection used for friend/connection requests. It only runs when a sender selects a receiver for a transfer session — completely unrelated code path to sending/receiving a connection request."
  implication: "3f436fe is very unlikely to be the root cause of a missing CONNECTION request. Lower priority; do not focus further here unless connection-layer leads are exhausted."

- timestamp: "2026-06-22T00:00:01Z"
  checked: "lib/data/repositories/handshake_repository.dart — sendProposal(), streamIncomingPending(), and related stream methods"
  found: "sendProposal() writes doc '${_uid}_$partnerUid' to neutral_handshakes with status:'pending', proposerId, partnerId. streamIncomingPending() queries .where('partnerId', isEqualTo: _uid).where('status', isEqualTo: 'pending'). This is consumed by FindFriendsScreen._subscribePending() (lib/presentation/home/find_friends_screen.dart:160-178), which populates _pendingRequests via setState. Looks structurally correct end-to-end."
  implication: "The write path and the intended read path both look correct in isolation. Bug must be in: (a) security rules denying the list query, (b) a missing index silently breaking the listen, (c) something preventing FindFriendsScreen's listener from being active/visible to the user, or (d) UI not surfacing pending requests outside of FindFriendsScreen (HomeScreen has no streamIncomingPending subscription at all — only outgoing/active streams)."

- timestamp: "2026-06-22T00:00:02Z"
  checked: "firestore.rules lines 157-194 — neutral_handshakes match block, 'allow read' rule"
  found: "allow read: if isAuthenticated() && (resource == null || resource.data.proposerId == request.auth.uid || resource.data.partnerId == request.auth.uid); — this rule covers both get and list semantics per-document. For a list query filtered by partnerId == request.auth.uid, every matched doc satisfies resource.data.partnerId == request.auth.uid, so the rule should evaluate ALLOW for each doc in a syntactically correct list call."
  implication: "Rule text alone does not show an obvious denial for the recipient's query shape. Need to actually run it against the emulator to be sure (rules engines have surprised people before with list vs get semantics)."

- timestamp: "2026-06-22T00:00:03Z"
  checked: "Uncommitted diff to rules-tests/neutral_handshakes.test.mjs"
  found: "New tests HAND-09-5 and HAND-09-6 were added (uncommitted) specifically as 'regression coverage for streamActiveConnectionsAsPartner/Proposer ... a list query, not a get' — comments reference status=='connected' but the actual where() filters use status=='pending'. This strongly suggests a prior debugging session already suspected the list-query/rules interaction and was mid-investigation when interrupted Tests have not yet been run/verified (no commit, no CI confirmation found)."
  implication: "This is very likely a continuation of the exact same investigation. Need to actually execute these tests against the local emulator to see PASS/FAIL — this is the fastest way to confirm or refute the rules hypothesis."

- timestamp: "2026-06-22T00:00:04Z"
  checked: "firestore.indexes.json (untracked/new) and firebase.json diff"
  found: "firestore.indexes.json exists on disk, is untracked in git (never committed), and contains indexes: [] (completely empty, only a fieldOverride for audit_logs/loggedAt). firebase.json's uncommitted diff adds \"indexes\": \"firestore.indexes.json\" to the firestore config block — previously firebase.json did not reference an indexes file at all. Equality-only composite queries (partnerId==X && status==Y) are generally covered by Firestore's automatic single-field index merging and do NOT require an explicit composite index entry, per Firebase docs (https://firebase.google.com/docs/firestore/query-data/index-overview)."
  implication: "Missing index is unlikely to be the direct cause of streamIncomingPending() failing, since it's equality-only. But the file being newly added/empty/uncommitted is suspicious as unrelated/incomplete work-in-progress; worth confirming it's not masking an index-needed query elsewhere (e.g. orderBy combined with where) before ruling out entirely."

- timestamp: "2026-06-22T00:00:05Z"
  checked: "Ran rules-tests/neutral_handshakes.test.mjs against local Firestore emulator (JAVA_HOME pointed at JDK 25 to work around firebase-tools Java 21+ requirement) with current firestore.rules"
  found: "All 6 tests PASS including HAND-09-5 (Partner lists where partnerId==self && status=='pending' -> ALLOW) and HAND-09-6 (Proposer lists where proposerId==self && status=='pending' -> ALLOW). Direct, repeatable, unambiguous evidence that the current firestore.rules does NOT deny the exact list-query shape used by streamIncomingPending()/streamOutgoingPending()."
  implication: "Firestore security rules hypothesis is REFUTED for the local rules file. Caveat: this only proves the LOCAL firestore.rules file is fine — does not yet prove the DEPLOYED rules in production match this file. Need to check if rules were actually deployed (firebase.json change + missing index commit suggests deploy step may have been skipped)."

## Eliminated Hypotheses

- hypothesis: "Firestore security rules for neutral_handshakes deny the recipient's list query (partnerId==self && status==pending), causing a silent empty stream."
  evidence: "rules-tests/neutral_handshakes.test.mjs HAND-09-5 and HAND-09-6 both PASS against the local firestore.rules file run through the Firestore emulator — assertSucceeds(getDocs(q)) succeeds for both the partner-side and proposer-side list queries. Additionally wrote and ran a temporary onSnapshot-based repro test (B listens via the exact streamIncomingPending() query shape BEFORE A creates the proposal doc) — listener received [] then [\"user-a-uid_user-b-uid\"] with zero errors, exactly matching the real-time flow used by FindFriendsScreen._subscribePending(). Temp test file removed after use."
  timestamp: "2026-06-22T00:00:05Z"

- hypothesis: "selectSenderHandshake's role-conflict guard (commit 3f436fe) incorrectly filters out legitimate connection requests."
  evidence: "Read the full diff of 3f436fe. The guard lives in KeyRepository.selectSenderHandshake, which operates exclusively on the SESSION-layer 'handshakes' collection (sender/receiver key exchange for an active transfer). The connection-layer bug is about 'neutral_handshakes' (HandshakeRepository), a structurally separate collection/class with no code path overlap. The guard cannot affect sendProposal()/streamIncomingPending()."
  timestamp: "2026-06-22T00:00:00Z"

- hypothesis: "Missing/empty firestore.indexes.json causes the composite query (partnerId==X && status==pending) to fail with FAILED_PRECONDITION."
  evidence: "Confirmed via Firebase docs that equality-only multi-field queries are covered by automatic single-field index merging — no composite index required. Confirmed empirically: the onSnapshot repro test above ran successfully against the emulator (which enforces the same index requirements as production) with zero errors and zero missing-index warnings."
  timestamp: "2026-06-22T00:00:06Z"

- hypothesis: "9189186 (UserRepository.streamUser/isFriend) or d98feb2 (auth_test mocks) touched connection-layer code and caused the regression."
  evidence: "Read both full diffs. 9189186 only touches lib/data/repositories/user_repository.dart (streamUser/isFriend additions) and receiver_transfer_screen.dart (sessionManager wiring for DecryptScreen) — no overlap with HandshakeRepository or neutral_handshakes. d98feb2 only touches test/module_tests/auth_test.dart mock setup — test-only, no production code changed. Neither is on the code path for sendProposal/streamIncomingPending."
  timestamp: "2026-06-22T00:00:07Z"

- hypothesis: "Uncommitted register_screen.dart change broke the connection-request flow."
  evidence: "Diff only wraps isUsernameTaken() in try/catch for registration-screen username availability checking — entirely within the registration form, unrelated to HandshakeRepository/FindFriendsScreen."
  timestamp: "2026-06-22T00:00:08Z"

## Resolution

root_cause: "Not conclusively identified within this session — rules and index hypotheses were both tested and refuted against the local emulator; investigation stalled before confirming whether deployed rules matched local at the time."
fix: "No code change was applied as part of this debug session."
verification: "User confirmed on 2026-07-05 that connection requests now arrive correctly for user B. Likely resolved incidentally by other handshake_repository.dart / rules changes landed since the investigation (e.g. deployed rules sync, or subsequent handshake flow fixes), not by a targeted fix from this session."
files_changed: []
