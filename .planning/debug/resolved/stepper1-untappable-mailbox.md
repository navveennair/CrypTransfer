---
status: resolved
trigger: "check why once when sender and receiver is connected , why is stepper 1 ignored , with stepper 2 turned on under receive mode and waiting for sender handshake ? By right the 1st stepper should be tapped but it is untappable , skips to receive mode turned on without generating RSA Keypair"
created: 2026-07-02T00:00:00Z
updated: 2026-07-02T00:00:00Z
---

## Current Focus

reasoning_checkpoint:
  hypothesis: "ReceiverScreen._loadReadyToReceiveState() sets _isReadyToReceive purely from Firestore's isReadyToReceive field, independent of whether local RSA keys actually exist on this device. When that flag is true but local keys are absent (multi-device use of the same account, app reinstall, OS secure-storage clear, or any other path that loses local key material without also flipping the Firestore flag), Step 1's card becomes permanently untappable because IgnorePointer(ignoring: _isReadyToReceive) at receiver_screen.dart:828-829 gates purely on the (stale) ready flag, not on _step1Done. Compounding this, the Step 2 Switch's onChanged guard (`_step1Done && !_isTogglingReady ? _onToggleReady : null`, line 619) also evaluates to null in this state (since _step1Done is false), so the user cannot even toggle Step 2 off to escape — it is a complete dead-end requiring app restart or manual Firestore edit."
  confirming_evidence:
    - "receiver_screen.dart:825-836 — IgnorePointer's `ignoring` param is `_isReadyToReceive` alone, with no `_step1Done` term, directly observed by reading the widget tree."
    - "receiver_screen.dart:617-621 — Switch onChanged is `_step1Done && !_isTogglingReady ? _onToggleReady : null`; when _step1Done is false this is null regardless of _isReadyToReceive, so the user has no UI escape hatch to turn Step 2 off either."
    - "receiver_screen.dart:218-236 — _loadReadyToReceiveState() awaits _authService.getIsReadyToReceive(uid) and sets _isReadyToReceive directly with no cross-check against _checkKeyStatus()/hasKeyPair(); the two initState calls (_checkKeyStatus() and _loadReadyToReceiveState()) run concurrently and never reconcile."
    - "Ruled out KeyRepository.clearStaleKeys() (key_repository.dart:822-847) as the trigger: it only wipes the local private key when scan.hasStaleRsaSession is true, and hasStaleRsaSession requires `!isReady` (key_repository.dart:774-775) — so the Clear Cache vault feature cannot produce the isReady=true + no-local-key combination; it structurally only fires when isReady is already false."
    - "Ruled out RsaKeyManagerScreen._onDelete()/AuthRepository.deleteKeyPair() as the direct trigger via the normal in-app path: the gear icon that opens RsaKeyManagerScreen is itself disabled while _isReadyToReceive is true (`onPressed: _isReadyToReceive ? null : _openKeyManager`, line 772), so a user cannot delete keys through the vault screen while the mailbox shows ready. The desync must originate from something outside this screen's control (different device sharing the same Firestore user doc, reinstall, OS-level secure-storage clear, or a killed app that never ran the setReadyToReceive(false) close path) — but the exact external trigger doesn't change the fix: the UI must not trust _isReadyToReceive blindly."
  falsification_test: "If IgnorePointer's condition were changed to also require _step1Done and the bug persisted (Step 1 still untappable when local keys are missing), the hypothesis would be refuted. Reading the code confirms _step1Done is a plain getter (_hasPrivateKey && _hasPublicKey, line 77) computed independently of _isReadyToReceive, so gating on it is sufficient and directly falsifiable by inspection — no other guard intercepts Step 1's GestureDetector/IgnorePointer."
  fix_rationale: "Rather than only patching the IgnorePointer/Switch gating (symptom-level), reconcile state at the source in _loadReadyToReceiveState(): when Firestore reports isReadyToReceive=true, verify local keys actually exist via _authService.hasKeyPair(). If they don't, treat the session as not-ready locally (_isReadyToReceive=false) and asynchronously correct the Firestore flag via setReadyToReceive(false) so future loads (this device or others) and any sender relying on that flag see accurate state. This addresses the root cause — untrusted/unreconciled remote state — rather than just unlocking the UI while leaving Firestore permanently wrong."
  blind_spots: "Have not reproduced this end-to-end on a device/emulator (no test harness invoked); relying on static code reading, not a running repro. Have not identified the exact real-world action that first produces the isReady=true/no-local-key combination (candidates: multi-device same account, reinstall, OS secure-storage clear, or app killed before _onToggleReady(false) runs) — the fix is deliberately trigger-agnostic so this is an acceptable blind spot. Have not checked SenderScreen for any assumption that isReadyToReceive implies a valid decryptable public key that this fix might affect (setReadyToReceive(false) here doesn't touch the Firestore publicKey field, so any sender mid-transfer would only stop seeing this receiver as 'ready', not lose its public key)."
