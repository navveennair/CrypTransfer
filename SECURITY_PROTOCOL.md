# CrypTransfer Security Protocol

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
