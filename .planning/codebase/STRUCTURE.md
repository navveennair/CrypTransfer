# Structure — CrypTransfer

**Mapped:** 2026-05-28
**Build system:** Flutter (Dart) + Gradle Kotlin DSL (Android)

---

## 1. Top-Level Layout

```
cryptransfer/
├── lib/                      Flutter app code (52 .dart files)
├── android/                  Android-specific build + native bridge
├── ios/                      iOS skeleton (not the active target)
├── web/                      Web bootstrap (Impeller WASM)
├── test/                     Unit + integration tests (18 .dart files)
├── scripts/                  PowerShell + Dart automation (5 files)
├── design-system/
│   └── cryptransfer/         Canonical UI rules (MASTER.md, etc.)
├── graphify-out/             Generated knowledge graph + analyses
├── .planning/                GSD planning state + codebase map (this doc)
├── pubspec.yaml              Flutter dependencies
├── analysis_options.yaml     flutter_lints config
└── CLAUDE.md                 Project instructions (source of truth)
```

---

## 2. `lib/` — Application Code

```
lib/
├── main.dart                                  Firebase init, MaterialApp root
├── app_theme.dart                             GitHub Dark + gold/purple ColorScheme
├── firebase_options.dart                      Generated FirebaseOptions
│
├── core/
│   ├── constants/
│   │   └── firebase_constants.dart            Collection names (users, handshakes, transfers, transfer_logs, neutral_handshakes)
│   ├── errors/
│   │   └── app_exceptions.dart                Typed exceptions (KeyNotFoundException, …)
│   ├── services/
│   │   └── auth_method_service.dart           Auth-provider linkage helpers
│   └── utils/
│       ├── biometric_helper.dart              local_auth 3.0.1 wrapper (persistAcrossBackgrounding)
│       ├── file_utils.dart                    Path / filename helpers
│       ├── notification_service.dart          In-app notification orchestration
│       ├── security_lifecycle_mixin.dart      ⭐ Uint8List zero-wipe + FLAG_SECURE + MethodChannel
│       ├── session_manager.dart               ⭐ SessionState machine + broadcast stateStream
│       ├── session_state.dart                 SessionState enum (extracted to break import cycle)
│       ├── theme_service.dart                 Theme mode persistence
│       └── tofu_service.dart                  Trust-on-first-use key pinning
│
├── data/
│   ├── models/
│   │   ├── notification_model.dart
│   │   ├── transfer_model.dart
│   │   └── user_model.dart
│   ├── repositories/
│   │   ├── admin_repository.dart              Admin queries (all users, all transfer_logs)
│   │   ├── auth_repository.dart               Auth + profile bootstrap
│   │   ├── cleanup_repository.dart            End-of-session deletion
│   │   ├── handshake_repository.dart          neutral_handshakes (friend connections)
│   │   ├── key_repository.dart                ⭐ selectSenderHandshake (WriteBatch), streamHandshakesForSender
│   │   ├── transfer_repository.dart           transfers/{id} lifecycle, updateReceiverStatus, writeAuditLog
│   │   └── user_repository.dart               users/{uid} field reads/writes
│   └── services/
│       ├── encryption_service.dart            ⭐ Hybrid RSA+AES, compute() isolates, bindSession reactive kill-switch
│       ├── transfer_log_service.dart          Audit log helper (participants array)
│       └── transfer_service.dart              ⭐ 64KB chunked file I/O (kChunkSize), resolve()
│
├── services/
│   └── firestore_migration.dart               One-shot schema migrations
│
└── presentation/
    ├── auth/
    │   ├── splash_screen.dart                 Animated splash, route gate
    │   ├── onboarding_screen.dart
    │   ├── login_screen.dart
    │   └── register_screen.dart
    │
    ├── home/
    │   ├── home_screen.dart                   Entry; recent transfers; role picker
    │   ├── find_friends_screen.dart           Search + _SearchResultTile (per-user handshake stream)
    │   ├── sidebar_drawer.dart                Glassmorphic drawer
    │   └── notifications_screen.dart
    │
    ├── receiver/
    │   ├── receiver_screen.dart               ⭐ Owns SessionManager, delegates kill-switch, FLAG_SECURE listener
    │   ├── receiver_transfer_screen.dart      ⭐ Now takes SessionManager via constructor (gap resolved)
    │   ├── decrypt_screen.dart                Save & Suicide pattern (_Phase.done, clean-room decrypt)
    │   └── receiver_end_session_screen.dart
    │
    ├── sender/
    │   ├── sender_screen.dart                 ⭐ TransferService.resolve, plaintext register+wipe+unregister
    │   ├── transfer_progress_screen.dart      ⭐ Non-repudiation + reactive cleanup sync listener
    │   └── sender_session_ended_screen.dart
    │
    ├── admin/
    │   ├── admin_dashboard.dart
    │   ├── admin_dashboard_screen.dart
    │   └── widgets/
    │       ├── connection_node_map.dart       Real-time active node viz
    │       ├── security_pulse_feed.dart       transfer_logs live stream
    │       ├── transfer_volume_chart.dart
    │       └── user_management_list.dart      isAdmin toggle, account state
    │
    ├── vault/
    │   └── rsa_key_manager_screen.dart        Manual key inspection / regen
    │
    ├── settings/
    │   └── settings_screen.dart
    │
    └── widgets/
        └── shared_widgets.dart                ⭐ CrypButton (3D glass, sessionState-aware), other atoms
```

