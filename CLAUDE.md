
## Architecture & Design

### UI Framework
- **Core**: Flutter with Material 3 enabled.
- **Theme**: Custom **GitHub Dark** palette.
  - Background: `#0D1117` (`githubDarkBg`)
  - Surface: `#161B22` (`githubDarkSurface`)
  - Primary: `#58A6FF` (`githubDarkPrimary`)
- **Rendering**: **Impeller Backend** (OpenGLES) used for enhanced performance and security against UI-layer side-channel attacks.

### Admin Dashboard
The system includes an Admin Dashboard (`lib/presentation/admin/`) for platform oversight:
- **Connection Node Map**: Real-time visualization of active transfer nodes.
- **User Management**: Privilege control via the `isAdmin` Firestore field.
- **Audit Integration**: Direct connection to the top-level `transfers_log` collection for global activity monitoring.

### Data Model (Graphify Data Nodes)
Main data entities as identified by the system graph:
- **Handshakes (`rsa_key_transfers`)**: Stores ephemeral RSA public keys and handshake status (`handshake_complete`) for secure AES key exchange.
- **Transfers (`transfers`)**: Tracks active file transfer metadata, initialization vectors (IV), and encrypted AES keys.
- **User Audit (`transfers_log`)**: Immutable record of transfer events, including `participants` and security lifecycle events.
- **User Profiles (`users`)**: Identity documents containing `publicKey`, `isReadyToReceive` status, and `isAdmin` flags.

---

## Project Structure

### Layer Architecture
```
lib/
├── core/
│   └── utils/
│       ├── security_lifecycle_mixin.dart   ← Uint8List zero-wipe mixin (applied to all screens)
│       └── session_manager.dart            ← SessionState enum + kill-switch handshake
├── data/
│   ├── repositories/
│   │   ├── auth_repository.dart
│   │   ├── key_repository.dart
│   │   └── transfer_repository.dart        ← updateReceiverStatus(), writeAuditLog()
│   └── services/
│       ├── encryption_service.dart         ← Hybrid crypto + closeReceiverSession()
│       └── transfer_service.dart           ← 64 KB chunked file reads (TransferService.resolve)
└── presentation/
    ├── receiver/
    │   ├── receiver_screen.dart             ← owns SessionManager; delegates kill-switch
    │   └── receiver_transfer_screen.dart    ← DecryptScreen / Save & Suicide
    ├── sender/
    │   ├── sender_screen.dart               ← uses TransferService.resolve for memory-stable reads
    │   └── transfer_progress_screen.dart    ← Non-repudiation Firestore listener
    ├── session/
    │   └── end_session_screen.dart
    └── widgets/
        └── shared_widgets.dart              ← CrypButton 3D system + SessionState visual feedback
```

### Kill Switch: UI → SessionManager → Encryption Service Chain

The "Closed Mailbox" kill switch flows through `SessionManager` which owns the `SessionState` and orchestrates the wipe:

```
UI trigger
    │
    ▼
SessionManager.handleLifecycleState()  ← paused/detached lifecycle
SessionManager.wipeSession()           ← PopScope back-nav
SessionManager.reset()                 ← manual close via _onToggleReady
    │
    ├── stateNotifier → SessionState.terminated  (CrypButton reacts)
    ├── EncryptionService.closeReceiverSession()
    │       ├── Firestore: delete publicKey, isReadyToReceive=false
    │       ├── FlutterSecureStorage: delete private key
    │       ├── Batch-delete rsa_key_transfers (fromUserId)
    │       ├── Batch-delete notifications (rsa_key_received, fromUserId)
    │       └── _logSecurityEvent (no key material)
    └── onBuffersWipe()  →  SecurityLifecycleMixin.wipeAll()
            └── Uint8List.fillRange(0) for every registered buffer
```

| UI Trigger | Method | SessionState after |
|---|---|---|
| Toggle switch off | `_onToggleReady(false)` → `reset()` | `open` |
| Incoming transfer | `_handleIncomingTransfer` → `lock()` | `locked` |
| Back navigation (PopScope) | `wipeSession()` | `terminated` |
| App backgrounded/killed | `handleLifecycleState(paused/detached)` | `terminated` |
| `dispose()` auto-wipe | `SecurityLifecycleMixin.wipeAll()` | — (buffers zeroed) |

