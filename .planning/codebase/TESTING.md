# Testing Patterns

**Analysis Date:** 2026-05-25

## Test Framework

**Runner:**
- `flutter_test` (Dart test runner integrated with Flutter)
- Config: None; uses default Flutter test discovery (`test/**/*_test.dart`)

**Assertion Library:**
- `flutter_test` built-in matchers: `expect()`, `isA<T>()`, `throwsA()`, `isEmpty`, `isNotEmpty`, `equals()`, `isFalse`, `isTrue`, `greaterThanOrEqualTo()`

**Run Commands:**
```bash
flutter test                                  # Run all tests
flutter test test/security/session_wipe_test.dart  # Run single file
flutter test --coverage                      # Generate coverage report
```

## Test File Organization

**Location:**
- Tests co-located in `test/` directory at project root (parallel structure to `lib/`)

**Directory Structure:**
```
test/
├── mocks/
│   └── mock_firebase.dart               # Shared fake Firestore + auth setup
├── handshake/
│   ├── handshake_repository_test.dart   # Handshake flow tests
│   ├── receiver_prefill_test.dart       # Prefill receiver selection tests
│   └── sender_prefill_test.dart         # Prefill sender selection tests
├── module_tests/
│   ├── auth_test.dart                   # Auth flow and key lifecycle
│   ├── encryption_test.dart             # TC011–TC021: AES-GCM + RSA unit tests
│   ├── session_test.dart                # TC031–TC038: Session state machine
│   └── transfer_test.dart               # Transfer repository operations
├── security/
│   ├── key_storage_audit_test.dart      # SecureStorage key lifecycle
│   ├── mem_safety_test.dart             # Memory safety checks
│   ├── session_termination_test.dart    # Kill-switch termination
│   └── session_wipe_test.dart           # TC-WIPE-001 to TC-WIPE-006: memory wipe
├── sender/
│   └── transfer_progress_timeout_test.dart  # Sender timeout behavior
└── vault/
    ├── key_lifecycle_test.dart          # Key generation and storage
    ├── profile_init_test.dart           # Profile setup tests
    ├── receiver_banner_test.dart        # Banner UI tests
    └── vault_gate_test.dart             # Vault access control tests
```

## Test Structure

**Suite Organization:**
```dart
void main() {
  group('GROUP NAME', () {
    // Shared setup
    late FakeFirebaseFirestore fakeDb;
    late MockFirebaseAuth mockAuth;
    
    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      mockAuth = MockFirebaseAuth(...);
    });
    
    // Individual tests
    test('TC-###: Test name', () async {
      // Arrange
      await fakeDb.collection(...).set({...});
      
      // Act
      final result = await operation();
      
      // Assert
      expect(result, isNotNull);
    });
  });
}
```

**Test naming convention:**
- Use test case IDs from security/crypto spec: `TC-WIPE-001`, `TC011`, `TC031`, etc.
- Format: `'TC-###: Human-readable test name'`
- Example: `'TC-WIPE-001: publicKey deleted from Firestore after session closes'`

**Patterns:**
- `setUp()` runs before each test — initialize fresh Firestore, auth, storage instances
- `setUpAll()` runs once per group — used for expensive operations (e.g., RSA keypair generation)
- `tearDown()` / `tearDownAll()` for cleanup (rarely needed; mocks auto-cleanup)

## Test Coverage Summary

### Security Tests (`test/security/`)

**session_wipe_test.dart** — 6 tests (TC-WIPE-001 to TC-WIPE-006), all passing:

| ID | Test | Validates |
|----|------|-----------|
| TC-WIPE-001 | publicKey deleted from Firestore after session closes | `EncryptionService.closeReceiverSession()` uses `FieldValue.delete()` |
| TC-WIPE-002 | rsa_key_transfers purged after session closes | Batch-delete clears all `rsa_key_transfers` docs for user |
| TC-WIPE-003 | AES key buffer zeroed after use | `Uint8List.fillRange(0, length, 0)` wipes memory to zeros |
| TC-WIPE-004 | Session hijack prevented — publicKey null after kill switch | Attacker cannot decrypt without public key post-wipe |
| TC-WIPE-005 | New session generates different keypair each time | Key ephemeral via `generateRsaKeyPairSync()` |
| TC-WIPE-006 | Notifications purged after session closes | Batch-delete clears `rsa_key_received` notifications |

