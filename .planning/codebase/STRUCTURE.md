# Directory Structure
_Last updated: 2026-06-15_

## Top-Level Layout

```
cryptransfer/
├── lib/                    # All Dart source code
│   ├── main.dart           # App entry point
│   ├── app_theme.dart      # Global Material 3 theme + glass palette
│   ├── firebase_options.dart # Generated Firebase config (platform-specific)
│   ├── core/               # Cross-cutting utilities — no business logic
│   ├── data/               # Repositories, services, models
│   ├── presentation/       # Screens and widgets
│   └── services/           # One-off infrastructure services (Firestore migration)
├── test/                   # Dart unit tests
├── android/                # Android native project
│   ├── app/
│   │   ├── build.gradle.kts        # SDK versions, R8, signing config
│   │   ├── proguard-rules.pro      # Keep rules for Flutter/Firebase/PointyCastle
│   │   └── src/main/kotlin/com/example/cryptransfer/
│   │       └── MainActivity.kt     # FLAG_SECURE + security MethodChannel
│   └── key.properties      # git-ignored; release signing credentials
├── ios/                    # iOS native project
├── assets/                 # Static assets (images, fonts)
├── design-system/          # UI/UX documentation and audit reports
│   └── cryptransfer/
│       ├── MASTER.md               # Global design rules (colors, typography, spacing)
│       ├── UI-AUDIT-REPORT.md      # 10 UI inconsistencies with severity
│       ├── UI-CONSISTENCY-MAP.md   # Before/after component mappings
│       └── QUICK-FIX-GUIDE.md      # Phase 2 secondary fixes
├── firestore.rules         # Firestore security rules
├── firestore.indexes.json  # Firestore composite index definitions
├── firebase.json           # Firebase project config
├── pubspec.yaml            # Flutter package manifest
├── analysis_options.yaml   # Dart linter config
├── scripts/                # PowerShell/Dart automation scripts
│   ├── silent_guardian.ps1         # Headless security scanner
│   ├── update_status.ps1           # Syncs CLAUDE.md status markers
│   ├── security_audit_report.dart  # Generates Obsidian security reports
│   └── launch_guardian.bat         # Windows Task Scheduler launcher
├── .planning/              # GSD planning artifacts (not shipped)
│   ├── codebase/           # Codebase map documents (this file's directory)
│   ├── phases/             # Per-phase implementation plans
│   ├── debug/              # Bug investigation notes
│   └── uat/                # UAT checklists
└── graphify-out/           # Knowledge graph outputs
    ├── graph.json          # Full codebase relationship graph
    └── GRAPH_REPORT.md     # Human-readable graph summary
```

---

## Key Directories

### `lib/core/`
Cross-cutting utilities. No imports from `lib/data/` or `lib/presentation/`. Safe to import from anywhere.

```
lib/core/
├── constants/
│   └── firebase_constants.dart   # All Firestore collection names, Storage paths, secure-storage keys
├── errors/
│   └── app_exceptions.dart       # AppException hierarchy (Auth/Transfer/Crypto/Network/KeyNotFound/RoleConflict)
└── utils/
    ├── session_state.dart         # SessionState enum (standalone — prevents circular import)
    ├── session_manager.dart       # Kill-switch state machine; owns stateNotifier + stateStream
    ├── security_lifecycle_mixin.dart  # Uint8List buffer registry; Kotlin FLAG_SECURE MethodChannel
    ├── biometric_helper.dart      # local_auth 3.0.1 Face ID / fingerprint wrapper
    ├── theme_service.dart         # ChangeNotifier for ThemeMode persistence
    ├── notification_service.dart  # Firestore notification stream helpers
    ├── transfer_status_utils.dart # Display-name mapping for transfer status strings
    ├── file_utils.dart            # File extension / MIME helpers
    └── tofu_service.dart          # Trust-On-First-Use public key verification
```

### `lib/data/`
All Firebase I/O, cryptographic operations, and domain models. Never imports from `lib/presentation/`.

