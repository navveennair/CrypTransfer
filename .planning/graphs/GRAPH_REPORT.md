# Graph Report - .  (2026-04-15)

## Corpus Check
- Corpus is ~29,331 words - fits in a single context window. You may not need a graph.

## Summary
- 352 nodes · 392 edges · 52 communities detected
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 52 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_EncryptionService.bindSession()|EncryptionService.bindSession()]]
- [[_COMMUNITY_Kill Switch UI to SessionManager to EncryptionService Chain|Kill Switch UI to SessionManager to EncryptionService Chain]]
- [[_COMMUNITY_AesEncryptResult (ciphertext + key + iv)|AesEncryptResult (ciphertext + key + iv)]]
- [[_COMMUNITY_Auto-Wipe on ToggleApp CloseScreen Exit|Auto-Wipe on Toggle/App Close/Screen Exit]]
- [[_COMMUNITY_AppException (base)|AppException (base)]]
- [[_COMMUNITY_Android applicationId Update TODO (Pre-Play Store)|Android applicationId Update TODO (Pre-Play Store)]]
- [[_COMMUNITY_GeneratedPluginRegistrant.java|GeneratedPluginRegistrant.java]]
- [[_COMMUNITY_EncryptionService|EncryptionService]]
- [[_COMMUNITY_AppDelegate|AppDelegate]]
- [[_COMMUNITY_fromUserId NOT Stored in Notification Docs (only fromUsername)|fromUserId NOT Stored in Notification Docs (only fromUsername)]]
- [[_COMMUNITY_CrypTransfer Android App Identity|CrypTransfer Android App Identity]]
- [[_COMMUNITY_Automation Protocol and Scripts (Guardian, Daily Report)|Automation Protocol and Scripts (Guardian, Daily Report)]]
- [[_COMMUNITY_AesEncryptResult|AesEncryptResult]]
- [[_COMMUNITY_Security Audit Logging (_logSecurityEvent)|Security Audit Logging (_logSecurityEvent)]]
- [[_COMMUNITY_CLAUDE.md Architecture & Status Document|CLAUDE.md Architecture & Status Document]]
- [[_COMMUNITY_Closed Mailbox UI Flow (ReceiverScreen toggle, session lock)|Closed Mailbox UI Flow (ReceiverScreen toggle, session lock)]]
- [[_COMMUNITY_handle_new_rx_page()|handle_new_rx_page()]]
- [[_COMMUNITY_build.gradle.kts|build.gradle.kts]]
- [[_COMMUNITY_MainActivity.kt|MainActivity.kt]]
- [[_COMMUNITY_silent_guardian.ps1|silent_guardian.ps1]]
- [[_COMMUNITY_BiometricHelper.authenticate()|BiometricHelper.authenticate()]]
- [[_COMMUNITY_Gemini Graphify Graph Usage Rules|Gemini Graphify Graph Usage Rules]]
- [[_COMMUNITY_BiometricHelper (Face ID - Bypassed)|BiometricHelper (Face ID - Bypassed)]]
- [[_COMMUNITY_Rationale TransferService for Memory-Stable 64KB Reads|Rationale: TransferService for Memory-Stable 64KB Reads]]
- [[_COMMUNITY_update_status.ps1|update_status.ps1]]
- [[_COMMUNITY_AppTheme (Material3 Theme)|AppTheme (Material3 Theme)]]
- [[_COMMUNITY_TransferRepository.generateId()|TransferRepository.generateId()]]
- [[_COMMUNITY_TransferRepository.deleteStorageFile()|TransferRepository.deleteStorageFile()]]
- [[_COMMUNITY_TransferRepository.deleteTransfer()|TransferRepository.deleteTransfer()]]
- [[_COMMUNITY_EncryptionService.encodePublicKey()|EncryptionService.encodePublicKey()]]
- [[_COMMUNITY_EncryptionService.encodePrivateKey()|EncryptionService.encodePrivateKey()]]
- [[_COMMUNITY_BiometricHelper|BiometricHelper]]
- [[_COMMUNITY_formatFileSize()|formatFileSize()]]
- [[_COMMUNITY_NotificationService.unreadCountStream()|NotificationService.unreadCountStream()]]
- [[_COMMUNITY_NotificationService.allStream()|NotificationService.allStream()]]
- [[_COMMUNITY_NotificationService.latestUnreadStream()|NotificationService.latestUnreadStream()]]
- [[_COMMUNITY_NotificationService.markRead()|NotificationService.markRead()]]
- [[_COMMUNITY_NotificationService.markAllRead()|NotificationService.markAllRead()]]
- [[_COMMUNITY_SecurityLifecycleMixin.registerBuffer()|SecurityLifecycleMixin.registerBuffer()]]
- [[_COMMUNITY_SessionManager.stateNotifier (ValueNotifier)|SessionManager.stateNotifier (ValueNotifier)]]
- [[_COMMUNITY_CrypButton 3D Button System|CrypButton 3D Button System]]
- [[_COMMUNITY_Guardian Cycle Automation Protocol|Guardian Cycle Automation Protocol]]
- [[_COMMUNITY_Agent Changelog Document|Agent Changelog Document]]
- [[_COMMUNITY_HomeScreen Overlay Notification Banner (_NotifBanner)|HomeScreen Overlay Notification Banner (_NotifBanner)]]
- [[_COMMUNITY_SessionState.open|SessionState.open]]
- [[_COMMUNITY_SessionState.locked|SessionState.locked]]
- [[_COMMUNITY_SessionState.decrypting|SessionState.decrypting]]
- [[_COMMUNITY_ReceiverScreen|ReceiverScreen]]
- [[_COMMUNITY_AuthRepository|AuthRepository]]
- [[_COMMUNITY_Roadmap Pre-Release (Play Store) Tasks|Roadmap: Pre-Release (Play Store) Tasks]]
- [[_COMMUNITY_GeneratedPluginRegistrant.h|GeneratedPluginRegistrant.h]]
- [[_COMMUNITY_Runner-Bridging-Header.h|Runner-Bridging-Header.h]]

