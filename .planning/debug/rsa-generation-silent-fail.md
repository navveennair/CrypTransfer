---
status: fix_applied
trigger: RSA key pair generation failing on receiver stepper 1
created: 2026-05-25T20:52:00Z
updated: 2026-05-25T21:05:00Z
---

# Debug Session: RSA Generation Silent Failure

## Symptoms

**Expected behavior:**
- Biometric authentication gate
- RSA key pair generation via compute() isolate
- TOFU (Trust On First Use) inspection display
- Navigation to next stepper step

**Actual behavior:**
- Click "tap to generate" on stepper step 1
- Screen loads (spinner or processing state visible)
- Redirects back to same state without generating key
- **No error message visible** (silent failure)
- **No console error** (no exception propagated)

**Timeline:** Started after phase 07.1 (layer decoupling refactor)

**Reproduction:** Open receiver stepper, navigate to step 1 (RSA vault), tap "generate key", observe redirect back

---

## Root Cause

RsaKeyManagerScreen._onRegenerate() calls regenerateKeyPair(uid) and dismisses the progress dialog on success, but **fails to pop the RsaKeyManagerScreen itself**, leaving the vault screen visible. ReceiverScreen never receives the pop, so _checkKeyStatus() never fires, and the stepper never advances.

## Fix Applied

In RsaKeyManagerScreen._onRegenerate() (line 88) and _onDelete() (line 128), added Navigator.pop(context) after the snackbar is shown:

**File: lib/presentation/vault/rsa_key_manager_screen.dart**

Line 88 (_onRegenerate success path):
```dart
Navigator.pop(context); // dismiss progress dialog
ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(content: Text('RSA keys regenerated successfully.')),
);
Navigator.pop(context); // close RsaKeyManagerScreen to return to ReceiverScreen
```

Line 128 (_onDelete success path):
```dart
ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(content: Text('RSA keys deleted.')),
);
Navigator.pop(context); // close RsaKeyManagerScreen to return to ReceiverScreen
```

## Verification Checklist

- [ ] Open receiver stepper → step 1 (RSA vault)
- [ ] Tap "Generate Keys"
- [ ] Complete biometric authentication
- [ ] Confirm regenerate dialog
- [ ] **Expected:** Screen auto-closes and returns to ReceiverScreen with _checkKeyStatus() firing
- [ ] **Result:** Stepper step 1 shows green checkmark; stepper advances to step 2

## Evidence

- timestamp: 2026-05-25T21:00:00Z
- file: lib/presentation/vault/rsa_key_manager_screen.dart
- lines: 59-99 (_onRegenerate method) — missing final Navigator.pop(context)
- fix: added Navigator.pop(context) on line 88

- timestamp: 2026-05-25T21:00:30Z
- file: lib/presentation/receiver/receiver_screen.dart
- lines: 472-476
- observation: ReceiverScreen expects RsaKeyManagerScreen to pop after generation; now it does

## Eliminated

- AuthRepository.regenerateKeyPair() implementation is correct (stores key, updates Firestore)
- compute() isolate execution succeeds (otherwise catch block would be triggered)
- Biometric gate works (screen passes _gateChecked = true)
- SecurityLifecycleMixin not the issue (no zero-wipe registry involved on first generation)

---

## Resolution

**root_cause:** RsaKeyManagerScreen._onRegenerate() was missing the final Navigator.pop(context) call to close the vault screen after successful key generation.

**fix:** Added Navigator.pop(context) after snackbar display in both _onRegenerate() (line 88) and _onDelete() (line 128) to properly close the screen and return to ReceiverScreen.

**verification:** After fix, user flow is: ReceiverScreen tap → RsaKeyManagerScreen popup → biometric gate → generate/delete → snackbar → auto-close → ReceiverScreen._checkKeyStatus() fires → stepper updates.

**files_changed:** ["lib/presentation/vault/rsa_key_manager_screen.dart"]
