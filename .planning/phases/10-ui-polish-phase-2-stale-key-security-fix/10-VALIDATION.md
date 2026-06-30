---
phase: 10
slug: ui-polish-phase-2-stale-key-security-fix
status: draft
nyquist_compliant: false
wave_0_complete: true
created: 2026-05-31
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (Flutter SDK) |
| **Config file** | none — uses `flutter test` CLI |
| **Quick run command** | `flutter test test/sender/stale_key_test.dart --no-pub` |
| **Full suite command** | `flutter test --no-pub` |
| **Estimated runtime** | ~30 seconds (quick) / ~90 seconds (full) |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/sender/stale_key_test.dart --no-pub`
- **After every plan wave:** Run `flutter test --no-pub`
- **Before `/gsd-verify-work`:** Full suite must be green (113+/114)
- **Max feedback latency:** 90 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 10-01-T1 | 01 | 1 | D-01 | T-10-01 | `previousPublicKey` captured before `setState`; stale check fires when key changes | unit (logic model) | `flutter test test/sender/stale_key_test.dart --no-pub` | ✅ GAP2-01 | ⬜ pending |
| 10-01-T2 | 01 | 1 | D-02 | T-10-01 | Mid-flight guard short-circuits stale check when `_encrypting || _encryptingKey` | unit (logic model) | `flutter test test/sender/stale_key_test.dart --no-pub` | ✅ GAP2-02 | ⬜ pending |
| 10-01-T3 | 01 | 1 | D-03 | T-10-01 | `_wipeSensitiveData()` called + SnackBar shown when stale key detected | unit (logic model) | `flutter test test/sender/stale_key_test.dart --no-pub` | ✅ GAP2-01 | ⬜ pending |
| 10-02-T1 | 02 | 1 | D-04/D-05/D-06 | — | Glassmorphic dialogs render (spacing 32/8 per UI-SPEC) | manual | device run | N/A | ⬜ pending |
| 10-02-T2 | 02 | 1 | D-07 | — | Admin dashboard visual identity committed | manual | device run | N/A | ⬜ pending |
| 10-02-T3 | 02 | 1 | D-08 | — | ROADMAP.md housekeeping committed | git audit | `git log --oneline -3` | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements.

- `test/sender/stale_key_test.dart` — GAP2-01, GAP2-02, GAP3-02 already exist and pass (3/3)
- No new test files needed for Phase 10

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Glassmorphic dialogs render correctly across 6 screens | D-04, D-05, D-06 | No widget test exists for dialog visuals; flutter_test has limited BackdropFilter support | Run app on device; trigger each dialog (disconnect, abort, go-back, role conflict, end-session); verify GlassContainer renders, CrypButton confirm, TextButton cancel, 48px icon, correct spacing |
| Admin dashboard visual identity | D-07 | Pure visual change (AppBar title, widget wrapping) | Open admin dashboard on device; verify title reads `CrypTransferAdmin`, GlassContainer wraps node + log tiles, Orbitron/Exo2 fonts visible |
| Spacing corrections (32/8) | D-04 | Visual pixel diff not automatable in flutter_test | Verify each dialog has `SizedBox(height: 32)` body-to-buttons and `SizedBox(width: 8)` button gap via code grep before commit |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 90s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
