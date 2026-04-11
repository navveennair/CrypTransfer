---
tags: [module, auth, agent-active]
status: complete
---

# Module: Authentication

## Responsibility
Handles user registration, login, logout, and biometric authentication via Firebase Auth.

## Files Owned
- `lib/presentation/auth/login_screen.dart` — username + password login
- `lib/presentation/auth/register_screen.dart` — full registration with real-time validation
- `lib/presentation/auth/splash_screen.dart` — auth state gate (routes to Login or Home)
- `lib/data/repositories/auth_repository.dart` — Firebase Auth + Firestore user document logic

## Dependencies
- `firebase_auth` — authentication
- `cloud_firestore` — user document (username lookup, profile)
- `flutter_secure_storage` — private key storage (adjacent to auth flow)
- `local_auth` — biometric authentication (bypassed pre-viva)

## AuthRepository Public API
| Method | Purpose |
|--------|---------|
| `register()` | Creates Firebase Auth user + writes `users/{uid}` Firestore doc |
| `loginWithUsername()` | Queries `users` by `username` → extracts `email` → `signInWithEmailAndPassword` |
| `logout()` | `_auth.signOut()` |
| `isUsernameTaken(username)` | Debounced uniqueness check (used by RegisterScreen) |
| `generateAndStoreKeyPair()` | Generates RSA-2048 keypair via `Isolate.run()`, stores private key in SecureStorage, updates `publicKey` in Firestore |
| `hasKeyPair()` | Checks SecureStorage for private key existence |
| `getPublicKey()` | Reads `publicKey` from `users/{uid}` |
| `getPrivateKeyJson()` | Reads private key JSON from SecureStorage |
| `getUserProfile(uid)` | Fetches `UserModel` from Firestore |

## ✅ compute() Migration (resolved)
`generateAndStoreKeyPair()` was migrated from `Isolate.run()` to `compute()`.
A top-level function `_generateKeyPairIsolate` was added to `auth_repository.dart`
(required by `compute()` — cannot be a closure or instance method).
Guardian scanner now marks AuthRepository as **SECURE**.
Both the step-0 key generation and sidebar drawer regen paths use `compute()`.

## Firestore User Document Schema
```
users/{uid}
  username:              String       — written at register()
  email:                 String       — written at register()
  phone:                 String       — written at register()
  publicKey:             String?      — null when mailbox closed (written by setupReceiverSession)
  isReadyToReceive:      bool         — written by setupReceiverSession / closeReceiverSession
  sessionActive:         bool         — written by setupReceiverSession / closeReceiverSession
  publicKeyUploadedAt:   Timestamp?   — written by setupReceiverSession
  lastSessionClosed:     Timestamp?   — written by closeReceiverSession
  createdAt:             Timestamp    — written at register()
```

> **`UserModel` note**: `UserModel.fromDoc()` reads only 5 fields: `username`, `email`, `phone`,
> `publicKey`, `createdAt`. The fields `isReadyToReceive`, `sessionActive`, `publicKeyUploadedAt`,
> `lastSessionClosed` are NOT exposed via `UserModel` — they are accessed directly from Firestore
> by `EncryptionService` and `ReceiverScreen`.

> `UserModel.hasPublicKey` → `publicKey != null && publicKey!.isNotEmpty` — used by SenderScreen.

> No `isDisabled` or `isAdmin` fields — not implemented. Access control is via Firestore security rules only.

## Exception Hierarchy (`lib/core/errors/app_exceptions.dart`)
| Exception | Thrown by | Cause |
|-----------|-----------|-------|
| `AppException` | Base class | Never thrown directly |
| `AuthException` | `AuthRepository`, `KeyRepository` | Firebase Auth / Firestore auth failure |
| `TransferException` | `TransferRepository` | Upload / download / status update failure |
| `CryptoException` | `EncryptionService` | AES or RSA operation failure |
| `NetworkException` | `KeyRepository`, `AuthRepository` | Firestore / Storage network failure |
| `KeyNotFoundException` | `KeyRepository` | RSA key missing on send attempt |

All exceptions extend `AppException`. Callers catch specific subclasses.
`toString()` returns `message` directly — safe for UI display.

## Current Status
✅ Firebase Auth login/register done  
✅ Username-based login (not email — queries `users` by `username` to retrieve `email`)  
✅ Real-time field validation on RegisterScreen with 600ms debounced Firestore uniqueness check  
✅ Per-field visual status icons (pristine / checking / valid / invalid)  
✅ Role selection (Sender/Receiver) — via HomeScreen after login  
✅ SplashScreen auth gate — auto-routes returning users to HomeScreen  
⚠️ Biometric auth implemented via `biometric_helper.dart` but **bypassed** — re-enable before viva  
⚠️ `generateAndStoreKeyPair()` uses `Isolate.run()` — Guardian WARNING (legacy path, intentional)

## Agent Instructions
1. Never store raw passwords — Firebase Auth handles hashing
2. Username login translates to email via direct `users` collection query (not a separate index)
3. Biometric bypass is TEMPORARY — re-enable `local_auth` check before viva
4. `register()` writes to both Firebase Auth and `users/{uid}` Firestore doc
5. The `generateAndStoreKeyPair()` legacy path is still active for step 0 key generation — do not remove
6. Update this doc after any auth flow changes

## Open Tasks
- [ ] Re-enable biometric authentication before viva
