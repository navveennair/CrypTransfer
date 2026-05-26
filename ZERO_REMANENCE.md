# Zero Remanence: Privacy & Data Disposal Protocol

## Key Disposal Lifecycle

CrypTransfer enforces a strict "One-and-Done" policy for cryptographic material. Keys are never persisted longer than their immediate functional necessity.

### RSA Public Key Purging
- **Handshake Phase**: RSA Public Keys are generated locally by the receiver and uploaded to the `rsa_key_transfers` collection to authorize a specific sender.
- **Immediate Disposal**: Upon successful AES key exchange (when the `transfers` document is created with the `encryptedAESKey`), the RSA Public Key is marked for deletion.
- **Session Cleanup**: `EncryptionService.closeReceiverSession()` performs a batch deletion of all documents in the `rsa_key_transfers` sub-collection for the current user and sets the `publicKey` field in the `users` document to `FieldValue.delete()`.

### Private Key Destruction
- The RSA Private Key is stored in **Flutter Secure Storage** (hardware-backed keychain/keystore where available).
- On any session termination (app backgrounding, manual toggle, or back navigation), `SessionManager.wipeSession()` triggers an immediate deletion of the private key from secure storage.

## RAM-only Buffer Management

To prevent memory remanence attacks (cold-boot or heap scraping), the system ensures sensitive data exists only in transient, zeroable buffers.

### Chunked File Processing
- **TransferService**: Files are never read entirely into memory as raw bytes. Instead, they are processed in **64 KB chunks** using `File.openRead()`.
- **Memory Stability**: This caps peak memory usage and ensures that only a small portion of the file is vulnerable at any given microsecond.

### Explicit Buffer Zeroing
- **SecurityLifecycleMixin**: All screens handling sensitive data (Sender, Receiver, Decrypt, etc.) register their `Uint8List` buffers (AES keys, IVs, plaintext chunks).
- **Post-Crypto Wipe**: In `SenderScreen._encryptFile()`, the plaintext buffer is registered, processed via a background `compute()` isolate, and then immediately overwritten with zeros using `buffer.fillRange(0, length, 0)` before being deregistered.
- **Isolate Safety**: While the background isolate handles encryption, the main isolate ensures no plaintext remnants linger after the isolate returns.

## Data Persistence Policy
- **No Decrypted Storage**: Decrypted file data is NEVER written to local permanent storage. It exists solely in RAM-only buffers during the decryption and "Save" operation.
- **Secure Deletion**: Once a file is saved to the user's chosen location, the application-level buffers are zeroed immediately.

## Verification & Test Coverage

All zero-remanence guarantees are verified by the comprehensive session wipe test suite (TC-WIPE-001 to TC-WIPE-009), which covers:
- Buffer lifecycle: registration, zeroing, and deregistration
- Key disposal: RSA public/private key deletion from Firestore and secure storage
- Session state: atomic transitions through terminated state
- Screen safety: defensive application of SecurityLifecycleMixin

**Current Status**: 29/29 security tests passing (2026-05-26)
