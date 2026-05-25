# Codebase Structure

**Analysis Date:** 2026-05-25

## Directory Layout

```
cryptransfer/
├── lib/
│   ├── main.dart                          # App entry point — Firebase init, MaterialApp root
│   ├── app_theme.dart                     # Material 3 theme (GitHub Dark palette + glassmorphic)
│   ├── firebase_options.dart              # Platform-specific Firebase config (auto-generated)
│   │
│   ├── core/                              # Shared infrastructure (no domain logic)
│   │   ├── constants/
│   │   │   └── firebase_constants.dart    # Firestore collection names, Storage paths, field names
│   │   ├── errors/
│   │   │   └── app_exceptions.dart        # Typed exception hierarchy
│   │   ├── services/
│   │   │   └── auth_method_service.dart   # MethodChannel auth helpers
│   │   └── utils/
│   │       ├── biometric_helper.dart      # Face ID/fingerprint integration
│   │       ├── notification_service.dart  # Push notification handling
│   │       ├── session_manager.dart       # Receiver state machine (open/locked/decrypting/terminated)
│   │       ├── session_state.dart         # SessionState enum (extracted to prevent circular imports)
│   │       ├── security_lifecycle_mixin.dart  # Buffer register/wipe on widget lifecycle
│   │       ├── theme_service.dart         # Theme mode toggle (ChangeNotifier)
│   │       └── tofu_service.dart          # TOFU key pinning (Trust On First Use)
│   │
│   ├── data/                              # Business logic — Firebase abstractions, crypto, I/O
│   │   ├── models/
│   │   │   ├── transfer_model.dart        # Transfer document mapping (pending/received/completed)
│   │   │   ├── user_model.dart            # User document mapping (username, email, isAdmin, publicKey)
│   │   │   └── notification_model.dart    # Notification document mapping
│   │   ├── repositories/
│   │   │   ├── auth_repository.dart       # Firebase Auth + key pair checking
│   │   │   ├── admin_repository.dart      # Admin dashboard queries
│   │   │   ├── handshake_repository.dart  # Neutral handshake (connection proposals)
│   │   │   ├── key_repository.dart        # User search, friend requests, RSA key lifecycle
│   │   │   └── transfer_repository.dart   # File upload, transfer metadata, audit logging
│   │   └── services/
│   │       ├── encryption_service.dart    # RSA/AES crypto facade, session lifecycle hooks
│   │       ├── transfer_log_service.dart  # Firestore audit logging
│   │       └── transfer_service.dart      # 64 KB chunked file I/O (memory-stable reads)
│   │
│   └── presentation/                      # Flutter UI — screens, widgets, navigation
│       ├── admin/
│       │   ├── admin_dashboard.dart
│       │   ├── admin_dashboard_screen.dart
│       │   └── widgets/
│       │       ├── connection_node_map.dart     # Real-time connection visualization
│       │       ├── security_pulse_feed.dart     # Audit event feed
│       │       ├── transfer_volume_chart.dart   # Transfer metrics chart
│       │       └── user_management_list.dart    # Admin user list
│       │
│       ├── auth/
│       │   ├── login_screen.dart          # Firebase email/password login
│       │   ├── register_screen.dart       # Firebase email/password signup
│       │   ├── onboarding_screen.dart     # Post-registration setup
│       │   └── splash_screen.dart         # Auth state check on app startup
│       │
│       ├── home/
│       │   ├── home_screen.dart           # Main tab navigation (Send/Receive/Connections)
│       │   ├── find_friends_screen.dart   # User search + friend requests + reactive status
│       │   ├── notifications_screen.dart  # Notification inbox
│       │   └── sidebar_drawer.dart        # Navigation drawer
│       │
│       ├── receiver/
│       │   ├── receiver_screen.dart       # Mailbox opening (RSA generation, sender selection)
│       │   ├── receiver_transfer_screen.dart  # Container for decrypt flow
│       │   ├── decrypt_screen.dart        # Decryption + Save & Suicide pattern
│       │   ├── receiver_end_session_screen.dart  # Session cleanup flow
│       │   └── download_confirm_screen.dart      # (legacy or internal)
│       │
│       ├── sender/
│       │   ├── sender_screen.dart         # File picking, encryption, receiver authorization
│       │   ├── sender_session_ended_screen.dart  # Post-transfer cleanup screen
│       │   └── transfer_progress_screen.dart  # Non-repudiation listener (receiverStatus tracking)
│       │
│       ├── session/
│       │   └── end_session_screen.dart    # Session cleanup + home navigation
│       │
│       ├── settings/
│       │   └── settings_screen.dart       # User settings (theme, notifications)
│       │
│       ├── vault/
│       │   └── rsa_key_manager_screen.dart  # RSA key management UI
│       │
│       └── widgets/
│           └── shared_widgets.dart        # Reusable components (GlassButton, CrypButton, GlassContainer, StepCard, etc.)
│
├── android/                               # Native Android layer
│   ├── app/
│   │   ├── build.gradle.kts               # R8 minification, release signing config, SDK versions
│   │   ├── proguard-rules.pro             # Keep rules for crypto + Firebase (PointyCastle, Firebase)
│   │   └── src/
│   │       └── main/
│   │           ├── kotlin/com/example/cryptransfer/
│   │           │   └── MainActivity.kt    # FLAG_SECURE + MethodChannel security bridge
│   │           └── AndroidManifest.xml
│   ├── build.gradle.kts                   # Project-level Gradle config
│   └── settings.gradle.kts                # Module declarations + plugin management
│
├── test/                                  # Automated tests
│   ├── mocks/
│   │   └── mock_firebase.dart             # Fake Firestore/Auth for unit tests
│   ├── module_tests/
│   │   ├── auth_test.dart                 # Authentication flow tests
│   │   ├── encryption_test.dart           # AES-GCM + RSA tests (TC011–TC021)
│   │   ├── session_test.dart              # SessionManager state transitions
│   │   └── transfer_test.dart             # Transfer upload/download flow
│   └── security/
│       ├── key_storage_audit_test.dart    # Private key storage verification
│       └── session_wipe_test.dart         # Kill-switch tests (TC-WIPE-001 to TC-WIPE-006)
│
├── scripts/                               # Automation + CI/CD helpers
│   ├── silent_guardian.ps1                # Security scanner — checks CLAUDE.md rules, writes Obsidian vault
│   ├── update_status.ps1                  # flutter analyze sync → CLAUDE.md Completed Features update
│   ├── security_audit_report.dart         # Dart script — generates security audit Markdown
│   ├── write_obsidian_report.dart         # Dart script — writes daily summary report
│   └── launch_guardian.bat                # Windows batch launcher for Task Scheduler
│
├── graphify-out/                          # Knowledge graph (committed, auto-updated)
│   ├── graph.json                         # Semantic knowledge graph of codebase
│   ├── graph.html                         # Interactive graph visualization
│   ├── GRAPH_REPORT.md                    # Graph analysis report
│   ├── manifest.json                      # Graph metadata
│   └── cost.json                          # Graph generation cost
│
├── .planning/                             # GSD orchestrator artifacts (not app code)
│   ├── codebase/                          # Architecture & structure docs (ARCHITECTURE.md, STRUCTURE.md, etc.)
│   ├── phases/                            # Phase implementation plans
│   ├── ROADMAP.md                         # Feature roadmap
│   └── STATE.md                           # Project state snapshot
│
├── pubspec.yaml                           # Dart package manifest + dependencies
├── pubspec.lock                           # Dependency lock file (committed)
├── analysis_options.yaml                  # Linter rules (flutter analyze)
├── CLAUDE.md                              # Project instructions, architecture notes, known issues
└── README.md                              # (if present — project overview)
```

