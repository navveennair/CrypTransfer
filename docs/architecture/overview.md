<!-- generated-by: gsd-doc-writer -->

# Architecture Overview

## System Overview

CrypTransfer is a Flutter (Dart, Material 3) mobile application for secure
peer-to-peer file transfer using hybrid RSA/AES encryption. Users authenticate
via Firebase Auth, connect with other users through a two-stage handshake
system, and exchange files that are encrypted client-side (AES-256-GCM with a
per-transfer key wrapped in RSA-OAEP) before being uploaded to Firebase
Storage. Firestore acts as the signaling and metadata layer — it never stores
plaintext file content or private keys.

The architectural style is a **layered architecture** (`core` / `data` /
`presentation`) combined with a **reactive, stream-driven session model**: the
receiver's "mailbox" state, sender connection status, and transfer progress
all propagate via Firestore real-time listeners rather than polling or manual
refresh. A dedicated `SessionManager` + `SecurityLifecycleMixin` pair
implements a "Closed Mailbox" kill switch that wipes keys and zeroes in-memory
buffers on session termination.

## Component Diagram

```
                      ┌─────────────────────────────┐
                      │        presentation/         │
                      │  (Flutter screens/widgets)   │
                      │                              │
                      │  auth/  home/  sender/       │
                      │  receiver/  admin/  vault/    │
                      │  settings/  widgets/          │
                      └───────────────┬──────────────┘
                                       │ uses
                                       ▼
                      ┌─────────────────────────────┐
                      │          data/                │
                      │                              │
                      │  repositories/                │
                      │   ├─ auth_repository          │
                      │   ├─ user_repository          │
                      │   ├─ handshake_repository      │  (neutral_handshakes)
                      │   ├─ key_repository            │  (handshakes, RSA keys)
                      │   ├─ transfer_repository        │  (transfers, transfer_logs)
                      │   ├─ cleanup_repository         │
                      │   └─ admin_repository           │
                      │                              │
                      │  services/                    │
                      │   ├─ encryption_service       │  (RSA-OAEP + AES-256-GCM)
                      │   └─ transfer_service          │  (64 KB chunked file I/O)
                      │                              │
                      │  models/                      │
                      │   ├─ user_model                │
                      │   ├─ transfer_model            │
                      │   └─ notification_model        │
                      └───────────────┬──────────────┘
                                       │ uses
                                       ▼
                      ┌─────────────────────────────┐
                      │          core/                │
                      │                              │
                      │  utils/                       │
                      │   ├─ session_manager          │  (SessionState machine)
                      │   ├─ session_state             │  (enum, standalone)
                      │   ├─ security_lifecycle_mixin  │  (buffer zero-wipe)
                      │   ├─ biometric_helper          │
                      │   ├─ tofu_service               │
                      │   ├─ notification_service       │
                      │   ├─ theme_service               │
                      │   └─ file_utils / transfer_status_utils │
                      │                              │
                      │  constants/firebase_constants  │  (collection names)
                      │  errors/app_exceptions          │  (typed exceptions)
                      │  services/auth_method_service   │
                      └─────────────────┬──────────────┘
                                         │
                                         ▼
                      ┌─────────────────────────────┐
                      │   Firebase (Auth/Firestore/    │
                      │         Storage)               │
                      └─────────────────────────────┘

Native bridge:
  android/app/.../MainActivity.kt  ◄──── MethodChannel "cryptransfer/security"
       FLAG_SECURE / isFlagSecureActive / clearSession
                  ▲
                  │
  SecurityLifecycleMixin (core/utils) ── queried by SenderScreen pre-flight
```

Data flow direction: `presentation` → `data` (repositories/services) →
`core` (shared utilities/constants) → Firebase backend. `core/utils` also
flows back into `presentation` (mixins applied to screen `State` classes) and
into `data/services` (e.g. `EncryptionService` imports `SessionState` from
`core/utils/session_state.dart`).

## Directory Structure Rationale