next_action: "awaiting human verification: reproduce the original stuck state on a real device (or simulate isReadyToReceive=true with no local key) and confirm Step 1 becomes tappable and Step 2 shows OFF on ReceiverScreen open."

## Symptoms

expected: "Step 1 (RSA Keypair) should be tappable/reachable so the user can generate an RSA keypair before Receive Mode (Step 2) is usable. Step 2 should not be ON, and mailbox should not be waiting for a sender handshake, until Step 1 is actually done."
actual: "On opening the Receiver screen, Step 2 (Receive Mode) is already ON and waiting for sender handshake, while Step 1 shows 'No RSA keys found' (not-done state) — but Step 1 is untappable/unresponsive, so the user cannot generate keys. The flow skips straight to receive mode without ever generating an RSA keypair."
errors: "None reported by user (no visible crash/snackbar)."
timeline: "Not clarified precisely by user; keys were generated on this device in a previous session (not a fresh install)."
reproduction: "User answered: open the Receive screen fresh — Step 2 is already ON without the user manually toggling it. Device previously had RSA keys generated in an earlier session."

Additional orchestrator-gathered context (via AskUserQuestion):
- Step 1 visual state confirmed as "Shows 'No RSA keys found' but can't tap it" (not the done/green state) — rules out the simpler explanation that keys silently exist and are just hidden.
- Device had previously generated keys in an earlier session (not fresh install) — points at a wipe/reset path (e.g. recent KeyRepository.clearStaleKeys() / ClearCacheSheet vault feature per recent commits "feat(vault): add ClearCacheSheet scan/confirm/clear UI" and "feat(vault): add KeyRepository.clearStaleKeys()") that may have removed local keys without resetting server-side ready state.
- Reproduction confirmed as: opening the Receive screen fresh already shows Step 2 ON — the user did NOT manually flip the Step 2 switch this session.

## Related code (from prior investigation this session)

- lib/presentation/receiver/receiver_screen.dart:77-80 — `_step1Done => _hasPrivateKey && _hasPublicKey`; `_step2Done => _isReadyToReceive`.
- lib/presentation/receiver/receiver_screen.dart:218-236 — `_loadReadyToReceiveState()` reads `getIsReadyToReceive(uid)` from Firestore/backend on initState and sets `_isReadyToReceive` directly, independent of local key status.
- lib/presentation/receiver/receiver_screen.dart:825-836 — Step 1 card wrapped in `AnimatedOpacity(opacity: _isReadyToReceive ? 0.4 : 1.0)` + `IgnorePointer(ignoring: _isReadyToReceive)` — gated purely on `_isReadyToReceive`, not on `_step1Done`.
- lib/presentation/receiver/receiver_screen.dart:617-621 — Step 2 switch `onChanged: _step1Done && !_isTogglingReady ? _onToggleReady : null` — this guard only blocks *manual* toggling; it does not protect against `_isReadyToReceive` already being true from persisted/stale state on load.
- Related but distinct, already-resolved session: .planning/debug/stepper3-prefill-sender-not-recognized.md (prefill-before-mailbox-open ordering bug — fixed via `_pendingPrefilledSender` deferred pattern, visible in current code at receiver_screen.dart:279-284).
- Recent relevant commits (git log): "chore(cleanup): remove dead service files and add missing transferLogs constant", "feat(vault): wire Clear Cache into sidebar", "feat(vault): add ClearCacheSheet scan/confirm/clear UI", "feat(vault): add KeyRepository.clearStaleKeys()" — new key-wipe feature landed recently, plausible source of the desync.

## Eliminated

- hypothesis: "KeyRepository.clearStaleKeys() / ClearCacheSheet vault feature wipes local keys while leaving Firestore isReadyToReceive=true, causing the desync."
  evidence: "key_repository.dart:774-775 — scanForStaleKeys() computes hasStaleRsaSession = !isReady && (hasFirestorePublicKey || hasLocalPrivateKey). clearStaleKeys() (line 822-847) only deletes the local private key / Firestore publicKey when scan.hasStaleRsaSession is true. Since hasStaleRsaSession structurally requires isReady to already be false, this feature cannot produce the isReady=true + no-local-key combination the bug requires."
  timestamp: 2026-07-02T00:10:00Z

- hypothesis: "RsaKeyManagerScreen._onDelete() / AuthRepository.deleteKeyPair() is reached while the mailbox is still 'ready', wiping local keys without resetting isReadyToReceive."
  evidence: "receiver_screen.dart:772 — the gear IconButton that opens RsaKeyManagerScreen has onPressed: _isReadyToReceive ? null : _openKeyManager, so it is disabled whenever _isReadyToReceive is true. The normal in-app path to delete/regenerate keys is unreachable while the mailbox shows ready, so this is not the direct trigger via UI navigation (though deleteKeyPair() itself still doesn't touch isReadyToReceive, confirming the same class of bug exists there defensively)."
  timestamp: 2026-07-02T00:12:00Z

## Evidence

