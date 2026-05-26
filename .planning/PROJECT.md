# CrypTransfer

## What This Is

CrypTransfer is a secure, end-to-end encrypted peer-to-peer file transfer app built with Flutter and Firebase, designed for high-assurance environments where transferred files must leave no recoverable trace on either device after the session ends (zero remanence). Built as a thesis demonstration platform at the University of Hertfordshire.

## Core Value

Zero-remanence file transfer: plaintext, AES session keys, and RSA private keys are cryptographically wiped from both sender and receiver at session end. The receiver controls session termination; the sender reacts reactively to Firestore deletion events. All cryptography runs in compute() isolates, never on the main thread.

## Requirements

- End-to-end hybrid encryption (RSA-OAEP + AES-CBC) with ephemeral key pairs per session
- Zero-remanence guarantee: all key material wiped from memory and secure storage at session end
- Receiver-as-master session control with reactive sender-side cleanup via Firestore stream
- Tamper-evident, immutable audit logs on both sender and receiver subcollections
- Android security hardening: FLAG_SECURE, R8 minification, biometric-gated RSA vault
- Real-time peer discovery via Firestore .snapshots() streams (no polling)
- Admin dashboard for platform oversight and user management

## Overview

CrypTransfer is a secure, end-to-end encrypted peer-to-peer file transfer app built with Flutter and Firebase. It is designed for high-assurance environments where transferred files must leave no recoverable trace on either device after the session ends — a property called **zero remanence**.

The app uses a hybrid RSA + AES encryption scheme: the receiver generates an ephemeral RSA key pair per session, the sender encrypts the AES session key with the receiver's public RSA key, and the file is transferred as AES-encrypted chunks. All key material is wiped from memory and secure storage at session end.

Primary use case: thesis demonstration / academic research platform (University of Hertfordshire). Target platform: Android (Play Store release pending).

---

## Goals

1. **Zero-remanence transfer** — no plaintext, AES key, or RSA private key survives session end on either device.
2. **Receiver-as-master session control** — the receiver initiates cleanup; the sender reacts to Firestore deletion events.
3. **Reactive peer discovery** — connections, handshakes, and incoming transfers surface immediately via Firestore `.snapshots()` streams.
4. **Tamper-evident audit trail** — every transfer is logged to immutable Firestore subcollections on both sender and receiver.
5. **Defense-in-depth hardening** — FLAG_SECURE (screenshot block), R8 minification, biometric key vault, security rules enforcement.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI framework | Flutter (Material 3, Impeller/OpenGLES backend) |
| Theme | GitHub Dark palette (`#0D1117` bg, `#58A6FF` primary) |
| Auth | Firebase Auth (email/password + Google Sign-In) |
| Database | Cloud Firestore |
| Storage | Firebase Storage (encrypted file chunks) |
| Secure storage | flutter_secure_storage (RSA private key) |
| Crypto | PointyCastle — RSA-OAEP + AES-CBC hybrid; all crypto runs in `compute()` isolates |
| State | Flutter `setState` + `StreamBuilder` (no external state manager) |
| Platform | Android (Kotlin `MainActivity.kt`) |
| Build | Gradle KTS + R8 minification + release signing |

---

## Architecture

```
lib/
├── core/
│   └── utils/
│       ├── session_manager.dart       — SessionState machine + kill-switch orchestrator
│       ├── session_state.dart         — SessionState enum (open/locked/decrypting/terminated)
│       └── security_lifecycle_mixin.dart — Uint8List zero-wipe registry; applied to all screens
├── data/
│   ├── repositories/
│   │   ├── auth_repository.dart       — Auth, RSA key lifecycle, biometric vault
│   │   ├── key_repository.dart        — Handshakes, friendships, peer discovery streams
│   │   └── transfer_repository.dart   — Transfer CRUD, audit log, Storage delete
│   └── services/
│       ├── encryption_service.dart    — Hybrid crypto + reactive kill-switch binding
│       └── transfer_service.dart      — 64 KB chunked file reads (memory-stable)
└── presentation/
    ├── auth/                          — Login, Register, Google Sign-In
    ├── home/                          — HomeScreen, FindFriendsScreen
    ├── receiver/
    │   ├── receiver_screen.dart       — Mailbox; owns SessionManager + live streams
    │   ├── decrypt_screen.dart        — Save & Suicide pattern (_saveAndWipe)
    │   └── receiver_end_session_screen.dart — D-03 4-step cleanup (audit → storage → WriteBatch → RSA wipe)
    ├── sender/
    │   ├── sender_screen.dart         — Connection screen; reactive handshake stream
    │   ├── transfer_progress_screen.dart — Reactive !snapshot.exists listener
    │   └── sender_session_ended_screen.dart — D-10 edge-case stale doc check
    ├── profile/
    │   └── rsa_key_manager_screen.dart — Biometric-gated RSA Vault
    ├── admin/                         — Admin dashboard (connection node map, user management)
    ├── session/                       — (EndSessionScreen deleted in Phase 4)
    └── widgets/
        └── shared_widgets.dart        — CrypButton 3D system + SessionState visual feedback
```

