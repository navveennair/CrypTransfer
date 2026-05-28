# Architecture — CrypTransfer

**Mapped:** 2026-05-28
**Type:** Mobile (Flutter / Android focus) + Firebase (Firestore / Auth / Storage)

---

## 1. High-Level Pattern

**Three-layer clean architecture** with reactive state management:

```
┌──────────────────────────────────────────────────────────────┐
│  Presentation  (lib/presentation/)                           │
│  Screens + widgets — Material 3, StatefulWidgets,            │
│  StreamBuilders backed by stable State-field streams.        │
└────────────────────────┬─────────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────────┐
│  Data  (lib/data/)                                           │
│  Repositories (Firestore I/O) + Services (crypto, chunked    │
│  file I/O, transfer-log fan-out).                            │
└────────────────────────┬─────────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────────┐
│  Core  (lib/core/)                                           │
│  Cross-cutting: SessionManager state machine,                │
│  SecurityLifecycleMixin (buffer wipe), constants, errors.    │
└──────────────────────────────────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────────┐
│  Native bridge  (android/.../MainActivity.kt)                │
│  FLAG_SECURE, clearSession via MethodChannel.                │
└──────────────────────────────────────────────────────────────┘
```

Cross-layer reactivity is the key trick: `SessionManager` exposes a broadcast `Stream<SessionState>`; the data layer (`EncryptionService.bindSession`) and the presentation layer (`CrypButton.sessionState`, `ReceiverTransferScreen` listener) both subscribe — no manual orchestration from screens to trigger crypto cleanup.

---

## 2. Entry Points

| Entry | File | Role |
|-------|------|------|
| Dart `main()` | `lib/main.dart` | Firebase init, theme bootstrap, `MaterialApp` mount |
| Theme | `lib/app_theme.dart` | GitHub Dark + custom gold/purple ColorScheme |
| Firebase config | `lib/firebase_options.dart` | Generated `DefaultFirebaseOptions` |
| Android | `android/app/src/main/kotlin/com/example/cryptransfer/MainActivity.kt` | `FlutterActivity`, sets `FLAG_SECURE` in `onCreate`, registers `com.example.cryptransfer/security` MethodChannel |
| First route (logged out) | `lib/presentation/auth/splash_screen.dart` → onboarding/login |
| First route (logged in) | `lib/presentation/home/home_screen.dart` |

---

## 3. Layers in Detail

### 3.1 Core (`lib/core/`)

Cross-cutting concerns. No Flutter widget code; pure Dart + Firebase SDK.

| File | Purpose |
|------|---------|
| `core/constants/firebase_constants.dart` | Centralised collection names (`users`, `handshakes`, `transfers`, `transfer_logs`, `neutral_handshakes`) |
| `core/errors/app_exceptions.dart` | Typed exceptions (e.g. `KeyNotFoundException`) |
| `core/services/auth_method_service.dart` | Auth-method bookkeeping (which providers a user has linked) |
| `core/utils/biometric_helper.dart` | `local_auth` 3.0.1 wrapper — `persistAcrossBackgrounding: true`; no `options:` wrapper |
| `core/utils/file_utils.dart` | Path / filename helpers |
| `core/utils/notification_service.dart` | In-app notification orchestration (`notifications` Firestore subcollection) |
| `core/utils/security_lifecycle_mixin.dart` | **God node.** `registerBuffer` / `unregisterBuffer` / `wipeAll`; queries `isFlagSecureActive` via MethodChannel; static `requestNativeClear()` invokes `clearSession`. Applied to every screen that touches key material. |
| `core/utils/session_manager.dart` | `SessionState` machine + `Stream<SessionState>` broadcast; `selectSender`, `clearSender`, `lock`, `setDecrypting`, `reset`, `wipeSession`, `handleLifecycleState` |
| `core/utils/session_state.dart` | Standalone `SessionState` enum (extracted to break circular import between `SessionManager` and `EncryptionService`) |
| `core/utils/theme_service.dart` | Theme mode persistence + switching |
| `core/utils/tofu_service.dart` | Trust-on-first-use key-pinning helpers |

### 3.2 Data — Repositories (`lib/data/repositories/`)

Pure Firestore I/O. No widget references. All `Future<T>` / `Stream<T>` returning.

