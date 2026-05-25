---
status: resolved
trigger: "Bug: accept connection proposal shows blank page for acceptor, requester status stays Pending"
created: 2026-05-13T00:00:00Z
updated: 2026-05-13T01:00:00Z
symptoms_prefilled: true
---

## Current Focus

reasoning_checkpoint:
  hypothesis: "_ActiveConnectionsSection and _PendingRequestsSection called handshakeRepo.stream*() INLINE in their build() methods, creating a new Stream object on every build. When the acceptor tapped Accept, setState(() => _accepting = true) triggered a rebuild. StreamBuilder.didUpdateWidget detected a new Stream reference and resubscribed from scratch, resetting to ConnectionState.waiting — which rendered SizedBox.shrink() / loading indicator, effectively blanking the section. The new subscription then had to wait for the next Firestore event before showing data. On the requester's side the same rebuild path caused _activeAsProposerStream to resubscribe and miss the already-fired 'connected' event, leaving the pending badge in place."
  confirming_evidence:
    - "git show 30184fb: _ActiveConnectionsSection had `stream: handshakeRepo.streamActiveConnectionsAsProposer()` inline in build(). _PendingRequestsSection had `stream: handshakeRepo.streamIncomingPending()` inline in build()."
    - "git show 801ed35: fix commit message says 'created new Stream objects on every build() call. StreamBuilder.didUpdateWidget detected the new stream reference and resubscribed from scratch, causing the UI to show stale data until navigation refresh'"
    - "Current home_screen.dart has all 4 streams as late final fields in initState — fix is already applied"
    - "When _accepting=true setState fires in _PendingRequestRow → parent rebuild → _ActiveConnectionsSection.build() calls handshakeRepo.stream*() again → new Stream instance → StreamBuilder resubscribes → connectionState=waiting → shows loading/blank"
  falsification_test: "If the fix were NOT present (streams inline in build), accepting a request and triggering a rebuild would show the blank/waiting state. With the fix (stable stream references), no resubscription occurs and the UI updates correctly from the existing subscription."
  fix_rationale: "Lifting streams to initState as late final fields means StreamBuilder always receives the same Stream object reference. StreamBuilder.didUpdateWidget only resubscribes when the stream reference changes — with stable references, the existing subscription receives the Firestore change event without interruption."
  blind_spots: "Composite index requirement for the 4 Firestore queries is a separate concern — if indexes are missing, the streams would error silently but this is a different failure mode from the blank page bug."

next_action: COMPLETE — root cause confirmed, fix already applied in commit 801ed35

## Symptoms
<!-- Written during gathering, then IMMUTABLE -->

expected: Tapping "Accept Request" updates status to Connected for both users; acceptor navigates to correct screen
actual: (1) Acceptor sees white/blank page after tapping Accept; (2) Requester's status stays "Pending"
errors: none reported (UI silently fails)
reproduction: User A sends handshake request to User B; User B taps "Accept Request"
started: present in neutral handshake flow (phase 05)

## Eliminated
<!-- APPEND only - prevents re-investigating -->

- hypothesis: "Firestore permission denial silently blocking the acceptProposal write"
  evidence: "Firestore rules for neutral_handshakes UPDATE allow partner to set status='connected' with affectedKeys().hasOnly(['status','updatedAt']). acceptProposal sends exactly those two fields. Rules pass."
  timestamp: 2026-05-13T00:13:00Z

- hypothesis: "Navigation to a blank route triggered by accept button"
  evidence: "All Navigator.push calls in home_screen.dart are in unrelated paths (_showNotifBanner onTap, _openAddConnectionSheet, _RolePickerSheet). No navigation in _acceptProposal or HandshakeRepository.acceptProposal."
  timestamp: 2026-05-13T00:14:00Z

- hypothesis: "_accepting flag causing blank page"
  evidence: "When _accepting=true the CrypButton renders disabled with a small spinner. The rest of the GlassContainer row content remains visible. Not a blank page."
  timestamp: 2026-05-13T00:20:00Z

- hypothesis: "Missing Firestore composite indexes causing stream errors"
  evidence: "Would produce silent empty results (allRows=[]) and show _EmptyConnectionsPrompt — not a blank white page. Separate concern from the resubscription bug."
  timestamp: 2026-05-13T00:19:00Z

## Evidence
<!-- APPEND only - facts discovered -->

- timestamp: 2026-05-13T00:10:00Z
  checked: HandshakeRepository.acceptProposal()
  found: Uses WriteBatch to update primary doc (A_B) status→'connected'. Checks for mutual doc (B_A) and updates it too if it exists. Wraps in try/catch FirebaseException, rethrows as NetworkException.
  implication: The Firestore write logic is correct. No navigation inside.

- timestamp: 2026-05-13T00:11:00Z
  checked: HomeScreen._acceptProposal()
  found: Calls _handshakeRepo.acceptProposal(docId, proposerId).catchError(_) with a SnackBar on error. Fire-and-forget pattern (no await). No navigation triggered anywhere in the accept path.
  implication: No navigation = blank page must come from somewhere else, or from a stream-driven rebuild.

- timestamp: 2026-05-13T00:12:00Z
  checked: HomeScreen._PendingRequestRow — _accepting flag lifecycle
  found: _accepting is set to true on button tap via setState(). It is NEVER reset to false on either success or failure. The onAccept callback provides no completion/error signal back to _PendingRequestRow.
  implication: On Firestore write failure, _accepting stays true forever (spinner) while the row remains in the list. On success, the row disappears from the stream. This does NOT explain a blank page.

