---
status: investigating
trigger: "Active Connections section on HomeScreen shows frozen/unresponsive screen, green Connected badge never appears for accepted connections (may still show Pending or nothing). Role Picker bottom sheet works; navigation to SenderScreen/ReceiverScreen with UID pre-fill also works."
created: 2026-05-13T00:00:00Z
updated: 2026-05-13T00:02:00Z
symptoms_prefilled: true
---

## Current Focus

hypothesis: CONFIRMED — root causes identified through exhaustive code tracing

Root cause for FROZEN/UNRESPONSIVE screen:
  The triple-nested StreamBuilder in _ActiveConnectionsSection (lines 920-1014)
  shows a CircularProgressIndicator on first load until all three streams
  emit their first snapshot. More critically, there is NO hasError branch.
  If any stream errors (Firestore permission denied, network failure), the
  StreamBuilder is in ConnectionState.active with snapshot.hasError=true,
  snapshot.data=null, docs=[], allRows=[] — and _EmptyConnectionsPrompt
  renders ("No connections yet"). This empty-state rendering is what users
  perceive as "frozen" — the screen IS responding to taps, but showing
  wrong content with no error feedback. The duplicate stream subscription
  in _startOutcomeListener (line 107 creates a new streamOutgoingPending
  SEPARATE from the _outgoingPendingStream field at line 55) means any
  per-doc outcome subs are based on a different stream instance, causing
  mis-timed event processing.

Root cause for MISSING CONNECTED BADGE:
  CONFIRMED via code path trace: the data model, field names, stream queries,
  Firestore write rules, and StreamBuilder badge logic are ALL consistent.
  The Connected badge WILL appear once a doc transitions to status=connected
  in Firestore AND the stream reads are permitted. However, there are two
  bugs that can silently prevent the badge from appearing:

  BUG A — _PendingRequestRow._accepting never resets (home_screen.dart ~1234):
  When the user taps Accept in _PendingRequestRow, _accepting is set to true
  (button becomes spinner). widget.onAccept() fires. If acceptProposal throws
  a NetworkException (Firestore error), _acceptProposal's catchError only
  shows a SnackBar — it does NOT call setState(() => _accepting = false).
  The Accept button is permanently stuck as a spinner. The user CANNOT retry
  without scrolling away and back (re-mounting the widget). This is not the
  badge cause but masks whether accept actually worked.

  BUG B — No hasError handling in _ActiveConnectionsSection StreamBuilders
  (home_screen.dart lines 929-1014):
  If streamActiveConnectionsAsProposer or streamActiveConnectionsAsPartner
  error (e.g. Firestore offline, permission denied on the connected doc),
  snapshot.hasError is true but there is no error branch — it falls through
  to empty docs, allRows is empty, and _EmptyConnectionsPrompt renders.
  The user sees "No connections yet" even though connections exist in Firestore.
  This is the primary cause of the "never appears" symptom when network
  conditions are the issue.

  BUG C — _incomingPendingStream single-subscription stream used by both
  StreamBuilder AND _startHandshakeListener via a separate instance (not
  same stream object). Each call to _handshakeRepo.streamIncomingPending()
  creates a new Firestore subscription. _PendingRequestsSection uses
  _incomingPendingStream (line 448/56), and _startHandshakeListener calls
  streamIncomingPending() again at line 91 — a separate Firestore listener.
  Similarly _outgoingPendingStream (line 55) vs line 107 in _startOutcomeListener.
  These are wasteful but do NOT cause the badge to fail — they're independent
  subscriptions to the same Firestore query.

next_action: ANALYSIS COMPLETE — returning structured root cause report

## Symptoms

expected: Active Connections list renders connected users with green Connected badge after acceptance
actual: Screen shows No connections yet or CircularProgressIndicator; green Connected badge never appears
errors: none reported — visual/behavioral failure (errors silently swallowed by catchError/hasError)
reproduction: Accept a connection request -> return to HomeScreen Active Connections section
started: unknown

## Eliminated

- hypothesis: Field name mismatch between what sendProposal writes and what stream queries filter on
  evidence: sendProposal writes 'proposerId', 'partnerId', 'proposerUsername', 'partnerUsername'. Stream queries filter on same fields. UI reads same fields. All consistent.
  timestamp: 2026-05-13T00:02:00Z

- hypothesis: Wrong status string written on acceptance
  evidence: acceptProposal writes status='connected'. streamActiveConnectionsAsProposer/AsPartner query WHERE status=='connected'. _StatusBadge receives isConnected=true when docs come from these streams. All consistent.
  timestamp: 2026-05-13T00:02:00Z

- hypothesis: Firestore rules block the update in acceptProposal
  evidence: Rule allows partner to update status to 'connected' with diff restricted to status+updatedAt. acceptProposal batch.update sends exactly those two fields. Rules match the write.
  timestamp: 2026-05-13T00:02:00Z

- hypothesis: Missing Firestore composite indexes for two-equality compound queries
  evidence: Firestore does NOT require composite indexes for multiple equality (==) filters. Two ==  clauses on different fields are handled via automatic single-field index merge. Confirmed by Firestore documentation.
  timestamp: 2026-05-13T00:02:00Z

- hypothesis: Single-subscription stream conflict from two listeners on same stream instance
  evidence: _startHandshakeListener and _startOutcomeListener create NEW stream instances (separate .snapshots() calls), not second listeners on the same stream object. Each Firestore stream object has exactly one listener.
  timestamp: 2026-05-13T00:02:00Z