⭐ = touched repeatedly by recent commits; review first when investigating any session/transfer/security issue.

---

## 3. `android/` — Android Build + Native Bridge

```
android/
├── key.properties                 ⚠ git-ignored; storeFile / storePassword / keyAlias / keyPassword
├── settings.gradle.kts            Module include + plugin management
├── build.gradle.kts               Project-level: repositories
├── gradle.properties
├── gradle/wrapper/
└── app/
    ├── build.gradle.kts           App-level: SDK versions, applicationId, R8, signing
    │                              ⚠ applicationId = "com.example.cryptransfer" (line 43) — must change before Play release
    ├── proguard-rules.pro         R8 keep rules for Flutter / Firebase / PointyCastle
    ├── google-services.json       Firebase project: cryptransfer-96e9f
    └── src/
        ├── main/
        │   ├── AndroidManifest.xml
        │   ├── kotlin/com/example/cryptransfer/
        │   │   └── MainActivity.kt
        │   │     • onCreate → window.addFlags(FLAG_SECURE)
        │   │     • configureFlutterEngine → MethodChannel com.example.cryptransfer/security
        │   │       - isFlagSecureActive → (flags & FLAG_SECURE) != 0
        │   │       - clearSession → System.gc()
        │   └── res/                Launcher icons (mipmap-*), themes, drawables
        ├── debug/AndroidManifest.xml
        └── profile/AndroidManifest.xml
```

**Security hardening files (all DONE):**
- `MainActivity.onCreate` → `FLAG_SECURE`
- `build.gradle.kts` → `isMinifyEnabled = true`, `isShrinkResources = true`, `proguard-android-optimize.txt` + `proguard-rules.pro`
- Release signing reads `android/key.properties`; falls back to debug signing if absent (so `flutter run --release` works on dev machines without secrets)

---

## 4. `test/` — Tests

```
test/
├── mocks/
│   └── mock_firebase.dart                 fake_cloud_firestore / firebase_auth_mocks bootstrap
│
├── module_tests/
│   ├── auth_test.dart                     Auth flow (login/register/logout)
│   ├── encryption_test.dart               AES-256-GCM + RSA-2048 (TC011–TC021)
│   ├── session_test.dart                  SessionManager state machine
│   └── transfer_test.dart                 TransferRepository lifecycle
│
├── security/
│   ├── session_wipe_test.dart             TC-WIPE-001..006 — kill-switch + remanence
│   ├── session_termination_test.dart      Lifecycle-driven termination
│   ├── mem_safety_test.dart               Buffer registration / wipeAll
│   └── key_storage_audit_test.dart        FlutterSecureStorage delete semantics
│
├── handshake/
│   ├── handshake_repository_test.dart     Proposal + accept + disconnect
│   ├── receiver_prefill_test.dart         Role picker prefill flow (Phase fix 05-07)
│   └── sender_prefill_test.dart
│
├── role_assignment/
│   └── role_conflict_test.dart
│
├── sender/
│   └── transfer_progress_timeout_test.dart    300s safety timeout
│
└── vault/
    ├── key_lifecycle_test.dart
    ├── profile_init_test.dart
    ├── receiver_banner_test.dart
    └── vault_gate_test.dart
```

