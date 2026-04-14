# Graph Report - .  (2026-04-14)

## Corpus Check
- 2 files · ~5,000 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 315 nodes · 357 edges · 48 communities detected
- Extraction: 85% EXTRACTED · 15% INFERRED · 0% AMBIGUOUS · INFERRED: 52 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Encryption & Screen Security Pipeline|Encryption & Screen Security Pipeline]]
- [[_COMMUNITY_Auth & Crypto Core|Auth & Crypto Core]]
- [[_COMMUNITY_Kill Switch & Session Lifecycle|Kill Switch & Session Lifecycle]]
- [[_COMMUNITY_Security Lifecycle Management|Security Lifecycle Management]]
- [[_COMMUNITY_Data Layer & Crypto Testing|Data Layer & Crypto Testing]]
- [[_COMMUNITY_Error Handling Layer|Error Handling Layer]]
- [[_COMMUNITY_Architecture & Open Issues|Architecture & Open Issues]]
- [[_COMMUNITY_Reactive Kill-Switch Binding|Reactive Kill-Switch Binding]]
- [[_COMMUNITY_Notifications & Transfer Tests|Notifications & Transfer Tests]]
- [[_COMMUNITY_Android App Identity|Android App Identity]]
- [[_COMMUNITY_DevOps & Tooling|DevOps & Tooling]]
- [[_COMMUNITY_Crypto Primitives|Crypto Primitives]]
- [[_COMMUNITY_Architecture Documentation|Architecture Documentation]]
- [[_COMMUNITY_Android Build Config|Android Build Config]]
- [[_COMMUNITY_Android Entry Point|Android Entry Point]]
- [[_COMMUNITY_UI Components & State|UI Components & State]]
- [[_COMMUNITY_Flutter Plugin Registry|Flutter Plugin Registry]]
- [[_COMMUNITY_Guardian Script|Guardian Script]]
- [[_COMMUNITY_Biometric Auth|Biometric Auth]]
- [[_COMMUNITY_Project Documentation|Project Documentation]]
- [[_COMMUNITY_Transfer Service Rationale|Transfer Service Rationale]]
- [[_COMMUNITY_Pre-Viva Roadmap|Pre-Viva Roadmap]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]
- [[_COMMUNITY_Community 26|Community 26]]
- [[_COMMUNITY_Community 27|Community 27]]
- [[_COMMUNITY_Community 28|Community 28]]
- [[_COMMUNITY_Community 29|Community 29]]
- [[_COMMUNITY_Community 30|Community 30]]
- [[_COMMUNITY_Community 31|Community 31]]
- [[_COMMUNITY_Community 32|Community 32]]
- [[_COMMUNITY_Community 33|Community 33]]
- [[_COMMUNITY_Community 34|Community 34]]
- [[_COMMUNITY_Community 35|Community 35]]
- [[_COMMUNITY_Community 36|Community 36]]
- [[_COMMUNITY_Community 37|Community 37]]
- [[_COMMUNITY_Community 38|Community 38]]
- [[_COMMUNITY_Community 39|Community 39]]
- [[_COMMUNITY_Community 40|Community 40]]
- [[_COMMUNITY_Community 41|Community 41]]
- [[_COMMUNITY_Community 42|Community 42]]
- [[_COMMUNITY_Community 43|Community 43]]
- [[_COMMUNITY_Community 44|Community 44]]
- [[_COMMUNITY_Community 45|Community 45]]
- [[_COMMUNITY_Community 46|Community 46]]
- [[_COMMUNITY_Community 47|Community 47]]

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
- `CrypTransfer Android App Identity` --conceptually_related_to--> `Android FLAG_SECURE Security Hardening`  [INFERRED]
  android/app/src/main/res/mipmap-hdpi/ic_launcher.png → CLAUDE.md
- `Update Status PowerShell Script` --references--> `SecurityLifecycleMixin (Uint8List Zero-Wipe Registry)`  [EXTRACTED]
  scripts/update_status.ps1 → lib/core/utils/security_lifecycle_mixin.dart
