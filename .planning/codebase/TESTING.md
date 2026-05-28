# Testing — CrypTransfer

**Mapped:** 2026-05-28
**Framework:** `flutter_test` (+ `mockito`, `fake_cloud_firestore`, `firebase_auth_mocks`)
**Static analysis:** `flutter analyze` → No issues found (2026-05-26)
**Unit suite:** 29/29 passing (2026-05-26)

---

## 1. Test Tooling

| Package | Role |
|---------|------|
| `flutter_test` | Unit + widget framework |
| `mockito` | Repository / service mocking |
| `fake_cloud_firestore` | In-memory Firestore — used for handshake, transfer, session tests |
| `firebase_auth_mocks` | In-memory Auth — used for `module_tests/auth_test.dart` |
| `flutter_lints` (via `analysis_options.yaml`) | Static analysis |

Mock bootstrap helpers: `test/mocks/mock_firebase.dart`.

---

## 2. Test Layout

```
test/
├── mocks/
│   └── mock_firebase.dart                    Shared fake Firestore + Auth bootstrap
│
├── module_tests/                             "Module-level" unit tests
│   ├── auth_test.dart                        Login / register / logout / error mapping
│   ├── encryption_test.dart                  AES-256-GCM + RSA-2048 (TC011–TC021)
│   ├── session_test.dart                     SessionManager state transitions + stateStream emissions
│   └── transfer_test.dart                    TransferRepository lifecycle, updateReceiverStatus, writeAuditLog (participants)
│
├── security/                                 Security-critical regression suite
│   ├── session_wipe_test.dart                TC-WIPE-001 .. TC-WIPE-006 — the kill-switch suite
│   ├── session_termination_test.dart         Lifecycle-driven termination (paused/detached)
│   ├── mem_safety_test.dart                  registerBuffer / unregisterBuffer / wipeAll invariants
│   └── key_storage_audit_test.dart           FlutterSecureStorage delete semantics
│
├── handshake/
│   ├── handshake_repository_test.dart        sendProposal / acceptProposal (runTransaction) / disconnect (WriteBatch)
│   ├── receiver_prefill_test.dart            Role picker prefill — _pendingPrefilledSender defers selectSender (fix 05-07)
│   └── sender_prefill_test.dart              Mirror tests for sender side
│
├── role_assignment/
│   └── role_conflict_test.dart               Receiver/sender conflict guards
│
├── sender/
│   └── transfer_progress_timeout_test.dart   300s safety timeout — sender doesn't hang forever if receiver never completes cleanup
│
└── vault/
    ├── key_lifecycle_test.dart               RSA key generate / publish / delete
    ├── profile_init_test.dart                user doc bootstrap
    ├── receiver_banner_test.dart             Status banner state machine
    └── vault_gate_test.dart                  Gate before key-vault screen access
```

Total: **18 test files**.

---

## 3. Security Test Cases — Required Coverage

Documented in CLAUDE.md → Completed Features → "Session hijack prevention tested" and "TC-WIPE-001 to TC-WIPE-006 all passing".

| Case ID | Covered behavior |
|---------|-------------------|
| **TC-WIPE-001** | Toggle-off → public key deleted from Firestore, private key wiped from device |
| **TC-WIPE-002** | Back navigation (`PopScope`) wipes session, batch-deletes handshakes |
| **TC-WIPE-003** | App backgrounded / detached → lifecycle observer fires wipe |
| **TC-WIPE-004** | Active transfer locks toggle; close blocked during `locked`/`decrypting` |
| **TC-WIPE-005** | Kill-switch audit log written with `status: 'kill_switch'` + `participants` |
| **TC-WIPE-006** | `selectedSenderUid` deletion propagates → sender stream emits empty → sender `_revertToWaiting()` |

These live in `test/security/session_wipe_test.dart`.

**Encryption suite** (`test/module_tests/encryption_test.dart`):
- **TC011–TC021** — AES-256-GCM encrypt/decrypt round-trip, RSA-2048 wrap/unwrap of AES key, IV handling, ciphertext integrity.

---

## 4. Test Patterns

### 4.1 Repository tests with `fake_cloud_firestore`

```dart
final fake = FakeFirebaseFirestore();
final repo = KeyRepository(firestore: fake);
await repo.selectSenderHandshake(receiverId: 'R', senderId: 'S', publicKey: pk);
final batch = await fake.collection('handshakes').doc('R_S').get();
expect(batch.exists, isTrue);
expect(batch.data()!['status'], equals('handshake_complete'));
```

