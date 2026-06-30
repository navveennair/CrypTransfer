<!-- generated-by: gsd-doc-writer -->
# Testing

CrypTransfer uses the standard Flutter test toolchain (`flutter_test`) together
with Firebase mocking libraries to test repositories, services, and security
behaviours without requiring a live Firebase project.

## Test Framework and Setup

- **Framework**: `flutter_test` (bundled with the Flutter SDK).
- **Firebase mocking**:
  - [`fake_cloud_firestore`](https://pub.dev/packages/fake_cloud_firestore) (`^4.1.0+1`) — in-memory Firestore for repository and security tests.
  - [`firebase_auth_mocks`](https://pub.dev/packages/firebase_auth_mocks) (`^0.15.1`) — mocked `FirebaseAuth` / `MockFirebaseAuth`.
  - [`mockito`](https://pub.dev/packages/mockito) (`^5.4.0`) — used for `MockFirebaseStorage` and other interface mocks.
- **Lints**: `flutter_lints: ^6.0.0`.

These are declared under `dev_dependencies` in `pubspec.yaml`. No additional
setup is required beyond `flutter pub get` — the fakes run entirely in-memory
and do not contact a real Firebase project.

## Running Tests

Run the full suite from the project root:

```bash
flutter test
```

Run a single test file:

```bash
flutter test test/security/session_wipe_test.dart
```

Run all tests in a directory (e.g. all security tests):

```bash
flutter test test/security/
```

Some test files include an explicit `--no-pub` invocation comment for faster
iteration once dependencies are already resolved:

```bash
flutter test test/security/navigation_guard_test.dart --no-pub
```

There is no dedicated `flutter test --coverage` script wired into the project
and no CI workflow configuration (`.github/workflows/`) was found — tests are
currently run locally via `flutter test`.

## Test Organization

Tests live under `test/`, organized by feature area rather than by mirroring
`lib/` 1:1:

| Directory | Covers |
|---|---|
| `test/admin/` | Admin dashboard guard, repository, and chart-aggregation logic |
| `test/handshake/` | Receiver-authorized handshake flow, sender/receiver pre-fill behaviour |
| `test/mocks/` | Shared Firebase/storage test doubles (see below) |
| `test/module_tests/` | Core module tests for auth, encryption, session, and transfer repositories/services |
| `test/role_assignment/` | Sender/receiver role-conflict exception handling |
| `test/security/` | Security-critical lifecycle, kill-switch, key-storage, and navigation-guard tests |
| `test/sender/` | Sender-side stale-key invalidation and transfer-progress timeout behaviour |
| `test/vault/` | RSA key vault lifecycle, profile initialization, and biometric gate behaviour |

### Naming Conventions

- Test files use `_test.dart` suffixes (e.g. `session_wipe_test.dart`,
  `auth_test.dart`, `admin_repository_test.dart`).
- Each `main()` wraps related tests in a `group(...)` block named after the
  feature under test (e.g. `'SESSION WIPE SECURITY TESTS'`,
  `'HANDSHAKE REPOSITORY TESTS'`, `'VAULT KEY LIFECYCLE TESTS'`).
- Individual `test(...)` cases are prefixed with a traceable test-case ID
  matching the project's requirement-tracking scheme, e.g.:
  - `TC-WIPE-001` … `TC-WIPE-009` — kill-switch / session-wipe security tests
  - `TC-SEC-001` … `TC-SEC-011` — key-storage and crypto property audits
  - `TC-MEM-001` — memory-safety / file-picker guards
  - `TC011`–`TC021`, `TC022`–`TC030`, `TC031`–`TC038` — encryption, transfer,
    and session module tests
  - `TC-HAND-07`, `TC-HAND-08` — sender/receiver pre-fill handshake tests
  - `TC-ROLE-01` — role-conflict exception tests
  - `TC-VAULT-01`, `TC-VAULT-05`, `TC-VAULT-06` — vault gate / profile / banner tests
  - `GAP1-01`…`GAP1-03`, `GAP2-01`/`GAP2-02`, `V07-01`…`V07-10` — phase-tracked
    gap-closure stubs (see "Stub Tests" below)
- Some test files end with `-stub` in the test description, indicating a
  placeholder test pending fuller implementation (e.g.
  `test/vault/profile_init_test.dart`, `test/vault/receiver_banner_test.dart`,
  `test/vault/vault_gate_test.dart`, `test/sender/transfer_progress_timeout_test.dart`,
  `test/security/navigation_guard_test.dart`). These verify the underlying
  boolean/state logic in isolation while full widget-level coverage is added
  in later phases.

## Mocking Strategy

Shared Firebase test doubles live in `test/mocks/mock_firebase.dart`:

- `MockFirebaseSetup` — convenience factory exposing:
  - `MockFirebaseSetup.firestore` → a fresh `FakeFirebaseFirestore()` instance
  - `MockFirebaseSetup.auth` → a fresh `MockFirebaseAuth()` instance
- `MockFirebaseStorage` — a `mockito`-based stub implementing
  `FirebaseStorage`, used so repositories that construct
  `FirebaseStorage.instance` (e.g. `TransferRepository`) can be tested without
  a real Firebase app.
- `FakeSecureStorage` — an in-memory `FlutterSecureStorage` override backed by
  a plain `Map<String, String>`, implementing `read`, `write`, `delete`,
  `readAll`, `containsKey`, and `deleteAll`. Used to test private-key
  storage/wipe flows without platform channel calls.

Most test files create a fresh `FakeFirebaseFirestore()` (and
`MockFirebaseAuth()` where auth context is needed) in `setUp()`, so each test
runs against an isolated in-memory database.

Pure-logic tests (e.g. `chart_aggregation_test.dart`,
`role_conflict_test.dart`, parts of `session_wipe_test.dart`) avoid Firebase
mocking entirely and test top-level functions or `Uint8List` buffer
operations directly.

## Notable Security Test Suites

### Session Wipe / Kill Switch — `test/security/session_wipe_test.dart`

Implements **TC-WIPE-001 through TC-WIPE-009**, validating the "Closed
Mailbox" kill-switch behaviour described in the project architecture:

- **TC-WIPE-001**: `publicKey` is deleted from the user's Firestore document
  and `isReadyToReceive` / `sessionActive` are set to `false` after a session
  closes.
- **TC-WIPE-002**: All `handshakes` documents for a receiver are purged
  (batch-deleted) on session close — no "ghost keys" remain.
- **TC-WIPE-003**: AES key buffers (`Uint8List`) are zero-filled
  (`fillRange(0, length, 0)`) after use.
- **TC-WIPE-004**: Session hijack prevention — once `publicKey` is deleted and
  `isReadyToReceive` is `false`, no key material remains for an attacker to
  read.
- **TC-WIPE-005**: Each session generates a distinct (ephemeral) AES key —
  no key reuse across sessions.
- **TC-WIPE-006**: `rsa_key_received` notifications are purged from the
  `notifications` collection on session close.
- **TC-WIPE-007**: `SessionManager.wipeSession()` transitions
  `SessionState` to `terminated`, invokes the `onBuffersWipe` callback exactly
  once, and is idempotent on repeated calls.
- **TC-WIPE-008**: `SecurityLifecycleMixin.wipeAll()`-equivalent logic is safe
  (does not throw) when the registered buffer list is empty.
- **TC-WIPE-009**: The `PopScope.onPopInvokedWithResult` guard only triggers
  `wipeAll()` when `didPop == true`.

### Key Storage Audit — `test/security/key_storage_audit_test.dart`

Implements **TC-SEC-001 through TC-SEC-011**, auditing that no private-key
material leaks into Firestore and that cryptographic primitives satisfy their
expected security properties (e.g. `TC-SEC-001` verifies the private key is
**not** present in the `users` collection after registration and key
generation).

### Session Termination — `test/security/session_termination_test.dart`

Implements **TC-TERM-001** (currently a stub), covering the requirement that
audit logs are written to both participants' `audit_logs` subcollections
*before* any document deletion occurs during end-of-session cleanup.

### Navigation Guard — `test/security/navigation_guard_test.dart`

Implements **GAP1-01 to GAP1-03** (Phase 09 — Navigation Safety), validating
the `canPop` boolean logic for `ReceiverScreen` (e.g. `canPop` must be `false`
while the mailbox is open, regardless of handshake state).

### Memory Safety — `test/security/mem_safety_test.dart`

Implements **TC-MEM-001**, validating that `SenderScreen._pickFile()` uses
`withData: kIsWeb` (not `withData: true`), ensuring file bytes are not loaded
into memory on mobile/desktop platforms.

## Module Tests (`test/module_tests/`)

- **`auth_test.dart`** — `AuthRepository` registration/login error handling
  (e.g. email-already-in-use), using a custom `_EmailInUseAuth` mock.
- **`encryption_test.dart`** — TC011–TC021, exercises the low-level
  `runAesGcmEncrypt` / `runAesGcmDecrypt` top-level functions directly
  (synchronous, avoiding the `compute()` Flutter binding requirement).
- **`session_test.dart`** — TC031–TC038, covers `KeyRepository` and
  `TransferRepository` session-related operations.
- **`transfer_test.dart`** — TC022–TC030, covers `TransferModel`,
  `TransferRepository`, and `EncryptionService` transfer flows.

## Other Test Suites

- **`test/admin/`** — `AdminGuard` route-wrapper tests (D-01 to D-03,
  currently documented as requiring further mock setup), `AdminRepository`
  unit tests (D-04, D-08, D-12), and `aggregateTransferLogs` chart-aggregation
  logic (D-05, D-06) — the latter is a pure-Dart function test with a fixed
  reference date (`2026-06-08`).
- **`test/handshake/`** — `HandshakeRepository` tests, plus
  `ReceiverScreen`/`SenderScreen` constructor-level pre-fill tests
  (`TC-HAND-07`, `TC-HAND-08`) verifying `preFilledSenderUid` /
  `preFilledPartnerUid` parameters are accepted without error.
- **`test/role_assignment/role_conflict_test.dart`** — `TC-ROLE-01`, verifies
  `RoleConflictException` is a proper `AppException` subtype thrown on
  sender/receiver role race conditions.
- **`test/sender/`** — `stale_key_test.dart` (Phase 09, GAP2-01/GAP2-02:
  stale AES key invalidation when the receiver's public key changes
  mid-session) and `transfer_progress_timeout_test.dart` (Phase 07, V07-01 to
  V07-10: pulsing waiting-indicator and reactive cleanup sync UI states —
  currently TODO stubs).
- **`test/vault/`** — `key_lifecycle_test.dart` (RSA keypair
  generation/storage via `AuthRepository`), `profile_init_test.dart`
  (`TC-VAULT-05`: atomic profile/preferences doc creation), and
  `receiver_banner_test.dart` / `vault_gate_test.dart` (`TC-VAULT-06`,
  `TC-VAULT-01`: boolean-logic stubs for banner visibility and biometric gate
  behaviour).