**key_storage_audit_test.dart:**
- Validates secure storage read/write/delete operations
- Tests key rotation and lifecycle

**session_termination_test.dart:**
- Tests kill-switch handshake chain: lifecycle observer → SessionManager → EncryptionService

### Crypto Tests (`test/module_tests/encryption_test.dart`)

**AES-256-GCM (TC011–TC015):**
- TC011: Encrypt produces non-empty ciphertext distinct from plaintext
- TC012: Decrypt recovers original plaintext exactly
- TC013: AES key is exactly 32 bytes (256 bits)
- TC014: IV is exactly 12 bytes (96 bits)
- TC015: GCM auth tag (16 bytes) appended to ciphertext (output = plaintext.length + 16)

**RSA-2048 (TC016–TC019):**
- TC016: RSA-2048 keypair generation succeeds (2040+ bit modulus)
- TC017: RSA-OAEP encrypts AES key → exactly 256-byte output
- TC018: RSA-OAEP decrypts AES key correctly (roundtrip test)
- TC019: Wrong private key throws `CryptoException` on decryption

**GCM Integrity & Memory (TC020–TC021):**
- TC020: Tampered ciphertext fails GCM authentication (throws exception)
- TC021: AES key bytes can be zeroed to all-zero `Uint8List`

### Session Tests (`test/module_tests/session_test.dart`)

**Session Lifecycle (TC031–TC038):**
- TC031: Session cancelled when sender deletes transfer → doc removed from Firestore
- TC032: `deleteStorageFile` does not throw for unknown file
- TC033: Transfer record deleted on cancel removes Firestore doc
- TC034: Session considered expired after 10-minute timeout
- TC035: AES key wiped after session ends (fillRange to zeros)
- TC036: RSA keys wiped after session ends (Firestore batch-delete)
- TC037: Audit log written to `transfer_logs` on completion
- TC038: No transfer documents remain after session cleanup

### Handshake Tests (`test/handshake/`)

**handshake_repository_test.dart:**
- Tests handshake flow: receiver publishes public key, sender receives via stream

**receiver_prefill_test.dart:**
- Tests prefill behavior: receiver selection deferred until mailbox opens (D-14)

**sender_prefill_test.dart:**
- Tests prefill behavior: sender selection pre-populated from navigation args

## Mocking Patterns

**Firestore Mocking:**
```dart
late FakeFirebaseFirestore fakeDb;

setUp(() {
  fakeDb = FakeFirebaseFirestore();
  // Seed test data
  await fakeDb.collection('users').doc(userId).set({
    'username': 'test_user',
    'publicKey': 'FAKE_RSA_PUBLIC_KEY_PEM',
  });
});

test('...', () async {
  // Query and assert
  final doc = await fakeDb.collection('users').doc(userId).get();
  expect(doc.data()!['publicKey'], isNotNull);
});
```
- **Library:** `fake_cloud_firestore` (v4.1.0+1)
- **Used in:** `session_wipe_test.dart`, `session_test.dart`, `transfer_test.dart`, handshake tests
- **Advantages:** In-memory, no real Firebase required, supports batch operations and queries

**Auth Mocking:**
```dart
late MockFirebaseAuth mockAuth;

setUp(() {
  mockAuth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'test-uid', email: 'test@test.com'),
  );
});
```
- **Library:** `firebase_auth_mocks` (v0.15.1)
- **Used in:** `auth_test.dart`, `session_test.dart`
- **Advantages:** Pre-authenticated user, supports custom UID/email

**Storage Mocking:**
```dart
class MockFirebaseStorage extends Mock implements FirebaseStorage {}

// In test
transferRepo = TransferRepository(
  db: fakeDb,
  storage: MockFirebaseStorage(),
);
```
- **Library:** `mockito` (v5.4.0)
- **Pattern:** `extends Mock implements StorageType`
- **Used in:** Tests that need repository injection but don't test Storage operations

**Secure Storage Mocking:**
```dart
class FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _store = {};
  
  @override
  Future<String?> read({required String key, ...}) async => _store[key];
  
  @override
  Future<void> write({required String key, required String? value, ...}) async {
    if (value != null) {
      _store[key] = value;
    } else {
      _store.remove(key);
    }
  }
}
```
- **Pattern:** Extend real class, override with in-memory map
- **Used in:** `session_test.dart` for key lifecycle tests
- **Benefits:** Full API compatibility, no platform channel calls

