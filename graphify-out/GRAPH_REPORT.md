# Graph Report - .  (2026-05-25)

## Corpus Check
- 0 files · ~0 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 55 nodes · 30 edges · 27 communities detected
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 4 edges (avg confidence: 0.82)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_iOS App Life Cycle|iOS App Life Cycle]]
- [[_COMMUNITY_Flutter Plugin Registration|Flutter Plugin Registration]]
- [[_COMMUNITY_Core App Services|Core App Services]]
- [[_COMMUNITY_LLDB Debug Helpers|LLDB Debug Helpers]]
- [[_COMMUNITY_iOS Unit Testing|iOS Unit Testing]]
- [[_COMMUNITY_Security Implementation|Security Implementation]]
- [[_COMMUNITY_iOS Scene Management|iOS Scene Management]]
- [[_COMMUNITY_Android Activity & Security|Android Activity & Security]]
- [[_COMMUNITY_iOS Bridging & Plugins|iOS Bridging & Plugins]]
- [[_COMMUNITY_Android Flowchart Automation|Android Flowchart Automation]]
- [[_COMMUNITY_UI Design & Themes|UI Design & Themes]]
- [[_COMMUNITY_Android Build Configuration|Android Build Configuration]]
- [[_COMMUNITY_Android Project Settings|Android Project Settings]]
- [[_COMMUNITY_Android App Build|Android App Build]]
- [[_COMMUNITY_Security Flag Status|Security Flag Status]]
- [[_COMMUNITY_Silent Guardian Script|Silent Guardian Script]]
- [[_COMMUNITY_Update Status Script|Update Status Script]]
- [[_COMMUNITY_UI Framework|UI Framework]]
- [[_COMMUNITY_Admin Dashboard|Admin Dashboard]]
- [[_COMMUNITY_Transfer Management|Transfer Management]]
- [[_COMMUNITY_Audit Logging|Audit Logging]]
- [[_COMMUNITY_User Management|User Management]]
- [[_COMMUNITY_Transfer Service|Transfer Service]]
- [[_COMMUNITY_Sender UX|Sender UX]]
- [[_COMMUNITY_Silent Guardian Service|Silent Guardian Service]]
- [[_COMMUNITY_Visual Design Palette|Visual Design Palette]]
- [[_COMMUNITY_Immersive User Experience|Immersive User Experience]]

## God Nodes (most connected - your core abstractions)
1. `AppDelegate` - 5 edges
2. `GeneratedPluginRegistrant` - 4 edges
3. `Session Manager` - 4 edges
4. `RunnerTests` - 3 edges
5. `Security Lifecycle Mixin` - 3 edges
6. `Android FLAG_SECURE` - 3 edges
7. `handle_new_rx_page()` - 2 edges
8. `SceneDelegate` - 2 edges
9. `Impeller Rendering Backend` - 2 edges
10. `Encryption Service` - 2 edges

## Surprising Connections (you probably didn't know these)
- `Cyberpunk UI Style` --semantically_similar_to--> `GitHub Dark Theme Palette`  [INFERRED] [semantically similar]
  design-system/cryptransfer/MASTER.md → CLAUDE.md
- `iOS Runner Bridging Header` --references--> `iOS GeneratedPluginRegistrant Header`  [EXTRACTED]
  ios/Runner/Runner-Bridging-Header.h → ios/Runner/GeneratedPluginRegistrant.h

## Hyperedges (group relationships)
- **Kill Switch Execution Chain** — claude_session_manager, claude_encryption_service, claude_security_lifecycle_mixin [EXTRACTED 1.00]
- **Core Data Entities** — claude_rsa_key_transfers, claude_transfers, claude_transfers_log, claude_users [EXTRACTED 1.00]

## Communities

### Community 0 - "iOS App Life Cycle"
Cohesion: 0.33
Nodes (3): AppDelegate, FlutterAppDelegate, FlutterImplicitEngineDelegate

### Community 1 - "Flutter Plugin Registration"
Cohesion: 0.4
Nodes (2): GeneratedPluginRegistrant, -registerWithRegistry

### Community 2 - "Core App Services"
Cohesion: 0.4
Nodes (5): Encryption Service, Closed Mailbox Kill Switch, Receiver Screen, RSA Key Transfers Data Model, Session Manager

### Community 3 - "LLDB Debug Helpers"
Cohesion: 0.5
Nodes (2): handle_new_rx_page(), Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.

### Community 4 - "iOS Unit Testing"
Cohesion: 0.5
Nodes (2): RunnerTests, XCTestCase

### Community 5 - "Security Implementation"
Cohesion: 0.67
Nodes (4): Android FLAG_SECURE, Impeller Rendering Backend, Android MainActivity, Security Lifecycle Mixin

