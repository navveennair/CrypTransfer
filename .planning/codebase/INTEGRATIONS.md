# External Integrations

**Analysis Date:** 2026-04-19

## APIs & External Services

**Firebase Services:**
- Firebase Authentication - Email/password user signup and login
  - SDK: firebase_auth 6.3.0
  - Flow: `lib/data/repositories/auth_repository.dart` → `register()`, `loginWithUsername()`
  - Config: `lib/firebase_options.dart` (platform-specific API keys)

- Firebase Cloud Messaging (planned but not integrated) - Notification delivery
  - Stub: Not in current pubspec.yaml
  - Alternative: Custom polling via Firestore `notifications` collection

## Data Storage

**Databases:**

- **Cloud Firestore** (Primary document database)
  - Client: cloud_firestore 6.2.0
  - Connection: Auto-initialized via `Firebase.initializeApp()` in `lib/main.dart`
  - Collections managed in `lib/core/constants/firebase_constants.dart`:
    - `users` - User profiles (username, email, phone, publicKey, isReadyToReceive, selectedSenderUid)
    - `transfers` - Active transfer metadata (senderId, receiverId, transferDate, fileHash, status, participants)
    - `transfer_logs` / `transferLogs` - Audit trail (loggedAt, transferDate, participants, fileHash)
    - `notifications` - In-app alerts (type: rsa_key_received, fromUserId, toUserId, read)
    - `rsa_key_transfers` - Hybrid crypto handshake signaling (fromUserId, toUserId, publicKey, status: handshake_complete)
    - `friends` - Friend request tracking (requesterUid, receiverUid, status)
  - Usage: `lib/data/repositories/` and `lib/presentation/` screens directly instantiate `FirebaseFirestore.instance`
  - Batch operations: Used in kill-switch cleanup (`EncryptionService.closeReceiverSession()`)

**File Storage:**

- **Firebase Cloud Storage** (Encrypted file archive)
  - Client: firebase_storage 13.2.0
  - Path prefix: `transfers/{senderUid}/{transferUid}/encrypted_file`
  - Max upload: 100 MB (enforced in `lib/core/constants/firebase_constants.dart` maxDownloadBytes)
  - Flow: `lib/presentation/sender/sender_screen.dart` → `SenderScreen._encryptFile()` uploads encrypted Uint8List to Storage
  - Cleanup: `lib/presentation/session/end_session_screen.dart` → `_endSession()` deletes Storage file on session close

**Local Storage:**

- **FlutterSecureStorage** - Device keystore for RSA private keys
  - Client: flutter_secure_storage 10.0.0
  - Keys: `lib/core/constants/firebase_constants.dart`:
    - `rsa_private_key` - User's RSA-2048 private key (stored encrypted)
    - `rsa_public_key_{uid}` - Cached peer public keys
  - Usage: `lib/data/services/encryption_service.dart` → `generateAndStoreKeyPair()`, `loadPrivateKey()`, `decryptMessage()`
  - Wipe: On receiver kill-switch (`closeReceiverSession()` deletes private key)

**Caching:**

- None (in-memory only via Dart isolates and compute())

## Authentication & Identity

**Auth Provider:**

- **Firebase Authentication (Email/Password)**
  - Implementation: `lib/data/repositories/auth_repository.dart`
  - Sign-up: `register()` creates `FirebaseAuth` user + Firestore `users` doc with username uniqueness check
  - Login: `loginWithUsername()` queries `users` collection by username, then authenticates via email
  - State: `authStateChanges()` stream consumed by `SplashScreen` to determine logged-in state
  - Tokens: Firebase ID tokens (managed by Firebase SDK internally)

**Biometric Authentication (Bypassed):**

- **local_auth 3.0.1** - Fingerprint, face, iris, PIN/pattern fallback
  - Status: Currently stubbed/disabled (see `lib/core/utils/biometric_helper.dart`)
  - Methods: `checkBiometrics()`, `authenticate(reason)` return hardcoded `true`
  - Roadmap: Re-enable before viva (see CLAUDE.md "Pre-Viva" section)