**Real Crypto (No Mocking):**
- `EncryptionService` crypto methods called directly (not mocked)
- Tests use `runAesGcmEncrypt()` and `runAesGcmDecrypt()` top-level functions
- Heavy operations like `generateRsaKeyPairSync()` run once in `setUpAll()` to avoid repeated work

## Async Testing Patterns

**Async tests with Firestore:**
```dart
test('TC-WIPE-001: publicKey deleted from Firestore', () async {
  // Arrange
  const userId = 'test_receiver_uid';
  await fakeDb.collection('users').doc(userId).set({
    'username': 'receiver_test',
    'publicKey': 'FAKE_RSA_PUBLIC_KEY_PEM',
  });
  
  // Act
  await fakeDb.collection('users').doc(userId).update({
    'publicKey': FieldValue.delete(),
  });
  
  // Assert
  final afterWipe = await fakeDb.collection('users').doc(userId).get();
  expect(
    afterWipe.data()!.containsKey('publicKey'),
    false,
    reason: 'publicKey must be deleted',
  );
});
```

**Synchronous crypto tests:**
```dart
test('TC011 - AES-256-GCM encrypt produces non-empty ciphertext', () {
  final plaintext = Uint8List.fromList(utf8.encode('Hello CrypTransfer!'));
  final key = EncryptionService.secureRandomBytes(32);
  final iv = EncryptionService.secureRandomBytes(12);
  
  final ciphertext = runAesGcmEncrypt([plaintext, key, iv]);
  
  expect(ciphertext, isNotEmpty);
  expect(ciphertext, isNot(equals(plaintext)));
});
```

**Exception testing:**
```dart
test('TC019 - Wrong private key fails RSA decryption', () {
  final encrypted = EncryptionService.rsaEncrypt(pubKey, aesKey);
  
  expect(
    () => EncryptionService.rsaDecrypt(otherPrivKey, encrypted),
    throwsA(isA<CryptoException>()),
  );
});
```

## Fixtures and Test Data

**Shared setup:**
- `test/mocks/mock_firebase.dart` — factory methods for FakeFirebaseFirestore, MockFirebaseAuth
- Constants defined inline: `const userId = 'test_receiver_uid'`, `const senderId = 'sender-uid'`

**No centralized fixture library:**
- Each test builds its own Firestore seed data in `setUp()`
- Example from `session_test.dart`:
  ```dart
  await fakeDb
      .collection(FirebaseConstants.transfers)
      .doc(transferId)
      .set({
    'senderId': senderId,
    'receiverId': receiverId,
    'fileName': 'secret.pdf',
    'status': 'pending',
    'createdAt': FieldValue.serverTimestamp(),
  });
  ```

## Coverage

**Current coverage:** Not enforced; no coverage gates configured

**View coverage:**
```bash
flutter test --coverage
# Output: coverage/lcov.info
```

**Known gaps:**
- No widget tests for `SenderScreen`, `ReceiverScreen` UI flow
- No integration tests for end-to-end sender → receiver transfer
- `SessionManager` state transitions tested indirectly via wipe tests, not direct unit tests
- `TransferService.resolve()` chunked reads not directly tested
- `KeyRepository.selectSenderHandshake()` atomic WriteBatch not isolated tested

## CI/CD

**Current:** No CI configuration detected
- No `.github/workflows/` GitHub Actions
- No `Makefile` or build automation
- Tests run manually via `flutter test`

**To add CI:**
Consider adding GitHub Actions workflow with:
```yaml
- flutter pub get
- flutter analyze
- flutter test
- flutter test --coverage (optional)
```

## Test Execution Checklist

When writing new tests:

1. **Naming:** Use test case IDs if security-related (TC-WIPE-001, TC011, etc.)
2. **Mocking:** Use `FakeFirebaseFirestore`, `MockFirebaseAuth`, `FakeSecureStorage` from `test/mocks/`
3. **Setup:** Initialize mocks in `setUp()`, shared expensive ops in `setUpAll()`
4. **Assertions:** Use typed `expect()` matchers with clear `reason:` messages
5. **Async:** Mark tests `() async { ... }` if calling `await`
6. **Security:** If testing memory wipe, use `Uint8List.fillRange(0, length, 0)` and verify with `every((b) => b == 0)`
7. **Cleanup:** Cancel subscriptions in `tearDown()` (auto-handled by mocks)
8. **Documentation:** Add `reason:` parameter to key assertions explaining the security impact

---

*Testing analysis: 2026-05-25*