---

## Key Firestore Collections

| Collection | Purpose |
|------------|---------|
| `users/{uid}` | User profile, `publicKey`, `isReadyToReceive`, `selectedSenderUid`, `isAdmin` |
| `users/{uid}/friendships/{friendId}` | Bilateral friend records (status: pending/accepted) |
| `users/{uid}/connections/{connId}` | Legacy connection records |
| `users/{uid}/audit_logs/{logId}` | Immutable per-user transfer history |
| `users/{uid}/rsa_key_manager/{logId}` | Immutable RSA key lifecycle audit |
| `users/{uid}/profile/preferences` | Theme preference, biometric settings |
| `handshakes/{id}` | RSA public key exchange (auto-ID docs, one per locked session) |
| `transfers/{transferId}` | Active transfer metadata, IV, encrypted AES key |
| `transfer_logs/{logId}` | Append-only transfer start log |
| `security_audit_log/{logId}` | Security events (kill-switch fires, key wipes) |

### Handshakes Collection — Auto-ID Architecture (Phase 07.1 fix)

The `handshakes/{id}` collection uses **Firestore auto-ID** for all documents. Each locked session gets a unique ID, independent of user UIDs. This eliminates collision when roles reverse in bidirectional transfers.

**Document structure:**
- `receiverId`: User who opened the mailbox
- `senderId`: User who will send the file
- `receiverUid`, `senderUid`: Role identifiers for validation
- `publicKey`: Receiver's RSA public key (encrypted by sender)
- `status`: `'handshake_complete'` (ready for transfer)
- `receiverReady`: Boolean signaling receiver readiness

**Creation flow:**
`KeyRepository.selectSenderHandshake()` is called when receiver explicitly selects a sender. It:
1. Generates a new Firestore auto-ID
2. Atomically writes receiver's user doc (`selectedSenderUid`) + handshake doc in a WriteBatch
3. Returns the auto-ID for reference during session cleanup

**Stream query:**
`streamHandshakesForSender()` queries `WHERE senderId == currentUser` and discovers all handshakes where the current user is the intended sender. This works regardless of document ID scheme since the query filters by field, not ID.

---

## Security Properties

- **FLAG_SECURE** — blocks task-switcher screenshots at Android window level (`MainActivity.kt`)
- **R8 minification** — `isMinifyEnabled = true` with PointyCastle keep rules
- **Zero-wipe registry** — `SecurityLifecycleMixin` tracks all `Uint8List` buffers; `wipeAll()` zeroes on dispose/background
- **Kill-switch chain** — `SessionManager.stateStream → EncryptionService.bindSession` (reactive; no manual wipe call)
- **Receiver-as-master** — only the receiver can trigger session end; sender reacts to Firestore doc deletion
- **Compute isolates** — all RSA/AES operations run in `compute()` to prevent main-thread key exposure
- **Biometric vault** — RSA key lifecycle (regenerate/delete) gated behind biometric auth

---

## Milestone

**v1.0** — Pre-viva thesis demonstration build

Remaining pre-viva items:
- Face ID re-enable (`biometric_helper.dart` — bypassed for testing)
- Chapter 3/5 thesis updates
- Phase 4 human UAT (TERM-06, TERM-07 pending device test)
