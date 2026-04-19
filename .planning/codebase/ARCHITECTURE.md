# Architecture

**Analysis Date:** 2025-04-19

## Pattern Overview

**Overall:** Clean Layered Architecture with Reactive State Management

CrypTransfer implements a three-tier architecture with clear separation between presentation (Flutter UI), business logic (services & repositories), and external integrations (Firebase, cryptography). The app uses:
- **Reactive state flow**: `SessionManager` owns receiver mailbox state machine; UI subscribes via `StateNotifier` and `Stream`
- **Computed isolation**: Heavy crypto (AES-GCM, RSA) runs in background isolates via `compute()`
- **Domain-driven collections**: Firestore collections model real-world entities (users, transfers, RSA handshakes)

**Key Characteristics:**
- Sender and receiver isolated, independent workflows
- Receiver-authorized handshake: receiver selects sender before any key material flows
- Kill-switch cascades through `SessionManager.stateStream` → `EncryptionService` → Firestore cleanup
- Memory-stable file I/O: 64 KB chunked reads prevent heap contention with crypto buffers
- Android hardening: `FLAG_SECURE` window flag + R8 code obfuscation for releases

## Layers

**Presentation Layer:**
- Purpose: Flutter UI screens, widgets, navigation
- Location: `lib/presentation/`
- Contains: StatefulWidget screens, reusable components, dialogs
- Depends on: Repositories, Services, SessionManager, SecurityLifecycleMixin
- Used by: User interaction flows

**Data Layer (Repositories & Services):**
- Purpose: Business logic, Firestore abstractions, crypto operations
- Location: `lib/data/`
  - `repositories/`: Firestore CRUD (auth, keys, transfers)
  - `services/`: Stateless crypto utilities (AES-GCM, RSA) and file I/O
  - `models/`: Dart data classes mapping to Firestore documents
- Depends on: Firebase, PointyCastle, core constants/errors
- Used by: Presentation screens, other services

**Core Layer:**
- Purpose: Shared utilities, state management, constants
- Location: `lib/core/`
  - `utils/`: `SecurityLifecycleMixin`, `SessionManager`, `BiometricHelper`
  - `constants/`: `FirebaseConstants` (Firestore/Storage names, limits)
  - `errors/`: Typed exception hierarchy
- Depends on: Flutter, Firebase
- Used by: All other layers

**Android Native Layer:**
- Purpose: Security hardening, OS integration
- Location: `android/app/src/main/kotlin/com/example/cryptransfer/MainActivity.kt`
- Provides: `FLAG_SECURE` window flag, MethodChannel for pre-flight security checks
- Consumed by: `SecurityLifecycleMixin.isFlagSecureActive()`

## Data Flow

**Sender Encryption Flow:**

1. `SenderScreen._pickFile()` caches `PlatformFile`
2. `_encryptFile()`:
   - Reads file via `TransferService.resolve(filePath, fallbackBytes)` in 64 KB chunks
   - `registerBuffer(plaintext)` (safety net)
   - `compute(_runAesGcm, [plaintext, aesKey, iv])` encrypts in isolate
   - `unregisterBuffer(plaintext)` + `fillRange(0)` zeroes plaintext
3. Sender selects receiver from `rsa_key_transfers` Firestore stream
4. `rsaEncrypt(publicKey, aesKey)` wraps AES key with receiver's public key
5. `TransferRepository.uploadAndCreate()`:
   - Uploads ciphertext to `Firebase Storage/transfers/{id}/encrypted_file`
   - Writes transfer metadata to Firestore (senderId, receiverId, encryptedAESKey, iv, status: pending)
   - Streams progress (0.0 → 1.0)
6. Navigate to `TransferProgressScreen` (non-repudiation listener)

**Receiver Decryption Flow:**

1. `ReceiverScreen._generateKeys()`:
   - `EncryptionService.setupReceiverSession(uid)` via `compute()`
   - RSA-2048 keypair generated, private key → `FlutterSecureStorage`
   - Public key published to Firestore `users.{uid}.publicKey`
2. `_onSenderSelected()`:
   - `SessionManager.selectSender(uid, username)`
   - `KeyRepository.selectSenderHandshake()` atomic WriteBatch:
     - `users.{uid}.selectedSenderUid = senderUid`
     - `rsa_key_transfers` doc upserted with `status: handshake_complete`
   - Initialize `_transferStream` listening for pending transfers
