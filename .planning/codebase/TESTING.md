# Testing
_Last updated: 2026-06-15_

## Framework

**Runner:**
- `flutter_test` (SDK built-in)
- Config: none — uses Flutter's default test runner; no `jest.config.*` or `vitest.config.*`

**Assertion Library:**
- `flutter_test` matchers (`expect`, `isTrue`, `isFalse`, `isNull`, `isNotNull`, `isA<T>()`, `equals`, `isEmpty`, `isNotEmpty`, `throwsA`, `returnsNormally`, `completes`, `throwsException`)

**Mock / Fake Libraries:**
- `fake_cloud_firestore: ^4.1.0+1` — in-memory Firestore for repository tests (no real Firebase app required)
- `firebase_auth_mocks: ^0.15.1` — `MockFirebaseAuth` + `MockUser` for auth repository tests
- `mockito: ^5.4.0` — `Mock` base class for stub implementations (e.g. `MockFirebaseStorage`)
- `build_runner: ^2.4.0` — required for Mockito codegen if `@GenerateMocks` annotations are added

**Run Commands:**
```bash
flutter test                              # Run all tests
flutter test test/module_tests/           # Run module tests only
flutter test test/security/               # Run security tests only
flutter test test/path/to/file_test.dart --no-pub  # Run a single test file
flutter test --coverage                   # Generate coverage report
```

## Structure

**Location:**
- All tests live under `test/` (separate from `lib/`, not co-located with source)

**Subdirectory Organization:**
```
test/
├── mocks/
│   └── mock_firebase.dart           # Shared fakes: MockFirebaseSetup, MockFirebaseStorage, FakeSecureStorage
├── admin/
│   ├── admin_guard_test.dart        # AdminGuard widget stubs (TODO — not yet implemented)
│   ├── admin_repository_test.dart   # AdminRepository unit tests
│   └── chart_aggregation_test.dart  # Chart data aggregation logic
├── handshake/
│   ├── handshake_repository_test.dart  # HandshakeRepository CRUD + stream tests
│   ├── receiver_prefill_test.dart      # Receiver prefill deferred sender selection
│   └── sender_prefill_test.dart        # Sender prefill path
├── module_tests/
│   ├── auth_test.dart               # AuthRepository registration/login/logout (TC001–TC010)
│   ├── encryption_test.dart         # AES-GCM + RSA-OAEP crypto primitives (TC011–TC021)
│   ├── session_test.dart            # Session lifecycle via Firestore (TC031–TC038)
│   └── transfer_test.dart           # Transfer Firestore doc lifecycle (TC022–TC030)
├── role_assignment/
│   └── role_conflict_test.dart      # Dual-role conflict detection
├── security/
│   ├── key_storage_audit_test.dart  # SecureStorage key lifecycle auditing
│   ├── mem_safety_test.dart         # Memory safety: null-path guard, buffer wipe (TC-MEM-001)
│   ├── navigation_guard_test.dart   # canPop logic, session-lock guard (GAP1-xx stubs)
│   ├── session_termination_test.dart # Kill-switch + cleanup ordering (TC-TERM-001–008)
│   └── session_wipe_test.dart       # Session wipe state machine (TC-WIPE-001–009)
├── sender/
│   ├── stale_key_test.dart          # Stale AES key invalidation logic (GAP2/GAP3 stubs)
│   └── transfer_progress_timeout_test.dart  # 300s sender safety timeout
└── vault/
    ├── key_lifecycle_test.dart      # RSA key regenerate/delete ordering + fingerprinting
    ├── profile_init_test.dart       # Profile doc initialization
    ├── receiver_banner_test.dart    # Receiver notification banner
    └── vault_gate_test.dart         # Biometric vault gate logic
```

## Test Types

