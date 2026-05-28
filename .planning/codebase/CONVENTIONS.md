# Conventions — CrypTransfer

**Mapped:** 2026-05-28
**Lint config:** `analysis_options.yaml` with `flutter_lints` enabled
**Static analysis status:** `flutter analyze` → No issues found (last verified 2026-05-26)

---

## 1. File & Symbol Naming

| Element | Rule | Example |
|---------|------|---------|
| File | `snake_case.dart` | `lib/data/repositories/key_repository.dart` |
| Class | `PascalCase` | `SessionManager`, `CrypButton`, `SecurityLifecycleMixin` |
| Public member | `lowerCamelCase` | `selectSenderHandshake`, `closeReceiverSession` |
| Private member | `_lowerCamelCase` | `_onToggleReady`, `_handshakeSub`, `_transferStream` |
| Top-level constant | `k` prefix + `lowerCamelCase` | `kChunkSize` |
| Enum cases | `lowerCamelCase` | `SessionState.open`, `SessionState.locked` |
| Firestore collection | `snake_case` | `transfer_logs`, `neutral_handshakes` |
| Firestore field | `lowerCamelCase` (one deliberate exception) | `selectedSenderUid`, `cleanup_initiated` (boolean signal — `snake_case` to flag as a state signal) |

---

## 2. Code Style

### 2.1 Linting
- `flutter_lints` enabled via `analysis_options.yaml`.
- All code must pass `flutter analyze` with **No issues found** before commit.
- Recent fixes that established the rule:
  - `unnecessary_underscores` — never use `__` or `___`; always single `_` (`PageRouteBuilder` callbacks in `splash_screen.dart`).
  - Deprecated `Switch.activeColor` → `activeThumbColor` (Material 3).
  - `use_build_context_synchronously` — never use `context.mounted` in async callbacks; use the State's own `mounted` property.

### 2.2 Material 3 + Theme
- **Use `Theme.of(context).colorScheme.*` exclusively.** No hardcoded colors anywhere.
  - This was enforced by the Phase 1 UI fix (commit `6503b66`, 2026-05-27): 20+ hardcoded colors → 0 across 46 files.
- Canonical palette (defined in `lib/app_theme.dart`):
  - Primary: `#F59E0B` (gold)
  - Secondary: `#FBBF24` (gold lighter)
  - Tertiary / CTA / accent: `#8B5CF6` (purple)
  - Background: `#0F172A` (dark navy)
  - Surface: `#161B22` (GitHub Dark)
- Step indicators use semantic slots:
  - Step 2 → `colorScheme.secondary`
  - Step 3 "Send Key" → `colorScheme.tertiary` + key icon

### 2.3 Button system
- **`CrypButton` only.** The older `GlassButton` has been retired (PR `6503b66`).
- `CrypButton` is a `StatefulWidget`:
  - `_isPressed` drives the scale animation.
  - `HapticFeedback.lightImpact()` on press.
  - `transformAlignment: Alignment.center` on the scale `AnimatedContainer`.
  - `Matrix4.diagonal3Values` (not deprecated `..scale()`).
- `sessionState` parameter overrides face colour + content:
  | State | Face | Icon | Interactable |
  |-------|------|------|--------------|
  | `open` | primary | child widget | yes |
  | `locked` | amber | lock | no |
  | `decrypting` | primary | spinner | no |
  | `terminated` | error red | block | no |

### 2.4 Spacing & layout
- Material 3 default spacing scale (4 / 8 / 16 / 24 / 32 dp).
- Glassmorphic surfaces follow opacity rules in `design-system/cryptransfer/MASTER.md`.
- Touch targets — Phase 2 will verify ≥ 48 dp on every interactive element.

---

## 3. Architectural Patterns

### 3.1 Repository pattern
- Repositories live in `lib/data/repositories/`.
- Pure Firestore I/O. Return `Future<T>` or `Stream<T>` — no Flutter widgets.
- Field names referenced from `lib/core/constants/firebase_constants.dart` where possible (see §6 on field-name drift).

### 3.2 Atomic operations
- **`runTransaction`** for read-then-write where TOCTOU matters.
  - Example: `HandshakeRepository.acceptProposal()` — reads pending status, writes connected status only if still pending.