- `SecurityLifecycleMixin (Uint8List Zero-Wipe Registry)` --calls--> `MethodChannel: com.example.cryptransfer/security`  [EXTRACTED]
  lib/core/utils/security_lifecycle_mixin.dart → android/app/src/main/kotlin/com/example/cryptransfer/MainActivity.kt
- `SecurityLifecycleMixin (Uint8List Zero-Wipe Registry)` --references--> `Android FLAG_SECURE Window Protection`  [EXTRACTED]
  lib/core/utils/security_lifecycle_mixin.dart → android/app/src/main/kotlin/com/example/cryptransfer/MainActivity.kt
- `Session Wipe Test Suite Results (TC-WIPE-001 to TC-WIPE-006 all PASS)` --references--> `Security Key Storage Audit Test Suite (TC-SEC-001 to TC-SEC-011)`  [INFERRED]
  docs/modules/security.md → test/security/key_storage_audit_test.dart

## Hyperedges (group relationships)
- **Kill Switch Wipe Chain** — claude_md_session_manager, claude_md_encryption_service, claude_md_close_receiver_session, claude_md_security_lifecycle_mixin, claude_md_wipe_all, claude_md_receiver_screen [EXTRACTED 1.00]
- **SecurityLifecycleMixin Applied Screens** — claude_md_security_lifecycle_mixin, claude_md_sender_screen, claude_md_receiver_screen, claude_md_transfer_progress_screen, claude_md_download_confirm_screen, claude_md_end_session_screen, claude_md_receiver_transfer_screen [EXTRACTED 1.00]
- **DevOps and Tooling Files** — claude_md_build_gradle, claude_md_proguard_rules, claude_md_silent_guardian, claude_md_update_status, claude_md_security_audit_dart, claude_md_write_obsidian_dart, claude_md_launch_guardian_bat [EXTRACTED 1.00]
- **Reactive Kill-Switch Binding (SessionManager â†’ EncryptionService)** — claude_md_session_state_stream, claude_md_bind_session, claude_md_unbind_session, claude_md_session_manager, claude_md_encryption_service, claude_md_session_state [EXTRACTED 1.00]
- **Receiver-Authorized Handshake Flow** — claude_md_key_repository, claude_md_select_sender_handshake, claude_md_stream_handshakes_for_sender, claude_md_sender_screen, claude_md_receiver_screen, claude_md_session_isolation, claude_md_waiting_for_connection_widget [EXTRACTED 1.00]
- **Android Security Hardening** — claude_md_main_activity, claude_md_flag_secure, claude_md_r8_minification, claude_md_build_gradle, claude_md_proguard_rules, claude_md_key_properties, claude_md_method_channel [EXTRACTED 1.00]

## Communities

### Community 0 - "Encryption & Screen Security Pipeline"
Cohesion: 0.07
Nodes (38): EncryptionService.bindSession(), EncryptionService.closeReceiverSession(), DownloadConfirmScreen, SenderScreen._encryptFile(), EncryptionService, EndSessionScreen, FLAG_SECURE (Android Screenshot Block), Graphify Knowledge Graph (graphify-out/graph.json) (+30 more)

### Community 1 - "Auth & Crypto Core"
Cohesion: 0.14
Nodes (31): AesEncryptResult (ciphertext + key + iv), App Exception Hierarchy, AuthRepository (Register/Login/RSA Keygen via compute), BiometricHelper (Auth Bypass â€” Testing), Flutter compute() Background Isolate, EncryptionService (Hybrid RSA-2048 + AES-256-GCM), File Utils (formatFileSize), FirebaseConstants (Collection Names + Keys) (+23 more)

### Community 2 - "Kill Switch & Session Lifecycle"
Cohesion: 0.08
Nodes (29): Kill Switch UI to SessionManager to EncryptionService Chain, SessionState Enum (open/locked/decrypting/terminated), Closed Mailbox Rule (setupReceiverSession / closeReceiverSession), Encryption Module Documentation, Security Audit Logging (_logSecurityEvent), Closed Mailbox Kill Switch Threat and Defence, Security Module Documentation, OWASP Mobile Top 10 Coverage Table (+21 more)

