# Graph Report - .  (2026-04-12)

## Corpus Check
- Corpus is ~22,535 words - fits in a single context window. You may not need a graph.

## Summary
- 309 nodes · 352 edges · 56 communities detected
- Extraction: 91% EXTRACTED · 8% INFERRED · 1% AMBIGUOUS · INFERRED: 28 edges (avg confidence: 0.85)
- Token cost: 4,200 input · 1,100 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Automation & Reporting Protocol|Automation & Reporting Protocol]]
- [[_COMMUNITY_Auth & Firebase Layer|Auth & Firebase Layer]]
- [[_COMMUNITY_Windows Runner (Win32)|Windows Runner (Win32)]]
- [[_COMMUNITY_Security Screen Lifecycle|Security Screen Lifecycle]]
- [[_COMMUNITY_Transfer & Notification Service|Transfer & Notification Service]]
- [[_COMMUNITY_Encryption Engine|Encryption Engine]]
- [[_COMMUNITY_iOS Icon Variants|iOS Icon Variants]]
- [[_COMMUNITY_macOS App Icons|macOS App Icons]]
- [[_COMMUNITY_Android Brand Assets|Android Brand Assets]]
- [[_COMMUNITY_Receiver Kill Switch|Receiver Kill Switch]]
- [[_COMMUNITY_Linux Runner|Linux Runner]]
- [[_COMMUNITY_Web PWA Icons|Web PWA Icons]]
- [[_COMMUNITY_macOS App Delegate|macOS App Delegate]]
- [[_COMMUNITY_Crypto Bug Fixes|Crypto Bug Fixes]]
- [[_COMMUNITY_Windows Flutter Window|Windows Flutter Window]]
- [[_COMMUNITY_Android Plugin Registry|Android Plugin Registry]]
- [[_COMMUNITY_Platform Runner Tests|Platform Runner Tests]]
- [[_COMMUNITY_Hybrid Crypto Pipelines|Hybrid Crypto Pipelines]]
- [[_COMMUNITY_LLDB Debug Helper|LLDB Debug Helper]]
- [[_COMMUNITY_macOS Flutter Window|macOS Flutter Window]]
- [[_COMMUNITY_Windows Utilities|Windows Utilities]]
- [[_COMMUNITY_iOS Scene Delegate|iOS Scene Delegate]]
- [[_COMMUNITY_Audit Log & Transfers UI|Audit Log & Transfers UI]]
- [[_COMMUNITY_Android Entry Point|Android Entry Point]]
- [[_COMMUNITY_Linux Plugin Registry|Linux Plugin Registry]]
- [[_COMMUNITY_Linux Entry Point|Linux Entry Point]]
- [[_COMMUNITY_macOS Plugin Registry|macOS Plugin Registry]]
- [[_COMMUNITY_Silent Guardian Script|Silent Guardian Script]]
- [[_COMMUNITY_Windows Plugin Registry|Windows Plugin Registry]]
- [[_COMMUNITY_Windows Entry Point|Windows Entry Point]]
- [[_COMMUNITY_Thesis Open Issues|Thesis Open Issues]]
- [[_COMMUNITY_Android Build Config|Android Build Config]]
- [[_COMMUNITY_Android Settings|Android Settings]]
- [[_COMMUNITY_App Build Gradle|App Build Gradle]]
- [[_COMMUNITY_iOS Plugin Header|iOS Plugin Header]]
- [[_COMMUNITY_iOS Bridging Header|iOS Bridging Header]]
- [[_COMMUNITY_Linux Plugin Header|Linux Plugin Header]]
- [[_COMMUNITY_Linux App Header|Linux App Header]]
- [[_COMMUNITY_Update Status Script|Update Status Script]]
- [[_COMMUNITY_Windows Plugin Header|Windows Plugin Header]]
- [[_COMMUNITY_Windows Resource Header|Windows Resource Header]]
- [[_COMMUNITY_Windows Utils Header|Windows Utils Header]]
- [[_COMMUNITY_Win32 Window Header|Win32 Window Header]]
- [[_COMMUNITY_Changelog Agent|Changelog Agent]]
- [[_COMMUNITY_Transfer Flow|Transfer Flow]]
- [[_COMMUNITY_Session Lock Guard|Session Lock Guard]]
- [[_COMMUNITY_UI Font Dependency|UI Font Dependency]]
- [[_COMMUNITY_iOS Launch Screen|iOS Launch Screen]]
- [[_COMMUNITY_Android HDPI Icon|Android HDPI Icon]]
- [[_COMMUNITY_Android MDPI Icon|Android MDPI Icon]]
- [[_COMMUNITY_Face ID Pending|Face ID Pending]]
- [[_COMMUNITY_Crypto Algorithms Group|Crypto Algorithms Group]]
- [[_COMMUNITY_Screens Mixin Hyperedge|Screens Mixin Hyperedge]]
- [[_COMMUNITY_Kill Switch Hyperedge|Kill Switch Hyperedge]]
- [[_COMMUNITY_Hybrid Encryption Hyperedge|Hybrid Encryption Hyperedge]]
- [[_COMMUNITY_Full Transfer Hyperedge|Full Transfer Hyperedge]]

