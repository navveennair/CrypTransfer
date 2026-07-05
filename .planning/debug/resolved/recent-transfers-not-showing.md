---
slug: recent-transfers-not-showing
status: resolved
trigger: "transfers were done between two devices . check why isnt it showing up at recent transfers"
created: "2026-06-22"
updated: "2026-07-02"
---

# Debug Session: recent-transfers-not-showing

## Symptoms

- **Expected:** After a file transfer completes end-to-end between two physical devices, both the sender and the receiver should see the transfer listed in their "recent transfers" history.
- **Actual:** The completed transfer does not appear at all in "recent transfers" on either device.
- **Errors:** None observed. Completely silent — no console errors, no crash, no visible Firestore permission-denied or other error on either device.
- **Repro:** Normal full transfer between two physical devices, completed end-to-end with no interruption (sender sent, receiver received and decrypted successfully). Afterward, recent transfers list is empty on both sides.
- **Timeline:** Regression — this worked before and broke recently.

## Current Focus

reasoning_checkpoint:
  hypothesis: "Recent Transfers list reads from users/{uid}/audit_logs, but that audit log document is only written inside ReceiverEndSessionScreen._runFinalCleanup() Step 0 (writeFinalAuditLog), which only executes after the receiver explicitly taps the 'End Session' button on the post-decrypt summary screen. The screen is poppable (canPop: _phase == _Phase.ready) before that tap, so a user who finishes decrypting/saving the file and simply navigates back/away (without tapping 'End Session') leaves with zero audit log entries for either sender or receiver — explaining silent, errorless absence on both devices."
  confirming_evidence:
    - "TransferRepository.streamRecentTransfers() / streamAllTransfers() query users/{userId}/audit_logs ordered by loggedAt — the ONLY write path into that collection for a normal completed transfer is writeFinalAuditLog (transfer_repository.dart:203), called exactly once, from receiver_end_session_screen.dart:212."
    - "writeFinalAuditLog is invoked inside _runFinalCleanup, which only runs after the receiver taps 'End Session' (_initiateCleanup, triggered by CrypButton onPressed at line 471) — there is no automatic trigger on decrypt/save completion."
    - "ReceiverEndSessionScreen.build() sets PopScope(canPop: _phase == _Phase.ready) — while phase is 'ready' (i.e. before the user taps End Session) the screen can be backed out of/abandoned with no audit log side effect and no error."
    - "Sender side never writes a completion audit log itself — there is no sender-side EndSessionScreen; SenderTransferScreen only writes writeConnectionLostAuditLog on abort paths, confirming the only 'completed' record for either party comes from the receiver's single batched write."
    - "CleanupRepository.completeReceiverCleanup() — a second, unused, dead code path — also writes the same audit schema but is never called anywhere (grep confirms zero call sites), ruling it out as a relevant alternate path."
    - "Firestore security rules for users/{userId}/audit_logs allow create for any authenticated participant named as senderId/receiverId in the document — rules are not blocking the write; this is a flow/reachability issue, not a permissions issue (consistent with 'no errors observed')."
  falsification_test: "If the receiver explicitly completes the full End Session flow (taps 'End Session' button and either the sender confirms within 120s or the 120s safety timeout fires), writeFinalAuditLog WILL run and a doc will appear under both users/{senderId}/audit_logs and users/{receiverId}/audit_logs with status:'completed' — Recent Transfers would then show the entry. If it still does NOT show up after a full explicit End Session run, this hypothesis is wrong and the bug is in the write/query path itself (schema mismatch, rule rejection swallowed by try/catch, or query field name drift), not in flow-reachability."
  fix_rationale: "Root cause is a UX/reachability gap, not a logic bug in the write or read path. The minimal correct fix is to make the audit log unconditional on reaching this screen (write it automatically once, before the optional/destructive End Session cleanup proceeds), rather than gating the user's entire transfer history on them choosing to run an irreversible, scary-sounding 'Permanent Deletion' cleanup action. This preserves D-03's ordering intent (audit before deletion) while decoupling 'record that a transfer happened' from 'user opted into wiping local artifacts now'."
  blind_spots: "Have not run the app on two physical devices to directly observe whether testers actually skip End Session (no telemetry/analytics on screen abandonment) — this is inferred from code reachability, not directly observed user behavior. Have not checked SenderSessionEndScreen (timeout path) to see if it has its own independent audit-log gap. Have not yet checked whether sender ever reaches a screen that confirms completion without depending on the receiver's batch write."
next_action: "Read sender_session_end_screen.dart to check the timeout/abort-side completion path, then design minimal fix: write completion audit log earlier/unconditionally in the receiver completion flow."

## Evidence

- timestamp: "2026-06-22T00:00:00Z"
  checked: "transfer_repository.dart streamRecentTransfers/streamAllTransfers"
  found: "Both query users/{userId}/audit_logs ordered by loggedAt desc — Recent Transfers UI is 100% dependent on documents existing in this sub-collection."
  implication: "If no audit_logs doc is ever written for a transfer, it can never appear in Recent Transfers regardless of transfer doc state."