---

## 5. `scripts/` — Automation

```
scripts/
├── silent_guardian.ps1            Headless scanner (CLAUDE.md scanner rules → lib/ → Obsidian audit)
├── launch_guardian.bat            Hidden-window launcher for Task Scheduler
├── update_status.ps1              flutter analyze + CLAUDE.md sync (Open Issues ↔ Completed)
├── security_audit_report.dart     Generates structured security audit Markdown
└── write_obsidian_report.dart     Daily summary report writer
```

Outputs:
- `C:\Users\navve\ObsidianVault\CrypTransfer\DailyReports\`
- `C:\Users\navve\ObsidianVault\CrypTransfer\Security\`
- Error log: `C:\Users\navve\projects\cryptransfer\report_error.log`

---

## 6. `design-system/cryptransfer/` — UI Source of Truth

```
design-system/cryptransfer/
├── MASTER.md                  Global rules: colors, typography, spacing, effects, anti-patterns
├── UI-AUDIT-REPORT.md         10 UI inconsistencies with severity + fixes
├── UI-CONSISTENCY-MAP.md      Before/after visual mappings for all components
├── QUICK-FIX-GUIDE.md         Phase 2 secondary fixes (7–9 hrs remaining)
└── pages/                     Page-specific overrides (when present)
```

Rule order when building UI:
1. Check `design-system/cryptransfer/pages/[page-name].md` if it exists.
2. Otherwise follow `MASTER.md`.

---

## 7. `graphify-out/` — Knowledge Graph

```
graphify-out/
├── graph.json                                  Full knowledge graph (queryable via /graphify)
├── ZERO_REMANENCE_ANALYSIS.md                  Source of the compute() ciphertext limitation note
├── Agent Changelog.md
├── AES-256-GCM Encryption.md
├── Audit Log Document Schema (transfers_log{docId}).md
└── … many more derived/summary .md files
```

Rebuild after code changes: `/graphify . --update`.

---

## 8. `.planning/` — GSD State

```
.planning/
├── STATE.md                   Current phase/milestone (modified)
└── codebase/                  ← this map (mapped 2026-05-28)
    ├── STACK.md
    ├── ARCHITECTURE.md
    ├── STRUCTURE.md           ← you are here
    ├── CONVENTIONS.md
    ├── TESTING.md
    ├── INTEGRATIONS.md
    └── CONCERNS.md
```

---

## 9. Naming Conventions

| Element | Convention | Example |
|---------|------------|---------|
| Dart files | `snake_case.dart` | `transfer_progress_screen.dart` |
| Classes | `PascalCase` | `SessionManager`, `CrypButton` |
| Public members | `lowerCamelCase` | `selectSenderHandshake` |
| Private members | `_lowerCamelCase` | `_onToggleReady`, `_handshakeSub` |
| Constants | `lowerCamelCase` with `k` prefix for top-level | `kChunkSize` |
| Firestore collections | `snake_case` | `transfer_logs`, `neutral_handshakes` |
| Firestore fields | `lowerCamelCase` | `selectedSenderUid`, `isReadyToReceive`, `cleanup_initiated` (one exception, deliberate boolean signal) |
| Test files | `<feature>_test.dart` in matching subdirectory | `test/security/session_wipe_test.dart` |
| MethodChannel namespace | reverse-DNS | `com.example.cryptransfer/security` ⚠ couples to applicationId |

---

## 10. Key Locations Cheat Sheet

| Need to … | Go to |
|-----------|-------|
| Add a Firestore collection name | `lib/core/constants/firebase_constants.dart` |
| Touch session state machine | `lib/core/utils/session_manager.dart` (and `session_state.dart`) |
| Register a new sensitive buffer | mix in `SecurityLifecycleMixin` and call `registerBuffer()` |
| Add a screen with key material | `presentation/<area>/` + mix in `SecurityLifecycleMixin` |
| Change colors or typography | `lib/app_theme.dart` + check `design-system/cryptransfer/MASTER.md` rules |
| Wire a new MethodChannel call | `MainActivity.kt` handler + `SecurityLifecycleMixin` (or a peer) Dart side |
| Add a keep rule for release builds | `android/app/proguard-rules.pro` |
| Add an automated scanner rule | CLAUDE.md "State Scanner Rules" section + extend `scripts/silent_guardian.ps1` |
