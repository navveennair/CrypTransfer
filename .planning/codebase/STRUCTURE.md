# Codebase Structure

**Analysis Date:** 2025-04-19

## Directory Layout

```
cryptransfer/
├── lib/
│   ├── main.dart                          # App entry point
│   ├── app_theme.dart                     # Material 3 theme configuration
│   ├── firebase_options.dart              # Firebase platform-specific config
│   ├── core/
│   │   ├── constants/
│   │   │   └── firebase_constants.dart    # Firestore/Storage collection names, limits
│   │   ├── errors/
│   │   │   └── app_exceptions.dart        # Typed exception hierarchy
│   │   └── utils/
│   │       ├── biometric_helper.dart      # Face ID/fingerprint integration (bypassed for thesis)
│   │       ├── notification_service.dart  # Push notification handling
│   │       ├── session_manager.dart       # Receiver state machine (open/locked/decrypting/terminated)
│   │       ├── session_state.dart         # SessionState enum (extracted to prevent circular imports)
│   │       └── security_lifecycle_mixin.dart  # Buffer register/wipe on widget lifecycle
│   ├── data/
│   │   ├── models/
│   │   │   ├── transfer_model.dart        # Transfer document mapping
│   │   │   ├── user_model.dart            # User document mapping
│   │   │   └── notification_model.dart    # Notification document mapping
│   │   ├── repositories/
│   │   │   ├── auth_repository.dart       # Firebase Auth + key pair checking
│   │   │   ├── key_repository.dart        # User search, friend requests, RSA handshakes
│   │   │   └── transfer_repository.dart   # File upload, transfer metadata, notifications
│   │   └── services/
│   │       ├── encryption_service.dart    # RSA/AES crypto facade, session lifecycle hooks
│   │       ├── transfer_log_service.dart  # Firestore audit logging
│   │       └── transfer_service.dart      # 64 KB chunked file I/O
│   └── presentation/
│       ├── admin/
│       │   └── admin_dashboard_screen.dart
│       ├── auth/
│       │   ├── login_screen.dart
│       │   ├── register_screen.dart
│       │   └── splash_screen.dart         # Auth state check on app startup
│       ├── home/
│       │   ├── home_screen.dart           # Main tab navigation
│       │   ├── find_friends_screen.dart   # User search + friend requests
│       │   ├── notifications_screen.dart  # Notification inbox
│       │   └── sidebar_drawer.dart
│       ├── receiver/
│       │   ├── receiver_screen.dart       # Mailbox opening (RSA generation, sender selection)
│       │   ├── receiver_transfer_screen.dart  # Container for decrypt flow
│       │   ├── decrypt_screen.dart        # Decryption + save (Save & Suicide pattern)
│       │   └── download_confirm_screen.dart
│       ├── sender/
│       │   ├── sender_screen.dart         # File picking, encryption, receiver authorization
│       │   └── transfer_progress_screen.dart  # Non-repudiation listener
│       ├── session/
│       │   └── end_session_screen.dart    # Session cleanup + home navigation
│       └── widgets/
│           └── shared_widgets.dart        # CrypButton, StepCard, StatusBanner, UserAvatar
├── android/
│   ├── app/
│   │   ├── build.gradle.kts               # R8 minification, release signing config
│   │   ├── proguard-rules.pro             # Keep rules for crypto + Firebase
│   │   └── src/main/kotlin/com/example/cryptransfer/
│   │       └── MainActivity.kt            # FLAG_SECURE + MethodChannel security bridge
│   ├── build.gradle.kts
│   └── settings.gradle.kts
├── test/
│   ├── mocks/
│   │   └── mock_firebase.dart
│   ├── module_tests/
│   │   ├── auth_test.dart
│   │   ├── encryption_test.dart           # TC011–TC021 AES-GCM + RSA tests
│   │   ├── session_test.dart
│   │   └── transfer_test.dart
│   └── security/
│       ├── key_storage_audit_test.dart
│       └── session_wipe_test.dart         # TC-WIPE-001 to TC-WIPE-006
├── scripts/
│   ├── silent_guardian.ps1               # Security scanner → Obsidian vault
│   ├── update_status.ps1                 # flutter analyze → CLAUDE.md sync
│   ├── security_audit_report.dart
│   ├── write_obsidian_report.dart
│   └── launch_guardian.bat
├── pubspec.yaml
├── analysis_options.yaml
└── CLAUDE.md                              # Project instructions, architecture notes
```

## Naming Conventions

**Files:**
- Screens: `*_screen.dart` (e.g., `sender_screen.dart`)
- Services: `*_service.dart` (e.g., `encryption_service.dart`)
- Repositories: `*_repository.dart` (e.g., `transfer_repository.dart`)
- Models: `*_model.dart` (e.g., `transfer_model.dart`)
- Mixins: `*_mixin.dart` (e.g., `security_lifecycle_mixin.dart`)

**Dart Identifiers:**
- Classes: PascalCase (`SessionManager`, `TransferRepository`)
- Functions/methods: camelCase (`registerBuffer()`, `closeReceiverSession()`)
- Constants: UPPER_SNAKE_CASE or `kCamelCase` (`kChunkSize`, `FirebaseConstants.users`)
- Enum values: lowercase (`SessionState.open`, `SessionState.terminated`)

## Key File Locations

| Purpose | File |
|---------|------|
| App entry | `lib/main.dart` |
| Auth check | `lib/presentation/auth/splash_screen.dart` |
| Receiver mailbox | `lib/presentation/receiver/receiver_screen.dart` |
| Sender transfer | `lib/presentation/sender/sender_screen.dart` |
| Crypto engine | `lib/data/services/encryption_service.dart` |
| Session state machine | `lib/core/utils/session_manager.dart` |
| Chunked file I/O | `lib/data/services/transfer_service.dart` |
| RSA handshakes | `lib/data/repositories/key_repository.dart` |
| Firestore names | `lib/core/constants/firebase_constants.dart` |
| Material 3 theme | `lib/app_theme.dart` |
| Android security | `android/app/src/main/kotlin/com/example/cryptransfer/MainActivity.kt` |
| Signing config | `android/app/build.gradle.kts` |
| Kill-switch tests | `test/security/session_wipe_test.dart` |

## Where to Add New Code

**New transfer feature:**
- Repository: `lib/data/repositories/transfer_repository.dart`
- Service (if I/O): `lib/data/services/transfer_service.dart`
- UI: `lib/presentation/sender/` or `lib/presentation/receiver/`
- Constants: `lib/core/constants/firebase_constants.dart`

**New reusable widget:**
- `lib/presentation/widgets/shared_widgets.dart`

**New screen:**
- Create `lib/presentation/{feature}/{name}_screen.dart`
- Apply `SecurityLifecycleMixin` if it handles sensitive data

**New Kotlin feature:**
- `android/app/src/main/kotlin/com/example/cryptransfer/MainActivity.kt`

**Special directories:**
- `android/key.properties` — git-ignored, manual setup for release signing
- `graphify-out/` — generated knowledge graph, committed for offline queries
- `.planning/` — GSD planning artifacts, not app code

---

*Structure analysis: 2025-04-19*
