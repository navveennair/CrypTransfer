# Concerns — CrypTransfer

**Mapped:** 2026-05-28
**Scope:** Technical debt, known issues, security gaps, fragile patterns, and pre-release blockers.

Concerns are grouped by category and labeled with severity:

- 🔴 **Blocker** — must fix before next release / production use
- 🟠 **High** — material risk; schedule soon
- 🟡 **Medium** — known limitation; tracked, accepted for now
- 🟢 **Low** — cleanup / hygiene
- ✅ **Resolved** — formerly flagged, verified fixed (kept for memory)

---

## 1. Security Gaps

### 🟡 `compute()` isolate ciphertext not zeroed
- **Where:** `lib/data/services/encryption_service.dart` — encryption + decryption run inside `compute()` (a Flutter helper that uses a `RawReceivePort`-backed isolate).
- **Issue:** The encrypted `Uint8List` is allocated in the isolate's own heap. After `compute()` returns, the main isolate gets a copy back, but the isolate-side copy is unreachable from the main isolate — `fillRange(0)` cannot be called against it from outside.
- **Risk:** Until isolate GC runs, ciphertext bytes remain in process memory. Plaintext is mitigated (see §1.✅ below), but ciphertext + AES key plaintext live briefly in the isolate.
- **Status:** Inherent Dart isolate-model limitation; documented and accepted. Source: `graphify-out/ZERO_REMANENCE_ANALYSIS.md`.
- **Mitigations in place:** main-isolate copy is `fillRange`'d via `SecurityLifecycleMixin.wipeAll()` on every `dispose`/state transition.

### ✅ Sender plaintext zero-wipe — RESOLVED
- **Where:** `lib/presentation/sender/sender_screen.dart:323, 332-333`
- **Pattern:** `registerBuffer(plaintext)` immediately after `TransferService.resolve()` (safety net for throws), then `plaintext.fillRange(0, plaintext.length, 0)` + `unregisterBuffer(plaintext)` after `compute()` returns.
- **Verification:** present in current code; covered by silent-guardian scanner rule "_encryptFile contains registerBuffer → VERIFIED".

### ✅ Session hijack via stale `selectedSenderUid` — RESOLVED
- **Where:** `lib/data/services/encryption_service.dart#closeReceiverSession`
- **Pattern:** kill-switch deletes `selectedSenderUid` from receiver user doc + batch-deletes `handshakes` docs `WHERE receiverId==uid`. Sender stream goes empty → `_revertToWaiting()` clears cached state.
- **Tests:** `test/security/session_wipe_test.dart` TC-WIPE-001..006 all green.

---

## 2. Session Architecture

### ✅ `ReceiverTransferScreen` SessionManager propagation — RESOLVED
- **Previously flagged in CLAUDE.md.** Verified fixed.
- **Where:** `lib/presentation/receiver/receiver_transfer_screen.dart:21, 27, 92-93, 104, 198`
- **Implementation:** `final SessionManager sessionManager;` is now a required constructor arg; `initState` adds a listener via `widget.sessionManager.stateNotifier.addListener(_onSessionStateChanged)`, `dispose` removes it, and `_onSessionStateChanged` pops the screen when `state == SessionState.terminated`.
- **Action:** update CLAUDE.md → move this item from "Known Open Issues" to "Completed Features".

### 🟡 Cross-screen reactive binding fragility
- **Pattern:** `SessionManager.stateStream` (broadcast `StreamController`) is consumed by `EncryptionService.bindSession()` to trigger `closeReceiverSession()` reactively. Works correctly today.
- **Fragility:** any future code path that allocates an `EncryptionService` without calling `bindSession` (or fails to call `unbindSession` on dispose) will silently break kill-switch reactivity. There is no compile-time guarantee.
- **Mitigation suggestion:** add a debug-mode assertion in `closeReceiverSession` that warns if no active subscription is detected.

---

