# Architecture
_Last updated: 2026-06-15_

## Pattern

**Layered Clean Architecture with Reactive Session State Machine**

CrypTransfer is a Flutter mobile application that follows a strict three-layer architecture: `core` (cross-cutting utilities), `data` (repositories + services), and `presentation` (screens + widgets). The security design enforces a reactive kill-switch pattern where the session state machine (`SessionManager`) drives cryptographic cleanup (`EncryptionService`) via a broadcast stream rather than direct imperative calls. All heavy crypto runs in background isolates via `compute()`.

---

## Layers

### Core Layer (`lib/core/`)

**Purpose:** Cross-cutting utilities that have no dependency on `data` or `presentation`. No business logic — only contracts, constants, and lifecycle tools.

**Contains:**
- `constants/firebase_constants.dart` — single source of truth for all Firestore collection names, Storage paths, and secure-storage key names
- `errors/app_exceptions.dart` — typed exception hierarchy (`AuthException`, `TransferException`, `CryptoException`, `NetworkException`, `KeyNotFoundException`, `RoleConflictException`)
- `utils/session_state.dart` — `SessionState` enum (`open`, `locked`, `decrypting`, `terminated`) in its own file to prevent circular imports
- `utils/session_manager.dart` — owns `SessionState` transitions; exposes `stateNotifier` (ValueNotifier) and `stateStream` (broadcast Stream); orchestrates kill-switch handshake
- `utils/security_lifecycle_mixin.dart` — `SecurityLifecycleMixin<T>` mixin; manages a `_radioactiveBuffers` registry; zeroes all `Uint8List` buffers on `dispose()` or `wipeAll()`; calls Kotlin `isFlagSecureActive` and `clearSession` via MethodChannel `cryptransfer/security`
- `utils/biometric_helper.dart` — local_auth 3.0.1 wrapper for Face ID / fingerprint gates
- `utils/theme_service.dart` — `ChangeNotifier` persisting `ThemeMode` to SharedPreferences
- `utils/notification_service.dart` — Firestore notification stream helpers
- `utils/transfer_status_utils.dart` — display-name mapping for transfer status strings
- `utils/file_utils.dart` — file extension / MIME helpers
- `utils/tofu_service.dart` — Trust-On-First-Use public key verification helper

**Depends on:** Nothing in `data` or `presentation`.

---

### Data Layer (`lib/data/`)

**Purpose:** All Firebase I/O, cryptographic operations, and domain models. Never imports from `presentation`.

**Repositories** (`lib/data/repositories/`) — Each repository is instantiated directly by screens (no DI container). Constructor injection accepted for testing (all Firebase singletons are overridable).

| Repository | Responsibility |
|---|---|
| `auth_repository.dart` | Firebase Auth sign-in/register/Google, RSA keypair generation on register, user Firestore doc creation |
| `key_repository.dart` | RSA public key sharing, user search, connection management (`friendships` sub-collection), atomic sender-selection handshake (`selectSenderHandshake` WriteBatch), role assignment, session cleanup |
| `transfer_repository.dart` | Upload encrypted file to Storage, create/update/delete `transfers` docs, audit logs (per-user `audit_logs` sub-collection), synchronized turn-based cleanup protocol |
| `handshake_repository.dart` | Neutral connection proposals (`neutral_handshakes`), accept/reject flows, stream helpers for incoming/outgoing proposals |
| `user_repository.dart` | User profile reads and admin flag checks |
| `admin_repository.dart` | Admin-only queries: all active transfers, user management, audit log aggregation |
| `cleanup_repository.dart` | End-of-session Firestore cleanup operations |

**Services** (`lib/data/services/`) — Pure computational services with no direct Firebase UI dependencies.

| Service | Responsibility |
|---|---|
| `encryption_service.dart` | RSA-2048 key generation (`compute(_generateRsaKeyPairIsolate)`), AES-256-GCM encrypt/decrypt (both via `compute()`), RSA-OAEP encrypt/decrypt, `setupReceiverSession()` (publish public key to Firestore), `closeReceiverSession()` (kill-switch: 7-step Firestore wipe + SecureStorage delete + audit log), `bindSession()` / `unbindSession()` (reactive stream subscription to `SessionManager.stateStream`) |
| `transfer_service.dart` | Memory-stable file reads (`kChunkSize = 64 KB`); `resolve()` picks path-based chunked read on mobile/desktop, falls back to bytes on web |

**Models** (`lib/data/models/`):

| Model | Fields |
|---|---|
| `user_model.dart` | `uid`, `username`, `email`, `phone`, `publicKey`, `isAdmin`, `isActive`, `isFirstTime`, `createdAt` |
| `transfer_model.dart` | Transfer document fields including `encryptedAESKey`, `iv`, `status`, `receiverStatus` |
| `notification_model.dart` | Typed notification with `NotificationType` enum |

---

### Presentation Layer (`lib/presentation/`)