- hypothesis: StatelessWidget _ActiveConnectionsSection cannot react to stream events
  evidence: StreamBuilder maintains its own state regardless of whether the parent is StatefulWidget or StatelessWidget. Stream events cause StreamBuilder internal state updates and rebuilds.
  timestamp: 2026-05-13T00:02:00Z

## Evidence

- timestamp: 2026-05-13T00:02:00Z
  checked: handshake_repository.dart acceptProposal (lines 88-110) — full write path
  found: batch.update sends exactly {status:'connected', updatedAt:FieldValue.serverTimestamp()} to the doc identified by docId. Firestore rules accept this diff. No issue in write path.
  implication: If network is healthy and auth is valid, the write succeeds and Firestore emits the update to all connected listeners.

- timestamp: 2026-05-13T00:02:00Z
  checked: home_screen.dart _ActiveConnectionsSection (lines 919-1014) — StreamBuilder error handling
  found: Lines 929-935 check only ConnectionState.waiting for spinner. No hasError branch anywhere in the triple-nested StreamBuilder tree. If any stream is in error state, snapshot.data is null, docs is [], allRows is empty.
  implication: Silent failure — any stream error shows "No connections yet" instead of an error message. User perceives this as "frozen" (stuck on empty state).

- timestamp: 2026-05-13T00:02:00Z
  checked: home_screen.dart _PendingRequestRowState (lines 1180-1244) — accept button state management
  found: _accepting set to true on tap (line 1234). widget.onAccept fires (which calls _handshakeRepo.acceptProposal via .catchError). On error, catchError shows SnackBar but does NOT reset _accepting to false. No setState(() => _accepting = false) in error path.
  implication: Failed accept leaves the Accept button permanently as a spinner. User cannot retry without remounting the widget. This masks whether accept actually succeeded or failed.

- timestamp: 2026-05-13T00:02:00Z
  checked: home_screen.dart lines 91 vs 56, and 107 vs 55 — duplicate stream subscriptions
  found: _startHandshakeListener (line 91) calls _handshakeRepo.streamIncomingPending() independently from _incomingPendingStream (line 56). _startOutcomeListener (line 107) calls _handshakeRepo.streamOutgoingPending() independently from _outgoingPendingStream (line 55). Each creates a new Firestore WebSocket listener.
  implication: 2x Firestore read quotas consumed. Slightly different event timing between the listener-based subscriptions and the StreamBuilder-based ones. Not a correctness bug but a waste and a maintenance smell.

- timestamp: 2026-05-13T00:02:00Z
  checked: home_screen.dart _showProposalBanner onAccept (line 196-205) — banner accept path
  found: entry.remove() is called before acceptProposal. The acceptProposal is fire-and-forget (no await). _ProposalBannerState._accepting is set to true but the widget is then unmounted by entry.remove(). setState on an unmounted widget is safe (Flutter ignores it). No issue here.
  implication: Banner accept path is clean. Not a source of bugs.

- timestamp: 2026-05-13T00:02:00Z
  checked: Complete data flow for "UserA (current) accepts UserB's incoming proposal"
  found: Doc B_A (proposerId=B, partnerId=A, status=pending) gets updated to status=connected via acceptProposal. streamActiveConnectionsAsPartner (WHERE partnerId=A AND status=connected) returns doc B_A. _ActiveConnectionsSection partnerDocs loop reads data['proposerId']=B as uid. seenUids.add(B) succeeds. _ActiveConnectionRow(username=B, partnerUid=B, isConnected=true) added. _StatusBadge(isConnected:true) renders green Connected badge.
  implication: Correct end-to-end IF the stream emits without error. The only way the badge does NOT appear is if (a) the Firestore write failed (acceptProposal threw and .catchError swallowed it without resetting UI) or (b) the stream returned an error and _ActiveConnectionsSection fell through to empty state with no feedback.

## Resolution

root_cause: "TWO distinct bugs causing the two symptoms:
  (1) FROZEN/EMPTY SCREEN: _ActiveConnectionsSection has no hasError branch in any of its three nested StreamBuilders (home_screen.dart lines 929-1014). When any stream errors (network issue, Firestore offline), snapshot.data is null, the docs list is empty, allRows is empty, and _EmptyConnectionsPrompt ('No connections yet') renders silently — no error message, no retry option. Users see an apparently stuck empty state and interpret it as frozen.
  (2) MISSING CONNECTED BADGE: _PendingRequestRowState._accepting is set to true when Accept is tapped but is NEVER reset to false in the error branch (home_screen.dart around line 1234). If acceptProposal fails (Firestore write error), the Accept button is permanently stuck as a spinner. The user cannot retry, and since there is no visual error on the badge itself, they believe the accept succeeded but the badge never appeared. Combined with the StreamBuilder not surfacing stream errors (bug 1), the user sees the empty connections list and concludes the badge is missing."

fix: "Three changes needed:
  1. Add hasError handling to all three StreamBuilders in _ActiveConnectionsSection. When snapshot.hasError is true, show an error widget with a description and optionally a retry affordance. This makes failures visible rather than silent.
  2. Reset _accepting=false in the error branch of _PendingRequestRow's onAccept callback. The _acceptProposal method should call a completion callback or the .catchError should call setState. Since _acceptProposal is a void method in the parent state, the cleanest fix is to make the onAccept callback return a Future and use async/await in _PendingRequestRowState so it can reset _accepting on completion/error.
  3. Fix duplicate stream subscriptions: in _startHandshakeListener, replace _handshakeRepo.streamIncomingPending().listen(...) with _incomingPendingStream.listen(...); in _startOutcomeListener, replace _handshakeRepo.streamOutgoingPending().listen(...) with _outgoingPendingStream.listen(...)."

verification:
files_changed: []