- timestamp: "2026-06-22T00:00:00Z"
  checked: "All call sites of writeFinalAuditLog, writeAuditLog, writeAbortAuditLog, writeConnectionLostAuditLog, CleanupRepository.completeReceiverCleanup"
  found: "writeFinalAuditLog (the 'completed' status writer) has exactly one call site: receiver_end_session_screen.dart:212, inside _runFinalCleanup, itself only reachable via _initiateCleanup which is only invoked by the 'End Session' CrypButton onPressed handler. completeReceiverCleanup in cleanup_repository.dart duplicates this logic but has zero call sites (dead code)."
  implication: "There is no automatic/implicit path to a 'completed' audit log — it strictly requires explicit, manual receiver action on a screen the user can back out of."

- timestamp: "2026-06-22T00:00:00Z"
  checked: "receiver_end_session_screen.dart PopScope and AppBar config"
  found: "PopScope(canPop: _phase == _Phase.ready) — screen is poppable via system back button while in the initial 'ready' phase (i.e. before End Session is tapped), with automaticallyImplyLeading also true at that phase."
  implication: "User can navigate away after a successful decrypt+save without ever triggering the audit log write, with zero error/log output — exactly matching the silent symptom."

- timestamp: "2026-06-22T00:00:00Z"
  checked: "firestore.rules audit_logs match block"
  found: "allow create: if isAuthenticated() && (request.resource.data.senderId == request.auth.uid || request.resource.data.receiverId == request.auth.uid) — receiver is authenticated and named, so the batch write in writeFinalAuditLog would succeed if it executed. Rules are not the blocker."
  implication: "Confirms this is a reachability/flow gap, not a permission-denied-swallowed-silently issue."

- timestamp: "2026-06-22T00:00:00Z"
  checked: "sender_transfer_screen.dart Turn 2/Turn 4 listener logic and receiver's 120s _senderWaitTimeout"
  found: "Even if the sender never cooperates (app closed, no senderCleanedUp), the receiver's own 120s Timer in _initiateCleanup unconditionally calls _runFinalCleanup() once it fires, which still executes Step 0 (writeFinalAuditLog) first. Sender unresponsiveness does not block the audit log write once the receiver has tapped End Session."
  implication: "The single point of failure is upstream of all this synchronization: the receiver must tap 'End Session' at all. Everything downstream of that tap is self-healing within 120s."

## Eliminated Hypotheses

- hypothesis: "Firestore security rules silently reject the audit_logs write (permission-denied swallowed by try/catch)."
  evidence: "Rules explicitly allow create for any authenticated user named as senderId or receiverId in the written document; writeFinalAuditLog's batch sets exactly that shape for both users. No swallowing try/catch wraps this call in _runFinalCleanup — an exception here would surface via the existing catch block and set _error, which is visible to the user (not silent)."
  timestamp: "2026-06-22T00:00:00Z"

- hypothesis: "Field name / schema drift between writer and the streamRecentTransfers query (e.g. collection name mismatch 'audit_logs' vs 'auditLogs')."
  evidence: "FirebaseConstants.auditLogs = 'audit_logs' is used consistently by both the writer (transfer_repository.dart, cleanup_repository.dart) and the reader (streamRecentTransfers, streamAllTransfers, admin_repository collectionGroup query) — same constant, same string value, no drift found."
  timestamp: "2026-06-22T00:00:00Z"

## Resolution

root_cause: "Recent Transfers is driven exclusively by users/{uid}/audit_logs documents, which are written by exactly one code path: TransferRepository.writeFinalAuditLog(), called only from ReceiverEndSessionScreen._runFinalCleanup() — itself only reachable after the receiver explicitly taps the 'End Session' button. The screen's PopScope allows the user to navigate away during the initial 'ready' phase (immediately after a successful decrypt+save) without ever tapping that button, silently skipping the audit log write entirely for both sender and receiver. No error occurs because nothing fails — the write simply never runs."
fix: "Extracted writeFinalAuditLog call into idempotent _writeAuditLogOnce(), guarded by _auditLogWritten flag. Called eagerly (best-effort, errors swallowed) from initState() so the record is written as soon as the session-summary screen loads, decoupled from the 'End Session' button. _runFinalCleanup()'s Step 0 now calls the same guarded method — if the eager write already succeeded it's a no-op; if it failed (e.g. no network on load), it retries here and a failure still surfaces via the existing try/catch (_error + phase reset), preserving D-03's audit-before-deletion guarantee for the explicit cleanup path."
verification: "flutter analyze on the modified file: no issues found. Manual two-device retest not yet performed by user — recommend confirming a transfer now appears in Recent Transfers immediately after decrypt+save, even without tapping End Session."
files_changed:
  - lib/presentation/receiver/receiver_end_session_screen.dart
