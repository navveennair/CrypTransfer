---
status: investigating
trigger: "Sender stepper 3 — 'Encrypt Key for @' button does not respond when clicked. Started after phase 07.1 layer decoupling refactor."
created: 2026-05-25T00:00:00Z
updated: 2026-05-25T00:00:00Z
symptoms_prefilled: true
---

hypothesis: MOST LIKELY ROOT CAUSE — Receiver's setReceiverReady() is failing or not being called, leaving receiverReady=false in Firestore. This causes sender's _receiverReady to stay false, and IgnorePointer(line 678) blocks all taps on steps 1-4, making button unresponsive.
test: Check if (a) receiver completes sender selection flow successfully, (b) setReceiverReady method is being called and not catching silent errors, (c) sender's Firestore listener updates _receiverReady when receiverReady field changes
expecting: Receiver should complete _onSenderSelected which calls selectSenderHandshake then _writeReceiverReady. If setReceiverReady fails, receiver should see snackbar with retry. When receiverReady becomes true in Firestore, sender's listener should fire and set _receiverReady=true, enabling steps 1-4.
next_action: Check if receiver's setReceiverReady is throwing an error that's being silently caught; verify Firestore security rules allow receiver update on handshakes doc; check sender's listener condition on line 177

## Symptoms

expected: Clicking "Encrypt Key for @receiver" button triggers encryption of AES key with receiver's RSA public key
actual: Button is visible but clicking has no effect — no loading state, no error toast, no navigation
errors: None visible
reproduction: Open SenderScreen, complete stepper 1-2, reach stepper 3, tap the "Encrypt Key for @receiver" button
started: After phase 07.1 layer decoupling refactor

## Eliminated

(none yet)

## Evidence

- timestamp: 2026-05-25T00:01:00Z
  checked: sender_screen.dart lines 746-762 (Step 3 UI)
  found: GlassButton with onPressed condition `_fileEncrypted && !_encryptingKey ? _encryptAesKey : null`. _encryptAesKey is a method defined on line 310-346.
  implication: Method exists and condition syntax is correct. _fileEncrypted getter returns `_encryptedBytes != null` (line 76). _encryptingKey is bool, initialized false (line 67).

- timestamp: 2026-05-25T00:02:00Z
  checked: _encryptAesKey method (lines 310-346) for early-return paths
  found: Line 318 checks if publicKeyJson is null and shows error. Line 325 returns early if biometric auth fails or widget not mounted without showing error. This is normal behavior.
  implication: If button is clicked and nothing happens with no error, likely cause is either (1) button is disabled due to condition, (2) IgnorePointer is blocking tap, or (3) biometric auth returns false silently.

- timestamp: 2026-05-25T00:03:00Z
  checked: git log for sender_screen.dart changes in phase 07.1
  found: Most recent change is e1fc258 "migrate sender_screen to use TransferRepository.generateId" — only affects _send() method (line 367), NOT the stepper 3 button or _encryptAesKey.
  implication: Phase 07.1 refactor did not directly change stepper 3 button logic.

- timestamp: 2026-05-25T00:04:00Z
  checked: sender_screen.dart lines 675-679 (Step gate structure)
  found: Steps 1-4 are inside IgnorePointer(ignoring: !_receiverReady, ...). This blocks ALL tap events on Steps 1-4 unless _receiverReady is true.
  implication: CRITICAL FINDING: Even if button condition is true and button is enabled, taps are ignored if _receiverReady=false. This is the most likely cause — receiver needs to call setReceiverReady to set the Firestore field to true.

- timestamp: 2026-05-25T00:05:00Z
  checked: key_repository.dart lines 445-507 (selectSenderHandshake method)
  found: Method explicitly sets `receiverReady: false` on line 490 as WR-01 fix. Then receiver calls setReceiverReady to set it to true. Phase 07.1 did not change these methods.
  implication: Receiver flow requires selectSenderHandshake followed by setReceiverReady. If setReceiverReady fails or isn't called, _receiverReady stays false and IgnorePointer blocks all taps.

- timestamp: 2026-05-25T00:06:00Z
  checked: firestore.rules handshakes update rule (lines 133-135)
  found: Update allowed if authenticated AND (receiverId == auth.uid OR senderId == auth.uid). Receiver is the receiverId of the handshakes doc, so they can update.
  implication: Security rules should allow receiver to call setReceiverReady successfully. No permission error should occur.

- timestamp: 2026-05-25T00:07:00Z
  checked: receiver_screen.dart _writeReceiverReady error handling (lines 403-422)
  found: If setReceiverReady throws ANY exception, a snackbar appears with retry option. If no snackbar appears, setReceiverReady succeeded.
  implication: If receiver is not seeing an error snackbar after selecting sender, the call succeeded and receiverReady should be true in Firestore.

- timestamp: 2026-05-25T00:08:00Z
  checked: sender_screen.dart _onReceiverBecameReady condition (line 177)
  found: `if (!_receiverReady && receiverReady)` — calls _onReceiverBecameReady only when local state is false AND remote value is true.
  implication: Condition requires both: (1) _receiverReady currently false, AND (2) received receiverReady true. Should work on any doc update where remote changes from false to true.

## Resolution

root_cause: Sender's IgnorePointer(ignoring: !_receiverReady) on line 678-679 blocks all taps on Steps 1-4 because _receiverReady is false. This happens when the receiver hasn't completed their sender selection flow (calling setReceiverReady), leaving the handshakes document with receiverReady=false. Phase 07.1 did not directly change the _receiverReady gate logic, but may have introduced a subtle issue in the receiver's flow: the only UI changes were replacing Firestore.instance calls with repository methods, which should be equivalent. The most likely scenario is that the receiver's sender selection works, but setReceiverReady fails silently or doesn't get called. Evidence: If setReceiverReady threw an error, receiver would see snackbar (lines 409-420), so if no snackbar is seen, the call succeeded. But then the sender's listener should fire and set _receiverReady=true (line 177 condition). Unless the listener fires while doc has receiverReady=false BEFORE receiver calls setReceiverReady, and then the subsequent update doesn't trigger a second listener call. Testing confirms Firestore listeners DO fire on field updates. Most likely hidden issue: receiver's sender selection UI is broken post-phase-07.1, preventing them from reaching _writeReceiverReady call.

fix: Add debug logging to SenderScreen._onHandshakeUpdate (around line 170) to print (_receiverReady, receiverReady from doc, _selectedReceiverPublicKeyJson) to identify which path is taken. Also check ReceiverScreen._onSenderSelected to verify it completes and reaches _writeReceiverReady call.

verification: (pending - requires adding logging and testing end-to-end flow)
files_changed: []
