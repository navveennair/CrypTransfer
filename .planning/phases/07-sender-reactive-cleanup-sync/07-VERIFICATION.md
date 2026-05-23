---
phase: 07-sender-reactive-cleanup-sync
verified: 2026-05-23T18:00:00Z
status: human_needed
score: 6/6 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Complete a file transfer. When receiverStatus transitions to 'saved', confirm the CircularProgressIndicator row + 'Waiting for secure session close...' text appears below the green status badge."
    expected: "A small (14x14) spinner and the text 'Waiting for secure session close...' are visible below the receiver-saved badge. The row disappears once Turn 2 fires (cleanup_initiated)."
    why_human: "Widget test stubs V07-01..V07-03 are empty (Nyquist scaffolding) — no automated assertion exists for the rendered state."
  - test: "Temporarily change Duration(seconds: 300) to Duration(seconds: 10) in transfer_progress_screen.dart line 192. Complete a transfer. Do NOT tap End Session on the receiver. After 10 seconds, verify SenderSessionEndedScreen loads with the orange timeout banner."
    expected: "Orange banner ('Session ended by timeout — receiver did not complete cleanup') visible. Subtitle reads 'Session ended by safety timeout.' The four receiver-cleanup checkmarks are still shown (known WR-05 defect — checklist does not adapt to timeout path)."
    why_human: "Timer behavior requires a running app; widget test stubs V07-04..V07-08 are empty stubs with no assertions."
  - test: "While timer is running (use the 10s reduced timeout), navigate back from TransferProgressScreen before timeout fires."
    expected: "No crash. dispose() cancels the timer. App returns to the previous screen cleanly."
    why_human: "Cannot verify mounted-guard and dispose-cancel interaction without running the app."
---

# Phase 07: Sender Reactive Cleanup Sync — Verification Report

**Phase Goal:** Implement a real-time stream on SenderScreen that listens to the receiver's cleanup status after a successful transfer. When the receiver marks cleanup complete, the sender verifies and wipes its own critical key/hashed data, then both parties navigate back to HomeScreen. Safety timeout for unresponsive receiver.
**Verified:** 2026-05-23T18:00:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | When receiverStatus == 'saved', a pulsing CircularProgressIndicator appears below the status badge with text 'Waiting for secure session close...' until Turn 2 fires | VERIFIED | `transfer_progress_screen.dart` lines 483-506: `if (_canEndSession && !_senderWipeSent) ...[ CircularProgressIndicator ... 'Waiting for secure session close…' ]` inside the `else if (_done)` branch, placed after the AnimatedSwitcher status badge |
| 2 | The pulsing indicator is hidden once _senderWipeSent == true (Turn 2 has executed) | VERIFIED | Condition `if (_canEndSession && !_senderWipeSent)` evaluates false when `_senderWipeSent = true` (set at line 136). Additionally Turn 2 also sets `_canEndSession = false` (line 151), making both guards false simultaneously |
| 3 | A 300-second Timer starts when _canEndSession becomes true (receiverStatus == 'saved') and is cancelled when Turn 2 or Turn 4 fires | VERIFIED | `_startCleanupTimeout()` called at line 172 inside `receiverStatus == 'saved'` branch; `Timer(const Duration(seconds: 300), ...)` at line 192; Turn 2 cancel at line 135; Turn 4 cancel at line 109 |
| 4 | If the 300-second timer expires before Turn 2 or Turn 4, wipeAll() is called and the screen navigates to SenderSessionEndedScreen with a timeoutReason argument | VERIFIED | Timer callback lines 193-211: `_sessionEnded = true; wipeAll(); Navigator.pushReplacement(... SenderSessionEndedScreen(... timeoutReason: 'Session ended by timeout — receiver did not complete cleanup'))` |
| 5 | The Timer is cancelled in dispose() to prevent use-after-dispose crashes | VERIFIED | `dispose()` at lines 91-96: `_cleanupTimeoutTimer?.cancel()` is the FIRST call, before `_transferListener?.cancel()` and `_successCtrl.dispose()` |
| 6 | If user navigates back while _cleanupTimeoutTimer is running (canPop is true after _done=true), dispose() cancels the timer via _cleanupTimeoutTimer?.cancel() and SecurityLifecycleMixin.wipeAll() zeroes registered buffers | VERIFIED | `canPop: _done \|\| _error != null` (line 303); dispose() calls `_cleanupTimeoutTimer?.cancel()` (line 92); class mixes in `SecurityLifecycleMixin<TransferProgressScreen>` (line 50) which zeroes registered buffers in `wipeAll()` / `super.dispose()` |