```
lib/
├── core/
│   ├── constants/
│   │   └── firebase_constants.dart   ← single source of truth for collection
│   │                                    names, storage paths, secure-storage
│   │                                    keys, and limits (e.g. 100 MB download cap)
│   ├── errors/
│   │   └── app_exceptions.dart       ← typed exceptions (AuthException,
│   │                                    NetworkException, CryptoException,
│   │                                    KeyNotFoundException, TransferException,
│   │                                    RoleConflictException)
│   ├── services/
│   │   └── auth_method_service.dart  ← auth-method detection helper
│   └── utils/
│       ├── session_manager.dart      ← SessionState machine + kill-switch
│       │                                handshake (see Security Architecture)
│       ├── session_state.dart        ← standalone SessionState enum (avoids
│       │                                circular import with EncryptionService)
│       ├── security_lifecycle_mixin.dart ← Uint8List zero-wipe mixin + native
│       │                                MethodChannel bridge
│       ├── biometric_helper.dart     ← local_auth wrapper (Face ID / fingerprint)
│       ├── tofu_service.dart         ← Trust-On-First-Use key verification
│       ├── notification_service.dart ← in-app notification helpers
│       ├── theme_service.dart        ← GitHub Dark Material 3 theme
│       └── file_utils.dart / transfer_status_utils.dart ← formatting helpers
│
├── data/
│   ├── repositories/                 ← one repository per Firestore domain;
│   │                                    wraps queries/writes and translates
│   │                                    FirebaseException → typed app exceptions
│   │   ├── auth_repository.dart      ← Firebase Auth sign-in/up/out
│   │   ├── user_repository.dart      ← user profile reads/writes
│   │   ├── handshake_repository.dart ← `neutral_handshakes` connection proposals
│   │   ├── key_repository.dart       ← `handshakes` (RSA key exchange),
│   │   │                                connections, role assignment
│   │   ├── transfer_repository.dart  ← `transfers` + `transfer_logs`/`audit_logs`,
│   │   │                                upload/download, cleanup protocol
│   │   ├── cleanup_repository.dart   ← session/key cleanup helpers
│   │   └── admin_repository.dart     ← admin dashboard queries
│   │
│   ├── services/
│   │   ├── encryption_service.dart   ← RSA-2048 keygen, RSA-OAEP, AES-256-GCM
│   │   │                                (compute() isolates), receiver session
│   │   │                                lifecycle (setup/close), reactive
│   │   │                                kill-switch binding
│   │   └── transfer_service.dart     ← 64 KB chunked file reads (`kChunkSize`),
│   │                                    `resolve()` for mobile/desktop vs web
│   │
│   └── models/
│       ├── user_model.dart           ← `users/{uid}` document
│       ├── transfer_model.dart       ← `transfers/{id}` document
│       └── notification_model.dart   ← per-user `notifications` sub-collection
│
└── presentation/
    ├── auth/        ← splash, onboarding, login, register screens
    ├── home/        ← home screen, find friends, notifications, transfer summary, sidebar
    ├── sender/       ← SenderScreen (encrypt + upload), transfer progress,
    │                   session-end screen
    ├── receiver/     ← ReceiverScreen (mailbox), DecryptScreen, transfer screen,
    │                   end-session screen
    ├── admin/         ← admin dashboard (connection node map, security pulse
    │                   feed, transfer volume chart, user management)
    ├── vault/         ← RSA key manager screen
    ├── settings/      ← settings screen
    └── widgets/       ← shared_widgets.dart (CrypButton, GlassButton)
```

The `core / data / presentation` split keeps cryptography and Firestore access
out of widget code: screens call repository/service methods and react to
streams, while `core/utils` provides cross-cutting session-state and
zero-wipe behavior that any screen can opt into via a mixin.

## Key Abstractions

