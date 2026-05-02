---
phase: 3
slug: managed-profile-rsa-vault
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-05-02
completed: 2026-05-02
---

# Phase 03 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (Flutter 3.41.7) |
| **Config file** | No separate config — standard `flutter test` |
| **Quick run command** | `flutter analyze --no-pub` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~30 seconds (analyze); ~60 seconds (full suite) |

---

## Sampling Rate

- **After every task commit:** Run `flutter analyze --no-pub`
- **After every plan wave:** Run `flutter test test/security/ && flutter test test/vault/`
- **Before `/gsd-verify-work`:** Full suite must be green (`flutter test` + `flutter analyze` 0 issues)
- **Max feedback latency:** ~30 seconds (analyze)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 03-W0-01 | 01 | 0 | VAULT-07 | — | `flutter analyze` exits with 0 issues | static | `flutter analyze --no-pub` | ✅ | ⬜ pending |
| 03-W0-02 | 01 | 0 | VAULT-01 | — | Biometric gate test stub created | unit | `flutter test test/vault/vault_gate_test.dart` | ❌ W0 | ⬜ pending |
| 03-W0-03 | 01 | 0 | VAULT-02/03 | — | Key lifecycle test stubs created | unit | `flutter test test/vault/key_lifecycle_test.dart` | ❌ W0 | ⬜ pending |
| 03-W0-04 | 01 | 0 | VAULT-05 | — | Profile init test stub created | unit | `flutter test test/vault/profile_init_test.dart` | ❌ W0 | ⬜ pending |
| 03-W0-05 | 01 | 0 | VAULT-06 | — | ReceiverScreen banner test stub created | widget | `flutter test test/vault/receiver_banner_test.dart` | ❌ W0 | ⬜ pending |
| 03-01-01 | 02 | 1 | VAULT-07 | — | Constants added, analyze clean | static | `flutter analyze --no-pub` | ✅ | ⬜ pending |
| 03-01-02 | 02 | 1 | VAULT-05 | T-profile-init | Profile doc created atomically with users doc | unit | `flutter test test/vault/profile_init_test.dart` | ❌ W0 | ⬜ pending |
| 03-02-01 | 03 | 2 | VAULT-02 | T-key-regen | New private key written, Firestore publicKey updated, audit logged | unit | `flutter test test/vault/key_lifecycle_test.dart` | ❌ W0 | ⬜ pending |
| 03-02-02 | 03 | 2 | VAULT-03 | T-key-delete | SecureStorage cleared, publicKey nulled, audit doc appended | unit | `flutter test test/vault/key_lifecycle_test.dart` | ❌ W0 | ⬜ pending |
| 03-02-03 | 03 | 2 | VAULT-01 | T-biometric | Gate fires on screen open; pop on auth failure | widget | `flutter test test/vault/vault_gate_test.dart` | ❌ W0 | ⬜ pending |
| 03-03-01 | 04 | 3 | VAULT-06 | — | Banner visible when publicKey null in stream | widget | `flutter test test/vault/receiver_banner_test.dart` | ❌ W0 | ⬜ pending |
| 03-04-01 | 05 | 4 | VAULT-04 | T-immutable | `rsa_key_manager` docs immutable; `profile` writeable by owner | manual | Firebase Rules Playground | — | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/vault/` directory — create vault test directory
- [ ] `test/vault/vault_gate_test.dart` — VAULT-01: biometric gate pops on auth failure
- [ ] `test/vault/key_lifecycle_test.dart` — VAULT-02/03: regenerate + delete behaviour
- [ ] `test/vault/profile_init_test.dart` — VAULT-05: profile subcollection atomic write with fake_cloud_firestore
- [ ] `test/vault/receiver_banner_test.dart` — VAULT-06: banner visibility when publicKey null
- [ ] Fix 21 existing `flutter analyze` errors — **PREREQUISITE for all test runs**

*Wave 0 must complete before Wave 1 tasks begin.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `rsa_key_manager` docs are IMMUTABLE (update blocked) | VAULT-04 | Firestore rules only verifiable via Rules Playground or emulator; no emulator confirmed available | Open Firebase Console → Firestore → Rules Playground → attempt `update` on `users/{uid}/rsa_key_manager/{logId}` — expect `false` |
| `profile` subcollection allows owner update | VAULT-04 | Same as above | Rules Playground → `update` on `users/{uid}/profile/preferences` as owner — expect `true` |
| Biometric gate blocks key material on real device | VAULT-01 | Real biometrics require hardware (stub always returns true) | Manual test on device: if real `local_auth` re-enabled, confirm vault screen pops when biometric fails |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