## 3. Pre-Release Blockers (Play Store)

### 🔴 `applicationId` still placeholder
- **Where:** `android/app/build.gradle.kts:43` → `applicationId = "com.example.cryptransfer"`
- **Issue:** `com.example.*` is reserved for examples and **cannot be published to Google Play**.
- **Coupling:** changing `applicationId` requires:
  1. Renaming the Kotlin package in `android/app/src/main/kotlin/com/example/cryptransfer/MainActivity.kt`
  2. Updating MethodChannel namespace `com.example.cryptransfer/security` (referenced in `MainActivity.kt` and `lib/core/utils/security_lifecycle_mixin.dart`)
  3. Regenerating `google-services.json` from Firebase console with new package name (Firebase project `cryptransfer-96e9f`)
  4. Updating any keep rules in `android/app/proguard-rules.pro` that reference `com.example.cryptransfer.*`
- **Status:** Tracked in CLAUDE.md → Roadmap → Pre-Release.

### 🟠 Uncommitted `UI-FIX-SUMMARY.md` at repo root
- **Where:** `UI-FIX-SUMMARY.md` (8.5 KB, dated 2026-05-27)
- **Issue:** ad-hoc summary from Phase 1 UI fix work; not referenced by any other doc; not part of `design-system/`.
- **Action:** either (a) move into `design-system/cryptransfer/PHASE-1-COMPLETION.md` for archive, or (b) delete — content is duplicative of `design-system/cryptransfer/UI-AUDIT-REPORT.md` and the `## Design System` section of `CLAUDE.md`.

### 🟡 Thesis-side items (out of scope for code, in scope for project)
- Chapter 3 thesis update
- Chapter 5 testing results
- Figure numbering
- Acknowledgements shoutout
- **Source:** CLAUDE.md → Roadmap → Pre-Viva. Tracked here so they don't get lost when planning phases.

---

## 4. Design System — Phase 2 Pending

**Status:** Phase 1 complete (commit `6503b66`, 2026-05-27). Phase 2 estimated **7–9 hours**, fully documented in `design-system/cryptransfer/QUICK-FIX-GUIDE.md`. None of these are blockers, but each is a known inconsistency.

| # | Item | Effort | Severity |
|---|------|--------|----------|
| 1 | Extract typography to theme | 1–2 hrs | 🟠 High — currently inline `TextStyle` literals scattered across screens |
| 2 | Standardize glass opacity | 30 min | 🟡 Medium |
| 3 | StepCard visual hierarchy | 1.5 hrs | 🟠 High — affects sender/receiver step clarity |
| 4 | Session state colors | 30 min | 🟡 Medium — partially driven by `CrypButton.sessionState` already |
| 5 | Touch target verification (≥48dp) | 1 hr | 🟠 High — a11y compliance |
| 6 | Focus states for accessibility | 1.5 hrs | 🟠 High — keyboard/screen-reader users |
| 7 | Dark/light mode transitions | 1 hr | 🟢 Low |

**Recommendation:** bundle items 1, 3, 5, 6 into one accessibility/typography phase before Play Store submission; defer 2, 4, 7.

---

## 5. Recently-Discovered Bug Classes (Watch List)

These are not currently broken, but each surfaced as a real bug in recent history. Future code in the same shape should be reviewed against them.

### 🟠 Listener field-name drift
- **Incident:** commit `22a72b6` — sender cleanup listener was checking `status` (string) when the actual signal field is `cleanup_initiated` (boolean). Silent failure; sender hung on "Waiting for receiver…" until 300s timeout.
- **Pattern:** any Firestore listener that filters on a field name typed as a string literal is exposed to schema drift.
- **Suggested guard:** centralize field names as `const` strings in repository classes; reference these from both writers and listeners.