```
lib/data/
├── models/
│   ├── user_model.dart        # UserModel (uid, username, email, publicKey, isAdmin, ...)
│   ├── transfer_model.dart    # TransferModel (encryptedAESKey, iv, status, receiverStatus, ...)
│   └── notification_model.dart # NotificationModel + NotificationType enum
├── repositories/
│   ├── auth_repository.dart       # Firebase Auth + RSA keygen on register
│   ├── key_repository.dart        # RSA sharing, friendships, selectSenderHandshake WriteBatch
│   ├── transfer_repository.dart   # Upload, audit logs, synchronized cleanup protocol
│   ├── handshake_repository.dart  # Neutral connection proposals (neutral_handshakes)
│   ├── user_repository.dart       # User profile reads
│   ├── admin_repository.dart      # Admin-only Firestore queries
│   └── cleanup_repository.dart    # End-of-session cleanup operations
└── services/
    ├── encryption_service.dart    # RSA-2048, AES-256-GCM via compute(); session lifecycle
    └── transfer_service.dart      # 64 KB chunked file reads (kChunkSize = 65536)
```

### `lib/presentation/`
All Flutter screens and widgets. Organized by feature module.

```
lib/presentation/
├── auth/
│   ├── splash_screen.dart         # Auth check + startup session wipe
│   ├── login_screen.dart          # Email/password + Google sign-in
│   ├── register_screen.dart       # Registration + RSA keypair generation
│   └── onboarding_screen.dart     # First-time user onboarding
├── home/
│   ├── home_screen.dart           # Dashboard: active connections, recent transfers, role picker
│   ├── find_friends_screen.dart   # User search + connection management + _SearchResultTile (reactive per-tile status)
│   ├── notifications_screen.dart  # Notification inbox
│   ├── sidebar_drawer.dart        # Navigation drawer
│   └── transfer_summary_screen.dart # Full audit log history
├── sender/
│   ├── sender_screen.dart         # File selection, encryption, receiver selection (stepper UI)
│   ├── sender_transfer_screen.dart # Upload progress display
│   └── sender_session_end_screen.dart # Post-transfer session end confirmation
├── receiver/
│   ├── receiver_screen.dart       # Mailbox open/close, sender selection, transfer stream (stepper UI)
│   ├── receiver_transfer_screen.dart # Transfer arrival handler
│   ├── decrypt_screen.dart        # RSA-OAEP AES key decrypt + AES-GCM file decrypt + Save & Suicide
│   └── receiver_end_session_screen.dart # Post-decrypt session cleanup
├── settings/
│   └── settings_screen.dart       # Theme toggle, account settings
├── vault/
│   └── rsa_key_manager_screen.dart # RSA key lifecycle (generate, view, delete) with biometric gate
├── admin/
│   ├── admin_dashboard.dart       # Terminal-themed admin panel
│   ├── admin_guard.dart           # Route guard checking isAdmin Firestore field
│   └── widgets/
│       ├── connection_node_map.dart     # Real-time active transfer node visualization
│       ├── security_pulse_feed.dart     # Live security audit log feed
│       ├── transfer_volume_chart.dart   # fl_chart transfer volume graph
│       └── user_management_list.dart    # User privilege management (isAdmin toggle)
└── widgets/
    └── shared_widgets.dart        # GlassContainer, GlassButton, CrypButton (session-state-aware 3D button)
```

### `test/`
Dart unit tests organized by concern.

```
test/
├── mocks/
│   └── mock_firebase.dart         # Fake Firebase instances for unit tests
├── module_tests/                  # Core module unit tests
│   ├── auth_test.dart
│   ├── encryption_test.dart
│   ├── session_test.dart
│   └── transfer_test.dart
├── security/                      # Security-specific test cases
│   ├── session_wipe_test.dart     # TC-WIPE-001 through TC-WIPE-006
│   ├── session_termination_test.dart
│   ├── key_storage_audit_test.dart
│   ├── mem_safety_test.dart
│   └── navigation_guard_test.dart
├── handshake/                     # Handshake protocol tests
│   ├── handshake_repository_test.dart
│   ├── receiver_prefill_test.dart
│   └── sender_prefill_test.dart
├── vault/                         # RSA vault tests
│   ├── key_lifecycle_test.dart
│   ├── profile_init_test.dart
│   ├── receiver_banner_test.dart
│   └── vault_gate_test.dart
├── admin/                         # Admin dashboard tests
│   ├── admin_guard_test.dart
│   ├── admin_repository_test.dart
│   └── chart_aggregation_test.dart
├── sender/                        # Sender-flow tests
│   ├── stale_key_test.dart
│   └── transfer_progress_timeout_test.dart
└── role_assignment/
    └── role_conflict_test.dart
```