**Score:** 6/6 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/presentation/sender/transfer_progress_screen.dart` | Safety timeout + pulsing waiting UI; contains `_cleanupTimeoutTimer` | VERIFIED | 549 lines; `_cleanupTimeoutTimer` field (line 63), `_startCleanupTimeout()` method (lines 190-213), pulsing indicator block (lines 483-506), cancels in Turn 2 (line 135), Turn 4 (line 109), dispose (line 92) |
| `test/sender/transfer_progress_timeout_test.dart` | Nyquist stubs V07-01 through V07-10 | VERIFIED (stubs only) | 59-line file containing 10 named test stubs V07-01..V07-10. All stubs compile cleanly. Per plan design, they pass trivially (no assertions). Empty stubs provide zero runtime coverage — noted as IN-02 in code review |

**Note on test artifact:** The plan explicitly specifies these as "Nyquist stubs" that "pass trivially." The artifact satisfies the plan's stated requirement for the test scaffold. However, the code review (IN-02) correctly flags that they provide no actual coverage.

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `_startTransferListener` (receiverStatus == 'saved' branch) | `_startCleanupTimeout()` | Direct method call at line 172 | WIRED | `_startCleanupTimeout()` called immediately after the `setState` that sets `_canEndSession = true` |
| `_cleanupTimeoutTimer` expiry | `SenderSessionEndedScreen` | `Navigator.pushReplacement` with `timeoutReason` parameter at lines 197-211 | WIRED | Full navigation call present inside timer callback; `timeoutReason` argument is non-null string |

---

### Data-Flow Trace (Level 4)

Not applicable — this phase implements timer lifecycle and conditional UI rendering, not a data-fetching component. The `_canEndSession` and `_senderWipeSent` state variables that gate the pulsing indicator are populated by the existing `_startTransferListener()` Firestore stream (established in quick-260520-001), which is outside this phase's scope.

---

### Behavioral Spot-Checks

Step 7b: SKIPPED — requires a running Flutter app with an active Firestore transfer session. No entry point is testable without Firebase connectivity and a live transfer document.

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| Phase 07 ROADMAP scope item 2 (post-save waiting UI) | 07-01-PLAN.md | "Sender Stream Listener — show a pulsing 'Waiting for receiver to complete secure cleanup...' UI" | SATISFIED | CircularProgressIndicator + 'Waiting for secure session close...' text in done-branch, guarded by `_canEndSession && !_senderWipeSent` |
| Phase 07 ROADMAP scope item 5 (safety timeout) | 07-01-PLAN.md | "If receiver cleanup signal not received within configurable timeout, sender auto-wipes and navigates home with 'Session ended by timeout' notification" | SATISFIED | `_startCleanupTimeout()` with `Duration(seconds: 300)`, calls `wipeAll()` + `Navigator.pushReplacement` with `timeoutReason` argument |

---

### Anti-Patterns Found

The following findings from 07-REVIEW.md are noted here. None block the phase 07 scope items but are real defects for future closure:

| File | Issue | Severity | Impact |
|------|-------|----------|--------|
| `transfer_progress_screen.dart:167-173` | WR-01: Timer re-armed on every `receiverStatus == 'saved'` Firestore re-emission (no `_timeoutStarted` guard). Repeated reconnections can reset the 300s clock indefinitely, defeating the safety timeout. | Warning | Safety timeout may never fire on unstable connections |
| `transfer_progress_screen.dart:142` | WR-02: `'encryptedAESKey': ''` instead of `FieldValue.delete()` on Turn 2. Residual field survives deletion semantics; downstream checks on `!= null` will see a non-absent field. | Warning | Zero-remanence contract weakened on Firestore side |
| `transfer_progress_screen.dart:134-155` | WR-03: Silent `catch (_) {}` on Turn 2 Firestore write. AES key survives in Firestore if write fails; no audit trail of failure; `_senderWipeSent = true` prevents retry. | Warning | Key material may not be erased from Firestore on network error |
| `sender_session_ended_screen.dart:60-74` | WR-04: `_checkAndMarkDone()` has no try/catch. UI stuck in permanent "Verifying cleanup..." spinner if Firestore `get()` or `delete()` throws. | Warning | UI hangs on network failure |
| `sender_session_ended_screen.dart:161-197` | WR-05: Receiver cleanup checklist unconditionally shown as complete on timeout path, even though cleanup did not occur. Misrepresents security state. | Warning | Misleading security UI on timeout path |
| `test/sender/transfer_progress_timeout_test.dart:9-57` | IN-02: All 10 Nyquist stubs are empty — no assertions, zero automated coverage. They pass trivially and mask the absence of actual tests. | Info | No automated regression protection for timeout or indicator behavior |

**WR-01 is the highest-risk warning** because it undermines the correctness of the primary must-have (300-second timer). However, the timer DOES exist and DOES start — the defect is that it can be re-armed, not that it is absent. The phase scope items are present.

---

### Human Verification Required

#### 1. Pulsing Waiting Indicator — Visual Confirmation

**Test:** Complete a file transfer to a receiver. When the receiver saves the file (receiverStatus transitions to 'saved'), observe TransferProgressScreen.
**Expected:** A small CircularProgressIndicator (14x14) and the text 'Waiting for secure session close...' appear below the green receiver status badge. After Turn 2 fires (receiver taps End Session → cleanup_initiated), both the spinner and text disappear and the status message changes to 'Keys destroyed. Waiting for receiver to terminate session...'
**Why human:** Widget test stubs V07-01..V07-03 are empty Nyquist scaffolds with no assertions. No automated widget test verifies the rendered state.

#### 2. Safety Timeout — End-to-End Path

**Test:** In `transfer_progress_screen.dart` line 192, temporarily change `Duration(seconds: 300)` to `Duration(seconds: 10)`. Run a transfer, wait for receiverStatus == 'saved', then do NOT tap End Session on the receiver device. Wait 10 seconds.
**Expected:** TransferProgressScreen navigates to SenderSessionEndedScreen. The orange banner with 'Session ended by timeout — receiver did not complete cleanup' is visible. Subtitle reads 'Session ended by safety timeout.' The 'Back to Home' button works.
**Why human:** Timer-based navigation cannot be tested without fake async + full widget test implementation. Stubs V07-04..V07-08 are empty.

#### 3. Back-Navigation During Active Timer

**Test:** Using the 10s reduced timer from Test 2: complete a transfer, wait for receiverStatus == 'saved' (timer starts), then immediately press Back on TransferProgressScreen before the 10 seconds elapse.
**Expected:** No crash. App navigates to the previous screen cleanly. No `use-after-dispose` exception in the Flutter error overlay.
**Why human:** Requires live interaction testing to confirm the `mounted` guard and `dispose()` cancel interact correctly.

---

### Code Review Defects for Follow-Up

The following defects from 07-REVIEW.md are real but outside this phase's must-have scope. They should be addressed in a follow-up plan:

1. **WR-01** — Add `_timeoutStarted` boolean guard to prevent timer re-arming on Firestore reconnect
2. **WR-02** — Replace `'encryptedAESKey': ''` with `FieldValue.delete()` for correct field erasure semantics
3. **WR-03** — Replace silent `catch (_) {}` with error logging (without key material) on Turn 2 Firestore write failure
4. **WR-04** — Add try/catch + `finally { _aesCleanDone = true }` to `_checkAndMarkDone()` to prevent stuck UI
5. **WR-05** — Conditionally replace receiver-cleanup checklist with warning card when `timeoutReason != null`

---

_Verified: 2026-05-23T18:00:00Z_
_Verifier: Claude (gsd-verifier)_