## God Nodes (most connected - your core abstractions)
1. `EncryptionService (Hybrid RSA-2048 + AES-256-GCM)` - 14 edges
2. `Security Key Storage Audit Test Suite (TC-SEC-001 to TC-SEC-011)` - 12 edges
3. `SecurityLifecycleMixin` - 10 edges
4. `FirebaseConstants (Collection Names + Keys)` - 9 edges
5. `File Transfer Test Suite (TC022-TC030)` - 9 edges
6. `AuthRepository (Register/Login/RSA Keygen via compute)` - 8 edges
7. `KeyRepository (RSA Key Transfers + Handshake)` - 8 edges
8. `TransferRepository (Upload/Download/AuditLog)` - 8 edges
9. `EncryptionService.closeReceiverSession()` - 8 edges
10. `Session Lifecycle Test Suite (TC031-TC038)` - 8 edges

## Surprising Connections (you probably didn't know these)
- `AppException (base)` --implements--> `CryptoException`  [EXTRACTED]
   → 
- `Closed Mailbox Rule (setupReceiverSession / closeReceiverSession)` --conceptually_related_to--> `Closed Mailbox UI Flow (ReceiverScreen toggle, session lock)`  [EXTRACTED]
   → 
- `Security Module Documentation` --references--> `Closed Mailbox Kill Switch Threat and Defence`  [EXTRACTED]
   → 
- `Automation Protocol and Scripts (Guardian, Daily Report)` --conceptually_related_to--> `Silent Guardian Scanner (scripts/silent_guardian.ps1)`  [INFERRED 0.90]
   → 
- `TC036: RSA Keys Wiped After Session Ends` --rationale_for--> `Startup Session Wipe via KeyRepository.wipeAllSessionKeys()`  [INFERRED 0.85]
   → 
