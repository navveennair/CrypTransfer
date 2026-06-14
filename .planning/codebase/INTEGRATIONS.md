# External Integrations
_Last updated: 2026-06-15_

## Databases

**Cloud Firestore** (Firebase project: `cryptransfer-96e9f`)

- Client: `cloud_firestore ^6.2.0` — `FirebaseFirestore.instance` (singleton)
- No ORM; all queries are direct Firestore SDK calls
- Connection managed automatically by the SDK; initialized in `lib/main.dart` via `Firebase.initializeApp()`
- Security rules: `firestore.rules` (deployed to `cryptransfer-96e9f`; server-side enforcement)
- Emulator: port `8080` configured in `firebase.json` (UI emulator disabled)

**Collections:**

| Collection | Purpose | Key fields |
|------------|---------|------------|
| `users` | User profiles, public keys, session flags | `publicKey`, `isReadyToReceive`, `selectedSenderUid`, `sessionActive`, `isAdmin` |
| `users/{uid}/notifications` | Per-user inbox (connection requests, key events) | `type`, `toUserId` |
| `users/{uid}/audit_logs` | Immutable per-user transfer history | `senderId`, `receiverId`, `loggedAt` |
| `users/{uid}/rsa_key_manager` | Immutable RSA key lifecycle audit | `action`, `publicKeyHash`, `timestamp` |
| `users/{uid}/profile` | UX preferences (biometric gate, theme, vault timestamps) | `biometricGateEnabled`, `themeMode`, `keyVaultCreatedAt` |
| `users/{uid}/friendships` | Bidirectional connection records | `status` (`accepted`) |
| `transfers` | Active file transfer metadata + encrypted key material | `senderId`, `receiverId`, `encryptedAESKey`, `iv`, `status`, `receiverStatus` |
| `handshakes` | Session-layer RSA key exchange | `receiverId`, `senderId`, `publicKey`, `status` |
| `neutral_handshakes` | Connection-layer proposals (deterministic doc ID: `${proposerId}_${partnerId}`) | `proposerId`, `partnerId`, `status` (`pending`/`connected`/`rejected`) |
| `transfer_logs` | Append-only global audit log (started/completed/kill_switch events) | `participants[]`, `senderId`, `receiverId`, `status`, `loggedAt` |
| `security_audit_log` | Append-only security event log (admin-readable only) | `event`, `userId`, `timestamp`, `details` |

**Write patterns used:**
- `WriteBatch` for atomic multi-document writes (key exchange, disconnect, session cleanup)
- `runTransaction` for TOCTOU-safe operations (connection proposals)
- `FieldValue.serverTimestamp()` on all audit/timestamp fields
- `FieldValue.delete()` for zero-remanence key removal

---

## Authentication

**Firebase Authentication** (`firebase_auth ^6.3.0`)

- Client: `FirebaseAuth.instance`
- Implemented in: `lib/data/repositories/auth_repository.dart`

**Auth flows:**

| Flow | Method | Notes |
|------|--------|-------|
| Email + password register | `createUserWithEmailAndPassword` | Username uniqueness checked against `users` collection before creation |
| Email + password login | Firestore username lookup → `signInWithEmailAndPassword` | Username-to-email resolution via `users` collection `where('username')` query |
| Google Sign-In | `google_sign_in ^6.2.4` → `GoogleAuthProvider.credential` → `signInWithCredential` | Auto-creates `users` doc on first sign-in |
| Password reset | `sendPasswordResetEmail` | Resolves username → email first |
| Logout | `GoogleSignIn().signOut()` + `FirebaseAuth.signOut()` | Both called in sequence |

**Biometric gate:** `local_auth ^3.0.1` — guards app entry; configured per-user via `users/{uid}/profile/preferences.biometricGateEnabled`; implemented in `lib/core/utils/biometric_helper.dart`

**Session tokens:** Firebase JWTs; `getIdToken()` called after register/login to ensure token is active before Firestore writes. No custom session management — Firebase SDK handles token refresh.

**Private key storage:** `flutter_secure_storage ^10.0.0` — RSA private key stored under key `rsa_private_key` (Android Keystore / iOS Secure Enclave backed). Never transmitted.

---

## External APIs

| Service | Purpose | Auth Method | Client |
|---------|---------|-------------|--------|
| **Firebase Authentication** | User identity, JWT tokens | Firebase project API key (in `lib/firebase_options.dart`) | `firebase_auth ^6.3.0` |
| **Cloud Firestore** | Real-time NoSQL database | Firebase project API key + Firestore security rules | `cloud_firestore ^6.2.0` |
| **Firebase Storage** | Encrypted file upload/download (transfers) | Firebase project API key + Storage rules | `firebase_storage ^13.2.0` |
| **Google Sign-In** | OAuth 2.0 Google identity provider | OAuth client ID (embedded in `google-services.json`) | `google_sign_in ^6.2.4` |
| **Google Fonts** | Font delivery CDN | None (public) | `google_fonts ^8.0.2` |