**Purpose:** Flutter widgets and screens. May instantiate repositories directly. Uses `SecurityLifecycleMixin` to zero sensitive buffers on dispose.

**Screens by feature module:**

| Module | Screens |
|---|---|
| `auth/` | `splash_screen.dart`, `login_screen.dart`, `register_screen.dart`, `onboarding_screen.dart` |
| `home/` | `home_screen.dart`, `find_friends_screen.dart`, `notifications_screen.dart`, `sidebar_drawer.dart`, `transfer_summary_screen.dart` |
| `sender/` | `sender_screen.dart`, `sender_transfer_screen.dart`, `sender_session_end_screen.dart` |
| `receiver/` | `receiver_screen.dart`, `receiver_transfer_screen.dart`, `decrypt_screen.dart`, `receiver_end_session_screen.dart` |
| `settings/` | `settings_screen.dart` |
| `vault/` | `rsa_key_manager_screen.dart` |
| `admin/` | `admin_dashboard.dart`, `admin_guard.dart`, widgets: `connection_node_map.dart`, `security_pulse_feed.dart`, `transfer_volume_chart.dart`, `user_management_list.dart` |
| `widgets/` | `shared_widgets.dart` — global `GlassContainer`, `CrypButton` (3D session-state-aware button), `GlassButton` |

---

## Entry Points

### App Bootstrap (`lib/main.dart`)
1. `WidgetsFlutterBinding.ensureInitialized()`
2. `Firebase.initializeApp()` with platform-specific `firebase_options.dart`
3. `FirestoreMigration.initializeCollections()` — ensures `handshakes` and `neutral_handshakes` collections exist
4. `runApp()` wraps `CrypTransferApp` in `ChangeNotifierProvider<ThemeService>`
5. `MaterialApp` routes to `SplashScreen` as `home`; named route `/admin-dashboard` guarded by `AdminGuard`

### Splash Screen (`lib/presentation/auth/splash_screen.dart`)
- Checks `AuthRepository.authStateChanges` for existing session
- If authenticated: calls `KeyRepository().wipeAllSessionKeys(uid)` before navigating to `HomeScreen` (startup session hygiene)
- If unauthenticated: navigates to `LoginScreen`

---

## Data Flow

### Sender File Transfer Flow

1. **SenderScreen** — user selects a file; `FilePicker` returns `PlatformFile`
2. Receiver selected from active handshake stream (`KeyRepository.streamHandshakesForSender()`)
3. `SecurityLifecycleMixin.isFlagSecureActive()` — MethodChannel pre-flight to Kotlin; aborts if `FLAG_SECURE` not active
4. `TransferService.resolve(filePath, fallbackBytes)` — 64 KB chunked read into `Uint8List`; buffer registered with `registerBuffer(plaintext)`
5. `EncryptionService.encryptAesGcm(plaintext)` — AES-256-GCM via `compute()` background isolate; returns `AesEncryptResult`
6. Plaintext zeroed: `plaintext.fillRange(0, len, 0)` + `unregisterBuffer(plaintext)`
7. `EncryptionService.rsaEncrypt(receiverPublicKey, aesKey)` — RSA-OAEP wraps the AES key (via `compute()`)
8. `TransferRepository.uploadAndCreate()` — streams upload progress; writes `transfers` doc with `encryptedAESKey` (base64), `iv` (base64), `encryptedFileUrl`, `status: pending`
9. Navigation to **SenderTransferScreen** / **TransferProgressScreen** — Firestore listener watches `receiverStatus` and `cleanup_initiated` fields reactively

### Receiver Decrypt Flow

1. **ReceiverScreen** — `EncryptionService.setupReceiverSession(uid)` generates RSA-2048 keypair in isolate; private key → `FlutterSecureStorage`; public key → Firestore `users/{uid}.publicKey`
2. Receiver selects sender via `FindFriendsSenderSheet`; `KeyRepository.selectSenderHandshake()` atomic `WriteBatch`: sets `selectedSenderUid` on user doc + publishes receiver public key to `handshakes` collection
3. `_transferStream` (`StreamBuilder` on `transfers WHERE receiverId==uid AND senderId==senderUid AND status==pending`) fires on incoming transfer
4. `SessionManager.lock()` → `SessionState.locked`; auto-navigate to **ReceiverTransferScreen**
5. **DecryptScreen** — `FlutterSecureStorage` reads private key; `compute(_decryptAesKeyIsolate)` RSA-OAEP decrypts AES key; `EncryptionService.decryptAesGcm()` decrypts ciphertext
6. File saved via `path_provider`; `TransferRepository.updateReceiverStatus()` signals sender
7. `EncryptionService.closeReceiverSession(uid)` — 7-step kill switch; then `ReceiverEndSessionScreen`

### Kill-Switch (Reactive Termination)

