# Architecture

**Analysis Date:** 2026-05-25

## Pattern Overview

**Overall:** Layered MVC with reactive state management, cryptographic isolation via compute() isolates, and kill-switch architecture.

**Key Characteristics:**
- **Separation of concerns**: Data layer (repositories/services) decoupled from presentation via dependency injection
- **Reactive streams**: Firestore snapshots and session state emit events that drive UI without manual polling
- **Isolate-based crypto**: RSA/AES operations run in background isolates via `compute()` to prevent UI blocking and enable safe plaintext zeroing
- **Kill-switch architecture**: `SessionManager` state transitions drive reactive cleanup through `EncryptionService` without direct imperative calls
- **Zero-remanence lifecycle**: `SecurityLifecycleMixin` registers and wipes sensitive `Uint8List` buffers; `fillRange(0)` called on dispose and session termination
- **Memory-stable I/O**: 64 KB chunked reads prevent heap fragmentation during large file transfers
- **Android hardening**: `FLAG_SECURE` window flag prevents task-switcher thumbnails; R8 minification obfuscates release builds

## Layers

**Presentation Layer:**
- Purpose: Flutter UI — screens, widgets, theme, user interaction
- Location: `lib/presentation/`
- Contains: Stateful screens (`ReceiverScreen`, `SenderScreen`, `DecryptScreen`) with `SecurityLifecycleMixin`, glassmorphic widgets (`GlassButton`, `GlassContainer`), session state listeners via `ValueNotifier.listen()` and `StreamBuilder`
- Depends on: Data layer (repositories/services), core utils (`SessionManager`, `EncryptionService`)
- Used by: End users via MaterialApp routing from `SplashScreen`

**Data Layer:**
- Purpose: Backend abstraction — Firebase Auth, Firestore CRUD, Cloud Storage I/O
- Location: `lib/data/` with subdirectories:
  - `repositories/`: `KeyRepository` (user search, connections, RSA keys), `TransferRepository` (upload/download metadata, audit logging), `AuthRepository` (auth state)
  - `services/`: `EncryptionService` (AES-256-GCM, RSA-OAEP hybrid crypto), `TransferService` (chunked file I/O), `TransferLogService` (audit trails)
  - `models/`: `TransferModel`, `UserModel`, `NotificationModel` (Firestore document mappings)
- Depends on: Firebase SDK, PointyCastle crypto library, core constants and error types
- Used by: Presentation screens; repositories instantiated fresh or as singletons depending on UI scope

**Core Layer:**
- Purpose: Shared infrastructure — constants, error types, utilities, session management
- Location: `lib/core/` with subdirectories:
  - `constants/`: `FirebaseConstants` (Firestore collection names, Storage paths, document field names)
  - `errors/`: Exception hierarchy (`AuthException`, `CryptoException`, `NetworkException`, `KeyNotFoundException`, `TransferException`)
  - `utils/`: `SessionManager` (state machine), `SessionState` enum (extracted to prevent circular imports), `SecurityLifecycleMixin` (buffer registry), `BiometricHelper` (Face ID), `TofuService` (TOFU key pinning)
  - `services/`: `AuthMethodService` (method-channel auth helpers)
- Depends on: Flutter SDK only; no domain-specific logic
- Used by: All layers (presentation and data)

## Data Flow

**Sender Transfer Pipeline:**

