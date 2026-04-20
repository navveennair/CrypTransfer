---
updated_at: "2026-04-19T00:00:00.000Z"
---

## Architecture Overview

CrypTransfer is a Flutter mobile application implementing end-to-end encrypted peer-to-peer file transfer. The architecture follows a layered repository pattern with a reactive session state machine driving both UI and cryptographic lifecycle. The central design is a "Closed Mailbox" session model where the receiver controls session open/close and a kill-switch chain ensures all key material is wiped on any termination signal.

## Key Components

| Component | Path | Responsibility |
|-----------|------|----------------|
| SessionState | lib/core/utils/session_state.dart | Enum: open / locked / decrypting / terminated — isolated file prevents circular imports |
| SessionManager | lib/core/utils/session_manager.dart | Owns session state transitions, broadcast stateStream, kill-switch handshake, sender isolation |
| SecurityLifecycleMixin | lib/core/utils/security_lifecycle_mixin.dart | Mixin on State: Uint8List buffer registry, wipeAll(), FLAG_SECURE MethodChannel pre-flight |
| EncryptionService | lib/data/services/encryption_service.dart | AES-256-GCM + RSA-2048-OAEP crypto, setupReceiverSession, closeReceiverSession, bindSession/unbindSession |
| TransferService | lib/data/services/transfer_service.dart | 64 KB chunked file reads (kChunkSize), memory-stable I/O for large files |
| KeyRepository | lib/data/repositories/key_repository.dart | RSA key sharing, handshake atomics (WriteBatch), streamHandshakesForSender stream, connection management |
| TransferRepository | lib/data/repositories/transfer_repository.dart | Encrypted file upload/download, audit log, receiver status updates, pending transfer stream |
| AuthRepository | lib/data/repositories/auth_repository.dart | Firebase Auth register/login, username-based lookup, RSA key generation on registration |
| FirebaseConstants | lib/core/constants/firebase_constants.dart | Single source of truth for all Firestore collection names and Storage paths |
| ReceiverScreen | lib/presentation/receiver/receiver_screen.dart | Owns SessionManager, binds EncryptionService, manages transfer stream, kill-switch triggers |
| SenderScreen | lib/presentation/sender/sender_screen.dart | Handshake stream listener, file pick, AES encrypt in compute(), plaintext zero-wipe |
| CrypButton | lib/presentation/widgets/shared_widgets.dart | 3D button widget with session-state visual feedback (color + icon override per SessionState) |
| AdminDashboard | lib/presentation/admin/ | Admin-only screens: connection node map, security pulse feed, transfer charts, user management |
| MainActivity.kt | android/app/src/main/kotlin/.../MainActivity.kt | Sets FLAG_SECURE in onCreate; registers MethodChannel handler for isFlagSecureActive |

## Data Flow

### Send Flow
SenderScreen (file pick) -> TransferService.resolve() (64 KB chunked read) -> compute(_runAesGcm) (AES-256-GCM encrypt) -> rsaEncrypt(receiverPublicKey, aesKey) -> TransferRepository.uploadAndCreate() (Storage + Firestore)

### Receive Flow
ReceiverScreen (mailbox open) -> EncryptionService.setupReceiverSession() (RSA keygen in compute, Firestore publish) -> streamHandshakesForSender / selectSenderHandshake (atomic handshake) -> TransferRepository.watchPendingTransfers() stream -> SessionManager.setDecrypting() -> ReceiverTransferScreen / DecryptScreen -> EncryptionService.decryptAesGcm() -> save file

### Kill-Switch Chain
UI trigger (back nav / app pause / toggle off) -> SessionManager.wipeSession() -> stateStream emits SessionState.terminated -> EncryptionService.bindSession listener -> closeReceiverSession() (Firestore delete + SecureStorage delete + batch-delete handshakes) -> SecurityLifecycleMixin.wipeAll() (Uint8List.fillRange zero)

### Reactive Sender Revert
closeReceiverSession() deletes selectedSenderUid + handshakes -> streamHandshakesForSender() emits empty -> SenderScreen._onHandshakeUpdate() -> _revertToWaiting() (wipes cached key/file data)

## Conventions

- **Firestore collections** all referenced via `FirebaseConstants` string constants — no inline string literals
- **Crypto isolation**: all heavy crypto (RSA keygen, AES-GCM encrypt/decrypt) runs in `compute()` isolates — never on the UI thread
- **Session isolation**: one sender per receiver session enforced by `SessionManager.activeSenderUid`; `selectSender()` / `clearSender()` are the only mutation points
- **Buffer lifecycle**: every `Uint8List` holding key material is `registerBuffer()`-ed immediately on creation and `wipeAll()`-ed on dispose or kill-switch
- **SecurityLifecycleMixin** applied to: SenderScreen, ReceiverScreen, TransferProgressScreen, DownloadConfirmScreen, EndSessionScreen, DecryptScreen
- **Firestore streams**: `StreamBuilder` references stable `Stream` fields (initialized once in `initState` or event handler), never created inline in `build()` to prevent double-subscription
- **Android window protection**: `FLAG_SECURE` set once in `MainActivity.onCreate()` — applies to all Flutter screens without per-screen code
- **Error hierarchy**: typed exceptions from `lib/core/errors/app_exceptions.dart` — `AuthException`, `NetworkException`, `CryptoException`, `TransferException`, `KeyNotFoundException`

## Security Architecture

- **Hybrid encryption**: AES-256-GCM for file content, RSA-2048-OAEP to wrap the AES session key
- **Key storage**: private key stored in `FlutterSecureStorage` (Android Keystore-backed), never in Firestore
- **Public key lifecycle**: published to Firestore only during active receiver session; deleted by kill switch
- **Non-repudiation**: `receiverStatus` field updated at each decrypt phase; immutable audit log written to `transfer_logs`
- **Session binding**: `EncryptionService.bindSession(stateStream, uid)` creates a reactive subscription — no imperative call chain required for crypto cleanup
- **Known gap**: `compute()` isolate ciphertext (`Uint8List`) is not accessible for `fillRange` zeroing from main isolate (accepted platform limitation)