---

## Key Files

| File | Purpose |
|------|---------|
| `lib/main.dart` | App entry point: Firebase init, Firestore migration, ThemeService provider, route table |
| `lib/app_theme.dart` | Material 3 theme: gold primary, purple accent, navy dark background, glassmorphic constants |
| `lib/firebase_options.dart` | Auto-generated Firebase platform config (do not edit manually) |
| `lib/core/constants/firebase_constants.dart` | All Firestore collection names and Storage paths — single source of truth |
| `lib/core/errors/app_exceptions.dart` | Typed exception hierarchy — all repo/service throws use these |
| `lib/core/utils/session_state.dart` | `SessionState` enum — import this, not `session_manager.dart`, to avoid circular deps |
| `lib/core/utils/session_manager.dart` | Kill-switch state machine per receiver session |
| `lib/core/utils/security_lifecycle_mixin.dart` | `Uint8List` buffer wipe + Kotlin `FLAG_SECURE` MethodChannel bridge |
| `lib/data/services/encryption_service.dart` | RSA-2048 + AES-256-GCM via `compute()`; `closeReceiverSession()` 7-step kill switch |
| `lib/data/services/transfer_service.dart` | 64 KB chunked file I/O (`kChunkSize = 65536`) |
| `lib/data/repositories/key_repository.dart` | `selectSenderHandshake()` atomic WriteBatch; `streamHandshakesForSender()` reactive stream |
| `lib/data/repositories/transfer_repository.dart` | `uploadAndCreate()`, audit logs, synchronized cleanup protocol turns |
| `lib/data/repositories/handshake_repository.dart` | Neutral connection proposals (`neutral_handshakes` collection) |
| `lib/presentation/receiver/receiver_screen.dart` | Owns `SessionManager`; wires `bindSession`/`unbindSession`; stable `_transferStream` field |
| `lib/presentation/sender/sender_screen.dart` | `_handshakeSub` stream; `registerBuffer`/`unregisterBuffer` plaintext wipe; `isFlagSecureActive()` pre-flight |
| `lib/presentation/receiver/decrypt_screen.dart` | RSA-OAEP + AES-GCM decrypt in isolates; Save & Suicide pattern |
| `lib/presentation/widgets/shared_widgets.dart` | `GlassContainer`, `CrypButton` (session-state-aware), `GlassButton` |
| `lib/services/firestore_migration.dart` | Startup idempotent collection initialization |
| `android/app/src/main/kotlin/.../MainActivity.kt` | `FLAG_SECURE` in `onCreate()`; `isFlagSecureActive` and `clearSession` MethodChannel handlers |
| `android/app/build.gradle.kts` | R8 minification, release signing from `key.properties` |
| `android/app/proguard-rules.pro` | Keep rules for Flutter engine, Firebase SDK, PointyCastle |
| `firestore.rules` | Firestore security rules governing all collection access |
| `pubspec.yaml` | Package manifest: Flutter >=3.44.0, Dart SDK ^3.12.0 |

---

## Naming Conventions

### Files
- **Dart source files:** `snake_case.dart` — always (e.g., `receiver_screen.dart`, `encryption_service.dart`)
- **Test files:** mirror source structure, suffix `_test.dart` (e.g., `session_wipe_test.dart`)
- **Constants files:** descriptive noun + `_constants.dart` (e.g., `firebase_constants.dart`)