1. User navigates to `SenderScreen` from `HomeScreen`
2. Sender searches for receiver via `KeyRepository.searchUsers(query)` → queries `users` collection with username text index
3. Sender taps receiver → `KeyRepository.sendProposal(partnerUid)` → writes to `neutral_handshakes` collection with deterministic doc ID `${senderUid}_${receiverUid}` and status `pending`
4. Receiver taps "Accept" in `FindFriendsScreen._SearchResultTile` → `HandshakeRepository.acceptProposal()` → updates doc status to `accepted` + both directional docs created
5. Receiver navigates to `ReceiverScreen`, taps receiver setup step → generates RSA keypair via `EncryptionService.setupReceiverSession()` in compute isolate, saves private key to `FlutterSecureStorage`, publishes public key to Firestore `users.{uid}.publicKey`
6. Receiver selects sender from Active Connections list (populated by `KeyRepository.streamFriends()`) → calls `SessionManager.selectSender(uid, username)`
7. Selection triggers `KeyRepository.publishRSAPublicKey(targetUserId)` → upserts `rsa_key_transfers` doc with receiver's public key JSON + status `handshake_complete`
8. Sender listens via `KeyRepository.streamHandshakesForSender()` (query: `rsa_key_transfers WHERE toUserId==senderUid AND status==handshake_complete`)
9. Sender stream emits → shows "Secure Channel Established / Key received from @username" badge; caches receiver's public key JSON
10. Sender picks file via `FilePicker.platform.pickFiles()` → gets `PlatformFile` with `path` (mobile/desktop) or `bytes` (web)
11. Sender calls `_encryptFile()`:
    - Calls `TransferService.resolve(filePath: file.path, fallbackBytes: file.bytes)` → returns `Uint8List` of plaintext
    - Calls `registerBuffer(plaintext)` (safety net)
    - Calls `compute(runAesGcmEncrypt, [plaintext, key, iv])` → AES-256-GCM encryption in background isolate
    - Receives ciphertext back on main thread
    - Calls `plaintext.fillRange(0, plaintext.length, 0)` to zero plaintext
    - Calls `unregisterBuffer(plaintext)` to deregister from buffer registry
12. Sender encrypts AES key with receiver's RSA public key → `compute(_rsaOaepEncryptIsolate, [publicKeyJson, aesKey])` → RSA-OAEP in isolate
13. Sender calls `TransferRepository.uploadAndCreate()`:
    - Generates unique transfer ID via `_db.collection(transfers).doc().id`
    - Uploads ciphertext to `Firebase Storage/transfers/{transferId}/encrypted_file` via `ref.putData(encryptedBytes)`
    - Yields progress updates (0.0 → 1.0) via async generator
    - Creates transfer doc in `transfers` collection with senderId, receiverId, encryptedAESKey (base64), iv (base64), downloadUrl, fileName, fileSize, status: `pending`
14. Sender navigates to `TransferProgressScreen`
15. `TransferProgressScreen` listens to transfer doc via `FirebaseFirestore.instance.collection(transfers).doc(transferId).snapshots()`
16. When receiver saves file, transfer doc updates with `receiverStatus: 'saved'`; progress UI shows "Keys destroyed. Waiting for receiver to terminate session…"
17. Receiver updates transfer doc with `cleanup_initiated: true` after wiping keys
18. Sender detects `cleanup_initiated` → UI shows "Secure session terminated"; waits for transfer doc deletion
19. On transfer doc deletion, sender auto-navigates to `SenderSessionEndedScreen`

**Receiver Decrypt Pipeline:**

1. Receiver's `ReceiverScreen._transferStream` listens to transfers collection (query: `WHERE receiverId == uid AND status == pending`)
2. When sender uploads transfer, doc appears → `_handleIncomingTransfer()` fires
3. `SessionManager.lock()` → state transitions to `locked` (CrypButton turns amber, blocks interaction)
4. `SessionManager.setDecrypting()` → state transitions to `decrypting`
5. Auto-navigate to `ReceiverTransferScreen` via `_onSessionStateChanged()` listener
6. `ReceiverTransferScreen` loads transfer doc + fetches sender's public key from `users.{senderId}.publicKey`
7. Calls `_loadAESKey()` → `compute(_decryptAesKeyIsolate, [privateKeyJson, encryptedAESKey])` → RSA-OAEP decryption of AES key in isolate
8. Downloads ciphertext from Storage via `FirebaseStorage.instance.ref(storageUrl).getData()`
9. Calls `EncryptionService.decryptAesGcm()` → `compute(runAesGcmDecrypt, [ciphertext, key, iv])` → AES-256-GCM decryption in isolate
10. Receives plaintext back on main thread
11. Navigates to `DecryptScreen` with transfer ID
12. `DecryptScreen._loadTransfer()` loads transfer doc, writes plaintext to temp file via `getTemporaryDirectory()`, shows preview
13. User taps "Save File"
14. Calls `_saveAndWipe()`:
    - Invokes native channel `MethodChannel('com.example.cryptransfer/file').invokeMethod('saveToDownloads', {fileName, bytes})` → Android saves to public Downloads folder
    - Calls `_deleteTempFile()` to remove temp file
    - Updates transfer doc with `receiverStatus: 'saved'` + `receivedAt: serverTimestamp()`
    - Calls `_updateTransferStatus('completed')`