| Repository | Responsibility |
|------------|----------------|
| `auth_repository.dart` | Email/password + provider auth, user profile bootstrap |
| `user_repository.dart` | `users/{uid}` reads/writes (publicKey, isReadyToReceive, selectedSenderUid, sessionActive, isAdmin) |
| `key_repository.dart` | RSA public key publishing + receiver-authorized handshake. **`selectSenderHandshake()`** uses atomic `WriteBatch`: writes `selectedSenderUid` on user doc + upserts `handshakes/{receiverId}_{senderId}` in one commit. Streams: `streamHandshakesForSender()`, `isHandshake` flag stamps `handshake_complete`. |
| `handshake_repository.dart` | Friend-connection layer on `neutral_handshakes`. `sendProposal`, `acceptProposal` (uses `runTransaction` for TOCTOU safety), `disconnectFromUser` (`WriteBatch` removes both directions), `streamHandshakeWithUser` (merges deterministic `${a}_${b}` + `${b}_${a}` doc streams via single-subscription `StreamController.broadcast()`) |
| `transfer_repository.dart` | `transfers/{id}` lifecycle: create, `updateReceiverStatus`, `writeAuditLog` (writes to `transfer_logs` with `participants` array) |
| `cleanup_repository.dart` | End-of-session deletion: transfer doc, storage object, audit log |
| `admin_repository.dart` | Admin-only reads across all transfer logs / users |

### 3.3 Data — Services (`lib/data/services/`)

Stateful or compute-heavy logic. Pure Dart (no Flutter widgets).

| Service | Responsibility |
|---------|----------------|
| `encryption_service.dart` | Hybrid RSA + AES via PointyCastle. All crypto inside `compute()` isolates (was `Isolate.run()`; migrated to silence guardian WARNING). Key methods: `generateAndStoreKeyPair`, `encryptFile`, `decryptFile`, `closeReceiverSession`, `bindSession(stateStream, uid)` → subscribes to `SessionManager.stateStream` and auto-fires `closeReceiverSession` on `terminated`, `unbindSession()` |
| `transfer_service.dart` | `kChunkSize = 64 KB`; `readFile()` chunks via `File.openRead()`; `resolve()` picks chunked path-read on mobile/desktop, falls back to `bytes` on web. Used by `SenderScreen._encryptFile` for memory-stable large-file handling. |
| `transfer_log_service.dart` | Wraps audit-log writes with consistent `participants` array shape |

### 3.4 Presentation (`lib/presentation/`)

Grouped by feature area, not by widget type.

| Area | Top-level files |
|------|-----------------|
| `auth/` | splash → onboarding → login/register |
| `home/` | `home_screen.dart` (entry), `find_friends_screen.dart` (search + connect, `_SearchResultTile` streams per-user handshake status), `sidebar_drawer.dart`, `notifications_screen.dart` |
| `receiver/` | `receiver_screen.dart` (owns SessionManager), `receiver_transfer_screen.dart` (now receives `SessionManager` via constructor + listener), `decrypt_screen.dart` (Save & Suicide), `receiver_end_session_screen.dart` |
| `sender/` | `sender_screen.dart` (uses `TransferService.resolve`, FLAG_SECURE pre-flight), `transfer_progress_screen.dart` (non-repudiation listener + reactive cleanup-sync), `sender_session_ended_screen.dart` |
| `session/` | `end_session_screen.dart` (legacy / shared end-session flow) |
| `admin/` | `admin_dashboard.dart`, `admin_dashboard_screen.dart`, + widgets: `connection_node_map.dart`, `security_pulse_feed.dart`, `transfer_volume_chart.dart`, `user_management_list.dart` |
| `vault/` | `rsa_key_manager_screen.dart` |
| `settings/` | `settings_screen.dart` |
| `widgets/` | `shared_widgets.dart` — `CrypButton` (3D glassmorphic; replaces `GlassButton`; reacts to `SessionState`), other shared atoms |

---

## 4. Key Data Flows

### 4.1 Receiver-Authorized Handshake (the new connection model)