| Abstraction | Location | Description |
|---|---|---|
| `EncryptionService` | `lib/data/services/encryption_service.dart` | Static-only class: RSA-2048 keygen (`generateRsaKeyPairSync`, run via `compute()`), RSA-OAEP `rsaEncrypt`/`rsaDecrypt`, AES-256-GCM `encryptAesGcm`/`decryptAesGcm` (both via `compute()` isolates), receiver session lifecycle (`setupReceiverSession`, `closeReceiverSession`), and reactive kill-switch binding (`bindSession`/`unbindSession`). |
| `TransferService` | `lib/data/services/transfer_service.dart` | Static-only class providing memory-stable file I/O. `kChunkSize = 64 * 1024` (64 KB). `resolve()` picks a path-based chunked read on mobile/desktop or falls back to in-memory bytes on web. |
| `SessionManager` | `lib/core/utils/session_manager.dart` | Owns the `SessionState` enum (`open`, `locked`, `decrypting`, `terminated`) via a `ValueNotifier` plus a broadcast `stateStream`. Provides `lock()`, `setDecrypting()`, `reset()`, `wipeSession()`, `handleLifecycleState()`, `selectSender()`/`clearSender()` for single-sender session isolation. |
| `SessionState` | `lib/core/utils/session_state.dart` | Standalone enum extracted to avoid a circular import between `SessionManager` and `EncryptionService`. Re-exported from `session_manager.dart`. |
| `SecurityLifecycleMixin` | `lib/core/utils/security_lifecycle_mixin.dart` | Mixin for `State<T>` classes. `registerBuffer()`/`unregisterBuffer()` track sensitive `Uint8List`s; `wipeAll()` zero-fills and clears the registry on `dispose()`. Also bridges to native Android via the `cryptransfer/security` MethodChannel (`isFlagSecureActive()`, `requestNativeClear()`). |
| `KeyRepository` | `lib/data/repositories/key_repository.dart` | RSA key exchange and connection management: `selectSenderHandshake()` (atomic `WriteBatch` writing `selectedSenderUid` + `handshakes` doc), `streamHandshakesForSender()`, `fetchHandshakePublicKey()`, `disconnectFriend()`, `endSessionCleanup()`, `assignTransferRole()` (transactional role-conflict detection). |
| `TransferRepository` | `lib/data/repositories/transfer_repository.dart` | `transfers` collection + Storage I/O: `uploadAndCreate()` (upload progress stream + doc creation), `downloadEncryptedFile()`, `updateReceiverStatus()`, `writeFinalAuditLog()`/`writeAbortAuditLog()`/`writeConnectionLostAuditLog()`, synchronized cleanup protocol (`initiateCleanup()`, `senderWipeAESKey()`). |
| `HandshakeRepository` | `lib/data/repositories/handshake_repository.dart` | Connection-layer proposals in `neutral_handshakes` using deterministic doc IDs (`${proposerId}_${partnerId}`); `sendProposal()` uses a transaction to preserve `createdAt` on idempotent re-sends. |
| `FirebaseConstants` | `lib/core/constants/firebase_constants.dart` | Single source of truth for all Firestore collection names (`users`, `transfers`, `transfer_logs`, `handshakes`, `neutral_handshakes`, `notifications`, `connections`, `friendships`, `security_audit_log`), Storage paths, secure-storage key names, and `maxDownloadBytes` (100 MB). |
| `CrypButton` / `GlassButton` | `lib/presentation/widgets/shared_widgets.dart` | Shared 3D/glassmorphic button system. `CrypButton` accepts an optional `sessionState` and renders amber+lock (locked), primary+spinner (decrypting), or error-red+block (terminated), blocking interaction in all non-`open` states. |

## Encryption & Transfer Data Flow

CrypTransfer uses **hybrid encryption**: each file gets a fresh AES-256-GCM
key/IV, and that AES key is wrapped with the receiver's RSA-2048 public key
(RSA-OAEP) so only the receiver's private key (stored only on-device, never
in Firestore) can unwrap it.

### Sender path (`SenderScreen._encryptFile`, `lib/presentation/sender/sender_screen.dart`)

