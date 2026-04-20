# Security Audit Findings — Phase 02
## ReceiverTransferScreen Hardening & Memory Safety

**Phase:** 02 — ReceiverTransferScreen Hardening & Memory Safety
**ASVS Level:** L2
**Auditor:** gsd-security-auditor
**Date:** 2026-04-20

---

## Summary

**Threats Closed:** 5/12
**Threats Open:** 7/12
**Block-on:** blocker, major

---

## Closed Threats

| Threat ID | Category | Disposition | Evidence |
|-----------|----------|-------------|----------|
| T-02-05 | DoS | mitigate | `ReceiverTransferScreen` constructor takes no `sessionManager` parameter (receiver_transfer_screen.dart lines 14–26); no `sessionManager.dispose()` call exists anywhere in the file — the risk is structurally absent |
| T-02-06 | Repudiation | accept | Design decision accepted: `ReceiverScreen._transferStatusWidget` uses `addPostFrameCallback` (receiver_screen.dart line 875) before triggering navigation |
| T-02-11 | Info Disclosure | accept | Accepted risk: Web bytes held in browser sandbox; wiping browser-managed memory is outside FYP scope |
| T-02-12 | Repudiation | accept | Accepted risk: Zero-telemetry principle; no deeper diagnostic logged for Cloud-URI SnackBar |

---

## Open Threats

| Threat ID | Category | Disposition | Mitigation Expected | Files Searched | Finding |
|-----------|----------|-------------|---------------------|----------------|---------|
| T-02-01 | Tampering | mitigate | `_cancelled` field in `_ReceiverTransferScreenState`; `if (_cancelled \|\| !mounted) return;` after every await in `_runSteps` | lib/presentation/receiver/receiver_transfer_screen.dart | No `_cancelled` field exists. `_runSteps` (lines 105–121) uses only `if (!mounted) return;` — kill-switch cannot cancel an in-flight `_runSteps` sequence |
| T-02-02 | Info Disclosure | mitigate | `ValueListenableBuilder<SessionState>` in `ReceiverTransferScreen.build()` popping on `SessionState.terminated` | lib/presentation/receiver/receiver_transfer_screen.dart | No `SessionManager`, no `SessionState`, no `ValueListenableBuilder` anywhere in the file. Route is never popped on kill-switch termination |
| T-02-03 | Info Disclosure | mitigate | `SecurityLifecycleMixin` applied to `_ReceiverTransferScreenState` | lib/presentation/receiver/receiver_transfer_screen.dart | Line 40: `with SingleTickerProviderStateMixin` only — `SecurityLifecycleMixin` is absent; buffers allocated in this screen cannot be zeroed by `wipeAll` |
| T-02-04 | Info Disclosure | mitigate | `onPopInvokedWithResult` on `PopScope` calling `wipeAll()` when `didPop && _allStepsDone` | lib/presentation/receiver/receiver_transfer_screen.dart | Lines 148–149: `PopScope(canPop: _allStepsDone, ...)` has no `onPopInvokedWithResult` callback at all; back-navigation exits without any cleanup |
| T-02-07 | EoP | mitigate | `WidgetsBinding.instance.addPostFrameCallback` defers Navigator.pop; `if (!mounted) return;` inside | lib/presentation/receiver/receiver_transfer_screen.dart | `_proceed()` at line 126 calls `Navigator.pushReplacement` synchronously with no frame deferral and no `if (!mounted)` guard before the call |
| T-02-08 | Info Disclosure | mitigate | `FilePicker.pickFiles(withData: kIsWeb)` in sender_screen.dart | lib/presentation/sender/sender_screen.dart | Line 153: `FilePicker.pickFiles(withData: true)` — unconditional `true`; loads full file bytes into Dart heap on Android/iOS even when `file.path` is available for chunked reads |
| T-02-09 | DoS | mitigate | `if (!kIsWeb && file.path == null)` guard in `_pickFile` with SnackBar "This file type isn't supported" | lib/presentation/sender/sender_screen.dart | Lines 150–165: No `kIsWeb` check, no null-path guard, no SnackBar for cloud-URI files; a file with null path and null bytes will silently reach `_encryptFile` |
| T-02-10 | Tampering | mitigate | `if (kIsWeb && file.bytes == null) return;` AND `if (!kIsWeb && file.path == null) return;` in `_encryptFile` | lib/presentation/sender/sender_screen.dart | Line 171: only `if (file == null \|\| file.bytes == null) return;` — no platform-discriminated guards; the `!kIsWeb && file.path == null` path is not checked |

---

## Accepted Risks Log

| Threat ID | Category | Accepted Reason |
|-----------|----------|-----------------|
| T-02-06 | Repudiation | Design decision: SnackBar rendered before pop via `addPostFrameCallback` in `ReceiverScreen._transferStatusWidget` — receiver sees the notification before the route stack changes |
| T-02-11 | Info Disclosure | FYP scope: browser-managed memory is inaccessible for zeroing; risk is contained by the browser sandbox |
| T-02-12 | Repudiation | Zero-telemetry principle: no device or user-specific data logged beyond the minimal SnackBar; deeper diagnostic would violate the project's privacy stance |

---

## Next Steps

All 7 open threats require implementation before phase 02 is marked SECURED.

**Priority order (highest impact first):**

1. **T-02-02** — Add `SessionManager` parameter to `ReceiverTransferScreen`; add `ValueListenableBuilder<SessionState>` in `build()` that pops the route on `SessionState.terminated`
2. **T-02-03** — Add `SecurityLifecycleMixin` to `_ReceiverTransferScreenState` (`with SingleTickerProviderStateMixin, SecurityLifecycleMixin<ReceiverTransferScreen>`)
3. **T-02-01** — Add `bool _cancelled = false;` field; set it to `true` in a `_cancel()` method called by the session listener; add `if (_cancelled || !mounted) return;` after every `await` in `_runSteps`
4. **T-02-04** — Add `onPopInvokedWithResult: (didPop, _) { if (didPop && _allStepsDone) wipeAll(); }` to the `PopScope`
5. **T-02-07** — Wrap `Navigator.pushReplacement` in `_proceed()` with `if (!mounted) return;` and defer via `WidgetsBinding.instance.addPostFrameCallback`
6. **T-02-08** — Change `FilePicker.pickFiles(withData: true)` to `FilePicker.pickFiles(withData: kIsWeb)` in `_pickFile`
7. **T-02-09** — Add `if (!kIsWeb && file.path == null)` guard in `_pickFile` with SnackBar "This file type isn't supported on this platform"
8. **T-02-10** — Replace the single `file.bytes == null` guard in `_encryptFile` with platform-discriminated guards: `if (kIsWeb && file.bytes == null) return;` and `if (!kIsWeb && file.path == null) return;`

Re-run `/gsd-secure-phase` after implementing the above.