15. Receiver navigates to `ReceiverEndSessionScreen`
16. Calls `endSessionCleanup()`:
    - Updates transfer doc with `cleanup_initiated: true`
    - Calls `EncryptionService.closeReceiverSession(uid)` → reactive binding deletes public key from Firestore + private key from SecureStorage
    - Calls `KeyRepository.disconnectFriend(senderUid)` → `WriteBatch` removes both directional friendship docs
    - Deletes transfer doc via `_db.collection(transfers).doc(transferId).delete()`
17. Calls `Navigator.pushAndRemoveUntil()` → `HomeScreen` (clears back stack)

**Session Kill-Switch Flow:**

1. User toggles "Ready to Receive" switch off in `ReceiverScreen` → calls `_onToggleReady(false)`
2. Calls `SessionManager.reset()` → `clearSender()` + `_set(SessionState.open)`
3. `SessionManager.stateStream` emits `SessionState.open`
4. `EncryptionService.bindSession()` listener checks state; if not `terminated`, no action
5. **OR** app backgrounded/killed → `didChangeAppLifecycleState()` fires with `AppLifecycleState.paused` or `detached`
6. Calls `SessionManager.handleLifecycleState(lifecycle, onBuffersWipe: ...)` → checks if state is paused/detached
7. Calls `SessionManager.wipeSession(onBuffersWipe: ...)` → `clearSender()` + `_set(SessionState.terminated)`
8. `SessionManager.stateStream` emits `SessionState.terminated`
9. `EncryptionService.bindSession()` listener receives event → calls `closeReceiverSession(uid)`
10. `closeReceiverSession(uid)` performs atomic cleanup:
    - Deletes receiver's public key from `users.{uid}` doc via `_db.collection(users).doc(uid).update({publicKey: FieldValue.delete()})`
    - Wipes private key from `FlutterSecureStorage` via `_secure.delete(key: 'private_key_${uid}')`
    - Batch-deletes all `rsa_key_transfers` docs where `toUserId == uid` (removes sender authorization)
    - Batch-deletes all notification docs (clears stale connection alerts)
    - Calls `_logSecurityEvent()` to write audit event (no key material in log)
    - Calls `SecurityLifecycleMixin.requestNativeClear()` → invokes `clearSession` on Kotlin channel → `System.gc()` hint
11. Sender's `streamHandshakesForSender()` listener detects deleted `rsa_key_transfers` doc → stream emits empty list → calls `_revertToWaiting()` → clears cached receiver public key, resets UI to "Waiting for Connection" state
12. `SecurityLifecycleMixin.wipeAll()` called → iterates all `_radioactiveBuffers` → calls `fillRange(0, length, 0)` on each → clears registry

**State Management:**

- `SessionManager.stateNotifier` — `ValueNotifier<SessionState>` updated by `_set()`, read by UI via `.watch()` in `SenderScreen` step buttons (CrypButton disables when not open)
- `SessionManager.stateStream` — broadcast `Stream<SessionState>` emitted by `_set()`, subscribed by `EncryptionService.bindSession()` for reactive cleanup
- Firestore snapshots subscribed in `initState`, cancelled in `dispose` (prevents memory leaks)
- `StreamController.broadcast()` used for progress tracking (e.g., `_progressCtrl` in `SenderScreen._encryptFile()` emits 0.0–1.0)
- No Redux/BLoC used; Provider only for app-level theme switching via `ThemeService` (ChangeNotifierProvider in main.dart)

## Key Abstractions

**SessionManager** (`lib/core/utils/session_manager.dart`):
- Purpose: Centralizes receiver session state (open/locked/decrypting/terminated) and kill-switch orchestration
- Pattern: Singleton per ReceiverScreen instance; no static state
- Exposes: `stateNotifier` (ValueNotifier) for UI updates, `stateStream` (broadcast Stream) for reactive EncryptionService binding
- Methods: `selectSender(uid, username)`, `clearSender()`, `lock()`, `setDecrypting()`, `reset()`, `wipeSession()`, `handleLifecycleState()`
- Ensures: One active sender per session; idempotent wipeSession (subsequent calls no-op if already terminated)