### 4.2 Session state tests

`test/module_tests/session_test.dart` verifies:
- Every transition emits exactly once on `stateStream`.
- Broadcast stream allows multiple subscribers.
- `wipeSession()` ends in `terminated`.
- `handleLifecycleState(paused)` ends in `terminated`.

### 4.3 Listener regression tests

`test/sender/transfer_progress_timeout_test.dart` is the regression test for the **300 s safety timeout** (Phase 07): sender must not hang indefinitely if the receiver never sets `receiverStatus='saved'` or `cleanup_initiated=true`.

### 4.4 Mocking patterns
- Repositories take their Firestore handle via constructor injection.
- Services (`EncryptionService`, `SessionManager`) are constructed with optional dependencies for tests.
- Native MethodChannel calls are stubbed via `setMockMethodCallHandler` on the `com.example.cryptransfer/security` channel for tests that exercise `isFlagSecureActive` / `clearSession`.

---

## 5. Manual UAT (referenced but not automated)

Some flows have manual UAT signed off in commit messages or CLAUDE.md — automation would require a real device.

| Flow | Status | Source |
|------|--------|--------|
| Sender Step 3 biometric (Face ID / fingerprint) | Manual UAT pending → confirmed by commits `17d8c40`, `1459ad8` | CLAUDE.md Completed Features |
| Phase 07 reactive cleanup sync | UAT 3/3 passed | CLAUDE.md Completed Features |
| Home screen UAT gap fixes (05-06) | Manual flows tested | CLAUDE.md |
| Bidirectional disconnect | Manual UAT | CLAUDE.md |

---

## 6. Static Analysis & Lint Rules

- **`flutter analyze` is the gate.** Must return **No issues found** before non-WIP commit.
- Common fixes that established the rules:
  - `use_build_context_synchronously` → use State's `mounted`, not `context.mounted`.
  - `unnecessary_underscores` → single `_` in throwaway callback params.
  - Deprecation warnings → fix immediately (e.g. `Switch.activeColor` → `activeThumbColor`).
- Lint config: `analysis_options.yaml` with `flutter_lints`.

---

## 7. Silent Guardian — Rule-Based Scanner

`scripts/silent_guardian.ps1` runs the **scanner rules** in CLAUDE.md against `lib/`. This is not a test runner — it's a static-rule auditor that writes a Markdown report to the Obsidian vault.

Each rule maps source pattern → severity:

| Severity | Trigger examples |
|----------|------------------|
| **VERIFIED** | `SecurityLifecycleMixin` present, `compute()` for crypto, `closeReceiverSession` in receiver_screen, `bindSession`/`unbindSession` wired, `kChunkSize` in `transfer_service.dart`, etc. |
| **SECURE** | File contains `compute()` for crypto (positive marker) |
| **WARNING** | `Isolate.run()` for crypto (should be `compute()`); `_encryptFile` missing `registerBuffer` |
| **ISSUE** | Raw `FirebaseFirestore` calls in a screen |
| **CRITICAL** | `debugPrint` with key data |

Run cadence: scheduled via Windows Task Scheduler → `scripts/launch_guardian.bat` → headless PowerShell.

Output:
- `C:\Users\navve\ObsidianVault\CrypTransfer\Security\` — audit report
- `C:\Users\navve\ObsidianVault\CrypTransfer\DailyReports\` — daily summary
- `C:\Users\navve\projects\cryptransfer\report_error.log` — errors

The full rule list lives in **CLAUDE.md → "State Scanner Rules"** and is the canonical source.

---

## 8. Coverage Gaps (known)

These are tracked in CONCERNS.md but worth listing here too:

1. **`compute()` isolate ciphertext** — cannot be `fillRange(0)`'d from the main isolate. Accepted limitation; no test possible.
2. **Broadcast stream race** — if `EncryptionService.bindSession` subscribes *after* a `terminated` event fires, it misses the signal. Worth a future unit test on `SessionManager.stateStream` ordering guarantees.
3. **Native package-name coupling** — no test cross-checks `applicationId` ↔ Kotlin package ↔ MethodChannel namespace ↔ `google-services.json`. Manual.
4. **Phase 2 accessibility items** — no automated touch-target / focus-state tests yet.

---

## 9. Running Tests

```powershell
flutter test                              # full suite
flutter test test/security/               # security suite only
flutter test test/security/session_wipe_test.dart   # single file
flutter analyze                           # static analysis
```

For coverage:
```powershell
flutter test --coverage
# generates coverage/lcov.info
```
