---
phase: 02-receivertransferscreen-hardening-memory-safety
verified: 2026-04-20T04:00:00Z
status: gaps_found
score: 8/11 must-haves verified
overrides_applied: 0
gaps:
  - truth: "Backgrounding the app mid-decrypt causes ReceiverTransferScreen to pop and show 'Transfer cancelled — session wiped' SnackBar"
    status: partial
    reason: "The kill-switch fires and the route is popped (via popUntil), but no SnackBar is shown. The _onSessionStateChanged handler calls Navigator.of(context).popUntil without a showSnackBar call. The 'Transfer cancelled — session wiped' copy does not appear anywhere in the file."
    artifacts:
      - path: "lib/presentation/receiver/receiver_transfer_screen.dart"
        issue: "Line 104-109: _onSessionStateChanged sets _cancelled=true, calls wipeAll(), calls popUntil — no SnackBar"
    missing:
      - "Add ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transfer cancelled — session wiped'))) before the Navigator.of(context).popUntil call in _onSessionStateChanged"

  - truth: "ValueListenableBuilder<SessionState> wraps PopScope in build() to react to stateNotifier"
    status: failed
    reason: "The plan specified ValueListenableBuilder<SessionState> wrapping the PopScope in build(). The actual implementation uses stateNotifier.addListener(_onSessionStateChanged) in initState instead. No ValueListenableBuilder exists in the file. This is a valid alternative mechanism but diverges from the key_link pattern specified in the plan."
    artifacts:
      - path: "lib/presentation/receiver/receiver_transfer_screen.dart"
        issue: "ValueListenableBuilder<SessionState> not present; addListener pattern used instead"
    missing:
      - "Either convert to ValueListenableBuilder per plan OR document this as an accepted override (addListener is functionally equivalent but the key_link contract was not met)"

  - truth: "Cloud URI picks (Google Drive / Gmail on Android) that produce null path AND null bytes are caught before entering _encryptFile and the user sees a friendly SnackBar"
    status: failed
    reason: "The D-13 null-path guard is absent from _pickFile(). After result.files.first is obtained, there is no check for !kIsWeb && file.path == null. Cloud URI picks with null path will proceed to setState and then fail later in TransferService.resolve with a StateError — caught by the _encryptFile catch block which shows 'Encryption failed: ...' instead of the friendly 'This file type isn't supported — try saving it locally first.' message. The REVIEW-FIX (CR-02) only applied the withData change and downstream guard — it did not implement D-13."
    artifacts:
      - path: "lib/presentation/sender/sender_screen.dart"
        issue: "Lines 150-165: _pickFile() has no null-path guard. After MEM-01 withData change, cloud URI picks set _file to a PlatformFile with null path AND null bytes, which TransferService.resolve will throw on."
    missing:
      - "Add null-path guard in _pickFile after result.files.first: if (!kIsWeb && file.path == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(\"This file type isn't supported — try saving it locally first.\"))); return; }"
---

# Phase 02: ReceiverTransferScreen Hardening — Verification Report