## God Nodes (most connected - your core abstractions)
1. `CrypTransfer iOS App Icon (Flutter Logo Design)` - 16 edges
2. `Graph Report (graphify-out/GRAPH_REPORT.md)` - 12 edges
3. `AuthRepository` - 10 edges
4. `File Transfer Module` - 10 edges
5. `SecurityLifecycleMixin` - 10 edges
6. `ReceiverScreen` - 10 edges
7. `AppDelegate` - 8 edges
8. `Encryption Module` - 8 edges
9. `Security Module` - 8 edges
10. `UI/UX Module` - 7 edges

## Surprising Connections (you probably didn't know these)
- `Radioactive Buffer Tracker` --semantically_similar_to--> `Radioactive Variables`  [INFERRED] [semantically similar]
  docs/modules/security.md → SECURITY_PROTOCOL.md
- `Flutter Default App Icon` --conceptually_related_to--> `CrypTransfer Flutter Application`  [INFERRED]
  android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png → linux/CMakeLists.txt
- `Android App Icon (xhdpi)` --conceptually_related_to--> `CrypTransfer Flutter Application`  [INFERRED]
  android/app/src/main/res/mipmap-xhdpi/ic_launcher.png → linux/CMakeLists.txt
- `Android App Icon (xxhdpi)` --conceptually_related_to--> `CrypTransfer Flutter Application`  [INFERRED]
  android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png → linux/CMakeLists.txt
- `Closed Mailbox UI (ReceiverScreen toggle flow)` --references--> `ReceiverScreen`  [EXTRACTED]
  docs/modules/ui.md → CLAUDE.md

## Hyperedges (group relationships)
- **Closed Mailbox Kill Switch Components** — encryption_close_receiver_session, claudemd_receiver_screen, security_closed_mailbox_defence, encryption_closed_mailbox_rule [EXTRACTED 1.00]
- **Hybrid Encryption Pipeline** — encryption_aes_gcm, encryption_rsa_oaep, encryption_sender_pipeline, encryption_receiver_pipeline [EXTRACTED 1.00]
- **Full Transfer Flow Components** — file_transfer_module, claudemd_sender_screen, claudemd_receiver_screen, claudemd_decrypt_screen, transfer_non_repudiation, transfer_document_schema [EXTRACTED 1.00]
- **Multi-Platform Build Targets** — linux_cmake_root, windows_cmake_root, cryptransfer_app [EXTRACTED 1.00]
- **Screens Using SecurityLifecycleMixin** — claudemd_security_lifecycle_mixin, claudemd_sender_screen, claudemd_decrypt_screen, claudemd_transfer_progress_screen, claudemd_download_confirm_screen, claudemd_end_session_screen [EXTRACTED 1.00]
- **ReceiverScreen Auto-Wipe Mechanisms** — claudemd_receiver_screen, claudemd_on_toggle_ready, claudemd_show_close_session_dialog, claudemd_widgets_binding_observer, claudemd_pop_scope, claudemd_session_locked [EXTRACTED 1.00]
- **Automation Protocol Sync Commands** — claudemd_automation_protocol, claudemd_daily_report_command, claudemd_update_status_command, claudemd_guardian_cycle, claudemd_powershell_headless_wrapper [EXTRACTED 1.00]
- **Guardian Scanner Verification Checks** — claudemd_silent_guardian_scanner, claudemd_guardian_scanner_updated, claudemd_generate_store_keypair_compute, claudemd_participants_field, claudemd_encrypted_aes_key_drift_fix [EXTRACTED 1.00]
- **Top God Nodes (Cross-community Bridges)** — graph_god_node_auth_repository, graph_god_node_file_transfer_module, graph_god_node_encryption_module, graph_god_node_security_module [EXTRACTED 1.00]