## Monitoring & Observability

**Error Tracking:**

- None (in-app exception handling only)
- Manual error logging via Firestore `transfer_logs` collection (non-repudiation audit trail)

**Logs:**

- **Audit Trail via Firestore** - Transfer and session events logged to `transfer_logs` collection
  - Service: `lib/data/services/transfer_log_service.dart` → `writeAuditLog()`
  - Events tracked:
    - `encryption_initiated` - Sender begins encryption
    - `encryption_completed` - Ciphertext uploaded to Storage
    - `handshake_complete` - Receiver authorized sender (RSA key exchange)
    - `decryption_initiated` - Receiver starts decryption
    - `decryption_completed` - Plaintext saved to device
    - `session_closed` - Kill-switch wipe executed
  - Consumer: `AdminDashboardScreen` aggregates logs for analytics

- **Console Logging** - Stdlib `print()` and `debugPrint()` during development (disabled in production via R8 minification)

## CI/CD & Deployment

**Hosting:**

- **Google Play Store** (Target, not yet live)
  - Build: Android AAB (Android App Bundle) via Gradle
  - Signing: `android/key.properties` (git-ignored) reads keyAlias, keyPassword, storeFile, storePassword
  - Minification: R8 enabled (release builds) with Proguard rules in `android/app/proguard-rules.pro`

**Local Build Chain:**

- Flutter CLI: `flutter build apk --release` / `flutter build appbundle --release`
- Gradle: `android/app/build.gradle.kts` orchestrates compilation, minification, signing
- Signing config: Falls back to debug signing if `key.properties` absent (dev machines)

**CI Pipeline:**

- None detected (no GitHub Actions, Firebase CI, or cloud build config)
- Manual: Local builds via Flutter CLI

## Environment Configuration

**Required env vars:**

- None (Firebase config baked into `lib/firebase_options.dart` and `android/app/google-services.json`)
- Optional: `KEY_STORE_PASSWORD`, `KEY_ALIAS_PASSWORD` for Android signing (stored in `android/key.properties`)

**Secrets location:**

- `android/key.properties` (git-ignored) - Android signing credentials
- `.env` files - Not present; all Firebase config is committed (public API keys, project IDs)
- Sensitive keys (RSA private) - Device keystore via FlutterSecureStorage (encrypted at OS level)

## Webhooks & Callbacks

**Incoming:**

- None (app is client-side only; no server-side webhooks)

**Outgoing:**

- None (no external webhook calls; all communication is pull-based via Firestore listeners)

## Security Integration Points

**FLAG_SECURE (Android Native Bridge):**

- Kotlin: `MainActivity.onCreate()` sets `window.addFlags(LayoutParams.FLAG_SECURE)`
  - `android/app/src/main/kotlin/com/example/cryptransfer/MainActivity.kt`
  - Blocks task-switcher screenshots and screen captures at the Android window level
- MethodChannel: `com.example.cryptransfer/security` → `isFlagSecureActive()`
  - Dart: `lib/core/utils/security_lifecycle_mixin.dart` invokes before 64 KB chunk reads
  - Query: Confirms FLAG_SECURE is active before processing sensitive bytes
- Consumer: `lib/presentation/sender/sender_screen.dart` → `_encryptFile()` aborts if FLAG_SECURE inactive

**Cryptography Stack:**

- **PointyCastle 4.0.0** - RSA-2048 key generation and asymmetric encryption
  - Uses Fortuna PRNG for secure randomness
  - AES-256-GCM encryption (via `GCMBlockCipher`) in `compute()` isolates (100% main-isolate plaintext zero-wipe)
  - Flow: Plaintext → `RegisterBuffer()` + `compute(runAesGcmEncrypt)` → Ciphertext + `fillRange(0)` + `UnregisterBuffer()`

- **Secure Storage** - Device keystore for RSA private keys
  - `flutter_secure_storage` encrypts keys at the OS level (Keystore on Android, Keychain on iOS)

---

*Integration audit: 2026-04-19*