**Unit Tests (primary):**
- Repository logic tested against `FakeFirebaseFirestore` — no real Firebase required
- Crypto primitives (`runAesGcmEncrypt`, `runAesGcmDecrypt`, `rsaEncrypt`, `rsaDecrypt`) called directly (synchronous top-level functions) to avoid `compute()` Flutter binding dependency
- Pure logic tests mirror production guards verbatim (e.g. `PopScope` guard, `!done || sessionEnded` navigation guard)
- `SessionManager` state machine tested directly without widget environment

**Widget Tests (limited/stub):**
- `admin_guard_test.dart` contains `testWidgets` stubs with TODO bodies — not yet implemented
- Widget tests that need platform channels call `TestWidgetsFlutterBinding.ensureInitialized()` in `setUpAll`

**Integration / E2E Tests:**
- Not present in the test suite — integration covered by manual UAT documented in `.planning/phases/*/HUMAN-UAT.md`

## Mocking

**Shared mocks — always import from `test/mocks/mock_firebase.dart`:**

```dart
import '../mocks/mock_firebase.dart';

// In-memory Firestore (no Firebase app init needed)
final fakeDb = FakeFirebaseFirestore();

// Mock auth with a pre-signed-in user
final mockAuth = MockFirebaseAuth(
  signedIn: true,
  mockUser: MockUser(uid: 'sender-uid', email: 'sender@test.com'),
);

// In-memory FlutterSecureStorage (Map-backed, overrides all channel calls)
final fakeStorage = FakeSecureStorage();

// Mockito stub for FirebaseStorage (only needed so constructor doesn't hit instance)
class MockFirebaseStorage extends Mock implements FirebaseStorage {}
```

**Injecting into repositories:**
```dart
final repo = TransferRepository(db: fakeDb, storage: MockFirebaseStorage());
final keyRepo = KeyRepository(db: fakeDb, auth: mockAuth, secure: fakeStorage);
```

**Custom test-local fakes:**
- `_EmailInUseAuth extends MockFirebaseAuth` — overrides `createUserWithEmailAndPassword` to throw `FirebaseAuthException(code: 'email-already-in-use')`
- `_WrongPasswordAuth extends MockFirebaseAuth` — overrides `signInWithEmailAndPassword` to throw wrong-password
- `_ThrowingBatchFirestore extends FakeFirebaseFirestore` — overrides `batch()` to return a `_ThrowingWriteBatch` that throws on `commit()` (ordering tests)
- `_ThrowingWriteBatch extends Fake implements WriteBatch` — no-op mutations, throws on `commit()`

**MethodChannel stubs (for tests involving platform channels):**
```dart
setUpAll(() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/google_sign_in'),
    (_) async => null,
  );
});
```

**What to mock:**
- All Firebase services (Firestore, Auth, Storage) — always use fakes/mocks
- `FlutterSecureStorage` — use `FakeSecureStorage` from `test/mocks/mock_firebase.dart`
- Platform channels (GoogleSignIn, security MethodChannel) — use `setMockMethodCallHandler`