## Directory Purposes

| Directory | Purpose | Key Files |
|-----------|---------|-----------|
| `lib/core/constants/` | Firestore/Storage collection names and field names | `firebase_constants.dart` |
| `lib/core/errors/` | Typed exception hierarchy | `app_exceptions.dart` |
| `lib/core/utils/` | Shared utilities (SessionManager, crypto lifecycle) | `session_manager.dart`, `security_lifecycle_mixin.dart` |
| `lib/data/models/` | Firestore document mappings | `transfer_model.dart`, `user_model.dart` |
| `lib/data/repositories/` | Firebase CRUD abstractions | `key_repository.dart`, `transfer_repository.dart` |
| `lib/data/services/` | Stateless business logic (crypto, file I/O) | `encryption_service.dart`, `transfer_service.dart` |
| `lib/presentation/auth/` | Authentication screens (login, register, splash) | `splash_screen.dart` (entry point) |
| `lib/presentation/home/` | Main navigation + user discovery | `home_screen.dart`, `find_friends_screen.dart` |
| `lib/presentation/receiver/` | Receiver mailbox + decrypt flow | `receiver_screen.dart`, `decrypt_screen.dart` |
| `lib/presentation/sender/` | Sender file encryption + transfer flow | `sender_screen.dart`, `transfer_progress_screen.dart` |
| `lib/presentation/admin/` | Admin dashboard for platform oversight | `admin_dashboard_screen.dart` |
| `lib/presentation/widgets/` | Reusable UI components | `shared_widgets.dart` (GlassButton, CrypButton, etc.) |
| `android/app/` | Android app module build config | `build.gradle.kts`, `MainActivity.kt` |
| `test/` | Automated tests (unit, integration, security) | `session_wipe_test.dart` (kill-switch tests) |
| `scripts/` | DevOps automation (security scanning, reporting) | `silent_guardian.ps1` |
| `graphify-out/` | Knowledge graph (semantic codebase index) | `graph.json` |
| `.planning/` | GSD orchestrator artifacts | `ROADMAP.md`, `phases/` |