**Phase Goal:** Close the ReceiverTransferScreen kill-switch gap and eliminate the unregistered double plaintext copy in SenderScreen.
**Verified:** 2026-04-20T04:00:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Backgrounding the app mid-decrypt causes ReceiverTransferScreen to pop and show "Transfer cancelled — session wiped" SnackBar | PARTIAL | Route is popped via popUntil (line 108) when terminated fires, but no SnackBar is shown — showSnackBar call is absent from _onSessionStateChanged |
| 2 | ReceiverTransferScreen receives SessionManager from ReceiverScreen as a required constructor argument | VERIFIED | `final SessionManager sessionManager` at line 19, `required this.sessionManager` in constructor at line 25; receiver_screen.dart passes `sessionManager: _sessionManager` at line 107 |
| 3 | When SessionState.terminated fires, the _runSteps() async loop exits cleanly before its next setState | VERIFIED | `_cancelled = true` set at line 106; `_runSteps` checks `if (!mounted || _disposed || _cancelled)` at lines 136, 140, and 148 |
| 4 | Back-navigation after _allStepsDone==true triggers wipeAll() explicitly via PopScope callback | PARTIAL | `onPopInvokedWithResult: (didPop, _) { if (didPop) wipeAll(); }` at lines 178-180. Condition is `if (didPop)` not `if (didPop && _allStepsDone)` — wipeAll fires on any back-nav (broader than spec, not narrower; the plan required it after _allStepsDone). Functionally acceptable — wipeAll is idempotent — but the plan specified the narrower condition. |
| 5 | ReceiverTransferScreen disposal chains through SecurityLifecycleMixin → SingleTickerProviderStateMixin → framework | VERIFIED | State class at line 44-45: `with SingleTickerProviderStateMixin, SecurityLifecycleMixin<ReceiverTransferScreen>`; dispose() at lines 94-100 calls `_bounceCtrl.dispose()` then `super.dispose()` which chains through the mixin's `dispose()` (calls `wipeAll()`) then to State |
| 6 | ValueListenableBuilder<SessionState> wraps PopScope in build() | FAILED | Not present in the file. The addListener pattern was used instead. No ValueListenableBuilder exists anywhere in receiver_transfer_screen.dart |
| 7 | TC-WIPE-001 through TC-WIPE-007 remain green | UNCERTAIN | Cannot verify without running tests; the REVIEW-FIX and SUMMARY both assert green, but no programmatic run was performed here |
| 8 | On Android (non-web) the FilePicker returns PlatformFile with bytes==null — no unregistered plaintext copy lingers | VERIFIED | `FilePicker.pickFiles(withData: kIsWeb)` at sender_screen.dart line 153; on Android kIsWeb is false so withData=false, bytes will be null |
| 9 | On web (kIsWeb==true), bytes remains populated so the existing web path keeps working | VERIFIED | `withData: kIsWeb` is true on web, so bytes are populated; TransferService.resolve uses `fallbackBytes: file.bytes` at line 199 |
| 10 | Cloud URI picks that produce null path AND null bytes are caught before entering _encryptFile with a friendly SnackBar | FAILED | No D-13 null-path guard in _pickFile(). Cloud URI picks set _file then proceed; when _encryptFile runs, TransferService.resolve throws StateError which is caught and shown as "Encryption failed: ..." not the intended user-friendly message |
| 11 | FLAG_SECURE check in _encryptFile runs BEFORE any registerBuffer calls | VERIFIED | `isFlagSecureActive()` check at sender_screen.dart line 179; `registerBuffer(key)` at line 193 — FLAG_SECURE is checked outside the try block before any buffer registration |