`SessionState` enum: `open` · `locked` · `decrypting` · `terminated`  
`CrypButton` reads `sessionState` and overrides face colour + content:
- `locked` → amber + lock icon, interaction blocked
- `decrypting` → primary + spinner, interaction blocked
- `terminated` → error red + block icon, interaction blocked

`SecurityLifecycleMixin` is a **god node** (10 edges in graph) bridging `Security Screen Lifecycle`, `Receiver Kill Switch`, and `Encryption Engine` communities. Applied to: `SenderScreen`, `ReceiverScreen`, `TransferProgressScreen`, `DownloadConfirmScreen`, `EndSessionScreen`, `DecryptScreen`.

### Android Entry Point

```
android/
├── key.properties                ← git-ignored; holds keyAlias/keyPassword/storeFile/storePassword
├── app/
│   ├── build.gradle.kts          ← signing config + R8 minification wired up
│   ├── proguard-rules.pro        ← Flutter/Firebase/PointyCastle keep rules
│   └── src/main/kotlin/com/example/cryptransfer/
│       └── MainActivity.kt       ← FLAG_SECURE (onCreate) + security MethodChannel
└── settings.gradle.kts
```

**Security hardening — DONE:**
- `FLAG_SECURE` set in `MainActivity.onCreate()` — blocks task-switcher thumbnails and screenshots at the Android window level. Applies to every Flutter screen without per-screen changes.
- R8 minification enabled for release (`isMinifyEnabled = true`, `isShrinkResources = true`) with `proguard-android-optimize.txt` + `proguard-rules.pro`.
- Release signing reads from `android/key.properties` (git-ignored). Falls back to debug signing automatically if the file is absent, so `flutter run --release` still works on dev machines.

**To set up release signing on a new machine:**
```
# android/key.properties  (never commit this file)
storeFile=../my-release-key.jks
storePassword=<password>
keyAlias=<alias>
keyPassword=<password>
```

**Native–Dart bridge (explicit cross-references for graph tooling):**

| Native (MainActivity.kt) | Dart counterpart | Purpose |
|---|---|---|
| `window.addFlags(FLAG_SECURE)` in `onCreate()` | `SecurityLifecycleMixin.isFlagSecureActive()` — `lib/core/utils/security_lifecycle_mixin.dart` | Blocks screenshots; Dart queries before each 64 KB chunk read |
| MethodChannel `com.example.cryptransfer/security` → `isFlagSecureActive` | `SecurityLifecycleMixin._securityChannel` — same file | Returns `(flags & FLAG_SECURE) != 0` to Dart layer |
| MethodChannel consumer | `SenderScreen._encryptFile()` — `lib/presentation/sender/sender_screen.dart` | Aborts encryption if window is unprotected |

---

## DevOps & Tooling

All build-config and automation files belong to a single **DevOps & Tooling** cluster. Changes here affect CI, release builds, or the Guardian reporting pipeline — not app logic.

### Android Build Config

| File | Role |
|------|------|
| `android/app/build.gradle.kts` | App-level Gradle: SDK versions, signing config, R8 minification, release AAB output |
| `android/build.gradle.kts` | Project-level Gradle: repository declarations |
| `android/settings.gradle.kts` | Module include + plugin management |
| `android/app/proguard-rules.pro` | Keep rules for Flutter engine, Firebase, PointyCastle — prevents R8 from stripping crypto classes |

### Automation Scripts (`scripts/`)

| File | Role |
|------|------|
| `scripts/silent_guardian.ps1` | Headless security scanner: checks CLAUDE.md scanner rules against `lib/`, writes audit report to Obsidian vault |
| `scripts/update_status.ps1` | Runs `flutter analyze`, syncs Known Open Issues ↔ Completed Features in CLAUDE.md |
| `scripts/security_audit_report.dart` | Dart script: generates structured security audit Markdown for Obsidian |
| `scripts/write_obsidian_report.dart` | Dart script: writes daily summary report to Obsidian vault |
| `scripts/launch_guardian.bat` | Windows batch launcher: runs `silent_guardian.ps1` with headless flags for Task Scheduler |