1. **Pre-flight security check** — `SecurityLifecycleMixin.isFlagSecureActive()` queries the native Android `FLAG_SECURE` state via the `cryptransfer/security` MethodChannel; encryption is aborted if the window is unprotected.
2. **Memory-stable read** — `TransferService.resolve()` reads the source file in 64 KB chunks (`TransferService.kChunkSize`) into a single `Uint8List` (`plaintext`), avoiding loading the whole file via `PlatformFile.bytes`.
3. **Register for wipe** — `registerBuffer(plaintext)` is called immediately as a safety net.
4. **AES-256-GCM encrypt** — `EncryptionService.encryptAesGcm(plaintext)` runs `runAesGcmEncrypt` in a `compute()` isolate, generating a random 256-bit key and 96-bit IV and returning `AesEncryptResult { ciphertext, key, iv }`. The result's `key`, `iv`, and `ciphertext` buffers are registered for wipe.
5. **Plaintext zero-wipe** — after `compute()` returns, `plaintext.fillRange(0, plaintext.length, 0)` zeroes the main-isolate copy and `unregisterBuffer(plaintext)` removes it from the registry (avoiding a redundant pass in `wipeAll()`).
6. **Freshness check** — `KeyRepository.fetchHandshakePublicKey(receiverId)` (via the injected connection service) does a one-shot read of the receiver's current public key from the `handshakes` collection, closing the reactive-stream latency window before wrapping the AES key.
7. **RSA-OAEP wrap** — `EncryptionService.rsaEncrypt(receiverPublicKey, aesKey)` wraps the AES key with the receiver's RSA-2048 public key.
8. **Upload** — `TransferRepository.uploadAndCreate()` uploads the AES-GCM ciphertext to Firebase Storage at `transfers/{transferId}/encrypted_file`, then writes a `transfers/{transferId}` document containing `senderId`, `receiverId`, base64 `encryptedAESKey`, base64 `iv`, `encryptedFileUrl`, `fileName`, `fileSize`, `status: 'pending'`, `sessionActive: true`.
9. **Notify** — `TransferRepository.notifyReceiver()` writes a `rsa_key_received`-style notification (`📁 ... sent you an encrypted file`) to the receiver's `notifications` sub-collection.

### Receiver path (`ReceiverScreen` → `DecryptScreen`, `lib/presentation/receiver/`)

1. **Reactive trigger** — `ReceiverScreen` watches `transfers` (filtered by `receiverId`/`senderId`/`status == 'pending'`) via `TransferRepository.watchPendingTransfersFromSender()`. On a new doc, `_handleIncomingTransfer` calls `SessionManager.lock()` then `SessionManager.setDecrypting()`, which auto-navigates to `ReceiverTransferScreen`/`DecryptScreen`.
2. **Mark received** — `TransferRepository.markReceived(transferId)` sets `status: 'received'`.
3. **Download** — `TransferRepository.updateReceiverStatus(transferId, 'downloading')`, then `downloadEncryptedFile(transferId)` pulls the ciphertext from Storage (capped at `FirebaseConstants.maxDownloadBytes` = 100 MB).
4. **Decrypt** — `updateReceiverStatus(transferId, 'decrypting')`, then `EncryptionService.decryptAesGcm(ciphertext, aesKey, iv)` runs `runAesGcmDecrypt` in a `compute()` isolate. The AES key itself is recovered via `EncryptionService.decryptAesKeyWithPrivateKeyJson()` (RSA-OAEP decrypt using the on-device private key from `FlutterSecureStorage`).
5. **Decrypted** — `updateReceiverStatus(transferId, 'decrypted')`.
6. **Save & Suicide** — `_saveAndWipe()` writes the decrypted bytes to device storage, sets `updateReceiverStatus(transferId, 'saved')`, and transitions to `_Phase.done` — a "clean room" decrypt UI with no further interaction except returning home.

### Synchronized cleanup protocol (post-transfer)

After the receiver saves the file (`receiverStatus == 'saved'`), `TransferProgressScreen` (sender side) listens reactively to the `transfers` document:

1. **Turn 1 (Receiver)** — `TransferRepository.initiateCleanup(transferId)` sets `status: 'cleanup_initiated'`.
2. **Turn 2 (Sender)** — `TransferRepository.senderWipeAESKey(transferId)` clears `encryptedAESKey` from Firestore and sets `senderCleanedUp: true`.
3. **Turn 3/4** — Receiver deletes the `transfers/{id}` document and the Storage file (`deleteStorageFile`); sender's listener sees the doc disappear and auto-navigates to `SenderSessionEndedScreen`. A 300-second safety timeout unblocks the sender if the receiver never completes cleanup.
4. **Audit log** — `TransferRepository.writeFinalAuditLog()` writes an immutable `status: 'completed'` record to both users' `users/{uid}/auditLogs` sub-collections (used by `streamRecentTransfers`/`streamAllTransfers` for HomeScreen and TransferSummaryScreen).