- timestamp: 2026-07-02T00:05:00Z
  checked: "lib/presentation/receiver/receiver_screen.dart full file (initState, _checkKeyStatus, _loadReadyToReceiveState, _onToggleReady, step widgets, build)"
  found: "_checkKeyStatus() (sets _hasPrivateKey/_hasPublicKey from local secure storage + Firestore publicKey) and _loadReadyToReceiveState() (sets _isReadyToReceive from Firestore isReadyToReceive) are both fired from initState() independently and never cross-reconciled. Step 1's IgnorePointer (line 828-829) gates only on _isReadyToReceive. Step 2's Switch onChanged (line 619) gates only on _step1Done, with no allowance for turning OFF an already-'ready' session when _step1Done is false — a hard dead end when the two flags disagree in this specific direction (ready=true, step1=false)."
  implication: "Confirms the exact untappable-Step-1 mechanism described in the hypothesis; the bug is a pure UI/state-trust issue, not a Firestore rules or auth issue."

- timestamp: 2026-07-02T00:10:00Z
  checked: "lib/data/repositories/key_repository.dart (scanForStaleKeys, clearStaleKeys, setReadyToReceive, wipeAllSessionKeys)"
  found: "setReadyToReceive(bool) is a thin Firestore update of isReadyToReceive/readySince — nothing local. clearStaleKeys() only fires the local-key wipe when the scan already found isReady=false, so it cannot itself create the desync. No call site in this file calls setReadyToReceive(false) as a side effect of a local-key wipe when isReady was true beforehand."
  implication: "Eliminates the vault Clear Cache feature as the direct cause; the desync's real-world trigger is external to normal in-app flows (multi-device same account, reinstall, OS-level secure-storage clear, or an app kill that skips the _onToggleReady(false) close path) — but the fix must be trigger-agnostic reconciliation, not a patch to one specific wipe path."

- timestamp: 2026-07-02T00:12:00Z
  checked: "lib/presentation/vault/rsa_key_manager_screen.dart (_onDelete, _onRegenerate) and lib/data/repositories/auth_repository.dart (deleteKeyPair, regenerateKeyPair)"
  found: "Both deleteKeyPair() and regenerateKeyPair() touch only the private key (secure storage) and Firestore publicKey field — neither touches isReadyToReceive. However RsaKeyManagerScreen is only reachable via the ReceiverScreen gear icon which is disabled while _isReadyToReceive is true, so this path cannot be reached in the exact stuck state from within the app's own navigation."
  implication: "Confirms deleteKeyPair()/regenerateKeyPair() are not missing a reset call for any reachable path in this app version, but also confirms nothing anywhere in the codebase treats isReadyToReceive as needing to imply local key presence — supporting a reconciliation fix in ReceiverScreen itself as the correct root-cause-level fix rather than chasing one specific wipe call site."

## Resolution

root_cause: "ReceiverScreen trusts Firestore's isReadyToReceive flag unconditionally for driving Step 2 state and for gating Step 1's tappability, with no reconciliation against whether local RSA keys actually exist on this device (_step1Done). When isReadyToReceive is true in Firestore but local keys are missing on this device/session (external trigger — multi-device same account, reinstall, OS secure-storage clear, or a killed app that skipped the setReadyToReceive(false) close path — is plausible but not required to fix the bug), Step 1's IgnorePointer(ignoring: _isReadyToReceive) permanently blocks the 'No RSA keys found — tap to generate' card, and Step 2's Switch onChanged (gated on _step1Done) is also null, leaving the user with no way to regenerate keys or close the stale session from the UI."
fix: "In receiver_screen.dart _loadReadyToReceiveState(), after reading isReadyToReceive from Firestore, if it is true, verify local key presence via _authService.hasKeyPair(). If no local key exists, treat the session as not-ready locally (do not set _isReadyToReceive=true) and asynchronously call _connService.setReadyToReceive(false) to correct the stale Firestore flag. This unlocks Step 1 (IgnorePointer now sees _isReadyToReceive=false) and self-heals the backend flag for this and any other device reading the same user doc."
verification: "flutter analyze lib/presentation/receiver/receiver_screen.dart — No issues found. flutter test test/vault/receiver_banner_test.dart test/handshake/receiver_prefill_test.dart test/vault/key_lifecycle_test.dart — all pass (test/key_repository/clear_cache_test.dart fails to compile on a pre-existing, unrelated FirebaseConstants.handshakes reference — confirmed via git diff --stat that only receiver_screen.dart was touched by this fix, so this failure predates and is unrelated to the change). Logic re-derivation: with the fix, when isReadyToReceive=true and hasKeyPair()=false, _isReadyToReceive is set to false, so IgnorePointer(ignoring: _isReadyToReceive) evaluates to false (Step 1 tappable) and the Step 2 switch correctly renders OFF; when isReadyToReceive=true and hasKeyPair()=true (the normal legitimate case), effectiveReady stays true and behavior is unchanged. Self-verified by code inspection; end-to-end device/emulator verification requires the user's real environment (see checkpoint)."
files_changed:
  - "lib/presentation/receiver/receiver_screen.dart"