## Key File Locations

| Purpose | File |
|---------|------|
| App entry point | `lib/main.dart` |
| Auth state check | `lib/presentation/auth/splash_screen.dart` |
| Receiver mailbox | `lib/presentation/receiver/receiver_screen.dart` |
| Receiver decryption | `lib/presentation/receiver/decrypt_screen.dart` |
| Sender transfer | `lib/presentation/sender/sender_screen.dart` |
| Transfer progress tracking | `lib/presentation/sender/transfer_progress_screen.dart` |
| Crypto engine | `lib/data/services/encryption_service.dart` |
| Session state machine | `lib/core/utils/session_manager.dart` |
| Buffer register/wipe | `lib/core/utils/security_lifecycle_mixin.dart` |
| Chunked file I/O | `lib/data/services/transfer_service.dart` |
| User search + connections | `lib/data/repositories/key_repository.dart` |
| File upload + metadata | `lib/data/repositories/transfer_repository.dart` |
| Firestore collection names | `lib/core/constants/firebase_constants.dart` |
| Exception types | `lib/core/errors/app_exceptions.dart` |
| Material 3 theme | `lib/app_theme.dart` |
| Glassmorphic widgets | `lib/presentation/widgets/shared_widgets.dart` |
| Android security + MethodChannel | `android/app/src/main/kotlin/com/example/cryptransfer/MainActivity.kt` |
| Android signing config | `android/app/build.gradle.kts` |
| Kill-switch tests | `test/security/session_wipe_test.dart` |
| Security scanner | `scripts/silent_guardian.ps1` |
| Project instructions | `CLAUDE.md` |

## Naming Conventions

**Files:**
- Screens: `*_screen.dart` (e.g., `sender_screen.dart`, `decrypt_screen.dart`)
- Services: `*_service.dart` (e.g., `encryption_service.dart`, `transfer_service.dart`)
- Repositories: `*_repository.dart` (e.g., `transfer_repository.dart`, `key_repository.dart`)
- Models: `*_model.dart` (e.g., `transfer_model.dart`, `user_model.dart`)
- Mixins: `*_mixin.dart` (e.g., `security_lifecycle_mixin.dart`)
- Helpers: `*_helper.dart` (e.g., `biometric_helper.dart`)
- Tests: `*_test.dart` (e.g., `session_wipe_test.dart`)

**Dart Identifiers:**
- **Classes**: PascalCase — `SessionManager`, `TransferRepository`, `EncryptionService`, `SecurityLifecycleMixin`
- **Functions/methods**: camelCase — `registerBuffer()`, `closeReceiverSession()`, `resolve()`, `encryptAesGcm()`
- **Constants**: UPPER_SNAKE_CASE or `kCamelCase` — `kChunkSize = 64 * 1024`, `FirebaseConstants.users`, `FirebaseConstants.transfers`
- **Enum values**: lowercase — `SessionState.open`, `SessionState.locked`, `SessionState.decrypting`, `SessionState.terminated`, `TransferStatus.pending`
- **Private fields**: leading underscore — `_radioactiveBuffers`, `_stateStreamController`, `_sessionManager`
- **Private methods**: leading underscore — `_set()`, `_checkKeyStatus()`, `_handleIncomingTransfer()`

**File naming patterns:**

