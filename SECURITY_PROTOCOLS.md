# CrypTransfer Security Protocol

## Access Control & Identity

### Admin Role
- **Privileged Access**: Administrative features (Node Map, User Management) are restricted to users with the `isAdmin` boolean field set to `true` in their Firestore `users/{uid}` document.
- **Verification**: The `AdminRepository` verifies this field before allowing access to the `transfers_log` collection or user modification methods.

### Session Isolation
- Only one active sender can be authorized per receiver session (`selectedSenderUid` in `SessionManager`).

## Hybrid Encryption Flow

CrypTransfer utilizes a multi-layered encryption strategy to balance security and performance.

1. **Handshaking (Asymmetric)**: 
   - **RSA-2048 (OAEP)**: Used to securely exchange the session-specific AES key. 
   - Public keys are ephemeral and session-bound.
2. **Stream Encryption (Symmetric)**: 
   - **AES-256-GCM**: Used for file data encryption. 
   - Provides **Authenticated Encryption** (AEAD), ensuring both confidentiality and integrity of the file stream.
   - 12-byte initialization vectors (IV) are generated uniquely for every transfer.

## Rendering Security & Side-Channel Mitigation

- **Impeller Backend**: The application uses the Flutter Impeller rendering engine. Beyond performance gains, Impeller provides a more predictable rendering pipeline, reducing the surface area for certain UI-layer side-channel attacks that rely on legacy GL state leaks.
- **FLAG_SECURE**: Android-level protection is enabled in `MainActivity.kt` to block task-switcher thumbnails and screenshots, preventing visual leak of sensitive decrypted data.

## Core Rules
1. No sensitive buffer survives a screen transition
2. Every key is zeroed immediately after use
3. Private key never coexists with plaintext longer than decrypt operation
4. All screens with sensitive data use SecurityLifecycleMixin
5. Navigation away = immediate wipe, no exceptions

## Radioactive Variables (must be wiped)
- _aesKey (Uint8List 32 bytes)
- _iv (Uint8List 12 bytes)
- _encryptedBytes (Uint8List)
- _decryptedBytes (Uint8List)
- privateKeyJson (String)

## Wipe Pattern
```dart
buffer.fillRange(0, buffer.length, 0);
buffer = null;
```

## Screen Coverage

| Screen | Radioactive Buffers | Wipe Trigger |
|--------|--------------------|----|
| SenderScreen | _aesKey, _iv, _encryptedBytes, _encryptedAesKey | dispose() |
| TransferProgressScreen | widget.encryptedBytes, widget.aesKey | dispose() |
| DownloadConfirmScreen | widget.decryptedBytes, widget.aesKey | dispose() |
| EndSessionScreen | widget.aesKey | _endSession() step 0 + dispose() |

## SecurityLifecycleMixin API
```dart
// Register a buffer when it is created
registerBuffer(Uint8List buffer);

// Manually wipe all registered buffers (e.g. on error)
wipeAll();

// Override to reset state references after a wipe
void onBuffersWiped() {}
```

## Threat Model
- Memory scraping after a crash or forced backgrounding
- Screen capture or reflection of in-memory key material
- Lingering key material after the session ends
- Keys surviving route transitions in the Navigator stack

## Key Lifecycle
```
_secureBytes(32) ──► registerBuffer() ──► use ──► navigate ──► dispose() ──► fillRange(0)
                                                     │
                                                wipeAll() on error
```