**SecurityLifecycleMixin** (`lib/core/utils/security_lifecycle_mixin.dart`):
- Purpose: Automatic Uint8List zero-wipe on screen dispose; Kotlin FLAG_SECURE pre-flight check before chunk reads
- Pattern: Mixin applied to stateful widgets handling sensitive data
- Applied to: `SenderScreen`, `ReceiverScreen`, `DecryptScreen`, `TransferProgressScreen`, `DownloadConfirmScreen`, `EndSessionScreen`, `ReceiverEndSessionScreen`
- Methods: `registerBuffer(buffer)`, `unregisterBuffer(buffer)`, `wipeAll()`, `isFlagSecureActive()` (static async), `requestNativeClear()` (static async)
- Guarantees: All registered buffers zeroed before screen exit via `fillRange(0)`; pre-flight FLAG_SECURE check before TransferService reads

**EncryptionService** (`lib/data/services/encryption_service.dart`):
- Purpose: Hybrid crypto (RSA-OAEP for AES key wrapping, AES-256-GCM for file encryption); reactive kill-switch binding
- Pattern: Static methods delegating to top-level isolate functions via `compute()`; session lifecycle hooks
- Key methods:
  - `generateRsaKeyPairSync()` — synchronous RSA-2048 generation (runs in isolate via compute)
  - `encryptAesGcm(plaintext)` — returns `AesEncryptResult` with ciphertext, key, IV
  - `decryptAesGcm(ciphertext, key, iv)` — returns plaintext
  - `rsaEncrypt(publicKey, data)` — RSA-OAEP
  - `rsaDecrypt(privateKeyJson, ciphertext)` — RSA-OAEP
  - `bindSession(stateStream, uid)` — subscribes to SessionManager.stateStream, calls closeReceiverSession on terminated
  - `unbindSession()` — cancels subscription
  - `closeReceiverSession(uid)` — atomic Firestore/SecureStorage cleanup

**TransferService** (`lib/data/services/transfer_service.dart`):
- Purpose: Memory-stable file I/O for large transfers (64 KB chunked reads)
- Pattern: Static utility methods; no state
- Key methods:
  - `resolve(filePath, fallbackBytes)` — picks path-based read on mobile/desktop, fallback bytes on web
  - `readFile(filePath)` — allocates full file buffer, fills via 64 KB async chunks
  - `readFileWithProgress(filePath, onProgress)` — calls onProgress callback (0.0–1.0) after each chunk
  - `readChunked(filePath)` — yields chunks as Stream<Uint8List>
- Prevents: Unbounded heap allocation; GC contention between file reads and AES-GCM buffers

**KeyRepository** (`lib/data/repositories/key_repository.dart`):
- Purpose: RSA key exchanges, user connections, handshake lifecycle
- Pattern: Instance class with injected `FirebaseFirestore`, `FirebaseAuth`, `FlutterSecureStorage`
- Key methods:
  - `searchUsers(query)` — Firestore query on username field
  - `sendConnectionRequest(targetUserId)` → `sendProposal()` in HandshakeRepository
  - `publishRSAPublicKey(targetUserId)` — writes RSA public key JSON to `rsa_key_transfers` doc
  - `streamHandshakesForSender()` — Firestore query stream: `rsa_key_transfers WHERE toUserId==uid AND status==handshake_complete`
  - `disconnectFriend(partnerUid)` — WriteBatch removes both directional friendship docs
  - `getConnectionStatus(otherUserId)` — checks if users are already connected

**TransferRepository** (`lib/data/repositories/transfer_repository.dart`):
- Purpose: File transfer CRUD (upload to Storage, create transfer doc, notify receiver)
- Pattern: Instance class with injected `FirebaseFirestore`, `FirebaseStorage`
- Key methods:
  - `generateId()` — creates unique transfer doc ID
  - `uploadAndCreate()` — returns `Stream<double>` (async generator) yielding 0.0–1.0 progress
  - `notifyReceiver()` — creates notification doc after upload
  - `updateReceiverStatus()` — updates transfer doc `receiverStatus` field
  - `writeAuditLog()` — writes to `transfers_log` collection for non-repudiation

## Entry Points