- `TC029: Decrypted File Matches Original Plaintext` --conceptually_related_to--> `TC-SEC-007: AES-256-GCM Encrypt/Decrypt Roundtrip is Correct`  [INFERRED 0.80]
   → 
- `CrypTransfer Layer Architecture (lib/ structure)` --rationale_for--> `Encryption Module Documentation`  [INFERRED 0.80]
   → 
- `TC031: Session Cancelled When Sender Deletes Transfer` --conceptually_related_to--> `TC024: Transfer Record Created in Firestore with Correct Shape`  [INFERRED 0.70]
   → 
- `TC-WIPE-006: Notifications Purged After Session Closes` --conceptually_related_to--> `fromUserId NOT Stored in Notification Docs (only fromUsername)`  [INFERRED 0.70]
   → 
- `Notifications Module Documentation` --conceptually_related_to--> `HomeScreen Recent Transfers Query Gap (participants field missing)`  [INFERRED 0.60]
   → 

## Hyperedges (group relationships)
- **Kill Switch Wipe Chain** — claude_md_session_manager, claude_md_encryption_service, claude_md_close_receiver_session, claude_md_security_lifecycle_mixin, claude_md_wipe_all, claude_md_receiver_screen [EXTRACTED 1.00]
- **SecurityLifecycleMixin Applied Screens** — claude_md_security_lifecycle_mixin, claude_md_sender_screen, claude_md_receiver_screen, claude_md_transfer_progress_screen, claude_md_download_confirm_screen, claude_md_end_session_screen, claude_md_receiver_transfer_screen [EXTRACTED 1.00]
- **DevOps and Tooling Files** — claude_md_build_gradle, claude_md_proguard_rules, claude_md_silent_guardian, claude_md_update_status, claude_md_security_audit_dart, claude_md_write_obsidian_dart, claude_md_launch_guardian_bat [EXTRACTED 1.00]
- **Reactive Kill-Switch Binding (SessionManager â†’ EncryptionService)** — claude_md_session_state_stream, claude_md_bind_session, claude_md_unbind_session, claude_md_session_manager, claude_md_encryption_service, claude_md_session_state [EXTRACTED 1.00]
- **Receiver-Authorized Handshake Flow** — claude_md_key_repository, claude_md_select_sender_handshake, claude_md_stream_handshakes_for_sender, claude_md_sender_screen, claude_md_receiver_screen, claude_md_session_isolation, claude_md_waiting_for_connection_widget [EXTRACTED 1.00]
- **Android Security Hardening** — claude_md_main_activity, claude_md_flag_secure, claude_md_r8_minification, claude_md_build_gradle, claude_md_proguard_rules, claude_md_key_properties, claude_md_method_channel [EXTRACTED 1.00]

## Communities

### Community 0 - "EncryptionService.bindSession()"
Cohesion: 1.0
Nodes (42): EncryptionService.bindSession(), EncryptionService.closeReceiverSession(), CrypButton 3D Button System, DownloadConfirmScreen, SenderScreen._encryptFile(), EncryptionService, EndSessionScreen, FLAG_SECURE (Android Screenshot Block) (+34 more)

### Community 1 - "Kill Switch UI to SessionManager to EncryptionService Chain"
Cohesion: 1.0
Nodes (39): Kill Switch UI to SessionManager to EncryptionService Chain, SessionState Enum (open/locked/decrypting/terminated), Firestore User Document Schema, Closed Mailbox Rule (setupReceiverSession / closeReceiverSession), Hybrid Crypto Pipeline (Sender + Receiver sides), Encryption Module Documentation, Transfer Document Schema (Firestore transfers/{transferId}), Closed Mailbox Kill Switch Threat and Defence (+31 more)

