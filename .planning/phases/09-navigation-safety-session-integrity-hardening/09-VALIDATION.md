---
phase: 9
slug: navigation-safety-session-integrity-hardening
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-29
---

# Phase 9 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (bundled with Flutter 3.44.0) |
| **Config file** | `pubspec.yaml` — `dev_dependencies: flutter_test` |
| **Quick run command** | `flutter test test/security/ test/sender/ --no-pub` |
| **Full suite command** | `flutter test --no-pub` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/security/ test/sender/ --no-pub`
- **After every plan wave:** Run `flutter test --no-pub`
- **Before `/gsd-verify-work`:** Full suite must be green (107/108 baseline maintained)
- **Max feedback latency:** ~15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| GAP1-01 | 01 | 0 | Back-nav guard — canPop blocked | T-09-01 | ReceiverScreen canPop is false when mailbox is open | unit | `flutter test test/security/navigation_guard_test.dart --no-pub` | ❌ W0 | ⬜ pending |
| GAP1-02 | 01 | 0 | Transfer-in-progress block | T-09-01 | Back nav during active transfer shows SnackBar, no pop | unit | `flutter test test/security/navigation_guard_test.dart --no-pub` | ❌ W0 | ⬜ pending |
| GAP1-03 | 01 | 0 | Confirmed close triggers wipe | T-09-01 | Confirmed back-nav calls wipeSession | unit | `flutter test test/security/navigation_guard_test.dart --no-pub` | ❌ W0 | ⬜ pending |
| GAP2-01 | 01 | 1 | Stale AES key invalidation | T-09-02 | Stale AES key wiped when receiver public key changes mid-session | unit | `flutter test test/sender/stale_key_test.dart --no-pub` | ❌ W0 | ⬜ pending |
| GAP2-02 | 01 | 1 | Mid-flight guard | T-09-02 | Mid-flight guard prevents wipe during active compute() | unit | `flutter test test/sender/stale_key_test.dart --no-pub` | ❌ W0 | ⬜ pending |
| GAP3-01 | 01 | 1 | Browse Files disabled after encrypt | — | Browse Files button disabled after file encrypted | manual-only | n/a — requires file picker mock in widget test | manual | ⬜ pending |
| GAP3-02 | 01 | 1 | Change File wipes sensitive data | — | Change File confirmation dialog calls wipeSensitiveData | unit | `flutter test test/sender/stale_key_test.dart --no-pub` | ❌ W0 | ⬜ pending |
| GAP4-01 | 01 | 1 | Step 1 IgnorePointer lockout | T-09-03 | Step 1 IgnorePointer active when mailbox open | manual-only | n/a — requires widget test with tap simulation | manual | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/security/navigation_guard_test.dart` — stubs for GAP1-01, GAP1-02, GAP1-03 (back-nav guard, session-locked block, wipeSession on confirm)
- [ ] `test/sender/stale_key_test.dart` — stubs for GAP2-01, GAP2-02, GAP3-02 (stale-key invalidation, mid-flight guard, Change File confirm)

*Existing infrastructure: `test/security/session_wipe_test.dart` (29/29 passing) provides the SessionManager + EncryptionService fixture base. Wave 0 test files should import the same mock setup.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Browse Files button greyed after `_fileEncrypted` | GAP3-01 | Widget test requires file picker platform channel mock | Launch debug APK, select receiver, pick file, encrypt — verify Browse Files button is greyed and non-tappable |
| Step 1 StepCard IgnorePointer active | GAP4-01 | Requires tap simulation on platform-channel-dependent widget | Launch debug APK, open mailbox — attempt to tap Step 1 (key manager button), verify taps are ignored and card is at 0.4 opacity |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