### Community 3 - "Security Lifecycle Management"
Cohesion: 0.1
Nodes (19): Auto-Wipe on Toggle/App Close/Screen Exit, Closed Mailbox / Kill Switch Rule, Isolate.run() â†’ compute() Migration, SecurityLifecycleMixin Applied to Screens, EncryptionService, EncryptionService.closeReceiverSession(), EncryptionService._logSecurityEvent(), EncryptionService.setupReceiverSession() (+11 more)

### Community 4 - "Data Layer & Crypto Testing"
Cohesion: 0.09
Nodes (25): Firestore User Document Schema, Hybrid Crypto Pipeline (Sender + Receiver sides), Transfer Document Schema (Firestore transfers/{transferId}), Security Key Storage Audit Test Suite (TC-SEC-001 to TC-SEC-011), TC-SEC-001: Private Key NOT in Users Collection, TC-SEC-002: Private Key NOT in rsa_key_transfers, TC-SEC-003: Private Key NOT in Transfers Collection, TC-SEC-004: AES Key Stored in Transfers is RSA-OAEP Encrypted (+17 more)

### Community 5 - "Error Handling Layer"
Cohesion: 0.11
Nodes (15): AppException (base), AuthException, KeyNotFoundException, NetworkException, TransferException, encryptedAESKey Field Name Drift Fix, FirebaseConstants, FirebaseConstants.maxDownloadBytes (100 MB) (+7 more)

### Community 6 - "Architecture & Open Issues"
Cohesion: 0.11
Nodes (19): Android applicationId Update TODO (Pre-Play Store), compute() Isolate Ciphertext Not Zeroed (Accepted Risk), Known Open Issues (CLAUDE.md), CrypTransfer Layer Architecture (lib/ structure), ReceiverTransferScreen Does Not Propagate SessionManager (Open Issue), Viva and Thesis TODOs, AuthRepository Public API, Biometric Auth Bypassed (re-enable before viva) (+11 more)

### Community 7 - "Reactive Kill-Switch Binding"
Cohesion: 0.17
Nodes (14): EncryptionService, EncryptionService._sessionSub (StreamSubscription), EncryptionService.bindSession(), EncryptionService.closeReceiverSession(), EncryptionService.unbindSession(), ReceiverScreen._onToggleReady(), SessionManager, SessionManager._set() â€” state transition + stream emit (+6 more)

### Community 8 - "Notifications & Transfer Tests"
Cohesion: 0.14
Nodes (14): fromUserId NOT Stored in Notification Docs (only fromUsername), Notifications Module Documentation, Notification Document Schema (notifications/{docId}), NotificationService API (streams + mark-read), File Transfer Test Suite (TC022-TC030), TC022: File Data Correctly Represented Before Transfer, TC023: Transfer Record Has Required Fields for Storage Upload, TC024: Transfer Record Created in Firestore with Correct Shape (+6 more)

### Community 9 - "Android App Identity"
Cohesion: 0.19
Nodes (14): CrypTransfer Android App Identity, Android Launcher Icon (hdpi), Android Launcher Icon (mdpi), Android Launcher Icon (xhdpi), Android Launcher Icon (xxhdpi), Android Launcher Icon (xxxhdpi), Android FLAG_SECURE Security Hardening, Completed Features Registry (CLAUDE.md) (+6 more)

### Community 10 - "DevOps & Tooling"
Cohesion: 0.18
Nodes (14): Automation Protocol and Scripts (Guardian, Daily Report), Android App build.gradle.kts, DevOps & Tooling Cluster, Android key.properties (Release Signing), Launch Guardian Batch Launcher (launch_guardian.bat), Daily Report Generation Command, Update Status Automation Command, ProGuard Rules (proguard-rules.pro) (+6 more)

### Community 11 - "Crypto Primitives"
Cohesion: 0.18
Nodes (9): AesEncryptResult, CryptoException, EncryptionService.decodePrivateKey(), EncryptionService.decryptAesGcm(), EncryptionService.decryptAesKeyWithPrivateKeyJson(), EncryptionService.encryptAesGcm(), EncryptionService.rsaDecrypt(), runAesGcmDecrypt (top-level isolate fn) (+1 more)