## Communities

### Community 0 - "Automation & Reporting Protocol"
Cohesion: 0.09
Nodes (27): Automation Protocol & Scripts, Background Execution Policy (Non-Interactive), Daily Report Command, flutter analyze --no-pub, Guardian Cycle (12PM-12PM), Daily Report Command, Update Status Command, Obsidian DailyReports Path (+19 more)

### Community 1 - "Auth & Firebase Layer"
Cohesion: 0.08
Nodes (22): cloud_firestore dependency (auth), Exception Hierarchy (AppException subclasses), firebase_auth dependency, Firestore User Document Schema (users/{uid}), flutter_secure_storage dependency (auth), local_auth dependency (biometric), LoginScreen (auth), Authentication Module (+14 more)

### Community 2 - "Windows Runner (Win32)"
Cohesion: 0.17
Nodes (16): Create(), Destroy(), EnableFullDpiSupportIfAvailable(), GetClientArea(), GetThisFromHandle(), GetWindowClass(), MessageHandler(), OnCreate() (+8 more)

### Community 3 - "Security Screen Lifecycle"
Cohesion: 0.15
Nodes (20): DecryptScreen, DownloadConfirmScreen, EndSessionScreen, Non-repudiation Firestore listener (TransferProgressScreen), Open Issue: pushAndRemoveUntil after EndSession, Open Issue: Session cleanup after End Session, _Phase.done (Save & Suicide pattern), receiverStatus field (DecryptScreen phases) (+12 more)

### Community 4 - "Transfer & Notification Service"
Cohesion: 0.11
Nodes (20): File Transfer Module, Notification Document Schema (notifications/{docId}), NotificationModel + NotificationType enum, NotificationService, cloud_firestore dependency (notifications), Notifications Module, NotificationsScreen, cloud_firestore dependency (transfer) (+12 more)

### Community 5 - "Encryption Engine"
Cohesion: 0.11
Nodes (19): cloud_firestore dependency (encryption), flutter_secure_storage dependency (encryption), Encryption Module, pointycastle dependency, lib/core/utils/security_lifecycle_mixin.dart, lib/data/services/encryption_service.dart, Security Audit Logging (_logSecurityEvent), scripts/security_audit_report.dart (+11 more)

