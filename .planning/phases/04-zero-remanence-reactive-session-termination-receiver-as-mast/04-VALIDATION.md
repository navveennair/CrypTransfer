---
phase: 4
slug: zero-remanence-reactive-session-termination-receiver-as-mast
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-07
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test + fake_cloud_firestore + firebase_auth_mocks |
| **Config file** | none — standard flutter test runner |
| **Quick run command** | `flutter test test/security/session_termination_test.dart` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/security/session_termination_test.dart`
- **After every plan wave:** Run `flutter test`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 4-W0-01 | W0 | 0 | TERM-01..05,08 | V6, V3 | Test stubs created | unit | `flutter test test/security/session_termination_test.dart` | ❌ W0 | ⬜ pending |
| 4-01-01 | 01 | 1 | TERM-01 | V3 | Audit log written to both audit_logs subcollections before deletion | unit | `flutter test test/security/session_termination_test.dart -t TC-TERM-001` | ❌ W0 | ⬜ pending |
| 4-01-02 | 01 | 1 | TERM-02 | V6 | Storage deletion tolerates object-not-found | unit | `flutter test test/security/session_termination_test.dart -t TC-TERM-002` | ❌ W0 | ⬜ pending |
| 4-01-03 | 01 | 1 | TERM-03 | V6 | WriteBatch atomically deletes transfers/{id} + handshakes/{id} | unit | `flutter test test/security/session_termination_test.dart -t TC-TERM-003` | ❌ W0 | ⬜ pending |
| 4-01-04 | 01 | 1 | TERM-04 | V6 | closeReceiverSession deletes publicKey + private RSA key | unit | `flutter test test/security/session_termination_test.dart -t TC-TERM-004` | ❌ W0 | ⬜ pending |
| 4-02-01 | 02 | 2 | TERM-05 | V3 | Sender stream !snapshot.exists triggers wipeAll() | unit | `flutter test test/security/session_termination_test.dart -t TC-TERM-005` | ❌ W0 | ⬜ pending |
| 4-02-02 | 02 | 2 | TERM-08 | V6 | D-10 edge case: sender deletes stale transfer doc if still exists | unit | `flutter test test/security/session_termination_test.dart -t TC-TERM-008` | ❌ W0 | ⬜ pending |
| 4-03-01 | 03 | 3 | TERM-06 | V3 | Back nav blocked during ReceiverEndSessionScreen cleanup | manual | N/A | N/A | ⬜ pending |
| 4-03-02 | 03 | 3 | TERM-07 | V3 | SenderSessionEndedScreen Back to Home clears navigation stack | manual | N/A | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/security/session_termination_test.dart` — stubs for TC-TERM-001 through TC-TERM-005, TC-TERM-008
- [ ] No new conftest/setup needed — `FakeFirebaseFirestore` + `FakeSecureStorage` patterns established in `test/mocks/mock_firebase.dart`

*Note: `flutter_test`, `fake_cloud_firestore`, `firebase_auth_mocks` already present in pubspec.yaml — no install step required.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Back nav blocked during ReceiverEndSessionScreen cleanup | TERM-06 | PopScope.canPop is a widget behavior; not exercisable as a unit test | Tap "End Session" → immediately tap back → verify back is blocked during `_Phase.cleaning` |
| SenderSessionEndedScreen "Back to Home" clears stack | TERM-07 | Navigator stack state not easily verifiable in unit tests | Tap "Back to Home" → verify HomeScreen is reached and back stack is empty (no back arrow visible) |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