- **`WriteBatch`** for multi-doc atomic writes.
  - `KeyRepository.selectSenderHandshake()` — single batch: receiver user doc + `handshakes/{rid}_{sid}` doc.
  - `HandshakeRepository.disconnectFromUser()` — single batch: both `connections` sub-collection docs.
  - Kill-switch — single batches for `handshakes WHERE receiverId==uid` delete, and `notifications` delete.

### 3.3 Deterministic doc IDs
- `handshakes/{receiverId}_{senderId}` — idempotent re-sends, no duplicates.
- `neutral_handshakes/{proposerId}_{partnerId}` — same.
- `streamHandshakeWithUser(partnerUid)` merges both `${a}_${b}` and `${b}_${a}` streams via a single-subscription `StreamController.broadcast()`.

### 3.4 Service layer
- `EncryptionService`, `TransferService`, `TransferLogService` — stateful or compute-heavy logic with no widget references.
- All crypto runs inside `compute()` isolates (migrated from `Isolate.run()`; this was Guardian WARNING).
- `EncryptionService.bindSession(stateStream, uid)` subscribes to `SessionManager.stateStream` and auto-fires `closeReceiverSession` on `SessionState.terminated`. **No screen-level wiring of crypto cleanup is required.**

### 3.5 Reactive UI
- StreamBuilders MUST be backed by a `Stream` field stored on `State`, initialised once (`initState`, `_onSenderSelected`, etc.).
- **Never** construct `Stream` inside `build()` — caused the receiver double-subscription bug; root rule now.

### 3.6 Lifecycle hygiene
- Mix in `SecurityLifecycleMixin` on every screen handling key material.
- `registerBuffer(uint8List)` before allocating; `unregisterBuffer` after explicit `fillRange(0)`; `wipeAll()` runs automatically on `dispose()`.
- `PopScope` (Flutter 3.10+) on screens that need cleanup on back-nav (e.g. `ReceiverScreen`).
- `WidgetsBindingObserver.didChangeAppLifecycleState` for backgrounded/detached → delegate to `SessionManager.handleLifecycleState`.

---

## 4. Error Handling

### 4.1 Try / catch / finally
- **Spinners reset in `finally`.** Established when `HomeScreen` accept-spinner reset was fixed.
- Async callbacks check `mounted` before touching `BuildContext` or calling `setState`.
- Use the State's own `mounted` property in async callbacks. **Do not use `context.mounted`** — analyzer warns and the State's `mounted` is the canonical signal.

```dart
Future<void> _doThing() async {
  setState(() => _busy = true);
  try {
    await repo.something();
  } catch (e) {
    if (!mounted) return;
    _showErrorSnackBar('Failed: $e');
  } finally {
    if (mounted) setState(() => _busy = false);
  }
}
```

### 4.2 Typed exceptions
- `lib/core/errors/app_exceptions.dart` — `KeyNotFoundException`, etc.
- Repositories throw typed exceptions; screens map them to snackbars.

### 4.3 Snackbar helpers (extracted, 2026-05-26)
- `_showErrorSnackBar(String)`, `_showInfoSnackBar(String)`, `_showErrorMessage(String)` on screens that show many.
- Originally 7 verbose `ScaffoldMessenger.showSnackBar(...)` invocations on `HomeScreen` → consolidated to 3 helpers; 28 LOC → 7 LOC.
- Pattern: each helper centralises its own `mounted` check.

### 4.4 Stream error handling
- `StreamBuilder.builder` always handles `snapshot.hasError`. Established when Active Connections silently swallowed stream errors.

---

## 5. Security Conventions

These are not optional. They are scanner-enforced via `scripts/silent_guardian.ps1` (rule list lives in CLAUDE.md → "State Scanner Rules").

1. **`SecurityLifecycleMixin` on every screen handling key material.** Auto-wipes on `dispose`.
2. **`compute()` only** for crypto. `Isolate.run()` → flag WARNING.
3. **`registerBuffer` + explicit `fillRange(0)` + `unregisterBuffer`** for sender plaintext after `compute()`. Missing → WARNING ("plaintext remanence gap"). Present → VERIFIED.
4. **`FLAG_SECURE` pre-flight** via `SecurityLifecycleMixin.isFlagSecureActive()` before chunk reads in `SenderScreen._encryptFile`. Aborts if false.
5. **No `debugPrint` of key data.** Triggers CRITICAL flag.
6. **No raw `FirebaseFirestore` calls in screens.** Always via a repository. Triggers ISSUE flag.
7. **Kill-switch invariants** (receiver_screen.dart specific):
   - Contains `closeReceiverSession` → VERIFIED (Closed Mailbox)
   - Contains `didChangeAppLifecycleState` → VERIFIED (lifecycle auto-wipe)
   - Contains `SessionManager` → VERIFIED
   - Contains `bindSession` and `unbindSession` calls → VERIFIED (reactive binding wired)
   - Contains `activeSenderUid` / `selectedSenderUid` → VERIFIED (session isolation)