### Community 6 - "iOS Icon Variants"
Cohesion: 0.11
Nodes (19): Light Blue (#54C5F8) Primary Color, Navy Blue (#01579B) Accent Color, Flutter Default Logo Design, App Icon 20x20 @1x, App Icon 20x20 @2x, App Icon 20x20 @3x, App Icon 29x29 @1x, App Icon 29x29 @2x (+11 more)

### Community 7 - "macOS App Icons"
Cohesion: 0.33
Nodes (16): macOS App Icon 1024px, macOS App Icon 128px, macOS App Icon 16px, macOS App Icon 256px, macOS App Icon 32px, macOS App Icon 512px, macOS App Icon 64px, macOS App Icon - Default Flutter Logo Design (+8 more)

### Community 8 - "Android Brand Assets"
Cohesion: 0.23
Nodes (13): Android Launcher Icon Set, CrypTransfer Flutter Application, Flutter Default App Icon, Flutter Logo Visual Style (Light Blue Chevron), Android App Icon (xhdpi), Android App Icon (xxhdpi), Linux CMakeLists.txt (root), Linux Flutter CMakeLists.txt (+5 more)

### Community 9 - "Receiver Kill Switch"
Cohesion: 0.23
Nodes (11): closeReceiverSession Kill Switch (EncryptionService), ReceiverScreen._onToggleReady(), PopScope (ReceiverScreen back navigation wipe), ReceiverScreen, _sessionLocked + _showSessionLockedBanner(), TC-WIPE-001 to TC-WIPE-006 (session_wipe_test.dart), Silent Guardian Kill Switch Scanner, State Scanner Rules (+3 more)

### Community 10 - "Linux Runner"
Cohesion: 0.2
Nodes (0): 

### Community 11 - "Web PWA Icons"
Cohesion: 0.49
Nodes (10): Blue Colour Scheme (Sky Blue + Navy), Default Flutter Web Scaffold (Unbranded), Flutter Framework Logo, Maskable Icon (PWA Safe Zone Convention), Progressive Web App Icon Set, Web Favicon (Flutter Logo, 16px), PWA App Icon 192x192 (Flutter Logo), PWA App Icon 512x512 (Flutter Logo) (+2 more)

### Community 12 - "macOS App Delegate"
Cohesion: 0.22
Nodes (3): AppDelegate, FlutterAppDelegate, FlutterImplicitEngineDelegate

### Community 13 - "Crypto Bug Fixes"
Cohesion: 0.32
Nodes (8): encryptedAESKey Field Name Drift Fix, generateAndStoreKeyPair() migrated to compute(), Guardian Scanner Updated (compute/participants/encryptedAESKey checks), HomeScreen Recent Transfers Firestore Query, Legacy Isolate.run() Path (generateAndStoreKeyPair), participants field in writeAuditLog(), Community: Audit Log & Query Gap, Rationale: compute() over Isolate.run() for crypto

### Community 14 - "Windows Flutter Window"
Cohesion: 0.33
Nodes (1): FlutterWindow()

### Community 15 - "Android Plugin Registry"
Cohesion: 0.4
Nodes (2): GeneratedPluginRegistrant, -registerWithRegistry

### Community 16 - "Platform Runner Tests"
Cohesion: 0.4
Nodes (2): RunnerTests, XCTestCase

### Community 17 - "Hybrid Crypto Pipelines"
Cohesion: 0.6
Nodes (5): AES-256-GCM Encryption, Receiver Crypto Pipeline, RSA-2048-OAEP Key Wrapping, Sender Crypto Pipeline, OWASP Mobile Top 10 Coverage

### Community 18 - "LLDB Debug Helper"
Cohesion: 0.5
Nodes (2): handle_new_rx_page(), Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.

### Community 19 - "macOS Flutter Window"
Cohesion: 0.5
Nodes (2): MainFlutterWindow, NSWindow

### Community 20 - "Windows Utilities"
Cohesion: 0.67
Nodes (2): GetCommandLineArguments(), Utf8FromUtf16()

### Community 21 - "iOS Scene Delegate"
Cohesion: 0.67
Nodes (2): FlutterSceneDelegate, SceneDelegate

### Community 22 - "Audit Log & Transfers UI"
Cohesion: 0.67
Nodes (3): Audit Log Document Schema (transfers_log/{docId}), participants Field Implementation Gap, HomeScreen Recent Transfers Firestore Query

### Community 23 - "Android Entry Point"
Cohesion: 1.0
Nodes (1): MainActivity

### Community 24 - "Linux Plugin Registry"
Cohesion: 1.0
Nodes (0): 

### Community 25 - "Linux Entry Point"
Cohesion: 1.0
Nodes (0): 

### Community 26 - "macOS Plugin Registry"
Cohesion: 1.0
Nodes (0): 

### Community 27 - "Silent Guardian Script"
Cohesion: 1.0
Nodes (0): 

### Community 28 - "Windows Plugin Registry"
Cohesion: 1.0
Nodes (0): 

### Community 29 - "Windows Entry Point"
Cohesion: 1.0
Nodes (0): 

### Community 30 - "Thesis Open Issues"
Cohesion: 1.0
Nodes (2): Open Issue: Chapter 3 thesis update, Open Issue: Chapter 5 testing results

### Community 31 - "Android Build Config"
Cohesion: 1.0
Nodes (0): 

### Community 32 - "Android Settings"
Cohesion: 1.0
Nodes (0): 

### Community 33 - "App Build Gradle"
Cohesion: 1.0
Nodes (0): 

### Community 34 - "iOS Plugin Header"
Cohesion: 1.0
Nodes (0): 

### Community 35 - "iOS Bridging Header"
Cohesion: 1.0
Nodes (0): 

### Community 36 - "Linux Plugin Header"
Cohesion: 1.0
Nodes (0): 

### Community 37 - "Linux App Header"
Cohesion: 1.0
Nodes (0): 

### Community 38 - "Update Status Script"
Cohesion: 1.0
Nodes (0): 

### Community 39 - "Windows Plugin Header"
Cohesion: 1.0
Nodes (0): 

### Community 40 - "Windows Resource Header"
Cohesion: 1.0
Nodes (0): 

### Community 41 - "Windows Utils Header"
Cohesion: 1.0
Nodes (0): 

### Community 42 - "Win32 Window Header"
Cohesion: 1.0
Nodes (0): 

### Community 43 - "Changelog Agent"
Cohesion: 1.0
Nodes (1): Agent Changelog

### Community 44 - "Transfer Flow"
Cohesion: 1.0
Nodes (1): Full Transfer Flow (senderâ†’receiver)

### Community 45 - "Session Lock Guard"
Cohesion: 1.0
Nodes (1): Session Lock (_sessionLocked)

### Community 46 - "UI Font Dependency"
Cohesion: 1.0
Nodes (1): google_fonts dependency (Poppins)

### Community 47 - "iOS Launch Screen"
Cohesion: 1.0
Nodes (1): iOS Launch Screen Assets

### Community 48 - "Android HDPI Icon"
Cohesion: 1.0
Nodes (1): Android App Launcher Icon (HDPI)

### Community 49 - "Android MDPI Icon"
Cohesion: 1.0
Nodes (1): Android App Launcher Icon (MDPI)

### Community 50 - "Face ID Pending"
Cohesion: 1.0
Nodes (1): Open Issue: Face ID re-enable before viva

### Community 51 - "Crypto Algorithms Group"
Cohesion: 1.0
Nodes (1): Community: Crypto Algorithms

### Community 52 - "Screens Mixin Hyperedge"
Cohesion: 1.0
Nodes (1): Screens Using SecurityLifecycleMixin (hyperedge)

### Community 53 - "Kill Switch Hyperedge"
Cohesion: 1.0
Nodes (1): Closed Mailbox Kill Switch Components (hyperedge)

### Community 54 - "Hybrid Encryption Hyperedge"
Cohesion: 1.0
Nodes (1): Hybrid Encryption Pipeline (hyperedge)

### Community 55 - "Full Transfer Hyperedge"
Cohesion: 1.0
Nodes (1): Full Transfer Flow Components (hyperedge)

## Ambiguous Edges - Review These
- `Flutter Default App Icon` → `Android Launcher Icon Set`  [AMBIGUOUS]
  android/app/src/main/res/mipmap-xhdpi/ic_launcher.png · relation: conceptually_related_to
- `Open Issue: Chapter 3 thesis update` → `Open Issue: Chapter 5 testing results`  [AMBIGUOUS]
  CLAUDE.md · relation: conceptually_related_to

## Knowledge Gaps
- **97 isolated node(s):** `MainActivity`, `Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.`, `-registerWithRegistry`, `Daily Report Command`, `Update Status Command` (+92 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Android Entry Point`** (2 nodes): `MainActivity.kt`, `MainActivity`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Linux Plugin Registry`** (2 nodes): `fl_register_plugins()`, `generated_plugin_registrant.cc`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Linux Entry Point`** (2 nodes): `main.cc`, `main()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `macOS Plugin Registry`** (2 nodes): `RegisterGeneratedPlugins()`, `GeneratedPluginRegistrant.swift`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Silent Guardian Script`** (2 nodes): `silent_guardian.ps1`, `Write-Log()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Windows Plugin Registry`** (2 nodes): `RegisterPlugins()`, `generated_plugin_registrant.cc`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Windows Entry Point`** (2 nodes): `wWinMain()`, `main.cpp`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Thesis Open Issues`** (2 nodes): `Open Issue: Chapter 3 thesis update`, `Open Issue: Chapter 5 testing results`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Android Build Config`** (1 nodes): `build.gradle.kts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Android Settings`** (1 nodes): `settings.gradle.kts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `App Build Gradle`** (1 nodes): `build.gradle.kts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `iOS Plugin Header`** (1 nodes): `GeneratedPluginRegistrant.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `iOS Bridging Header`** (1 nodes): `Runner-Bridging-Header.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Linux Plugin Header`** (1 nodes): `generated_plugin_registrant.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Linux App Header`** (1 nodes): `my_application.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Update Status Script`** (1 nodes): `update_status.ps1`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Windows Plugin Header`** (1 nodes): `generated_plugin_registrant.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Windows Resource Header`** (1 nodes): `resource.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Windows Utils Header`** (1 nodes): `utils.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Win32 Window Header`** (1 nodes): `win32_window.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Changelog Agent`** (1 nodes): `Agent Changelog`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Transfer Flow`** (1 nodes): `Full Transfer Flow (senderâ†’receiver)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Session Lock Guard`** (1 nodes): `Session Lock (_sessionLocked)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `UI Font Dependency`** (1 nodes): `google_fonts dependency (Poppins)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `iOS Launch Screen`** (1 nodes): `iOS Launch Screen Assets`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Android HDPI Icon`** (1 nodes): `Android App Launcher Icon (HDPI)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Android MDPI Icon`** (1 nodes): `Android App Launcher Icon (MDPI)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Face ID Pending`** (1 nodes): `Open Issue: Face ID re-enable before viva`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Crypto Algorithms Group`** (1 nodes): `Community: Crypto Algorithms`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Screens Mixin Hyperedge`** (1 nodes): `Screens Using SecurityLifecycleMixin (hyperedge)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Kill Switch Hyperedge`** (1 nodes): `Closed Mailbox Kill Switch Components (hyperedge)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Hybrid Encryption Hyperedge`** (1 nodes): `Hybrid Encryption Pipeline (hyperedge)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Full Transfer Hyperedge`** (1 nodes): `Full Transfer Flow Components (hyperedge)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Flutter Default App Icon` and `Android Launcher Icon Set`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `Open Issue: Chapter 3 thesis update` and `Open Issue: Chapter 5 testing results`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `SecurityLifecycleMixin` connect `Security Screen Lifecycle` to `Receiver Kill Switch`, `Encryption Engine`?**
  _High betweenness centrality (0.094) - this node is a cross-community bridge._
- **Why does `Security Protocol Core Rules` connect `Encryption Engine` to `Security Screen Lifecycle`?**
  _High betweenness centrality (0.068) - this node is a cross-community bridge._
- **Why does `Security Module` connect `Encryption Engine` to `Transfer & Notification Service`?**
  _High betweenness centrality (0.067) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `File Transfer Module` (e.g. with `Encryption Module` and `Notifications Module`) actually correct?**
  _`File Transfer Module` has 4 INFERRED edges - model-reasoned connections that need verification._
- **What connects `MainActivity`, `Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.`, `-registerWithRegistry` to the rest of the system?**
  _97 weakly-connected nodes found - possible documentation gaps or missing edges._