### Community 2 - "AesEncryptResult (ciphertext + key + iv)"
Cohesion: 1.0
Nodes (31): AesEncryptResult (ciphertext + key + iv), App Exception Hierarchy, AuthRepository (Register/Login/RSA Keygen via compute), BiometricHelper (Auth Bypass â€” Testing), Flutter compute() Background Isolate, EncryptionService (Hybrid RSA-2048 + AES-256-GCM), File Utils (formatFileSize), FirebaseConstants (Collection Names + Keys) (+23 more)

### Community 3 - "Auto-Wipe on Toggle/App Close/Screen Exit"
Cohesion: 1.0
Nodes (19): Auto-Wipe on Toggle/App Close/Screen Exit, Closed Mailbox / Kill Switch Rule, Isolate.run() â†’ compute() Migration, SecurityLifecycleMixin Applied to Screens, EncryptionService, EncryptionService.closeReceiverSession(), EncryptionService._logSecurityEvent(), EncryptionService.setupReceiverSession() (+11 more)

### Community 4 - "AppException (base)"
Cohesion: 1.0
Nodes (15): AppException (base), AuthException, KeyNotFoundException, NetworkException, TransferException, encryptedAESKey Field Name Drift Fix, FirebaseConstants, FirebaseConstants.maxDownloadBytes (100 MB) (+7 more)

### Community 5 - "Android applicationId Update TODO (Pre-Play Store)"
Cohesion: 1.0
Nodes (19): Android applicationId Update TODO (Pre-Play Store), compute() Isolate Ciphertext Not Zeroed (Accepted Risk), Known Open Issues (CLAUDE.md), CrypTransfer Layer Architecture (lib/ structure), ReceiverTransferScreen Does Not Propagate SessionManager (Open Issue), Viva and Thesis TODOs, AuthRepository Public API, Biometric Auth Bypassed (re-enable before viva) (+11 more)

### Community 6 - "GeneratedPluginRegistrant.java"
Cohesion: 1.0
Nodes (14): filepickerplugin, fltfirebaseauthplugin, fltfirebasecoreplugin, fltfirebasefirestoreplugin, fltfirebasestorageplugin, flutterengine, fluttersecurestoragedarwinplugin, generatedpluginregistrant (+6 more)

### Community 7 - "EncryptionService"
Cohesion: 1.0
Nodes (14): EncryptionService, EncryptionService._sessionSub (StreamSubscription), EncryptionService.bindSession(), EncryptionService.closeReceiverSession(), EncryptionService.unbindSession(), ReceiverScreen._onToggleReady(), SessionManager, SessionManager._set() â€” state transition + stream emit (+6 more)

### Community 8 - "AppDelegate"
Cohesion: 1.0
Nodes (10): AppDelegate, flutter, FlutterAppDelegate, FlutterImplicitEngineDelegate, FlutterSceneDelegate, RunnerTests, SceneDelegate, uikit (+2 more)

### Community 9 - "fromUserId NOT Stored in Notification Docs (only fromUsername)"
Cohesion: 1.0
Nodes (14): fromUserId NOT Stored in Notification Docs (only fromUsername), Notifications Module Documentation, Notification Document Schema (notifications/{docId}), NotificationService API (streams + mark-read), File Transfer Test Suite (TC022-TC030), TC022: File Data Correctly Represented Before Transfer, TC023: Transfer Record Has Required Fields for Storage Upload, TC024: Transfer Record Created in Firestore with Correct Shape (+6 more)

### Community 10 - "CrypTransfer Android App Identity"
Cohesion: 1.0
Nodes (14): CrypTransfer Android App Identity, Android Launcher Icon (hdpi), Android Launcher Icon (mdpi), Android Launcher Icon (xhdpi), Android Launcher Icon (xxhdpi), Android Launcher Icon (xxxhdpi), Android FLAG_SECURE Security Hardening, Completed Features Registry (CLAUDE.md) (+6 more)

