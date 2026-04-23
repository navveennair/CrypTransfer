# Graph Report - .  (2026-04-20)

## Corpus Check
- 14 files · ~25,921 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 34 nodes · 22 edges · 12 communities detected
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
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

## God Nodes (most connected - your core abstractions)
1. `AppDelegate` - 5 edges
2. `GeneratedPluginRegistrant` - 4 edges
3. `MainActivity` - 3 edges
4. `RunnerTests` - 3 edges
5. `handle_new_rx_page()` - 2 edges
6. `SceneDelegate` - 2 edges
7. `Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.` - 1 edges
8. `iOS GeneratedPluginRegistrant Header` - 1 edges
9. `-registerWithRegistry` - 1 edges
10. `iOS Runner Bridging Header` - 1 edges

## Surprising Connections (you probably didn't know these)
- `iOS Runner Bridging Header` --references--> `iOS GeneratedPluginRegistrant Header`  [EXTRACTED]
  ios/Runner/Runner-Bridging-Header.h → ios/Runner/GeneratedPluginRegistrant.h

## Communities

### Community 0 - "Community 0"
Cohesion: 0.33
Nodes (3): AppDelegate, FlutterAppDelegate, FlutterImplicitEngineDelegate

### Community 1 - "Community 1"
Cohesion: 0.4
Nodes (2): GeneratedPluginRegistrant, -registerWithRegistry

### Community 2 - "Community 2"
Cohesion: 0.5
Nodes (1): MainActivity

### Community 3 - "Community 3"
Cohesion: 0.5
Nodes (2): handle_new_rx_page(), Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.

### Community 4 - "Community 4"
Cohesion: 0.5
Nodes (2): RunnerTests, XCTestCase

### Community 5 - "Community 5"
Cohesion: 0.67
Nodes (2): FlutterSceneDelegate, SceneDelegate

### Community 6 - "Community 6"
Cohesion: 1.0
Nodes (2): iOS Runner Bridging Header, iOS GeneratedPluginRegistrant Header

### Community 7 - "Community 7"
Cohesion: 1.0
Nodes (0): 

### Community 8 - "Community 8"
Cohesion: 1.0
Nodes (0): 

### Community 9 - "Community 9"
Cohesion: 1.0
Nodes (0): 

### Community 10 - "Community 10"
Cohesion: 1.0
Nodes (0): 

### Community 11 - "Community 11"
Cohesion: 1.0
Nodes (0): 

## Knowledge Gaps
- **4 isolated node(s):** `Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.`, `iOS GeneratedPluginRegistrant Header`, `-registerWithRegistry`, `iOS Runner Bridging Header`
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Community 6`** (2 nodes): `iOS Runner Bridging Header`, `iOS GeneratedPluginRegistrant Header`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 7`** (2 nodes): `silent_guardian.ps1`, `Write-Log()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 8`** (1 nodes): `build.gradle.kts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 9`** (1 nodes): `settings.gradle.kts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 10`** (1 nodes): `build.gradle.kts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 11`** (1 nodes): `update_status.ps1`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What connects `Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.`, `iOS GeneratedPluginRegistrant Header`, `-registerWithRegistry` to the rest of the system?**
  _4 weakly-connected nodes found - possible documentation gaps or missing edges._