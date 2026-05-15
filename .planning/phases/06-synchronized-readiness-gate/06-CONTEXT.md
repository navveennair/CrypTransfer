# Phase 6: Synchronized Readiness Gate - Context

**Gathered:** 2026-05-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Ensure the Sender cannot encrypt or pick files until the Receiver has prepared their cryptographic environment. Bridges the Neutral Handshake model (Phase 5) to the Transfer flow with a bidirectional readiness protocol. Covers: the readiness signal mechanism, sender-side gate UI, receiver-side trigger, and a 1-minute safety timer that ejects the sender if the session collapses while waiting.

The existing Zero Remanence session flow (SenderScreen → TransferProgressScreen; ReceiverScreen → ReceiverTransferScreen) is UNCHANGED after receiverReady gates open. Phase 6 adds the readiness layer on top; it does not alter in-session crypto or cleanup logic.

</domain>

<decisions>
## Implementation Decisions

### Readiness Signal Location
- **D-01:** `receiverReady` is added as a boolean field to the **RSA handshake doc** in the existing `handshakes/` Firestore collection (the same doc that carries `publicKey`, `receiverId`, `status: 'handshake_complete'`, etc.). This doc is already streamed by the sender via `KeyRepository.streamHandshakesForSender()`. No new collection or document type is required.
- **D-02:** `receiverReady` is initialized to `false` when the handshake doc is created. The receiver updates it to `true` after completing Step 3.
- **D-03:** The ROADMAP-specified `senderReady` field is Claude's discretion — it can be added symmetrically to the handshake doc for completeness, but Phase 6 defines no receiver behavior based on it. The planner may omit it if there is no use case within this phase's scope.

### Sender-Side Gate UI
- **D-04:** While `receiverReady == false`, Steps 1–4 in `SenderScreen` are **hidden** (not shown at all — not just greyed out). Step 0 card expands to show the pulsing `_WaitingForConnectionWidget`-style UI with text "Waiting for Receiver to prepare secure vault…" and a **visible countdown timer** ("MM:SS remaining").
- **D-05:** The countdown timer updates every second. Duration: 1 minute (60 seconds), as specified in ROADMAP scope item 4.
- **D-06:** When `receiverReady` becomes `true`: cancel the countdown timer, show a green SnackBar "Secure channel established. Receiver is ready.", and fade in Steps 1–4 via `AnimatedOpacity` (duration: 300 ms, consistent with existing step card pattern).

### Receiver-Side Trigger
- **D-07:** The receiver sets `receiverReady: true` on the handshake doc inside `ReceiverScreen._onSenderSelected()`, **after** `_connService.selectSenderHandshake()` completes successfully (i.e., after the setState call that sets `_handshakeDone = true`). This ensures the field is only written when Firestore confirms the handshake WriteBatch — not speculatively on sender selection.
- **D-08:** If the `receiverReady` write fails (Firestore error), the error is surfaced to the receiver via SnackBar; the receiver can retry by re-triggering the handshake.

### Safety Timer — Session Collapse
- **D-09:** If the handshake doc is **deleted** or its `status` changes to `rejected` while the sender is in the waiting state (before `receiverReady == true`), the 1-minute timer fires immediately (does not wait for expiry). The sender sees a red SnackBar "Session Terminated — receiver closed the session" and is navigated to HomeScreen via `Navigator.pushAndRemoveUntil`.
- **D-10:** If the timer expires naturally (60 seconds) before `receiverReady` is set, the same red SnackBar + HomeScreen navigation fires.
- **D-11:** Timer is cancelled and dismissed if `receiverReady` becomes `true` before expiry (session proceeds normally).