### Community 11 - "Automation Protocol and Scripts (Guardian, Daily Report)"
Cohesion: 1.0
Nodes (14): Automation Protocol and Scripts (Guardian, Daily Report), Android App build.gradle.kts, DevOps & Tooling Cluster, Android key.properties (Release Signing), Launch Guardian Batch Launcher (launch_guardian.bat), Daily Report Generation Command, Update Status Automation Command, ProGuard Rules (proguard-rules.pro) (+6 more)

### Community 12 - "AesEncryptResult"
Cohesion: 1.0
Nodes (9): AesEncryptResult, CryptoException, EncryptionService.decodePrivateKey(), EncryptionService.decryptAesGcm(), EncryptionService.decryptAesKeyWithPrivateKeyJson(), EncryptionService.encryptAesGcm(), EncryptionService.rsaDecrypt(), runAesGcmDecrypt (top-level isolate fn) (+1 more)

### Community 13 - "Security Audit Logging (_logSecurityEvent)"
Cohesion: 1.0
Nodes (10): Security Audit Logging (_logSecurityEvent), Security Module Documentation, OWASP Mobile Top 10 Coverage Table, Radioactive Buffer Tracker Table (all screens), Silent Guardian Scanner (scripts/silent_guardian.ps1), Startup Session Wipe via KeyRepository.wipeAllSessionKeys(), Security Protocol Core Rules (5 Rules), SecurityLifecycleMixin API Specification (+2 more)

### Community 14 - "CLAUDE.md Architecture & Status Document"
Cohesion: 1.0
Nodes (5): CLAUDE.md Architecture & Status Document, TransferService, TransferService.kChunkSize (64 KB), TransferService.readFile(), TransferService.resolve()

### Community 15 - "Closed Mailbox UI Flow (ReceiverScreen toggle, session lock)"
Cohesion: 1.0
Nodes (5): Closed Mailbox UI Flow (ReceiverScreen toggle, session lock), UI/UX Module Documentation, Navigation Model (pushAndRemoveUntil, pushReplacement patterns), Screen Registry Table (all screens, roles, triggers), Stepper Pattern (StepCard, sequential steps, opacity lock)

### Community 16 - "handle_new_rx_page()"
Cohesion: 1.0
Nodes (3): handle_new_rx_page(), Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages., lldb

### Community 17 - "build.gradle.kts"
Cohesion: 1.0
Nodes (1): R8 Minification + ProGuard (Release Hardening)

### Community 18 - "MainActivity.kt"
Cohesion: 1.0
Nodes (1): MainActivity

### Community 19 - "silent_guardian.ps1"
Cohesion: 1.0
Nodes (0): 

### Community 20 - "BiometricHelper.authenticate()"
Cohesion: 1.0
Nodes (0): 

### Community 21 - "Gemini Graphify Graph Usage Rules"
Cohesion: 1.0
Nodes (2): Gemini Graphify Graph Usage Rules, CrypTransfer Flutter Project README

### Community 22 - "BiometricHelper (Face ID - Bypassed)"
Cohesion: 1.0
Nodes (2): BiometricHelper (Face ID - Bypassed), Roadmap: Pre-Viva Tasks

### Community 23 - "Rationale: TransferService for Memory-Stable 64KB Reads"
Cohesion: 1.0
Nodes (2): Rationale: TransferService for Memory-Stable 64KB Reads, TransferService

### Community 24 - "update_status.ps1"
Cohesion: 1.0
Nodes (0): 

### Community 25 - "AppTheme (Material3 Theme)"
Cohesion: 1.0
Nodes (1): AppTheme (Material3 Theme)

### Community 26 - "TransferRepository.generateId()"
Cohesion: 1.0
Nodes (0): 

### Community 27 - "TransferRepository.deleteStorageFile()"
Cohesion: 1.0
Nodes (0): 

### Community 28 - "TransferRepository.deleteTransfer()"
Cohesion: 1.0
Nodes (0): 

### Community 29 - "EncryptionService.encodePublicKey()"
Cohesion: 1.0
Nodes (0): 