### Community 6 - "iOS Scene Management"
Cohesion: 0.67
Nodes (2): FlutterSceneDelegate, SceneDelegate

### Community 7 - "Android Activity & Security"
Cohesion: 1.0
Nodes (2): com.example.cryptransfer/security, MainActivity

### Community 8 - "iOS Bridging & Plugins"
Cohesion: 1.0
Nodes (2): iOS Runner Bridging Header, iOS GeneratedPluginRegistrant Header

### Community 9 - "Android Flowchart Automation"
Cohesion: 1.0
Nodes (0): 

### Community 10 - "UI Design & Themes"
Cohesion: 1.0
Nodes (2): GitHub Dark Theme Palette, Cyberpunk UI Style

### Community 11 - "Android Build Configuration"
Cohesion: 1.0
Nodes (0): 

### Community 12 - "Android Project Settings"
Cohesion: 1.0
Nodes (0): 

### Community 13 - "Android App Build"
Cohesion: 1.0
Nodes (0): 

### Community 14 - "Security Flag Status"
Cohesion: 1.0
Nodes (1): isFlagSecureActive

### Community 15 - "Silent Guardian Script"
Cohesion: 1.0
Nodes (0): 

### Community 16 - "Update Status Script"
Cohesion: 1.0
Nodes (0): 

### Community 17 - "UI Framework"
Cohesion: 1.0
Nodes (1): Flutter UI Framework

### Community 18 - "Admin Dashboard"
Cohesion: 1.0
Nodes (1): Admin Dashboard

### Community 19 - "Transfer Management"
Cohesion: 1.0
Nodes (1): Transfers Data Model

### Community 20 - "Audit Logging"
Cohesion: 1.0
Nodes (1): User Audit Log Model

### Community 21 - "User Management"
Cohesion: 1.0
Nodes (1): User Profiles Data Model

### Community 22 - "Transfer Service"
Cohesion: 1.0
Nodes (1): Transfer Service

### Community 23 - "Sender UX"
Cohesion: 1.0
Nodes (1): Sender Screen

### Community 24 - "Silent Guardian Service"
Cohesion: 1.0
Nodes (1): Silent Guardian Security Scanner

### Community 25 - "Visual Design Palette"
Cohesion: 1.0
Nodes (1): Design System Color Palette

### Community 26 - "Immersive User Experience"
Cohesion: 1.0
Nodes (1): Immersive Page Pattern

## Knowledge Gaps
- **23 isolated node(s):** `com.example.cryptransfer/security`, `MainActivity`, `isFlagSecureActive`, `Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.`, `iOS GeneratedPluginRegistrant Header` (+18 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Android Activity & Security`** (2 nodes): `com.example.cryptransfer/security`, `MainActivity`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `iOS Bridging & Plugins`** (2 nodes): `iOS Runner Bridging Header`, `iOS GeneratedPluginRegistrant Header`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Android Flowchart Automation`** (2 nodes): `generate_flowchart.py`, `create_flowchart_docx()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `UI Design & Themes`** (2 nodes): `GitHub Dark Theme Palette`, `Cyberpunk UI Style`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Android Build Configuration`** (1 nodes): `build.gradle.kts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Android Project Settings`** (1 nodes): `settings.gradle.kts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Android App Build`** (1 nodes): `build.gradle.kts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Security Flag Status`** (1 nodes): `isFlagSecureActive`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Silent Guardian Script`** (1 nodes): `silent_guardian.ps1`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Update Status Script`** (1 nodes): `update_status.ps1`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `UI Framework`** (1 nodes): `Flutter UI Framework`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Admin Dashboard`** (1 nodes): `Admin Dashboard`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Transfer Management`** (1 nodes): `Transfers Data Model`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Audit Logging`** (1 nodes): `User Audit Log Model`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `User Management`** (1 nodes): `User Profiles Data Model`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Transfer Service`** (1 nodes): `Transfer Service`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Sender UX`** (1 nodes): `Sender Screen`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Silent Guardian Service`** (1 nodes): `Silent Guardian Security Scanner`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Visual Design Palette`** (1 nodes): `Design System Color Palette`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Immersive User Experience`** (1 nodes): `Immersive Page Pattern`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Session Manager` connect `Core App Services` to `Security Implementation`?**
  _High betweenness centrality (0.015) - this node is a cross-community bridge._
- **Why does `Security Lifecycle Mixin` connect `Security Implementation` to `Core App Services`?**
  _High betweenness centrality (0.010) - this node is a cross-community bridge._
- **What connects `com.example.cryptransfer/security`, `MainActivity`, `isFlagSecureActive` to the rest of the system?**
  _23 weakly-connected nodes found - possible documentation gaps or missing edges._