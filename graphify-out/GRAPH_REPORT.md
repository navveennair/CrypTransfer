# Graph Report - .  (2026-05-25)

## Corpus Check
- 328 files · ~48,243 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 55 nodes · 30 edges · 27 communities detected
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 4 edges (avg confidence: 0.82)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]
- [[_COMMUNITY_Community 26|Community 26]]

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

### Community 0 - "Community 0"
Cohesion: 0.33
Nodes (3): AppDelegate, FlutterAppDelegate, FlutterImplicitEngineDelegate

### Community 1 - "Community 1"
Cohesion: 0.4
Nodes (2): GeneratedPluginRegistrant, -registerWithRegistry

### Community 2 - "Community 2"
Cohesion: 0.4
Nodes (5): Encryption Service, Closed Mailbox Kill Switch, Receiver Screen, RSA Key Transfers Data Model, Session Manager

### Community 3 - "Community 3"
Cohesion: 0.5
Nodes (2): handle_new_rx_page(), Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.

### Community 4 - "Community 4"
Cohesion: 0.5
Nodes (2): RunnerTests, XCTestCase

### Community 5 - "Community 5"
Cohesion: 0.67
Nodes (4): Android FLAG_SECURE, Impeller Rendering Backend, Android MainActivity, Security Lifecycle Mixin

### Community 6 - "Community 6"
Cohesion: 0.67
Nodes (2): FlutterSceneDelegate, SceneDelegate

### Community 7 - "Community 7"
Cohesion: 1.0
Nodes (2): com.example.cryptransfer/security, MainActivity

### Community 8 - "Community 8"
Cohesion: 1.0
Nodes (2): iOS Runner Bridging Header, iOS GeneratedPluginRegistrant Header

### Community 9 - "Community 9"
Cohesion: 1.0
Nodes (0): 

### Community 10 - "Community 10"
Cohesion: 1.0
Nodes (2): GitHub Dark Theme Palette, Cyberpunk UI Style

### Community 11 - "Community 11"
Cohesion: 1.0
Nodes (0): 

### Community 12 - "Community 12"
Cohesion: 1.0
Nodes (0): 

### Community 13 - "Community 13"
Cohesion: 1.0
Nodes (0): 

### Community 14 - "Community 14"
Cohesion: 1.0
Nodes (1): isFlagSecureActive

### Community 15 - "Community 15"
Cohesion: 1.0
Nodes (0): 

### Community 16 - "Community 16"
Cohesion: 1.0
Nodes (0): 

### Community 17 - "Community 17"
Cohesion: 1.0
Nodes (1): Flutter UI Framework

### Community 18 - "Community 18"
Cohesion: 1.0
Nodes (1): Admin Dashboard

### Community 19 - "Community 19"
Cohesion: 1.0
Nodes (1): Transfers Data Model

### Community 20 - "Community 20"
Cohesion: 1.0
Nodes (1): User Audit Log Model

### Community 21 - "Community 21"
Cohesion: 1.0
Nodes (1): User Profiles Data Model

### Community 22 - "Community 22"
Cohesion: 1.0
Nodes (1): Transfer Service

### Community 23 - "Community 23"
Cohesion: 1.0
Nodes (1): Sender Screen

### Community 24 - "Community 24"
Cohesion: 1.0
Nodes (1): Silent Guardian Security Scanner

### Community 25 - "Community 25"
Cohesion: 1.0
Nodes (1): Design System Color Palette

### Community 26 - "Community 26"
Cohesion: 1.0
Nodes (1): Immersive Page Pattern

## Knowledge Gaps
- **23 isolated node(s):** `com.example.cryptransfer/security`, `MainActivity`, `isFlagSecureActive`, `Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.`, `iOS GeneratedPluginRegistrant Header` (+18 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Community 7`** (2 nodes): `com.example.cryptransfer/security`, `MainActivity`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 8`** (2 nodes): `iOS Runner Bridging Header`, `iOS GeneratedPluginRegistrant Header`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 9`** (2 nodes): `generate_flowchart.py`, `create_flowchart_docx()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 10`** (2 nodes): `GitHub Dark Theme Palette`, `Cyberpunk UI Style`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 11`** (1 nodes): `build.gradle.kts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 12`** (1 nodes): `settings.gradle.kts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 13`** (1 nodes): `build.gradle.kts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 14`** (1 nodes): `isFlagSecureActive`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 15`** (1 nodes): `silent_guardian.ps1`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 16`** (1 nodes): `update_status.ps1`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 17`** (1 nodes): `Flutter UI Framework`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 18`** (1 nodes): `Admin Dashboard`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 19`** (1 nodes): `Transfers Data Model`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 20`** (1 nodes): `User Audit Log Model`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 21`** (1 nodes): `User Profiles Data Model`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 22`** (1 nodes): `Transfer Service`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 23`** (1 nodes): `Sender Screen`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 24`** (1 nodes): `Silent Guardian Security Scanner`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 25`** (1 nodes): `Design System Color Palette`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 26`** (1 nodes): `Immersive Page Pattern`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Session Manager` connect `Community 2` to `Community 5`?**
  _High betweenness centrality (0.015) - this node is a cross-community bridge._
- **Why does `Security Lifecycle Mixin` connect `Community 5` to `Community 2`?**
  _High betweenness centrality (0.010) - this node is a cross-community bridge._
- **What connects `com.example.cryptransfer/security`, `MainActivity`, `isFlagSecureActive` to the rest of the system?**
  _23 weakly-connected nodes found - possible documentation gaps or missing edges._