**Mobile/Desktop:**
- Location: `lib/main.dart` → `CrypTransferApp` StatelessWidget
- Entry: `runApp(ChangeNotifierProvider(create: (_) => ThemeService(), child: CrypTransferApp()))`
- Triggers: `flutter run` on dev machine or Play Store install on device
- Flow: Firebase initialization → MaterialApp with `SplashScreen` as home
- Responsibilities: Firebase platform-specific options, theme provider setup, route configuration

**SplashScreen Entry:**
- Location: `lib/presentation/auth/splash_screen.dart`
- Triggers: App startup after main.dart
- Flow: Checks `FirebaseAuth.currentUser` → routes to `LoginScreen` (not authenticated) or `HomeScreen` (authenticated)
- Responsibilities: Auth state check, initial Firebase connectivity validation

**HomeScreen Navigation:**
- Location: `lib/presentation/home/home_screen.dart`
- Tabs: Send (→ `SenderScreen`), Receive (→ `ReceiverScreen`), Connections (→ `FindFriendsScreen`)
- Admin dashboard accessible via drawer if `isAdmin` flag set in Firestore

**Android Native Entry:**
- Location: `android/app/src/main/kotlin/com/example/cryptransfer/MainActivity.kt` → `onCreate()`
- Triggers: Android app launch from home screen
- Flow: Inherits from `FlutterActivity` → `onCreate()` sets `FLAG_SECURE` → `configureFlutterEngine()` registers MethodChannels
- Responsibilities: Window security hardening, native-Dart bridge setup for FLAG_SECURE checks and file saves

## Error Handling

**Strategy:** Typed exception hierarchy with upstream propagation to presentation layer for user feedback.

**Exception Types:**

| Exception | Cause | Handling |
|-----------|-------|----------|
| `AuthException` | Firebase Auth failures, unauthenticated user, missing credentials | Caught in login/register screens; snackbar with actionable message |
| `NetworkException` | Firestore/Storage connection failures, permission errors | Retryable; snackbar with retry button or manual re-initiate |
| `CryptoException` | RSA/AES operation failures, isolate crashes | Fatal; blocks transfer; error dialog suggests restart |
| `KeyNotFoundException` | Missing RSA private/public key | Prompts key regeneration or connection reset |
| `TransferException` | Transfer doc operations fail | Caught in sender/receiver flow; stops transfer with error dialog |

**Recovery Patterns:**

- **No automatic retries** for I/O errors; user manually retries via UI button
- **Firestore security rule violations** return detailed error code (e.g., `PERMISSION_DENIED`) → mapped to user-friendly message
- **Compute isolate crashes** caught in `compute()` as exception, wrapped in `CryptoException`, propagated to caller
- **Missing MethodChannel** in `isFlagSecureActive()` swallowed safely (returns `true` on error to prevent blocking transfers)

**Example:**
```dart
try {
  await _repo.uploadAndCreate(...);
} on TransferException catch (e) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Upload failed: ${e.message}'))
  );
} on NetworkException catch (e) {
  // Offer retry
}
```

## Cross-Cutting Concerns

**Logging:**
- No persistent logging to disk
- `debugPrint()` disabled in production builds
- **No key material logged** — explicit ban in CLAUDE.md (SecurityLifecycleMixin docs specify "key data" banned)
- Audit logging via `TransferLogService.writeAuditLog()` — stores transfer events (senderId, receiverId, status) without key material

**Validation:**
- **File size**: Implicit via file picker; no explicit upload size limit in code
- **Username**: Minimum 2 characters for search queries (`KeyRepository.searchUsers()`)
- **RSA public key**: JSON deserialization validates format; parse error → `KeyNotFoundException`
- **AES key length**: 32 bytes enforced in `runAesGcmEncrypt()`; IV 12 bytes; GCM tag 16 bytes
- **Transfer metadata**: NonNull fields validated during model construction (`TransferModel.fromDoc()`)

**Authentication:**
- **Firebase Auth token** required for all Firestore/Storage operations
- **TOFU key pinning** via `TofuService` (lib/core/utils/tofu_service.dart) — receiver pins sender's RSA public key on first transfer, subsequent transfers verify match
- **Biometric auth** (Face ID) via `BiometricHelper` for private key access on first decrypt attempt of session

---

*Architecture analysis: 2026-05-25*