### Claude's Discretion
- Countdown display format (e.g., "00:45" vs "45 seconds remaining" vs "1:00").
- Whether the timer widget is integrated into the `_WaitingForConnectionWidget`-style container or shown separately below it.
- Animation curve and duration for the countdown opacity/fade.
- Exact Dart Timer implementation (periodic vs. countdown to a `DateTime`).
- Whether `senderReady` field is added to the handshake doc (symmetric bookkeeping only — not functionally required by Phase 6 scope).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Sender-side gate integration point
- `lib/presentation/sender/sender_screen.dart` — SenderScreen with `_onHandshakeUpdate`, `_WaitingForConnectionWidget`, `_ConnectedBadge`, and Steps 0–4 structure; the gate logic and waiting UI replace/extend Step 0 content
- `lib/data/repositories/key_repository.dart` — `streamHandshakesForSender()` (the existing stream the sender already listens to); `selectSenderHandshake()` (WriteBatch for RSA handshake doc + user doc)

### Receiver-side trigger integration point
- `lib/presentation/receiver/receiver_screen.dart` — `_onSenderSelected()` (location where `receiverReady: true` write is added, after `selectSenderHandshake()` returns)

### Handshake data model
- `lib/core/constants/firebase_constants.dart` — collection name constants (the RSA handshakes collection, `neutral_handshakes`, etc.)
- `lib/data/models/transfer_model.dart` — current TransferModel (for reference; Phase 6 does not add fields here — `receiverReady` goes on the handshake doc instead)

### Prior phase context
- `.planning/phases/05-neutral-handshake-model/05-CONTEXT.md` — Phase 5 decisions: session pre-fill (D-13/D-14), role picker, `preFilledPartnerUid`/`preFilledSenderUid` params; Phase 6 builds on top of this connection model

### Firestore rules
- `firestore.rules` — handshakes collection rules may need an update to allow the receiver to write `receiverReady: true` (if the current rules restrict updates to the handshake doc creator only)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `_WaitingForConnectionWidget` (`sender_screen.dart`) — pulsing `ScaleTransition` + `FadeTransition` + icon + text; extend or adapt for the "Waiting for receiver" gate state in Step 0
- `AnimatedOpacity` pattern — already used for Steps 1–4 to fade between enabled/disabled; use same pattern to hide/show steps based on `receiverReady`
- `AnimatedSwitcher` — used in SenderScreen Step 4 send button; can be used to switch between waiting UI and normal steps
- `streamHandshakesForSender()` → `_onHandshakeUpdate()` in SenderScreen — already processes the handshake doc snapshot; `receiverReady` field can be parsed in the same handler
- `_onSenderSelected()` in ReceiverScreen — location for the `receiverReady: true` write; already has `try/catch/setState` error handling pattern

### Established Patterns
- `StreamBuilder` on Firestore snapshots — used throughout for reactive UI; sender's readiness gate should use the existing `_handshakeSub` stream (not a new subscription)
- `setState` + `AnimatedOpacity` — the established way to show/hide step cards; use opacity + `IgnorePointer` or conditional render to hide steps 1–4
- `ScaffoldMessenger.of(context).showSnackBar()` — established pattern for SnackBar feedback
- `Navigator.pushAndRemoveUntil` — established pattern for HomeScreen ejection (used in Phase 4)
- `Timer.periodic` or `Timer` — standard Dart timer for countdown; cancel in `dispose()` and on receiverReady event

### Integration Points
- `_onHandshakeUpdate` in `SenderScreen` — already called whenever the handshake doc changes; add parsing of `receiverReady` field here to gate/unlock the UI
- `_onSenderSelected` in `ReceiverScreen` — add the `receiverReady: true` write immediately after `selectSenderHandshake()` succeeds, before the final `setState`
- `KeyRepository` — needs a new method (e.g., `setReceiverReady(handshakeDocId)`) or `selectSenderHandshake()` extended to include `receiverReady: true` in the WriteBatch

</code_context>

<specifics>
## Specific Ideas

- The countdown timer should be **visible inside the Step 0 waiting card** — not floating outside the step structure. This keeps the UI consistent with the existing step-card layout.
- When `receiverReady` fires and steps fade in, the sender should land at Step 1 (file pick) without needing to tap anything — the auto-advance is visual only (scroll/focus shift), not navigation.
- The Firestore security rules for the `handshakes/` collection may need a targeted update: the receiver needs write access to set `receiverReady` on a doc they did not create. This must be addressed in the same plan that writes the field.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 06-synchronized-readiness-gate*
*Context gathered: 2026-05-15*