### Classes
- **Widgets / Screens:** `PascalCase` + `Screen` suffix for full screens (e.g., `ReceiverScreen`, `SenderScreen`)
- **Widget helpers:** `PascalCase` + `Widget` or descriptive noun (e.g., `GlassContainer`, `CrypButton`)
- **Repositories:** `PascalCase` + `Repository` (e.g., `KeyRepository`, `TransferRepository`)
- **Services:** `PascalCase` + `Service` (e.g., `EncryptionService`, `TransferService`)
- **Models:** `PascalCase` + `Model` (e.g., `UserModel`, `TransferModel`)
- **Exceptions:** `PascalCase` + `Exception` (e.g., `CryptoException`, `NetworkException`)
- **Private state classes:** `_PascalCaseState` (e.g., `_ReceiverScreenState`)

### Functions / Methods
- **Public methods:** `lowerCamelCase` (e.g., `sendPublicKey()`, `closeReceiverSession()`)
- **Private methods:** `_lowerCamelCase` (e.g., `_onToggleReady()`, `_encryptFile()`)
- **Top-level isolate helpers:** `lowerCamelCase` describing function (e.g., `_generateRsaKeyPairIsolate`, `runAesGcmEncrypt`) — must be top-level (not closures or instance methods) for `compute()`

### Variables
- **Private state fields:** `_lowerCamelCase` with type prefix for booleans (e.g., `_isReadyToReceive`, `_encrypting`)
- **Stream subscriptions:** `_nounSub` (e.g., `_handshakeSub`, `_friendsSub`, `_transferStream`)
- **Constants:** `lowerCamelCase` for class constants (e.g., `kChunkSize`), `ALL_CAPS` avoided

### Enums
- **Type:** `PascalCase` (e.g., `SessionState`, `NotificationType`)
- **Values:** `lowerCamelCase` (e.g., `SessionState.open`, `SessionState.terminated`)

---

## Module Boundaries

### What `core/` owns
- No Firebase imports in `constants/` or `errors/`
- `session_manager.dart` and `security_lifecycle_mixin.dart` may import `session_state.dart` and Flutter framework packages
- `security_lifecycle_mixin.dart` imports `package:flutter/services.dart` for MethodChannel only

### What `data/` owns
- All Firebase SDK usage (Firestore, Storage, Auth, SecureStorage)
- All PointyCastle crypto operations
- Never imports from `lib/presentation/`

### What `presentation/` owns
- All Flutter widget code
- May import freely from `lib/core/` and `lib/data/`
- Instantiates repositories and services directly (no DI container)
- Screens using crypto buffers MUST mix in `SecurityLifecycleMixin`

### What `services/` (root) owns
- One-off infrastructure concerns that span the data/presentation boundary
- Currently: `firestore_migration.dart` (startup collection verification)

---

## Where to Add New Code

**New screen:**
- Implementation: `lib/presentation/{feature}/new_screen.dart`
- If it handles crypto buffers: add `with SecurityLifecycleMixin<NewScreen>` to `State`

**New repository:**
- Implementation: `lib/data/repositories/new_repository.dart`
- Pattern: constructor-inject Firebase singletons with default values; throw typed `AppException` subclasses; wrap `FirebaseException` in `NetworkException`

**New Firestore collection:**
- Add constant to `lib/core/constants/firebase_constants.dart`
- Add security rules to `firestore.rules`
- Add composite indexes to `firestore.indexes.json` if queries need them

**New typed exception:**
- Add to `lib/core/errors/app_exceptions.dart` extending `AppException`

**New shared widget:**
- Add to `lib/presentation/widgets/shared_widgets.dart` (for global primitives)
- Or create `lib/presentation/{feature}/widgets/` for feature-scoped widgets

**New test:**
- Place in `test/{concern}/{name}_test.dart`
- Use fakes from `test/mocks/mock_firebase.dart`
- Follow existing pattern: group by method, use descriptive test names

**New Firestore constant (collection / field / key):**
- Always add to `lib/core/constants/firebase_constants.dart` — never hardcode collection strings in screens or repositories