```
Any trigger (lifecycle pause, back-nav, toggle-off):
    │
    ▼
SessionManager.wipeSession()  or  handleLifecycleState()
    ├── _set(SessionState.terminated) → stateStream.add(terminated)
    │       └── EncryptionService._sessionSub fires:
    │               └── closeReceiverSession(uid)
    │                     ├── Firestore: delete publicKey, isReadyToReceive=false, selectedSenderUid deleted
    │                     ├── FlutterSecureStorage: delete private key
    │                     ├── Batch-delete handshakes (receiver-side + sender-side)
    │                     ├── Batch-delete pending transfers
    │                     ├── Batch-delete notifications (rsa_key_received, connection_request)
    │                     └── Write kill_switch audit log
    └── onBuffersWipe() → SecurityLifecycleMixin.wipeAll()
            └── Uint8List.fillRange(0) for every registered buffer
```

---

## Key Abstractions

### Repository Pattern
Repositories are plain Dart classes with optional constructor injection for Firebase singletons (enabling unit testing with fakes). No global service locator — screens instantiate repositories directly in `State` fields. Example: `final _connService = KeyRepository();`.

### SessionManager State Machine
`lib/core/utils/session_manager.dart` — one instance per `ReceiverScreen` session. Exposes:
- `ValueNotifier<SessionState> stateNotifier` — drives `CrypButton` visual state
- `Stream<SessionState> stateStream` (broadcast) — `EncryptionService.bindSession()` subscribes here for reactive crypto cleanup
- Transitions: `lock()`, `setDecrypting()`, `reset()`, `wipeSession()`

### SecurityLifecycleMixin
`lib/core/utils/security_lifecycle_mixin.dart` — applied to all screens handling crypto buffers: `SenderScreen`, `ReceiverScreen`, `TransferProgressScreen`, `DecryptScreen`, `ReceiverEndSessionScreen`, `SenderSessionEndScreen`. Overrides `dispose()` to call `wipeAll()`. Provides `registerBuffer()` / `unregisterBuffer()` for explicit buffer lifecycle management.

### EncryptionService (Static)
`lib/data/services/encryption_service.dart` — all methods are `static`. The reactive session binding is managed via a static `StreamSubscription? _sessionSub`. `bindSession(stateStream, uid)` subscribes; `unbindSession()` cancels.

### Two-Layer Handshake Model
- **Connection layer** (`neutral_handshakes`) — symmetric proposals between equal peers; deterministic doc ID `${proposerId}_${partnerId}`; manages `pending` → `connected`/`rejected` lifecycle
- **Session layer** (`handshakes`) — asymmetric RSA key exchange per transfer session; auto-ID docs; receiver publishes public key to sender via atomic `WriteBatch` in `selectSenderHandshake()`

### CrypButton (Session-State Widget)
`lib/presentation/widgets/shared_widgets.dart` — `StatefulWidget` with `SessionState sessionState` parameter. Visual state table:

| SessionState | Color | Icon | Interaction |
|---|---|---|---|
| `open` | primary | — | enabled |
| `locked` | amber | lock | blocked |
| `decrypting` | primary | spinner | blocked |
| `terminated` | error red | block | blocked |

---

## State Management

**Global state:** `ThemeService extends ChangeNotifier` provided via `ChangeNotifierProvider` in `main.dart`. Only manages light/dark/system theme mode.

**Per-screen state:** Standard `StatefulWidget` + `setState`. No Redux, BLoC, or Riverpod.

**Session state:** `SessionManager.stateNotifier` (ValueNotifier) consumed by `CrypButton` via `ValueListenableBuilder`. `SessionManager.stateStream` (broadcast Stream) consumed by `EncryptionService`.

**Real-time Firestore:** `StreamBuilder` widgets on stable `Stream` fields initialized once in `initState` (not inline on `build`). Key streams:
- `_transferStream` in `ReceiverScreen` — watches `transfers` for incoming files
- `_handshakeSub` in `SenderScreen` — watches `handshakes` for receiver authorization events
- `_recentTransfersStream` in `HomeScreen` — watches user's `audit_logs` sub-collection

---

## Error Handling

**Typed exceptions:** All repository and service methods throw subclasses of `AppException` (`AuthException`, `TransferException`, `CryptoException`, `NetworkException`, `KeyNotFoundException`, `RoleConflictException`). Callers catch at the screen level and surface errors as `SnackBar` messages.

**Firebase errors:** `on FirebaseException catch (e)` blocks in every repository method; wrapped into the appropriate `AppException` subclass before re-throwing.

**Crypto errors:** `compute()` isolate failures throw `CryptoException`. Screens catch and show error UI.

**Security failures:** `isFlagSecureActive()` returns `true` on failure (safe fallback); `requestNativeClear()` swallows errors silently (non-critical GC hint).

**Audit trail:** `EncryptionService._logSecurityEvent()` writes event names (never key material) to `security_audit_log` Firestore collection and `debugPrint`.