```
Receiver: opens mailbox (toggle ON)
   ↓
SessionManager.reset() → state=open
   ↓
Receiver searches/selects a sender (FindFriendsScreen or ReceiverScreen sender picker)
   ↓
KeyRepository.selectSenderHandshake() — atomic WriteBatch:
   • users/{receiverId}.selectedSenderUid = senderId
   • handshakes/{receiverId}_{senderId} = { receiverId, senderId, publicKey, status: 'handshake_complete' }
   ↓
Sender's stream (KeyRepository.streamHandshakesForSender) emits → _ConnectedBadge shown
   ↓
Sender picks file → SenderScreen._encryptFile:
   • SecurityLifecycleMixin.isFlagSecureActive() ?  (else abort)
   • TransferService.resolve(file)  →  Uint8List plaintext  (chunked 64KB on mobile/desktop)
   • registerBuffer(plaintext)
   • compute(encryptFile, {plaintext, receiverPublicKey})  →  {key, iv, ciphertext, encryptedAESKey}
   • plaintext.fillRange(0, …, 0); unregisterBuffer(plaintext)
   • Upload ciphertext to Firebase Storage, write transfers/{id} doc, write audit log
   ↓
Receiver's transfers stream emits  →  ReceiverScreen._handleIncomingTransfer:
   • SessionManager.lock()  →  state=locked  (CrypButton goes amber+lock; UI blocks)
   • SessionManager.setDecrypting()  →  state=decrypting
   ↓
Navigator.push to ReceiverTransferScreen (passes sessionManager)
   • Downloads ciphertext, runs decrypt in compute(), updates receiverStatus at each phase
   • Save & Suicide: write file, wipe buffers, set receiverStatus='saved'
   ↓
Sender's transfer_progress_screen listener sees receiverStatus='saved' → "Waiting for secure session close"
   ↓
Receiver closes (toggle, back-nav, app paused/detached, or explicit "Save & Suicide"):
   • SessionManager.wipeSession() OR handleLifecycleState(paused/detached)
   • SessionManager state → terminated   →  stateStream emits
   ↓
EncryptionService (bound via bindSession on mailbox open) reacts:
   • closeReceiverSession(uid):
       – delete users/{uid}.publicKey, set isReadyToReceive=false, clear selectedSenderUid
       – delete FlutterSecureStorage private key
       – batch-delete handshakes WHERE receiverId==uid
       – batch-delete notifications (rsa_key_received, type)
       – write transfer_logs entry { status: 'kill_switch', participants }
       – set cleanup_initiated=true on transfer doc  →  sender sees "Keys destroyed"
       – delete transfer doc + storage object via CleanupRepository
       – SecurityLifecycleMixin.requestNativeClear()  →  MethodChannel clearSession  →  System.gc()
   • SecurityLifecycleMixin.wipeAll() — fillRange(0) every registered buffer
   ↓
Sender's listener sees doc deletion  →  navigates to SenderSessionEndedScreen
```

### 4.2 Bidirectional Friend Connection (proposals on `neutral_handshakes`)

```
A sends proposal  →  handshake_repository.sendProposal()
   doc id = ${A}_${B},  status = 'pending'
B accepts          →  handshake_repository.acceptProposal()  (runTransaction — TOCTOU safe)
   status = 'connected',  connections sub-collections updated for both users
Disconnect         →  handshake_repository.disconnectFromUser(B)  (WriteBatch — atomic both sides)
```

Per-user search-result tile (`FindFriendsScreen._SearchResultTile`) subscribes to `streamHandshakeWithUser(partnerUid)` and renders Pending → Connected without re-search.

### 4.3 Kill-Switch Dispatch Matrix

| Trigger | Method called | Resulting `SessionState` |
|---------|---------------|--------------------------|
| Toggle switch off | `_onToggleReady(false)` → `SessionManager.reset()` | `open` (clean) |
| Incoming transfer detected | `_handleIncomingTransfer` → `SessionManager.lock()` | `locked` |
| Decryption starts | `SessionManager.setDecrypting()` | `decrypting` |
| Back navigation (`PopScope`) | `SessionManager.wipeSession()` | `terminated` |
| App backgrounded/killed | `SessionManager.handleLifecycleState(paused/detached)` | `terminated` |
| Screen `dispose()` | `SecurityLifecycleMixin.wipeAll()` | (buffers only) |

---

## 5. Abstractions Worth Knowing

### 5.1 `SecurityLifecycleMixin`
- Mixed into every screen handling key material: `SenderScreen`, `ReceiverScreen`, `TransferProgressScreen`, `DownloadConfirmScreen`/`DecryptScreen`, `EndSessionScreen`, `ReceiverTransferScreen`.
- API: `registerBuffer(Uint8List)`, `unregisterBuffer(Uint8List)`, `wipeAll()`, static `isFlagSecureActive()`, static `requestNativeClear()`.
- Auto-wipes on `dispose()`.