## Firestore Data Model

| Collection | Doc ID scheme | Key fields | Purpose |
|---|---|---|---|
| `neutral_handshakes` | `${proposerId}_${partnerId}` (deterministic) | `proposerId`, `proposerUsername`, `partnerId`, `partnerUsername`, `status` (`pending`/`connected`/`rejected`), `createdAt`, `updatedAt` | Connection-layer proposals between two users, symmetric roles. Managed by `HandshakeRepository`. `sendProposal()` uses a transaction so re-sends preserve the original `createdAt`. |
| `handshakes` | Auto-ID | `receiverId`, `senderId`, `publicKey`, `status` (`pending`/`handshake_complete`), `fromUsername`/`receiverUsername`, `sentAt`, `receiverReady` | Session-layer RSA public-key exchange per receiver-sender pair. Created/updated by `KeyRepository.selectSenderHandshake()` (atomic `WriteBatch` alongside `users/{receiverId}.selectedSenderUid`) or `sendPublicKey()`. `SenderScreen` subscribes via `streamHandshakesForSender()`. |
| `transfers` | Auto-ID (`generateId()`) | `senderId`, `receiverId`, `encryptedAESKey` (base64, RSA-wrapped), `iv` (base64), `encryptedFileUrl`, `fileName`, `fileSize`, `status` (`pending`/`received`/`cleanup_initiated`/`failed`/`completed`/`cancelled`/`rejected`/`in-progress`), `receiverStatus` (`downloading`/`decrypting`/`decrypted`/`saved`), `sessionActive`, `senderCleanedUp`, `createdAt`, `receivedAt` | Active file-transfer metadata, managed end-to-end by `TransferRepository`. Backing Storage object lives at `transfers/{transferId}/encrypted_file`. |
| `transfer_logs` | Auto-ID | `senderId`, `receiverId`, `participants` (array), `status` (`kill_switch`, etc.), `loggedAt` | Top-level audit collection used by the Admin Dashboard for global activity monitoring (kill-switch events written by `EncryptionService.closeReceiverSession()`). |
| `users/{uid}/auditLogs` | Auto-ID (per-user sub-collection) | `senderId`, `receiverId`, `senderUsername`, `receiverUsername`, `participants`, `fileName`, `fileSize`, `status` (`completed`/`aborted`/`connection_lost`), `timestamp`, `loggedAt` | Immutable per-user transfer history, written in pairs (sender + receiver) by `TransferRepository.writeFinalAuditLog()`/`writeAbortAuditLog()`/`writeConnectionLostAuditLog()`. Powers `streamRecentTransfers()` (HomeScreen, limit 3) and `streamAllTransfers()` (TransferSummaryScreen). |
| `users` | `{uid}` (Firebase Auth UID) | `username`, `email`, `phone`, `publicKey`, `isReadyToReceive`, `sessionActive`, `selectedSenderUid` (locked session authorization), `pendingSenderFor`/`pendingReceiverFor` (transactional role claims), `isAdmin` | User profile / identity documents. `selectedSenderUid` is the receiver-authorized sender for the current session; cleared by the kill switch (`closeReceiverSession`) and `endSessionCleanup()`. |
| `users/{uid}/connections` | `{partnerUid}` | (per-connection metadata) | Sub-collection for accepted connections (parallel to `friendships`). |
| `users/{uid}/friendships` | `{partnerUid}` | `uid`, `username`, `email`, `status` (`accepted`), `updatedAt` | Bidirectional friendship records written by `KeyRepository.sendConnectionRequest()` via `WriteBatch`. |
| `users/{uid}/notifications` | Auto-ID | `toUserId`, `fromUsername`, `type` (`friend_request`/`rsa_key_received`/`transfer_completed`/`transfer_aborted`/`file_received`), `message`, `read`, `createdAt` | Per-user notification inbox. |
| `security_audit_log` | Auto-ID | `event`, `userId`, `timestamp`, `details` | Security event log written by `EncryptionService._logSecurityEvent()` — event names and non-sensitive details only, never key material. |

## Security Architecture: SessionManager & Kill Switch

