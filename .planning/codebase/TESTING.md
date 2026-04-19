# Testing

**Analysis Date:** 2025-04-19

## Framework

- **Primary:** `flutter_test` (dart test runner)
- **Firestore mocking:** `fake_cloud_firestore` (in-memory Firestore)
- **Auth mocking:** `firebase_auth_mocks`
- **Crypto:** Direct PointyCastle calls (no mocking — real crypto)
- **Run command:** `flutter test`
- **Run single file:** `flutter test test/security/session_wipe_test.dart`

## Test File Organization

```
test/
├── mocks/
│   └── mock_firebase.dart               # Shared fake Firestore + auth setup
├── module_tests/
│   ├── auth_test.dart                   # Auth flow tests
│   ├── encryption_test.dart             # TC011–TC021: AES-GCM + RSA unit tests
│   ├── session_test.dart                # Session state machine tests
│   └── transfer_test.dart              # Transfer repository tests
└── security/
    ├── key_storage_audit_test.dart      # SecureStorage key lifecycle tests
    └── session_wipe_test.dart           # TC-WIPE-001 to TC-WIPE-006: kill-switch tests
```

## Test Coverage Summary

### Security Tests (`test/security/`)

**session_wipe_test.dart** — 6 tests (TC-WIPE-001 to TC-WIPE-006), all passing:

| ID | Test | Validates |
|----|------|-----------|
| TC-WIPE-001 | publicKey deleted from Firestore after session closes | closeReceiverSession() wipes Firestore field |
| TC-WIPE-002 | rsa_key_transfers purged after session closes | Batch-delete clears all key transfer docs |
| TC-WIPE-003 | AES key buffer zeroed after use | `fillRange(0)` wipes Uint8List to zeros |
| TC-WIPE-004 | Session hijack prevented — publicKey null after kill switch | Attacker cannot read key post-wipe |
| TC-WIPE-005 | New session generates different keypair each time | Key ephemeral, not reused |
| TC-WIPE-006 | Notifications purged after session closes | Batch-delete clears rsa_key_received notifications |

### Crypto Tests (`test/module_tests/encryption_test.dart`)

**AES-256-GCM (TC011–TC015):**
- TC011: Encrypt produces non-empty ciphertext distinct from plaintext
- TC012: Decrypt recovers original plaintext
- TC013: AES key is exactly 32 bytes (256 bits)
- TC014: IV is exactly 12 bytes (96 bits)
- TC015: GCM auth tag (16 bytes) appended to ciphertext

**RSA-2048 (TC016–TC019):**
- TC016: RSA-2048 keypair generation succeeds (2040+ bit modulus)
- TC017: RSA-OAEP encrypts AES key → 256-byte output
- TC018: RSA-OAEP decrypts AES key correctly (roundtrip)
- TC019: Wrong private key throws `CryptoException`

**GCM Integrity & Memory (TC020–TC021):**
- TC020: Tampered ciphertext fails GCM authentication (throws)
- TC021: AES key bytes can be zeroed to all-zero Uint8List

## Mocking Patterns

**Firestore:**
```dart
late FakeFirebaseFirestore fakeFirestore;
setUp(() {
  fakeFirestore = FakeFirebaseFirestore();
});
```
Used in: `session_wipe_test.dart`, `transfer_test.dart`

**Real crypto (no mocking):**
`encryption_test.dart` calls `EncryptionService.generateRsaKeyPairSync()` directly in `setUpAll()` to avoid repeated heavy RSA generation.

## Async Patterns

Tests with Firestore operations use `async/await`:
```dart
test('TC-WIPE-001: ...', () async {
  await fakeFirestore.collection('users').doc(userId).set({...});
  // ... act ...
  final result = await fakeFirestore.collection('users').doc(userId).get();
  expect(result.data()!.containsKey('publicKey'), false);
});
```

Synchronous crypto tests use plain `test('...', () { ... })`.

## Coverage Gaps

- `ReceiverScreen` UI flow has no widget tests
- `SenderScreen` encryption flow has no widget tests
- `SessionManager` state transitions not directly unit-tested (tested indirectly via wipe tests)
- `TransferService` chunked reads not covered
- `KeyRepository.selectSenderHandshake()` atomic WriteBatch not covered
- No integration tests for end-to-end sender → receiver flow

## CI

No CI configuration detected (no `.github/workflows/`, `Makefile`, or similar). Tests run manually via `flutter test`.

---

*Testing analysis: 2025-04-19*