No REST APIs, no webhooks, no third-party payment or messaging services.

---

## Storage

**Firebase Storage** (`firebase_storage ^13.2.0`)

- Used by: `lib/data/repositories/transfer_repository.dart`
- Storage path pattern: `transfers/{transferId}/encrypted_file`
- Content type: `application/octet-stream`
- Custom metadata: `{'fileName': originalFileName}`
- Files are AES-256-GCM encrypted before upload; plaintext never touches Firebase Storage
- Files are deleted during session cleanup (`endSessionCleanup` in `lib/presentation/session/end_session_screen.dart`)
- 100 MB file size limit enforced at selection time in `lib/presentation/sender/sender_screen.dart` (`FirebaseConstants.maxDownloadBytes = 100 * 1024 * 1024`)

**Local file system:**
- Decrypted files saved to public Downloads folder via `cryptransfer/file` MethodChannel → `MainActivity.saveToDownloads()`
- Android 10+ (API 29+): MediaStore.Downloads (no `WRITE_EXTERNAL_STORAGE` permission required)
- Android <10: Direct `FileOutputStream` (requires `WRITE_EXTERNAL_STORAGE`, declared in manifest with `maxSdkVersion="28"`)
- Temporary files accessed via `path_provider ^2.1.0`
- Decrypted files opened with `open_file ^3.3.2` via `FileProvider` (`androidx.core.content.FileProvider` in `AndroidManifest.xml`)

---

## Messaging / Queues

No message queues, pub/sub, or WebSocket connections. Real-time communication is handled exclusively through **Firestore snapshot listeners**:

- `ReceiverScreen`: `StreamBuilder` on `transfers` collection filtered by `receiverId` + `senderId` + `status == pending` — drives automatic navigation to decrypt screen
- `SenderScreen`: `StreamSubscription` on `handshakes` collection via `KeyRepository.streamHandshakesForSender()` — drives connection state (waiting → connected → reverted)
- `FindFriendsScreen`: per-tile `StreamSubscription` on `HandshakeRepository.streamHandshakeWithUser()` — real-time connection status without polling
- `HomeScreen`: listeners on `users/{uid}/notifications` and `neutral_handshakes` collections
- `TransferProgressScreen`: listener on `transfers/{transferId}` for `receiverStatus` and `cleanup_initiated` signals

All stream subscriptions are initialized in `initState` and cancelled in `dispose`.

---

## Native Bridges (Android MethodChannels)

| Channel | Method | Direction | Purpose |
|---------|--------|-----------|---------|
| `cryptransfer/security` | `isFlagSecureActive` | Dart → Kotlin | Verify `FLAG_SECURE` is set before each 64 KB chunk read |
| `cryptransfer/security` | `clearSession` | Dart → Kotlin | Best-effort GC hint after session close (`System.gc()`) |
| `cryptransfer/file` | `saveToDownloads` | Dart → Kotlin | Save decrypted bytes to public Downloads via MediaStore |

Implemented in: `android/app/src/main/kotlin/com/navveennair/cryptransfer/MainActivity.kt`
Consumed by: `lib/core/utils/security_lifecycle_mixin.dart`, `lib/presentation/receiver/decrypt_screen.dart`

---

## Environment Variables

No `.env` files are used. Configuration is embedded at build time:

| Config | Location | Notes |
|--------|----------|-------|
| Firebase API keys | `lib/firebase_options.dart` | Generated by FlutterFire CLI; committed to repo |
| Firebase project ID | `lib/firebase_options.dart`, `firebase.json` | `cryptransfer-96e9f` |
| Android app ID | `android/app/build.gradle.kts` | `com.navveennair.cryptransfer` |
| Google Services config | `android/app/google-services.json` | Generated by Firebase console; committed (contains no private keys) |
| Release keystore | `android/key.properties` | **Git-ignored**; must be created per machine |
| RSA private key (runtime) | `flutter_secure_storage` (device only) | Key: `rsa_private_key`; never persisted to cloud |

**Required for release builds:** `android/key.properties` with `storeFile`, `storePassword`, `keyAlias`, `keyPassword`.

**Firebase Firestore Emulator:** Configured at `localhost:8080` in `firebase.json`. App does not auto-connect to emulator; toggle requires code change in `lib/main.dart`.
