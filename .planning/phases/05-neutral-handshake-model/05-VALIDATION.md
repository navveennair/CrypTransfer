---
phase: 5
slug: neutral-handshake-model
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-12
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test + fake_cloud_firestore ^4.1.0+1 + firebase_auth_mocks ^0.15.1 |
| **Config file** | None — flutter test discovers test/ directory automatically |
| **Quick run command** | `flutter test test/handshake/ -x` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/handshake/ -x`
- **After every plan wave:** Run `flutter test`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 0 | HAND-01 | T-05-01 | proposerId == auth.uid enforced by Firestore rule | unit | `flutter test test/handshake/handshake_repository_test.dart -x` | ❌ W0 | ⬜ pending |
| 05-01-02 | 01 | 0 | HAND-02 | T-05-01 | acceptProposal only by partnerId | unit | `flutter test test/handshake/handshake_repository_test.dart -x` | ❌ W0 | ⬜ pending |
| 05-01-03 | 01 | 0 | HAND-03 | — | rejectProposal sets status=rejected | unit | `flutter test test/handshake/handshake_repository_test.dart -x` | ❌ W0 | ⬜ pending |
| 05-01-04 | 01 | 0 | HAND-04 | — | cancelProposal deletes doc; stream emits removal | unit | `flutter test test/handshake/handshake_repository_test.dart -x` | ❌ W0 | ⬜ pending |
| 05-01-05 | 01 | 0 | HAND-05 | — | streamIncomingPending emits partner's pending docs | unit | `flutter test test/handshake/handshake_repository_test.dart -x` | ❌ W0 | ⬜ pending |
| 05-02-01 | 02 | 1 | HAND-07 | — | SenderScreen pre-fill sets _receiverId without _FindSenderSheet | unit | `flutter test test/handshake/sender_prefill_test.dart -x` | ❌ W0 | ⬜ pending |
| 05-03-01 | 03 | 1 | HAND-08 | — | ReceiverScreen pre-fill calls selectSender() after checkKeyStatus | unit | `flutter test test/handshake/receiver_prefill_test.dart -x` | ❌ W0 | ⬜ pending |
| 05-04-01 | 04 | 2 | HAND-06 | — | Approval banner surfaces for incoming pending proposals | manual | — | N/A | ⬜ pending |
| 05-04-02 | 04 | 2 | HAND-09 | T-05-02 | Firestore rules block spoofing and self-accept | manual | Firebase Rules Playground | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/handshake/handshake_repository_test.dart` — stubs for HAND-01 through HAND-05
- [ ] `test/handshake/sender_prefill_test.dart` — stub for HAND-07
- [ ] `test/handshake/receiver_prefill_test.dart` — stub for HAND-08
- [ ] No new framework install needed — `fake_cloud_firestore` already in dev_dependencies

*Existing infrastructure covers all phase requirements — no new packages needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Approval banner appears when proposal arrives | HAND-06 | OverlayEntry not testable in flutter unit tests | Open two app instances; send proposal from A → B; verify _NotifBanner surfaces on B with Accept/Reject buttons |
| Firestore rules: only proposer creates, only partner updates | HAND-09 | Rules require Firebase Emulator or Rules Playground | Use Firebase Rules Playground: (1) attempt create with wrong proposerId → expect deny; (2) attempt update with proposer UID → expect deny; (3) attempt update with partner UID to 'connected' → expect allow |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