### 5.2 `SessionManager`
- Owns the active sender selection + session state for one receiver session.
- Broadcast `Stream<SessionState>` enables reactive binding without screen-level wiring.
- Stored field on the screen (NOT `InheritedWidget`-distributed) — explicit constructor propagation for screens that need it (`ReceiverTransferScreen`).

### 5.3 `CrypButton`
- 3D glassmorphic button system; replaces the older `GlassButton`.
- Reads `sessionState` and overrides face colour + content:
  - `locked` → amber + lock icon, interaction blocked
  - `decrypting` → primary + spinner, interaction blocked
  - `terminated` → error red + block icon, interaction blocked
- `StatefulWidget` with `_isPressed`, `HapticFeedback.lightImpact()`, `transformAlignment: Alignment.center` on the scale `AnimatedContainer`, `Matrix4.diagonal3Values` replacing deprecated `..scale()`.

### 5.4 Atomic Firestore patterns
- `runTransaction` — `acceptProposal` (TOCTOU window between read and write).
- `WriteBatch` — `selectSenderHandshake`, `disconnectFromUser`, kill-switch delete-handshakes, kill-switch delete-notifications.
- Deterministic doc IDs — `${receiverId}_${senderId}` (handshakes), `${proposerId}_${partnerId}` (neutral_handshakes). Idempotent re-sends, no duplicates.

### 5.5 Stable-stream rule
- StreamBuilders MUST be backed by a `Stream` field stored on `State`, assigned in `initState()` or once-only setters (e.g. `_onSenderSelected`).
- **Never** construct `Stream` inline in `build()` — caused the receiver double-subscription bug; root-caused and fixed.

---

## 6. Native Bridge

### 6.1 MethodChannel: `com.example.cryptransfer/security`

| Method | Kotlin (MainActivity) | Dart |
|--------|------------------------|------|
| `isFlagSecureActive` | returns `(window.attributes.flags & FLAG_SECURE) != 0` | `SecurityLifecycleMixin.isFlagSecureActive()` — queried before each 64 KB chunk read in `SenderScreen._encryptFile` |
| `clearSession` | `System.gc()` — best-effort heap-release hint (no key material is held natively) | `SecurityLifecycleMixin.requestNativeClear()` — final step of `EncryptionService.closeReceiverSession` |

### 6.2 Window flag
- `MainActivity.onCreate()` calls `window.addFlags(FLAG_SECURE)` — blocks screenshots and task-switcher thumbnails app-wide, no per-screen Flutter changes required.

---

## 7. Cluster Map (from `graphify-out/graph.json`)

| Cluster | Members |
|---------|---------|
| **Encryption Engine** | `encryption_service.dart`, `pointycastle`, `flutter_secure_storage`, `compute()` |
| **Kill Switch & Wipe Lifecycle** | `SecurityLifecycleMixin`, `SessionManager`, `closeReceiverSession`, `wipeAll`, `requestNativeClear` |
| **Session State Machine** | `SessionManager`, `SessionState`, `stateStream`, `EncryptionService.bindSession` |
| **Receiver-Authorized Handshake** | `key_repository.selectSenderHandshake`, `streamHandshakesForSender`, `handshakes/` collection, `_WaitingForConnectionWidget`, `_ConnectedBadge` |
| **Native Bridge** | `MainActivity.kt`, `com.example.cryptransfer/security` channel, `FLAG_SECURE`, `clearSession` |
| **DevOps & Tooling** | `android/app/build.gradle.kts`, `proguard-rules.pro`, `scripts/silent_guardian.ps1`, `scripts/update_status.ps1`, Obsidian vault writers |

`SecurityLifecycleMixin` is a god node (10 edges) bridging Security Screen Lifecycle ↔ Receiver Kill Switch ↔ Encryption Engine.

---

## 8. Out-of-Process Components

| Component | Where | Purpose |
|-----------|-------|---------|
| **Firebase Project `cryptransfer-96e9f`** | cloud | Auth + Firestore + Storage + security rules |
| **Obsidian Vault** | `C:\Users\navve\ObsidianVault\CrypTransfer\` | Daily report + Security audit destination (`scripts/write_obsidian_report.dart`, `scripts/security_audit_report.dart`) |
| **Silent Guardian** | `scripts/silent_guardian.ps1` (via `launch_guardian.bat`, Task Scheduler) | Headless scanner — runs CLAUDE.md scanner rules against `lib/`, writes audit Markdown to vault |
| **Status updater** | `scripts/update_status.ps1` | Runs `flutter analyze`, syncs Known Open Issues ↔ Completed Features in `CLAUDE.md` |