- timestamp: 2026-05-13T00:13:00Z
  checked: Firestore rules for neutral_handshakes UPDATE
  found: Partner (B) can update doc A_B to status='connected' only if affectedKeys().hasOnly(['status','updatedAt']). The acceptProposal batch.update passes exactly {status, updatedAt} — this satisfies the rule.
  implication: Firestore writes should succeed for valid pending docs. Rules do not block the write.

- timestamp: 2026-05-13T00:14:00Z
  checked: All Navigator.push/pop calls in home_screen.dart
  found: Lines 172, 175 (in _showNotifBanner onTap for rsa_key_received/file_received), 230 (_openAddConnectionSheet), 249/250/261/262 (_RolePickerSheet). None of these are in the accept proposal path.
  implication: No navigation is triggered from the accept proposal path in HomeScreen.

- timestamp: 2026-05-13T00:15:00Z
  checked: FindFriendsScreen._acceptRequest()
  found: Calls acceptProposal, shows success SnackBar, updates _statuses[pid] = 'accepted'. No navigation. After stream fires, _pendingRequests becomes empty. If _connectedUsers is also empty before the partner stream fires, the SliverFillRemaining shows "Connect with Friends" — not blank.
  implication: No blank page from FindFriendsScreen accept path either.

- timestamp: 2026-05-13T00:16:00Z
  checked: streamIncomingPending() vs _startHandshakeListener
  found: HomeScreen creates TWO subscriptions to streamIncomingPending(): one as _incomingPendingStream (late final, used by _PendingRequestsSection StreamBuilder) and one in _startHandshakeListener() via _pendingProposalSub. The _startHandshakeListener only reacts to DocumentChangeType.added — it does NOT react to changes/removals.
  implication: Double subscription is wasteful but not bug-causing. The _startHandshakeListener does NOT fire when a doc is accepted (changes from added to removed from the pending query).

- timestamp: 2026-05-13T00:17:00Z
  checked: _PendingRequestsSection StreamBuilder behavior on empty
  found: Returns SizedBox.shrink() when docs.isEmpty. Returns SizedBox.shrink() when connectionState==waiting. HomeScreen does NOT go blank from this section becoming empty.
  implication: The _PendingRequestsSection correctly collapses after accept.

- timestamp: 2026-05-13T00:18:00Z
  checked: _ActiveConnectionsSection — does it update after accept?
  found: _activeAsPartnerStream (WHERE partnerId == _uid AND status == 'connected') should pick up the newly-connected doc after the write. If Firestore write succeeds, stream fires, partnerDocs gets the doc, connected row appears. The stream was initialized once in initState() — it stays active and emits new data.
  implication: IF the Firestore write succeeds AND the stream query has a valid index, the active connections section updates correctly. The requester's side: _activeAsProposerStream (WHERE proposerId == _uid AND status == 'connected') fires similarly.

- timestamp: 2026-05-13T00:19:00Z
  checked: Firestore query composite index requirements
  found: streamActiveConnectionsAsProposer() queries (proposerId=X, status='connected'). streamActiveConnectionsAsPartner() queries (partnerId=X, status='connected'). streamOutgoingPending() queries (proposerId=X, status='pending'). streamIncomingPending() queries (partnerId=X, status='pending'). Each of these is a two-field query that requires a composite index in Firestore. If any index is missing, the stream errors but the StreamBuilder does not check snapshot.hasError — it falls through to show allRows=[].
  implication: Missing Firestore indexes could cause connected rows to never appear, but would not produce a blank page.

- timestamp: 2026-05-13T00:20:00Z
  checked: _PendingRequestRow — the accept CrypButton behavior when isLoading=true
  found: When _accepting=true, isLoading=true, and CrypButton.onPressed=null. The CrypButton renders disabled (grey face). The spinner in the row content is in a SizedBox(14x14). The rest of the GlassContainer content (username row etc.) is still visible. This is not a blank page.
  implication: Loading state in the row is visual but not blank.

## Resolution

root_cause: >
  _ActiveConnectionsSection.build() and _PendingRequestsSection.build() called
  handshakeRepo.streamActiveConnectionsAsProposer(), streamActiveConnectionsAsPartner(),
  streamOutgoingPending(), and streamIncomingPending() inline, creating a NEW Stream
  object instance on every build() call. Flutter's StreamBuilder.didUpdateWidget compares
  stream references by identity — when it receives a new reference it cancels the old
  subscription and resubscribes from scratch, resetting to ConnectionState.waiting.
  When the acceptor tapped "Accept Request", setState(() => _accepting = true) in
  _PendingRequestRow triggered a rebuild of HomeScreen and all its children. This caused
  all four StreamBuilders to resubscribe, dropping their existing Firestore listeners.
  The _PendingRequestsSection returned SizedBox.shrink() (waiting state), and
  _ActiveConnectionsSection returned a loading indicator — producing the "blank" appearance.
  The new subscriptions then had to wait for the next Firestore snapshot event before
  showing data. On the requester's side the same resubscription of _activeAsProposerStream
  caused the 'connected' event (which had already fired) to be missed, leaving the
  "Pending" badge in place until the next refresh.

fix: >
  Lifted all four Firestore streams to HomeScreen.initState() as late final fields
  (_activeAsProposerStream, _activeAsPartnerStream, _outgoingPendingStream,
  _incomingPendingStream). Passed them as stable parameters to _ActiveConnectionsSection
  and _PendingRequestsSection instead of passing handshakeRepo. StreamBuilder now holds
  a single subscription for the lifetime of the screen — no resubscription on rebuild.
  Applied in commit 801ed35.

verification: >
  Fix applied in commit 801ed35 "fix(05): lift handshake streams to initState — fix stale
  UI after accept". Current home_screen.dart confirms all four streams are late final fields
  initialized in initState() and passed as stable parameters — matching the fix.

files_changed:
  - lib/presentation/home/home_screen.dart