3. `_transferStream` emits → `_handleIncomingTransfer()` → `SessionManager.setDecrypting()` → auto-navigate
4. `ReceiverTransferScreen` / `DecryptScreen`:
   - Download ciphertext + encrypted AES key from Firestore
   - `EncryptionService.decryptAesGcm()` via `compute()`
   - Save to Downloads
5. `_saveAndWipe()`:
   - Update transfer status to "completed"
   - `SessionManager.wipeSession()` → reactive cleanup

**Kill-Switch Chain (Reactive):**

```
User action (toggle/back/app pause)
    ↓
SessionManager.wipeSession()
    ├── SessionState.terminated emitted on stateStream
    │   └── EncryptionService.bindSession() reacts
    │       └── EncryptionService.closeReceiverSession()
    │           ├── Delete publicKey from Firestore
    │           ├── Delete privateKey from FlutterSecureStorage
    │           ├── Batch-delete rsa_key_transfers
    │           ├── Batch-delete notifications
    │           └── Log security event
    └── SecurityLifecycleMixin.wipeAll()
        └── buffer.fillRange(0, buffer.length, 0) for all registered buffers
```

**State Management:**

- `SessionManager`: owns receiver state (open → locked → decrypting → terminated)
- `ValueNotifier<SessionState>`: UI subscriptions (CrypButton colors, badges)
- `Stream<SessionState>`: service subscriptions (EncryptionService binding)
- Sender: no persistent state; ephemeral per-file; connection purely reactive

## Key Abstractions

**SessionManager** (`lib/core/utils/session_manager.dart`):
- Receiver session lifecycle + kill-switch handshake
- Single instance per ReceiverScreen; idempotent transitions
- Emits `SessionState` via `StateNotifier` (UI) and broadcast `Stream` (services)

**TransferService** (`lib/data/services/transfer_service.dart`):
- Chunked 64 KB file I/O to prevent heap fragmentation
- `resolve(filePath, fallbackBytes)` picks path-based (mobile/desktop) or bytes-based (web) reads

**SecurityLifecycleMixin** (`lib/core/utils/security_lifecycle_mixin.dart`):
- Auto-register/wipe Uint8List buffers on screen lifecycle
- Applied to: `SenderScreen`, `ReceiverScreen`, `TransferProgressScreen`, `DecryptScreen`, `DownloadConfirmScreen`, `EndSessionScreen`
- `registerBuffer()` on allocation, `wipeAll()` on dispose

**KeyRepository** (`lib/data/repositories/key_repository.dart`):
- User search, friend requests, RSA key handshakes
- `selectSenderHandshake()`: atomic WriteBatch authorization
- `streamHandshakesForSender()`: live Firestore stream

**TransferRepository** (`lib/data/repositories/transfer_repository.dart`):
- Upload encrypted files, write metadata, update status
- `uploadAndCreate()` returns `Stream<double>` (0.0 → 1.0 progress)

**EncryptionService** (`lib/data/services/encryption_service.dart`):
- Stateless PointyCastle RSA/AES wrappers
- `encryptAesGcm()`, `decryptAesGcm()`: via `compute()`
- `setupReceiverSession()`, `closeReceiverSession()`: lifecycle hooks
- `bindSession()`, `unbindSession()`: reactive kill-switch binding

## Entry Points

- `lib/main.dart`: Firebase init, MaterialApp, SplashScreen
- `lib/presentation/auth/splash_screen.dart`: Firebase Auth check, route to LoginScreen or HomeScreen
- `lib/presentation/receiver/receiver_screen.dart`: RSA generation, sender selection, transfer listening
- `lib/presentation/sender/sender_screen.dart`: file picking, encryption, receiver stream, RSA wrapping
- `android/app/src/main/kotlin/com/example/cryptransfer/MainActivity.kt`: FLAG_SECURE + MethodChannel

## Error Handling

**Strategy:** Typed exception hierarchy with upstream propagation

1. **Firestore** → caught in repositories → wrapped in `NetworkException` or `AuthException`
2. **Crypto** → caught in `EncryptionService` → wrapped in `CryptoException`
3. **Missing keys** → `KeyNotFoundException`
4. **UI feedback** → caught in screen methods → `ScaffoldMessenger.showSnackBar()`

**Hierarchy:** `AppException` → `AuthException`, `TransferException`, `CryptoException`, `NetworkException`, `KeyNotFoundException`

---

*Architecture analysis: 2025-04-19*