**Score:** 8/11 truths verified (2 failed, 1 partial on truth 1, 1 partial on truth 4 — partial items counted as failing for score)

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/presentation/receiver/receiver_transfer_screen.dart` | ReceiverTransferScreen with SessionManager param, _cancelled flag, ValueListenableBuilder kill-switch pop, SecurityLifecycleMixin, onPopInvokedWithResult wipeAll | PARTIAL | SessionManager param present; _cancelled present; SecurityLifecycleMixin present; onPopInvokedWithResult present; ValueListenableBuilder MISSING; SnackBar on termination MISSING |
| `lib/presentation/receiver/receiver_screen.dart` | _navigateToDecrypt passes _sessionManager to ReceiverTransferScreen | VERIFIED | Line 104-107: `sessionManager: _sessionManager` passed in MaterialPageRoute builder |
| `lib/presentation/sender/sender_screen.dart` | _pickFile() uses withData: kIsWeb and guards null-path cloud URI edge case | PARTIAL | `withData: kIsWeb` present at line 153; null-path guard (D-13) MISSING from _pickFile |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| SessionManager.stateNotifier (ValueNotifier) | ReceiverTransferScreen.build() | ValueListenableBuilder wrapping PopScope | NOT_WIRED | ValueListenableBuilder does not exist; addListener pattern used instead |
| ValueListenableBuilder builder | Navigator.pop + ScaffoldMessenger.showSnackBar | WidgetsBinding.instance.addPostFrameCallback when terminated | NOT_WIRED | Neither addPostFrameCallback nor showSnackBar present in receiver_transfer_screen.dart |
| SessionState.terminated signal | _runSteps() loop exit | setState(() => _cancelled = true) before pop; _runSteps checks _cancelled || !mounted | WIRED (alt path) | _cancelled set in _onSessionStateChanged (addListener pattern); _runSteps checks `_cancelled` at all yield points |
| ReceiverScreen._navigateToDecrypt() | ReceiverTransferScreen constructor | sessionManager: _sessionManager argument | WIRED | receiver_screen.dart line 107 passes `sessionManager: _sessionManager` |
| _pickFile FilePicker.pickFiles | TransferService.resolve (chunked path-based reads) | withData flag gates whether PlatformFile.bytes is populated | WIRED | `withData: kIsWeb` at line 153 |
| _pickFile null-path detection | ScaffoldMessenger.showSnackBar "This file type isn't supported" | early return when !kIsWeb && file.path == null | NOT_WIRED | D-13 guard absent from _pickFile; null-path error surface only via TransferService.resolve StateError |

---

### Data-Flow Trace (Level 4)

Not applicable — this phase modifies security lifecycle wiring and memory management, not data-rendering components.

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| withData: kIsWeb present in sender_screen.dart | grep "withData: kIsWeb" sender_screen.dart | 1 match at line 153 | PASS |
| Old withData: true removed | grep "withData: true" sender_screen.dart | 0 matches | PASS |
| ValueListenableBuilder present in receiver_transfer_screen.dart | grep "ValueListenableBuilder" receiver_transfer_screen.dart | 0 matches | FAIL |
| SnackBar "Transfer cancelled" present | grep "Transfer cancelled" receiver_transfer_screen.dart | 0 matches | FAIL |
| null-path guard in _pickFile | grep "!kIsWeb && file.path == null" sender_screen.dart | 0 matches | FAIL |
| FLAG_SECURE before registerBuffer in _encryptFile | isFlagSecureActive at line 179; registerBuffer at line 193 | Pre-registration confirmed | PASS |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|---------|
| WIPE-02 | 02-01-PLAN | ReceiverTransferScreen observes kill-switch and pops the route | PARTIAL | Route IS popped on termination (popUntil at line 108), but SnackBar feedback is missing |
| WIPE-03 | 02-01-PLAN | SecurityLifecycleMixin applied to ReceiverTransferScreen | SATISFIED | Mixin applied at line 44-45; dispose chain verified |
| WIPE-04 | 02-01-PLAN | Explicit wipeAll() on back-nav via PopScope | SATISFIED | onPopInvokedWithResult at lines 178-180 calls wipeAll() on didPop |
| MEM-01 | 02-02-PLAN | PlatformFile.bytes null on Android; cloud URI guard with friendly SnackBar | PARTIAL | bytes=null on Android satisfied; cloud URI guard missing |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| receiver_transfer_screen.dart | 88 | `stateNotifier.addListener` in initState (plan specified ValueListenableBuilder) | Warning | Implementation deviates from plan spec; functionally equivalent but the addListener subscription requires manual removeListener management (which IS present at line 97, so no leak) |
| sender_screen.dart | 154-161 | No null-path guard after `result.files.first` | Blocker | Cloud URI picks on Android (Google Drive, Gmail) that return null path AND null bytes proceed into setState, then fail with "Encryption failed: Bad state: TransferService.resolve: no file path or bytes provided" instead of the intended user-friendly message |

---

### Human Verification Required

#### 1. Kill-Switch SnackBar on Route Pop

**Test:** Open ReceiverTransferScreen (mid-decrypt animation), then background the app.
**Expected:** ReceiverTransferScreen pops and the ReceiverScreen below shows "Transfer cancelled — session wiped" SnackBar.
**Why human:** The SnackBar is absent from the source — this will currently NOT show. Confirms the gap is user-visible.

#### 2. Cloud URI Pick Error Message

**Test:** On Android, use file picker and select a Google Drive file that has no local path.
**Expected:** User sees "This file type isn't supported — try saving it locally first."
**Why human:** Cloud URI picks require a real Android device with Drive; the current code will show "Encryption failed: Bad state: TransferService.resolve: no file path or bytes provided" instead.

---

## Gaps Summary

Three gaps block full goal achievement:

**Gap 1 — Missing SnackBar on kill-switch pop (WIPE-02 partial):** The kill-switch correctly terminates the session and pops ReceiverTransferScreen via `popUntil`. However, `_onSessionStateChanged` does not call `showSnackBar` before or after the pop. The user gets no feedback that the transfer was cancelled due to a session wipe. This is a UX gap and a partial WIPE-02 miss.

**Gap 2 — ValueListenableBuilder not implemented (plan key_link violation):** The plan specified `ValueListenableBuilder<SessionState>` wrapping the PopScope as the canonical reactive subscription pattern. The actual code uses `stateNotifier.addListener` in `initState` / `dispose`. This is functionally equivalent — the listener fires on termination, wipes and pops — but the specific contract in the plan key_links was not met. If this deviation is intentional (the addListener approach is cleaner and avoids build-time side effects), it should be accepted via an override.

**Gap 3 — D-13 null-path cloud URI guard missing from _pickFile (MEM-01 partial):** The REVIEW-FIX (CR-02) correctly applied `withData: kIsWeb` but did not implement the null-path SnackBar guard. After MEM-01, `_pickFile` on Android always produces `file.bytes == null`. A cloud URI pick with `file.path == null` will also have null bytes, so both are null. `_encryptFile` will call `TransferService.resolve(filePath: null, fallbackBytes: null)` which throws a `StateError` — the error surface is "Encryption failed: Bad state: ..." rather than the intended user-friendly message. Fix: add the D-13 guard to `_pickFile` before `setState`.

**Root cause of Gaps 1 and 3:** The REVIEW-FIX applied a different implementation strategy than the plan (CR-01 used addListener not ValueListenableBuilder; CR-02 omitted D-13). The REVIEW-FIX summary documents these as intentional choices, but Gaps 1 and 3 represent incomplete implementation regardless of the implementation path chosen.

---

_Verified: 2026-04-20T04:00:00Z_
_Verifier: Claude (gsd-verifier)_