### 🟠 StreamBuilder double-subscription
- **Incident:** receiver Step 3 previously created a new Firestore snapshot stream inline on every rebuild → multiple parallel subscriptions, charges, and race conditions.
- **Fix in place:** stream is now a `Stream` field initialised once in `_onSenderSelected()` and referenced by `StreamBuilder`.
- **Watch list rule:** **never construct `Stream` inside `build()`**. Always init once on State, store as field, pass to `StreamBuilder`.
- **Where to enforce:** any new screen with realtime data.

### 🟠 R8 strip of crypto class names
- **Incident:** PointyCastle reflection-based algorithm lookup would fail in release builds without keep rules.
- **Fix in place:** `android/app/proguard-rules.pro` has explicit keep rules for Flutter engine, Firebase, PointyCastle.
- **Watch list rule:** any new native-reflective dependency (PointyCastle algorithms, Firebase services, MethodChannel codecs) requires a matching `-keep` rule before merging.

### 🟡 Native package-name coupling
- **Pattern:** `applicationId`, Kotlin package, MethodChannel namespace `com.example.cryptransfer/security`, and `google-services.json` all encode the same string. Changing one without the others silently breaks the bridge.
- **Suggested guard:** add a `flutter analyze`-level check or a `silent_guardian.ps1` rule that compares the three.

---

## 6. Recently Resolved (kept for memory, do not re-flag)

| Item | Commit | Note |
|------|--------|------|
| Sender Step 3 biometric flow + transfer upload + proposal idempotency | `1459ad8` | UAT confirmed via subsequent commits |
| Sender cleanup listener field bug | `22a72b6` | Field-name drift fixed |
| Phase 1 UI consistency (20+ hardcoded colors → 0, button systems unified) | `6503b66` | 46 files; `flutter analyze` clean |
| Step 3 biometric error feedback + receiver loop guard | `17d8c40` | followed by `7559047` (wip) → resolved by `1459ad8` |
| Reactive kill-switch binding (SessionManager → EncryptionService) | (multiple) | Replaces manual `closeReceiverSession` call from `wipeSession` |
| Bidirectional disconnect via `disconnectFromUser` WriteBatch | (multiple) | Removes both `connections` sub-collection docs atomically |

---

## 7. Untracked / Stale Files

| File | Status | Recommendation |
|------|--------|----------------|
| `UI-FIX-SUMMARY.md` (root) | Untracked, 2026-05-27 | Move to `design-system/cryptransfer/` archive or delete |
| `.planning/STATE.md` | Modified | Verify in sync with current phase; commit if intentional |
| `CLAUDE.md` | Modified | Should be committed alongside Phase 1 UI fixes if not already |
| `.claude/settings.local.json` | Modified | Review before commit — may contain machine-local paths/permissions |

---

## 8. Performance / Memory Notes

- **64 KB chunked file reads** (`lib/data/services/transfer_service.dart`, `kChunkSize`) keeps RAM bounded for large transfers. Verified — no concern.
- **Plaintext lifecycle:** registered → encrypted → wiped → unregistered, all on main isolate. No concern.
- **Ciphertext lifecycle in isolate:** see §1.🟡 — accepted limitation.
- **Broadcast `StreamController` in `SessionManager`** — broadcast streams do not buffer events. If `EncryptionService.bindSession()` subscribes *after* a `terminated` event fires (unlikely given current wiring, but possible in race conditions), it will miss the signal. Worth a unit test.

---

## Summary

| Severity | Count |
|----------|-------|
| 🔴 Blocker | 1 (applicationId) |
| 🟠 High | 7 (4 design-system a11y items + 3 watch-list rules) |
| 🟡 Medium | 4 |
| 🟢 Low | 1 |
| ✅ Resolved | 6 |

**Top 3 priorities before next release:**
1. Rename `applicationId` away from `com.example.*` (with all 4 coupling fixes).
2. Phase 2 design-system items 1, 3, 5, 6 (a11y + typography).
3. Resolve `UI-FIX-SUMMARY.md` and the 3 other modified-but-uncommitted files.