**Background execution policy:** `powershell.exe -WindowStyle Hidden -NonInteractive -NoProfile -Command`
**Outputs:** `C:\Users\navve\ObsidianVault\CrypTransfer\DailyReports\` · `C:\Users\navve\ObsidianVault\CrypTransfer\Security\`
**Error log:** `C:\Users\navve\projects\cryptransfer\report_error.log`

### State Scanner Rules

When scanning `lib/` for status updates (used by `scripts/silent_guardian.ps1` and `scripts/update_status.ps1`):

- File contains SecurityLifecycleMixin → mark VERIFIED
- File contains compute() for crypto → mark SECURE
- File contains Isolate.run() for crypto → flag WARNING
- File contains raw FirebaseFirestore in screen → flag ISSUE
- File contains debugPrint with key data → flag CRITICAL
- receiver_screen.dart contains closeReceiverSession → mark VERIFIED (Closed Mailbox rule)
- receiver_screen.dart contains didChangeAppLifecycleState → mark VERIFIED (lifecycle auto-wipe)
- receiver_screen.dart contains SessionManager → mark VERIFIED (kill-switch handshake)
- session_manager.dart contains handleLifecycleState → mark VERIFIED (lifecycle delegation)
- sender_screen.dart contains TransferService.resolve → mark VERIFIED (64KB chunked reads)
- transfer_service.dart contains kChunkSize → mark VERIFIED (memory-stable transfer)
- sender_screen.dart _encryptFile contains registerBuffer → mark VERIFIED (plaintext zero-wipe registered)
- sender_screen.dart _encryptFile missing registerBuffer → flag WARNING (plaintext remanence gap)
- sender_screen.dart _encryptFile contains unregisterBuffer → mark VERIFIED (explicit plaintext wipe + deregister after compute)
- sender_screen.dart contains isFlagSecureActive → mark VERIFIED (Kotlin FLAG_SECURE pre-flight)
- receiver_screen.dart contains activeSenderUid → mark VERIFIED (session isolation — one sender)
- receiver_screen.dart contains onSenderSelected → mark VERIFIED (automatic handshake post-selection)
- receiver_screen.dart contains _transferStream → mark VERIFIED (stable Firestore stream; no double-subscription on rebuild)
- receiver_screen.dart contains setDecrypting → mark VERIFIED (reactive navigation to decrypt)
- session_manager.dart contains selectSender → mark VERIFIED (sender UID stored in session)
- key_repository.dart contains isHandshake → mark VERIFIED (handshake_complete stamping)
- sender_screen.dart contains _handshakeSub → mark VERIFIED (receiver-authorized streaming; no static receiver list)
- sender_screen.dart contains _WaitingForConnectionWidget → mark VERIFIED (pulsing wait state until receiver authorizes)
- sender_screen.dart contains _revertToWaiting → mark VERIFIED (stream-driven wipe when receiver closes session)
- key_repository.dart contains selectSenderHandshake → mark VERIFIED (atomic WriteBatch: user doc + rsa_key_transfers in one commit)
- key_repository.dart contains streamHandshakesForSender → mark VERIFIED (sender listens for receiver authorization events)
- encryption_service.dart closeReceiverSession contains selectedSenderUid → mark VERIFIED (kill-switch deletes authorization; sender stream reverts to waiting)
- encryption_service.dart contains bindSession → mark VERIFIED (reactive kill-switch: EncryptionService listens to SessionManager.stateStream)
- encryption_service.dart contains unbindSession → mark VERIFIED (clean teardown on deliberate close or dispose)
- session_manager.dart contains stateStream → mark VERIFIED (broadcast stream enables reactive EncryptionService binding)
- lib/core/utils/session_state.dart exists → mark VERIFIED (SessionState extracted to prevent circular import)
- receiver_screen.dart contains EncryptionService.bindSession → mark VERIFIED (session bind wired at mailbox open)
- receiver_screen.dart contains EncryptionService.unbindSession → mark VERIFIED (session unbind wired at close + dispose)

---

## graphify

This project has a persistent knowledge graph in `graphify-out/graph.json`.

**Before answering codebase questions:** check the graph first with `/graphify query "<question>"` — it maps relationships across files that are slow to re-derive by reading code.

**After code changes:** rebuild the graph with `/graphify . --update` so the graph stays in sync. Code-only changes use AST (no LLM, fast). Doc/image changes need a full semantic pass.

**To explore the graph:** `/graphify query`, `/graphify path`, `/graphify explain` — see the graphify skill for full usage.

---

## ✅ Completed Features

- [x] SecurityLifecycleMixin created
- [x] SenderScreen pre-flight wipe (`_wipeSensitiveData()` + handoff destruction)
- [x] DecryptScreen Save & Suicide pattern (`_saveAndWipe()`, `_Phase.done`, clean-room decrypt)
- [x] SecurityLifecycleMixin applied to SenderScreen, DecryptScreen, TransferProgressScreen, DownloadConfirmScreen, EndSessionScreen
- [x] Non-repudiation Firestore listener in TransferProgressScreen
- [x] `receiverStatus` field updated at each decrypt phase in DecryptScreen
- [x] `updateReceiverStatus()` in TransferRepository
- [x] closeReceiverSession Kill Switch (`EncryptionService.closeReceiverSession()` — public key deleted from Firestore, private key wiped from device, batch-delete rsa_key_transfers + notifications)
- [x] Auto-Wipe on toggle/app close/screen exit:
  - `ReceiverScreen._onToggleReady()` — full open/close mailbox flow
  - `ReceiverScreen._showCloseSessionDialog()` — confirmation bottom sheet before close
  - `WidgetsBindingObserver` + `didChangeAppLifecycleState` — auto-wipe on app pause/detach
  - `PopScope` wrapping ReceiverScreen Scaffold — wipe on back navigation
  - `_sessionLocked` state + `_showSessionLockedBanner()` — blocks close during active transfer
- [x] Session hijack prevention tested
- [x] TC-WIPE-001 to TC-WIPE-006 all passing (`test/security/session_wipe_test.dart`)
- [x] Silent Guardian Kill Switch scanner (FieldValue.delete check, ReceiverScreen wiring check, lifecycle observer check)
- [x] Obsidian Security audit report (`scripts/security_audit_report.dart`)
- [x] `generateAndStoreKeyPair()` migrated from `Isolate.run()` → `compute()` — Guardian WARNING resolved
- [x] `participants` field added to `writeAuditLog()` — HomeScreen Recent Transfers query now satisfied
- [x] `encryptedAESKey` field name drift fixed — all Dart identifiers now use uppercase AES to match Firestore key
- [x] Guardian scanner updated — compute() check, participants check, encryptedAESKey consistency check added
- [x] Session cleanup + pushAndRemoveUntil after EndSession — `canPop` fixed to `_phase == _Phase.ready` (prevents back-nav after done), "Back to Home" uses `Navigator.pushAndRemoveUntil` clearing the full stack, Firestore doc + Storage file + audit log cleanup all present in `_endSession()`
- [x] Receiver stepper synchronized to SenderScreen design — Step 2 uses `cs.secondary` (was hardcoded green), Step 3 "Send Key" uses `cs.tertiary` + key icon (was deepPurple, no icon)
- [x] CrypButton 3D button system implemented globally — `CrypButton` widget in `shared_widgets.dart`; applied to SenderScreen (steps 2/3/4), ReceiverScreen (steps 0/2/ready-button), TransferProgressScreen, DownloadConfirmScreen, EndSessionScreen
- [x] Android `FLAG_SECURE` — `MainActivity.onCreate()` sets `window.addFlags(LayoutParams.FLAG_SECURE)`; blocks task-switcher thumbnails and screenshots across all Flutter screens
- [x] Android R8 minification — `isMinifyEnabled = true`, `isShrinkResources = true`, `proguard-rules.pro` created with Flutter/Firebase/PointyCastle keep rules
- [x] Android release signing wired — `build.gradle.kts` reads `android/key.properties` (git-ignored); falls back to debug signing if file absent
- [x] `SessionManager` created (`lib/core/utils/session_manager.dart`) — owns `SessionState` enum (open/locked/decrypting/terminated), `handleLifecycleState()` kill-switch handshake, `wipeSession()` delegating to `EncryptionService` + `SecurityLifecycleMixin.wipeAll`
- [x] Kill-switch handshake wired in `ReceiverScreen` — `didChangeAppLifecycleState` delegates to `SessionManager.handleLifecycleState`; `PopScope` delegates to `SessionManager.wipeSession`; incoming transfer fires `SessionManager.lock()`
- [x] `TransferService` created (`lib/data/services/transfer_service.dart`) — `kChunkSize = 64 KB`; `readFile()` chunks via `File.openRead()`; `resolve()` picks path-based read on mobile/desktop and falls back to bytes on web
- [x] `SenderScreen._encryptFile()` uses `TransferService.resolve()` — replaces direct `file.bytes!` access with chunked 64 KB reads for memory-stable large-file handling
- [x] `CrypButton` session-state visual feedback — `sessionState` parameter drives amber/lock (locked), primary/spinner (decrypting), error-red/block (terminated); interaction blocked for all non-open states
- [x] **Active Session State refactor** — receiver flow transitioned from static connection to live session state:
  - Session isolation: `SessionManager.selectSender(uid, username)` + `clearSender()` enforce one active sender per session; stored in `SessionManager` (not local state)
  - Automatic handshake: sender selection triggers `KeyRepository.sendPublicKey(isHandshake: true)` — stamps `status: 'handshake_complete'` on `rsaKeyTransfers` doc
  - Firestore signaling: Step 3 replaced with `StreamBuilder` on `transfers` collection filtered by `receiverId`, `senderId`, `status == pending`; drives both waiting UI and navigation trigger
  - Reactive navigation: `_handleIncomingTransfer` calls `SessionManager.setDecrypting()` → `_onSessionStateChanged` auto-pushes to `ReceiverTransferScreen` without user interaction
  - Kotlin sync: `SecurityLifecycleMixin.isFlagSecureActive()` queries `com.example.cryptransfer/security` MethodChannel before 64 KB chunk reads; `MainActivity.configureFlutterEngine` registers the handler returning `(flags & FLAG_SECURE) != 0`
  - Removed: `_startTransferListener`, `_transferSub`, `_SendKeyRow`, `_SendKeySheet`, `_PulsingReadyButton`, `_openSendKeySheet`, `StatusBanner` from build
- [x] **Firestore double-stream fixed** — `_step3Content` previously created a new Firestore snapshot stream inline on every rebuild. Now `_transferStream` is a `Stream` field initialised once in `_onSenderSelected()` and cleared in `_onToggleReady(false)` / clear-sender button. `StreamBuilder` references the stable field — one subscription per session, no re-subscription on rebuild. (`receiver_screen.dart`)
- [x] **Sender plaintext zero-wipe** — `SenderScreen._encryptFile()` now calls `registerBuffer(plaintext)` immediately after `TransferService.resolve()` (safety net for any throw before encryption), then after `compute()` returns calls `plaintext.fillRange(0, plaintext.length, 0)` + `unregisterBuffer(plaintext)` to eagerly erase the main-isolate copy. `SecurityLifecycleMixin` gained `unregisterBuffer()` to remove an already-wiped buffer from the registry, preventing a redundant second pass in `wipeAll()`. (`sender_screen.dart`, `security_lifecycle_mixin.dart`)
- [x] **Receiver-Authorized Handshake** — connection model replaced: receiver explicitly selects a sender before any key material flows:
  - Atomic authorization: `KeyRepository.selectSenderHandshake()` uses a Firestore `WriteBatch` to atomically write `selectedSenderUid` to the receiver's user doc AND upsert the `rsa_key_transfers` doc with `status: 'handshake_complete'` — single network round-trip, no partial-write window
  - Sender streaming: `SenderScreen` replaces the static receiver-list with a live `StreamSubscription` on `streamHandshakesForSender()` (`rsa_key_transfers WHERE toUserId==senderUid AND status==handshake_complete`); connection state is purely reactive
  - Waiting animation: `_WaitingForConnectionWidget` (pulsing `ScaleTransition` + `AnimationController`) shown until a handshake doc appears; replaced by `_ConnectedBadge` ("Secure Channel Established / Key received from @username") on connect
  - Kill-switch reactive revert: `closeReceiverSession()` deletes `selectedSenderUid` AND batch-deletes `rsa_key_transfers` docs → sender stream emits empty → `_onHandshakeUpdate` calls `_revertToWaiting()`, wiping all cached key/file data and snackbar-notifying the user
  - "Share Public Key" step removed from ReceiverScreen build — authorization is now automatic on sender selection via `_onSenderSelected()`
- [x] **Reactive kill-switch binding (SessionManager → EncryptionService stream)** — closes the structural gap where `Encryption Module Documentation` was the only bridge between the `SessionManager State Machine` and `Kill Switch & Wipe Lifecycle` graph communities:
  - `SessionState` extracted to `lib/core/utils/session_state.dart` — standalone file prevents circular import when `EncryptionService` imports it
  - `SessionManager` exposes `Stream<SessionState> stateStream` via a `StreamController.broadcast()`; `_set()` emits every transition on the stream
  - `EncryptionService.bindSession(stateStream, uid)` subscribes and calls `closeReceiverSession(uid)` automatically when `SessionState.terminated` fires — no manual call from `wipeSession()` required
  - `EncryptionService.unbindSession()` cancels the subscription (called on deliberate toggle-off and `dispose()`)
  - `SessionManager.wipeSession()` simplified: transitions state + calls `onBuffersWipe()`; `uid` param removed (crypto cleanup is now reactive)
  - Graph impact: `Encryption Module Documentation` betweenness dropped 0.041 → 0.035; direct EXTRACTED edge `SessionManager.stateStream → EncryptionService.bindSession` now exists
- [x] **Bidirectional Disconnect** — users can now remove connections via `FindFriendsScreen`. `KeyRepository.disconnectFriend()` uses a `WriteBatch` to atomically remove the relationship from both users' `connections` sub-collections. UI features a `PopupMenuButton` on the 'Connected' status badge.
- [x] **Handshake is now a user-triggered event with reactive UI feedback** — `_FindSenderSheet` search results show `'Friend'` (green text) for connected users alongside a `GlassButton` labeled `'Send'`; tapping enters a per-user loading state (spinner replaces button), writes the receiver's RSA public key to Firestore via `KeyRepository.publishRSAPublicKey()`, then transforms the button into a green checkmark on success; on Firestore failure the button resets and a red `SnackBar` surfaces the error for retry
  - `publishRSAPublicKey(targetUserId)` uses a deterministic doc ID `${receiverUid}_${senderUid}` in the `handshakes/` collection — idempotent re-sends produce no duplicates; `streamHandshakesForSender()` on the sender side picks up the write immediately and transitions the sender out of the "Waiting for Connection" state
  - `SecurityLifecycleMixin.requestNativeClear()` static method added — invokes `clearSession` on the `com.example.cryptransfer/security` MethodChannel; `EncryptionService.closeReceiverSession()` calls it as step 7 after all Firestore/storage wipes complete
  - `MainActivity.kt` `clearSession` handler: no key material is held natively (all RSA/AES runs in Dart `compute()` isolates), so the handler calls `System.gc()` as a best-effort Kotlin heap-release hint

- [x] **Home screen UAT gap fixes (05-06)** — Accept spinner resets after error (async/await + finally); Active Connections surfaces Firestore stream errors (hasError branch); listeners reuse stable initState stream fields; pending-row InkWell removed so cancel confirmation sheet is reachable.
- [x] **Receiver stepper 3 prefill fix (05-07)** — `_pendingPrefilledSender` defers `_onSenderSelected` until `_onToggleReady(true)` fires after `setupReceiverSession`; eliminates silent `KeyNotFoundException` blocking RSA handshake via Active Connection role picker.
- [x] **End Session zero-remanence cleanup unblocked** — `transfers` delete rule extended to `receiverId`; receiver can now delete the transfer doc in `endSessionCleanup` without PERMISSION_DENIED. Deployed to `cryptransfer-96e9f` (commit `8fca91a`).
- [x] **Reactive connection status in search results** — `FindFriendsScreen` search result rows replaced with `_SearchResultTile` (StatefulWidget). Each tile subscribes to `HandshakeRepository.streamHandshakeWithUser()` in `initState` and cancels in `dispose`, giving per-tile real-time status without polling. `streamHandshakeWithUser` merges the two deterministic doc streams (`${myUid}_${partnerUid}` and `${partnerUid}_${myUid}`) via a single-subscription `StreamController` and emits a typed record `({String status, String docId})?`. The "Pending" label pulses via `AnimationController.repeat(reverse: true)` while status is `pending_sent`; the "Connected" badge appears immediately when the partner accepts without requiring a re-search. Static `_statuses` map, one-shot `_getConnectionStatus`, `_sendRequest`, and `_buildAction` removed from parent state.
- [x] **Phase 07 — Sender Reactive Cleanup Sync** — real-time stream on `TransferProgressScreen` listens to `receiverStatus` and `cleanup_initiated` signals after successful transfer. Pulsing `CircularProgressIndicator` with "Waiting for secure session close…" appears when `receiverStatus == 'saved'`; updates to "Keys destroyed. Waiting for receiver to terminate session…" when `cleanup_initiated` fires (Turn 2 AES key wipe from Firestore + RAM). Sender auto-navigates to `SenderSessionEndedScreen` on doc deletion (Turn 4). 300s safety timeout unblocks sender if receiver never completes cleanup. `_startTransferListener()` moved inside `_startUpload()` after `await .set()` — fixes silent stream cancellation caused by Firestore security rule evaluating `resource.data.senderId` as null on non-existent doc. UAT 3/3 passed.
- [x] **Global glassmorphic 3D design system** — `GlassButton`/`CrypButton` upgraded to `StatefulWidget` with `_isPressed`, `HapticFeedback.lightImpact()`, `transformAlignment: Alignment.center` on scale `AnimatedContainer`, `Matrix4.diagonal3Values` replacing deprecated `..scale()`. `acceptProposal` → `runTransaction` (TOCTOU safety). `disconnectFromUser(partnerUid)` `WriteBatch` deletes both directional docs. `streamHandshakeWithUser` `ctrl.close()` leak fixed. Auth screens, sidebar, home, admin, sender, receiver — all glassmorphic.

## ✅ Static Analysis

`flutter analyze` passes with **No issues found** as of 2026-05-15. Fixed in final quality pass:
- `unnecessary_underscores` — replaced `__`/`___` with `_` in `PageRouteBuilder` callbacks (`splash_screen.dart`)
- Deprecation — replaced `Switch.activeColor` with `activeThumbColor` (Material 3) (`receiver_screen.dart`)

## 🔲 Known Open Issues

### Security Gaps (from `graphify-out/ZERO_REMANENCE_ANALYSIS.md`)

- [ ] **`compute()` isolate ciphertext not zeroed** — the encrypted `Uint8List` lives in the isolate's heap and is not accessible for `fillRange` zeroing from the main isolate. Inherent platform limitation; accepted risk.

### Session Architecture (from Active Session State refactor)

- [ ] **`ReceiverTransferScreen` does not propagate `SessionManager`** — navigation is automatic but `ReceiverTransferScreen` creates its own `TransferRepository` without access to the `SessionManager` from `ReceiverScreen`. If the user backgrounds the app mid-decrypt, the `SessionManager.terminated` state is set by `ReceiverScreen.didChangeAppLifecycleState`, but `ReceiverTransferScreen` has no observer. Consider passing `sessionManager` as a constructor arg or using an `InheritedWidget`.


---

## Roadmap

### Pre-Viva

- [ ] Face ID re-enable (`biometric_helper.dart` — bypassed for thesis testing; see `lib/core/utils/biometric_helper.dart`)
- [ ] Chapter 3 thesis update
- [ ] Chapter 5 testing results
- [ ] Fix figure numbering in thesis
- [ ] Fix shoutout in acknowledgements

### Pre-Release (Play Store)

- [ ] Update `applicationId` from `com.example.cryptransfer` to final app ID (`android/app/build.gradle.kts`)