8. **Sender flow invariants** (sender_screen.dart specific):
   - Contains `TransferService.resolve` → VERIFIED (chunked reads)
   - Contains `isFlagSecureActive` → VERIFIED (Kotlin pre-flight)
   - Contains `_handshakeSub` and `_WaitingForConnectionWidget` → VERIFIED (receiver-authorized stream)
   - Contains `_revertToWaiting` → VERIFIED (kill-switch revert)

---

## 6. Field-Name Drift Avoidance

This is a recently-discovered bug class (commit `22a72b6`): a Firestore listener filtered on `status` when the actual signal field is `cleanup_initiated`. Silent failure.

**Rule:** any field referenced by both a writer and a listener should be a centralised `const String`. Today this is partially in `lib/core/constants/firebase_constants.dart` (collection names) and partially inline. Treat any new shared field as a candidate for promotion to a constant.

---

## 7. Comments & Documentation

- **Default: no comments.** Names should carry the meaning.
- Add a one-line comment only when the *why* is non-obvious — a hidden invariant, a workaround, a subtle ordering constraint.
  - Example (`receiver_transfer_screen.dart:92`): `// Wire up kill-switch: pop immediately if SessionManager fires terminated.`
- Never narrate what the code does in comments.
- `CLAUDE.md` is the canonical architectural doc — don't duplicate large sections in code.
- Per-page UI overrides go in `design-system/cryptransfer/pages/`.

---

## 8. Logging

- `debugPrint(...)` only. Never `print(...)`.
- Never include key material, ciphertext, IVs, or full payloads.
- Audit-relevant events go to Firestore `transfer_logs` (with a `participants` array) via `TransferRepository.writeAuditLog()` — not to `debugPrint`.

---

## 9. Imports & Module Boundaries

- Presentation may import data + core.
- Data may import core. **Data must not import presentation.**
- Core must not import data or presentation.
- The `SessionState` extraction (`lib/core/utils/session_state.dart`) was specifically to break a circular import between `SessionManager` (core) and `EncryptionService` (data).

---

## 10. Native Bridge Convention

- MethodChannel namespace: `com.example.cryptransfer/security`. **Coupled to `applicationId`** — see CONCERNS §3.
- Method name convention: lowerCamelCase verb (`isFlagSecureActive`, `clearSession`).
- Dart side lives in `SecurityLifecycleMixin` (queries) or other dedicated wrappers.
- Native side returns plain types only (`Boolean`, `String`, `null`).

---

## 11. Git Hygiene

- `key.properties` is `.gitignore`d; never commit secrets.
- Commit messages follow `<type>: <imperative>` (e.g. `fix: implement critical UI/UX fixes for consistency`).
- WIP commits prefixed `wip:` (e.g. `wip: sender-step3 UAT pending`); subsequent commits should resolve and reference them.
- `flutter analyze` clean before every non-WIP commit.

---

## 12. Anti-Patterns (avoid)

- ❌ Hardcoded colors (`Colors.red`, `Color(0xFF…)`) — always `Theme.of(context).colorScheme.*`.
- ❌ `GlassButton` — retired; use `CrypButton`.
- ❌ `Isolate.run()` for crypto — use `compute()`.
- ❌ `context.mounted` in async callbacks — use the State's `mounted`.
- ❌ Inline `Stream` construction in `build()` — store on State.
- ❌ Inline field-name string literals shared across writer + listener — promote to constant.
- ❌ Raw `FirebaseFirestore.instance` calls inside screens — use a repository.
- ❌ Skipping `_onSenderSelected` because of unrelated `KeyNotFoundException` — defer via `_pendingPrefilledSender` (fix 05-07).
- ❌ Random emoji in UI text or commit messages.