### Community 12 - "Architecture Documentation"
Cohesion: 0.4
Nodes (5): CLAUDE.md Architecture & Status Document, TransferService, TransferService.kChunkSize (64 KB), TransferService.readFile(), TransferService.resolve()

### Community 13 - "Android Build Config"
Cohesion: 0.5
Nodes (1): R8 Minification + ProGuard (Release Hardening)

### Community 14 - "Android Entry Point"
Cohesion: 0.5
Nodes (1): MainActivity

### Community 15 - "UI Components & State"
Cohesion: 0.5
Nodes (4): CrypButton 3D Button System, Rationale: SessionState Extracted to Prevent Circular Import, SessionState Enum, SharedWidgets (CrypButton)

### Community 16 - "Flutter Plugin Registry"
Cohesion: 0.67
Nodes (1): GeneratedPluginRegistrant

### Community 17 - "Guardian Script"
Cohesion: 1.0
Nodes (0): 

### Community 18 - "Biometric Auth"
Cohesion: 1.0
Nodes (0): 

### Community 19 - "Project Documentation"
Cohesion: 1.0
Nodes (2): Gemini Graphify Graph Usage Rules, CrypTransfer Flutter Project README

### Community 20 - "Transfer Service Rationale"
Cohesion: 1.0
Nodes (2): Rationale: TransferService for Memory-Stable 64KB Reads, TransferService

### Community 21 - "Pre-Viva Roadmap"
Cohesion: 1.0
Nodes (2): BiometricHelper (Face ID - Bypassed), Roadmap: Pre-Viva Tasks

### Community 22 - "Community 22"
Cohesion: 1.0
Nodes (0): 

### Community 23 - "Community 23"
Cohesion: 1.0
Nodes (1): AppTheme (Material3 Theme)

### Community 24 - "Community 24"
Cohesion: 1.0
Nodes (0): 

### Community 25 - "Community 25"
Cohesion: 1.0
Nodes (0): 

### Community 26 - "Community 26"
Cohesion: 1.0
Nodes (0): 

### Community 27 - "Community 27"
Cohesion: 1.0
Nodes (0): 

### Community 28 - "Community 28"
Cohesion: 1.0
Nodes (0): 

### Community 29 - "Community 29"
Cohesion: 1.0
Nodes (1): BiometricHelper

### Community 30 - "Community 30"
Cohesion: 1.0
Nodes (0): 

### Community 31 - "Community 31"
Cohesion: 1.0
Nodes (0): 

### Community 32 - "Community 32"
Cohesion: 1.0
Nodes (0): 

### Community 33 - "Community 33"
Cohesion: 1.0
Nodes (0): 

### Community 34 - "Community 34"
Cohesion: 1.0
Nodes (0): 

### Community 35 - "Community 35"
Cohesion: 1.0
Nodes (0): 

### Community 36 - "Community 36"
Cohesion: 1.0
Nodes (0): 

### Community 37 - "Community 37"
Cohesion: 1.0
Nodes (1): SessionManager.stateNotifier (ValueNotifier)

### Community 38 - "Community 38"
Cohesion: 1.0
Nodes (1): CrypButton 3D Button System

### Community 39 - "Community 39"
Cohesion: 1.0
Nodes (1): Guardian Cycle Automation Protocol

### Community 40 - "Community 40"
Cohesion: 1.0
Nodes (1): Agent Changelog Document

### Community 41 - "Community 41"
Cohesion: 1.0
Nodes (1): HomeScreen Overlay Notification Banner (_NotifBanner)

### Community 42 - "Community 42"
Cohesion: 1.0
Nodes (1): SessionState.open

### Community 43 - "Community 43"
Cohesion: 1.0
Nodes (1): SessionState.locked

### Community 44 - "Community 44"
Cohesion: 1.0
Nodes (1): SessionState.decrypting

### Community 45 - "Community 45"
Cohesion: 1.0
Nodes (1): ReceiverScreen

### Community 46 - "Community 46"
Cohesion: 1.0
Nodes (1): AuthRepository