### Community 30 - "EncryptionService.encodePrivateKey()"
Cohesion: 1.0
Nodes (0): 

### Community 31 - "BiometricHelper"
Cohesion: 1.0
Nodes (1): BiometricHelper

### Community 32 - "formatFileSize()"
Cohesion: 1.0
Nodes (0): 

### Community 33 - "NotificationService.unreadCountStream()"
Cohesion: 1.0
Nodes (0): 

### Community 34 - "NotificationService.allStream()"
Cohesion: 1.0
Nodes (0): 

### Community 35 - "NotificationService.latestUnreadStream()"
Cohesion: 1.0
Nodes (0): 

### Community 36 - "NotificationService.markRead()"
Cohesion: 1.0
Nodes (0): 

### Community 37 - "NotificationService.markAllRead()"
Cohesion: 1.0
Nodes (0): 

### Community 38 - "SecurityLifecycleMixin.registerBuffer()"
Cohesion: 1.0
Nodes (0): 

### Community 39 - "SessionManager.stateNotifier (ValueNotifier)"
Cohesion: 1.0
Nodes (1): SessionManager.stateNotifier (ValueNotifier)

### Community 40 - "CrypButton 3D Button System"
Cohesion: 1.0
Nodes (1): CrypButton 3D Button System

### Community 41 - "Guardian Cycle Automation Protocol"
Cohesion: 1.0
Nodes (1): Guardian Cycle Automation Protocol

### Community 42 - "Agent Changelog Document"
Cohesion: 1.0
Nodes (1): Agent Changelog Document

### Community 43 - "HomeScreen Overlay Notification Banner (_NotifBanner)"
Cohesion: 1.0
Nodes (1): HomeScreen Overlay Notification Banner (_NotifBanner)

### Community 44 - "SessionState.open"
Cohesion: 1.0
Nodes (1): SessionState.open

### Community 45 - "SessionState.locked"
Cohesion: 1.0
Nodes (1): SessionState.locked

### Community 46 - "SessionState.decrypting"
Cohesion: 1.0
Nodes (1): SessionState.decrypting

### Community 47 - "ReceiverScreen"
Cohesion: 1.0
Nodes (1): ReceiverScreen

### Community 48 - "AuthRepository"
Cohesion: 1.0
Nodes (1): AuthRepository

### Community 49 - "Roadmap: Pre-Release (Play Store) Tasks"
Cohesion: 1.0
Nodes (1): Roadmap: Pre-Release (Play Store) Tasks

### Community 50 - "GeneratedPluginRegistrant.h"
Cohesion: 1.0
Nodes (0): 

### Community 51 - "Runner-Bridging-Header.h"
Cohesion: 1.0
Nodes (0): 