| Type | Pattern | Example |
|------|---------|---------|
| Screen | `{feature}_{feature}_screen.dart` | `sender_screen.dart`, `decrypt_screen.dart` |
| Repository | `{domain}_repository.dart` | `transfer_repository.dart`, `key_repository.dart` |
| Service | `{service}_service.dart` | `encryption_service.dart`, `transfer_service.dart` |
| Model | `{entity}_model.dart` | `transfer_model.dart`, `user_model.dart` |
| Mixin | `{aspect}_mixin.dart` | `security_lifecycle_mixin.dart` |
| Helper | `{purpose}_helper.dart` | `biometric_helper.dart` |
| Constants | `{domain}_constants.dart` | `firebase_constants.dart` |
| Errors | `{type}_exception.dart` or `app_exceptions.dart` | `app_exceptions.dart` (all types in one file) |

## Where to Add New Code

**New Transfer Feature (e.g., file preview, compression):**
- Repository: `lib/data/repositories/transfer_repository.dart` — add method for Firestore operation
- Service (if I/O): `lib/data/services/transfer_service.dart` — add method for file handling
- UI: `lib/presentation/sender/` or `lib/presentation/receiver/` — new screen or widget
- Constants: `lib/core/constants/firebase_constants.dart` — add collection name or field name if needed
- Tests: `test/module_tests/transfer_test.dart` — add test case

**New Reusable Widget:**
- Add to `lib/presentation/widgets/shared_widgets.dart` — keep shared components together
- Use consistent styling from `AppTheme` (GlassContainer, glassmorphic colors)
- Export from a barrel file if widget becomes complex

**New Screen:**
- Create `lib/presentation/{feature}/{name}_screen.dart`
- Apply `SecurityLifecycleMixin<{ScreenName}>` mixin if handling sensitive data (plaintext, keys)
- Register route in `HomeScreen` or navigation drawer if user-accessible
- Call `registerBuffer()` on any sensitive `Uint8List` created in `initState`

**New Kotlin/Android Feature:**
- Add method to `MainActivity.kt` MethodChannel handler in `configureFlutterEngine()`
- Create new MethodChannel or extend existing `security` or `file` channel
- Add corresponding Dart wrapper in `SecurityLifecycleMixin` or new helper

**New Repository:**
- Create `lib/data/repositories/{domain}_repository.dart`
- Inject `FirebaseFirestore`, `FirebaseAuth`, and/or `FirebaseStorage` via constructor
- Throw typed exceptions (`NetworkException`, `AuthException`) on Firebase errors
- Return Firestore queries as `Stream` for reactive listeners

**New Service:**
- Create `lib/data/services/{service}_service.dart`
- Keep stateless (no instance variables)
- Use static methods for utility functions
- Delegate heavy computation to `compute()` isolates

**New Exception Type:**
- Add to `lib/core/errors/app_exceptions.dart` — extend `AppException`
- Use typed catch blocks in presentation layer for specific recovery

**New Firestore Collection:**
- Add constant to `lib/core/constants/firebase_constants.dart` — naming: `static const String {collection}s = '{collection}s'`
- Document expected fields as comment
- Create corresponding model in `lib/data/models/{entity}_model.dart` with `fromDoc()` factory

## Special Directories

**`android/key.properties`:**
- Purpose: Release signing credentials (git-ignored, never commit)
- Required on production machines; optional on dev machines (falls back to debug signing)
- Format:
  ```
  storeFile=../my-release-key.jks
  storePassword=<password>
  keyAlias=<alias>
  keyPassword=<password>
  ```

**`graphify-out/`:**
- Purpose: Semantic knowledge graph of codebase (committed, auto-updated by `/graphify . --update`)
- Generated by graphify agent; contains AST + LLM semantic analysis
- Useful for `graphify query "<question>"` to find relationships without re-reading code
- Stale after code changes; run `/graphify . --update` to refresh

**`.planning/`:**
- Purpose: GSD orchestrator artifacts (planning, phases, state tracking)
- Not part of app code; ignored at runtime
- Contains ROADMAP.md (feature list), phases/ (implementation plans), codebase/ (ARCHITECTURE.md, etc.)

**`test/`:**
- Purpose: Automated tests (unit, integration, security)
- Run with `flutter test` or `flutter test test/security/session_wipe_test.dart` (specific file)
- Mocks: `test/mocks/mock_firebase.dart` for Firestore/Auth faking

---

*Structure analysis: 2026-05-25*