### Community 47 - "Community 47"
Cohesion: 1.0
Nodes (1): Roadmap: Pre-Release (Play Store) Tasks

## Knowledge Gaps
- **98 isolated node(s):** `Generated Plugin Registrant (Android)`, `AppTheme (Material3 Theme)`, `File Utils (formatFileSize)`, `NotificationService (Firestore Notifications Read/Write)`, `SessionState Enum (open/locked/decrypting/terminated)` (+93 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Guardian Script`** (2 nodes): `silent_guardian.ps1`, `Write-Log()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Biometric Auth`** (2 nodes): `BiometricHelper.authenticate()`, `BiometricHelper.checkBiometrics()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Project Documentation`** (2 nodes): `Gemini Graphify Graph Usage Rules`, `CrypTransfer Flutter Project README`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Transfer Service Rationale`** (2 nodes): `Rationale: TransferService for Memory-Stable 64KB Reads`, `TransferService`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Pre-Viva Roadmap`** (2 nodes): `BiometricHelper (Face ID - Bypassed)`, `Roadmap: Pre-Viva Tasks`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 22`** (1 nodes): `update_status.ps1`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 23`** (1 nodes): `AppTheme (Material3 Theme)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 24`** (1 nodes): `TransferRepository.generateId()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 25`** (1 nodes): `TransferRepository.deleteStorageFile()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 26`** (1 nodes): `TransferRepository.deleteTransfer()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 27`** (1 nodes): `EncryptionService.encodePublicKey()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 28`** (1 nodes): `EncryptionService.encodePrivateKey()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 29`** (1 nodes): `BiometricHelper`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 30`** (1 nodes): `formatFileSize()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 31`** (1 nodes): `NotificationService.unreadCountStream()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 32`** (1 nodes): `NotificationService.allStream()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 33`** (1 nodes): `NotificationService.latestUnreadStream()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 34`** (1 nodes): `NotificationService.markRead()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 35`** (1 nodes): `NotificationService.markAllRead()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 36`** (1 nodes): `SecurityLifecycleMixin.registerBuffer()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 37`** (1 nodes): `SessionManager.stateNotifier (ValueNotifier)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 38`** (1 nodes): `CrypButton 3D Button System`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 39`** (1 nodes): `Guardian Cycle Automation Protocol`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 40`** (1 nodes): `Agent Changelog Document`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 41`** (1 nodes): `HomeScreen Overlay Notification Banner (_NotifBanner)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 42`** (1 nodes): `SessionState.open`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 43`** (1 nodes): `SessionState.locked`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 44`** (1 nodes): `SessionState.decrypting`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 45`** (1 nodes): `ReceiverScreen`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 46`** (1 nodes): `AuthRepository`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 47`** (1 nodes): `Roadmap: Pre-Release (Play Store) Tasks`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Are the 3 inferred relationships involving `EncryptionService (Hybrid RSA-2048 + AES-256-GCM)` (e.g. with `TransferModel (Firestore Transfer DTO + encryptedAESKey)` and `Flutter compute() Background Isolate`) actually correct?**
  _`EncryptionService (Hybrid RSA-2048 + AES-256-GCM)` has 3 INFERRED edges - model-reasoned connections that need verification._
- **What connects `Generated Plugin Registrant (Android)`, `AppTheme (Material3 Theme)`, `File Utils (formatFileSize)` to the rest of the system?**
  _98 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Encryption & Screen Security Pipeline` be split into smaller, more focused modules?**
  _Cohesion score 0.07 - nodes in this community are weakly interconnected._
- **Should `Auth & Crypto Core` be split into smaller, more focused modules?**
  _Cohesion score 0.14 - nodes in this community are weakly interconnected._
- **Should `Kill Switch & Session Lifecycle` be split into smaller, more focused modules?**
  _Cohesion score 0.08 - nodes in this community are weakly interconnected._
- **Should `Security Lifecycle Management` be split into smaller, more focused modules?**
  _Cohesion score 0.1 - nodes in this community are weakly interconnected._
- **Should `Data Layer & Crypto Testing` be split into smaller, more focused modules?**
  _Cohesion score 0.09 - nodes in this community are weakly interconnected._