## Knowledge Gaps
- **100 isolated node(s):** `Generated Plugin Registrant (Android)`, `AppTheme (Material3 Theme)`, `File Utils (formatFileSize)`, `NotificationService (Firestore Notifications Read/Write)`, `SessionState Enum (open/locked/decrypting/terminated)` (+95 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `silent_guardian.ps1`** (2 nodes): `silent_guardian.ps1`, `Write-Log()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `BiometricHelper.authenticate()`** (2 nodes): `BiometricHelper.authenticate()`, `BiometricHelper.checkBiometrics()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Gemini Graphify Graph Usage Rules`** (2 nodes): `Gemini Graphify Graph Usage Rules`, `CrypTransfer Flutter Project README`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `BiometricHelper (Face ID - Bypassed)`** (2 nodes): `BiometricHelper (Face ID - Bypassed)`, `Roadmap: Pre-Viva Tasks`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Rationale: TransferService for Memory-Stable 64KB Reads`** (2 nodes): `Rationale: TransferService for Memory-Stable 64KB Reads`, `TransferService`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `update_status.ps1`** (1 nodes): `update_status.ps1`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `AppTheme (Material3 Theme)`** (1 nodes): `AppTheme (Material3 Theme)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `TransferRepository.generateId()`** (1 nodes): `TransferRepository.generateId()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `TransferRepository.deleteStorageFile()`** (1 nodes): `TransferRepository.deleteStorageFile()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `TransferRepository.deleteTransfer()`** (1 nodes): `TransferRepository.deleteTransfer()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `EncryptionService.encodePublicKey()`** (1 nodes): `EncryptionService.encodePublicKey()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `EncryptionService.encodePrivateKey()`** (1 nodes): `EncryptionService.encodePrivateKey()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `BiometricHelper`** (1 nodes): `BiometricHelper`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `formatFileSize()`** (1 nodes): `formatFileSize()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `NotificationService.unreadCountStream()`** (1 nodes): `NotificationService.unreadCountStream()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `NotificationService.allStream()`** (1 nodes): `NotificationService.allStream()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `NotificationService.latestUnreadStream()`** (1 nodes): `NotificationService.latestUnreadStream()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `NotificationService.markRead()`** (1 nodes): `NotificationService.markRead()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `NotificationService.markAllRead()`** (1 nodes): `NotificationService.markAllRead()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `SecurityLifecycleMixin.registerBuffer()`** (1 nodes): `SecurityLifecycleMixin.registerBuffer()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `SessionManager.stateNotifier (ValueNotifier)`** (1 nodes): `SessionManager.stateNotifier (ValueNotifier)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `CrypButton 3D Button System`** (1 nodes): `CrypButton 3D Button System`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Guardian Cycle Automation Protocol`** (1 nodes): `Guardian Cycle Automation Protocol`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Agent Changelog Document`** (1 nodes): `Agent Changelog Document`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `HomeScreen Overlay Notification Banner (_NotifBanner)`** (1 nodes): `HomeScreen Overlay Notification Banner (_NotifBanner)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `SessionState.open`** (1 nodes): `SessionState.open`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `SessionState.locked`** (1 nodes): `SessionState.locked`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `SessionState.decrypting`** (1 nodes): `SessionState.decrypting`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `ReceiverScreen`** (1 nodes): `ReceiverScreen`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `AuthRepository`** (1 nodes): `AuthRepository`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Roadmap: Pre-Release (Play Store) Tasks`** (1 nodes): `Roadmap: Pre-Release (Play Store) Tasks`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `GeneratedPluginRegistrant.h`** (1 nodes): `GeneratedPluginRegistrant.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Runner-Bridging-Header.h`** (1 nodes): `Runner-Bridging-Header.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Security Module Documentation` connect `Security Audit Logging (_logSecurityEvent)` to `Kill Switch UI to SessionManager to EncryptionService Chain`?**
  _High betweenness centrality (0.030) - this node is a cross-community bridge._
- **Why does `Closed Mailbox Rule (setupReceiverSession / closeReceiverSession)` connect `Kill Switch UI to SessionManager to EncryptionService Chain` to `Closed Mailbox UI Flow (ReceiverScreen toggle, session lock)`?**
  _High betweenness centrality (0.026) - this node is a cross-community bridge._
- **Why does `Closed Mailbox Kill Switch Threat and Defence` connect `Kill Switch UI to SessionManager to EncryptionService Chain` to `Security Audit Logging (_logSecurityEvent)`?**
  _High betweenness centrality (0.023) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `EncryptionService (Hybrid RSA-2048 + AES-256-GCM)` (e.g. with `TransferModel (Firestore Transfer DTO + encryptedAESKey)` and `Flutter compute() Background Isolate`) actually correct?**
  _`EncryptionService (Hybrid RSA-2048 + AES-256-GCM)` has 3 INFERRED edges - model-reasoned connections that need verification._
- **What connects `Generated Plugin Registrant (Android)`, `AppTheme (Material3 Theme)`, `File Utils (formatFileSize)` to the rest of the system?**
  _100 weakly-connected nodes found - possible documentation gaps or missing edges._