The "Closed Mailbox" kill switch wipes all receiver-side key material and
in-memory buffers when a session ends — whether by explicit user action,
back navigation, or the app being backgrounded/killed.

### State machine (`lib/core/utils/session_state.dart`)

```
SessionState: open ──► locked ──► decrypting ──► terminated
                ▲___________________________________|
                (reset() returns to open)
```

- `open` — mailbox open, normal operation.
- `locked` — incoming transfer detected; back-navigation guard active.
- `decrypting` — decryption in progress on the receiver side.
- `terminated` — kill switch fired; keys wiped, session over (idempotent — no-op once reached).

### Kill-switch chain (`SessionManager`, `lib/core/utils/session_manager.dart`)

```
UI trigger
    │
    ▼
SessionManager.handleLifecycleState()   ← AppLifecycleState.paused/detached
SessionManager.wipeSession()            ← PopScope back-navigation
SessionManager.reset()                  ← manual close via toggle
    │
    ├── stateNotifier  → SessionState.terminated   (CrypButton reacts visually)
    ├── stateStream    → SessionState.terminated
    │       └── EncryptionService.bindSession() listener fires:
    │               EncryptionService.closeReceiverSession(uid)
    │                 ├── Firestore: delete publicKey, selectedSenderUid;
    │                 │     set isReadyToReceive=false, sessionActive=false
    │                 ├── FlutterSecureStorage: delete private key
    │                 ├── Batch-delete `handshakes` docs (receiverId == uid)
    │                 ├── Batch-delete `notifications` (type == rsa_key_received)
    │                 ├── Write `transfer_logs` audit entry (status: kill_switch)
    │                 └── SecurityLifecycleMixin.requestNativeClear() — best-effort
    │                       Kotlin GC hint via MethodChannel
    └── onBuffersWipe() → SecurityLifecycleMixin.wipeAll()
            └── Uint8List.fillRange(0, len, 0) for every registered buffer
```

`EncryptionService.bindSession(stateStream, uid)` is the reactive link: it
subscribes to `SessionManager.stateStream` and automatically calls
`closeReceiverSession()` when `SessionState.terminated` is emitted, so no
direct call from `wipeSession()` is required. `unbindSession()` cancels the
subscription on deliberate mailbox close or screen `dispose()`.

| UI Trigger | Method | Resulting `SessionState` |
|---|---|---|
| Toggle switch off | `_onToggleReady(false)` → `reset()` | `open` |
| Incoming transfer | `_handleIncomingTransfer` → `lock()` | `locked` |
| Back navigation (`PopScope`) | `wipeSession()` | `terminated` |
| App backgrounded/killed | `handleLifecycleState(paused/detached)` | `terminated` |
| Screen `dispose()` | `SecurityLifecycleMixin.wipeAll()` | — (buffers zeroed only) |

### Native bridge (`android/app/src/main/kotlin/.../MainActivity.kt`)

| Native side | Dart side | Purpose |
|---|---|---|
| `window.addFlags(FLAG_SECURE)` in `onCreate()` | `SecurityLifecycleMixin.isFlagSecureActive()` | Blocks screenshots/task-switcher thumbnails at the Android window level; Dart queries this before each 64 KB chunk read in `SenderScreen._encryptFile()`. |
| MethodChannel `cryptransfer/security` → `isFlagSecureActive` handler | `SecurityLifecycleMixin._securityChannel` | Returns `(flags & FLAG_SECURE) != 0`. Returns `true` on iOS/desktop and on `MissingPluginException` (safe fallback). |
| MethodChannel `cryptransfer/security` → `clearSession` handler | `SecurityLifecycleMixin.requestNativeClear()` | Best-effort `System.gc()` hint after `closeReceiverSession()` completes. No RSA/AES key material is held natively — all crypto runs in Dart `compute()` isolates. |

`SecurityLifecycleMixin` is applied to: `SenderScreen`, `ReceiverScreen`,
`TransferProgressScreen`, `DownloadConfirmScreen`, `EndSessionScreen`, and
`DecryptScreen`.

<!-- VERIFY: Production Firebase project ID and hosting/region configuration are not present in the repository contents reviewed. -->