**What NOT to mock:**
- `EncryptionService` crypto primitives — call top-level functions directly (`runAesGcmEncrypt`, `runAesGcmDecrypt`, `EncryptionService.rsaEncrypt`, `EncryptionService.rsaDecrypt`)
- `SessionManager` — instantiate directly; it has no external dependencies
- `FirebaseConstants` — use the real class (it's pure constants)

## Coverage

**Requirements:** No enforced coverage target
**Coverage generation:**
```bash
flutter test --coverage
# Output: coverage/lcov.info
```
No CI coverage gate or threshold is configured.

## Key Test Files

| File | What it tests |
|------|---------------|
| `test/mocks/mock_firebase.dart` | Shared `FakeFirebaseFirestore`, `MockFirebaseStorage`, `FakeSecureStorage` fakes used by all tests |
| `test/module_tests/auth_test.dart` | `AuthRepository` registration (TC001–TC003), login (TC004–TC007), logout (TC008–TC010); uses custom `_EmailInUseAuth` and `_WrongPasswordAuth` fakes |
| `test/module_tests/encryption_test.dart` | AES-256-GCM encrypt/decrypt (TC011–TC015), RSA-2048 keypair + OAEP encrypt/decrypt (TC016–TC019), GCM tamper detection (TC020), memory wipe (TC021); calls top-level isolate functions directly |
| `test/module_tests/transfer_test.dart` | Transfer Firestore doc creation/read/update (TC022–TC030); `notifyReceiver`, `markReceived`, `writeFinalAuditLog` |
| `test/module_tests/session_test.dart` | Session lifecycle (TC031–TC038); `deleteTransfer`, `wipeAllSessionKeys`, `writeFinalAuditLog`; uses seeded Firestore docs |
| `test/security/session_wipe_test.dart` | Kill-switch state machine (TC-WIPE-001–009); Firestore wipe, batch-delete, AES zero-fill, `SessionManager.wipeSession()` idempotency, `PopScope` guard logic |
| `test/security/session_termination_test.dart` | Cleanup sequencing (TC-TERM-001–005, 008); audit-log-before-delete ordering, `object-not-found` swallow, `WriteBatch` atomicity, sender `!snapshot.exists` guard |
| `test/security/mem_safety_test.dart` | `kIsWeb` platform gate (TC-MEM-001a/b), buffer registry wipe of 64KB plaintext + key + IV (TC-MEM-001c) |
| `test/security/navigation_guard_test.dart` | `canPop` logic (GAP1-01), session-lock SnackBar guard (GAP1-02) — logic stubs, no widget pump |
| `test/handshake/handshake_repository_test.dart` | `HandshakeRepository` CRUD: `sendProposal`, `acceptProposal`, `rejectProposal`, `cancelProposal`; stream tests for `streamIncomingPending`, `streamActiveConnectionsAsProposer/Partner`, `streamProposalOutcome` (TC-HAND-01 to 06c) |
| `test/vault/key_lifecycle_test.dart` | `AuthRepository.computeFingerprint`, `regenerateKeyPair`, `deleteKeyPair` ordering with `_ThrowingBatchFirestore`, `updateLastVaultAccess` |
| `test/sender/stale_key_test.dart` | Stale AES key wipe logic (GAP2-01/02/03), Change File wipe state model (GAP3-02) — pure logic stubs |
| `test/admin/admin_guard_test.dart` | `AdminGuard` widget stubs — `testWidgets` with TODO bodies; not yet implemented (requires injectable `AuthRepository`) |

## Test Naming Convention

- Group names describe the feature/class: `'Session Lifecycle (TC031–TC038)'`, `'HANDSHAKE REPOSITORY TESTS'`
- Test names always include the TC ID: `'TC031 - Session cancelled when sender deletes transfer'`
- Security tests print a pass line using `// ignore: avoid_print` + `print('✅ TC-WIPE-001 PASSED: ...')` for CI log visibility

## Setup Patterns

**Standard setUp:**
```dart
setUp(() async {
  fakeDb = FakeFirebaseFirestore();
  mockAuth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: senderId, email: 'sender@test.com'),
  );
  fakeStorage = FakeSecureStorage();
  repo = TransferRepository(db: fakeDb, storage: MockFirebaseStorage());
  // Seed required Firestore docs inline
  await fakeDb.collection('transfers').doc(transferId).set({...});
});
```

**`setUpAll` for heavy operations:**
```dart
setUpAll(() {
  // RSA key generation is synchronous but ~2–5s — generate once per group
  final keyPair = EncryptionService.generateRsaKeyPairSync();
  pubKey = keyPair.publicKey as RSAPublicKey;
  privKey = keyPair.privateKey as RSAPrivateKey;
});
```

**`setUpAll` for widget binding:**
```dart
setUpAll(() {
  TestWidgetsFlutterBinding.ensureInitialized();
});
```
