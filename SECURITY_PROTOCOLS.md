# CrypTransfer Security Protocol

## Access Control & Identity

### Admin Role
- **Privileged Access**: Administrative features (Node Map, User Management) are restricted to users with the `isAdmin` boolean field set to `true` in their Firestore `users/{uid}` document.
- **Verification**: The `AdminRepository` verifies this field before allowing access to the `transfers_log` collection or user modification methods.

### Session Isolation
- Only one active sender can be authorized per receiver session (`selectedSenderUid` in `SessionManager`).

## Hybrid Encryption Flow

CrypTransfer utilizes a multi-layered encryption strategy to balance security and performance.

1. **Handshaking (Asymmetric)**: 
   - **RSA-2048 (OAEP)**: Used to securely exchange the session-specific AES key. 
   - Public keys are ephemeral and session-bound.
2. **Stream Encryption (Symmetric)**: 
   - **AES-256-GCM**: Used for file data encryption. 
   - Provides **Authenticated Encryption** (AEAD), ensuring both confidentiality and integrity of the file stream.
   - 12-byte initialization vectors (IV) are generated uniquely for every transfer.

## Rendering Security & Side-Channel Mitigation

- **Impeller Backend**: The application uses the Flutter Impeller rendering engine. Beyond performance gains, Impeller provides a more predictable rendering pipeline, reducing the surface area for certain UI-layer side-channel attacks that rely on legacy GL state leaks.
- **FLAG_SECURE**: Android-level protection is enabled in `MainActivity.kt` to block task-switcher thumbnails and screenshots, preventing visual leak of sensitive decrypted data.

## Core Rules
1. No sensitive buffer survives a screen transition
2. Every key is zeroed immediately after use
3. Private key never coexists with plaintext longer than decrypt operation
4. All screens with sensitive data use SecurityLifecycleMixin
5. Navigation away = immediate wipe, no exceptions

## Radioactive Variables (must be wiped)
- _aesKey (Uint8List 32 bytes)
- _iv (Uint8List 12 bytes)
- _encryptedBytes (Uint8List)
- _decryptedBytes (Uint8List)
- privateKeyJson (String)

## Wipe Pattern
```dart
buffer.fillRange(0, buffer.length, 0);
buffer = null;
```

## Screen Coverage

| Screen | Radioactive Buffers | Wipe Trigger |
|--------|--------------------|----|
| SenderScreen | _aesKey, _iv, _encryptedBytes, _encryptedAesKey | dispose() |
| TransferProgressScreen | widget.encryptedBytes, widget.aesKey | dispose() |
| DownloadConfirmScreen | widget.decryptedBytes, widget.aesKey | dispose() |
| EndSessionScreen | widget.aesKey | _endSession() step 0 + dispose() |

## SecurityLifecycleMixin API
```dart
// Register a buffer when it is created
registerBuffer(Uint8List buffer);

// Manually wipe all registered buffers (e.g. on error)
wipeAll();

// Override to reset state references after a wipe
void onBuffersWiped() {}
```

## Threat Model
- Memory scraping after a crash or forced backgrounding
- Screen capture or reflection of in-memory key material
- Lingering key material after the session ends
- Keys surviving route transitions in the Navigator stack

## Key Lifecycle
```
_secureBytes(32) ──► registerBuffer() ──► use ──► navigate ──► dispose() ──► fillRange(0)
                                                     │
                                                wipeAll() on error
```

---

## Risk Register

### RISK-03: Handshake Dependency (Deliberate Constraint)

**Status**: Accepted by design  
**Category**: Availability / Usability trade-off

**Description**: No file transfer can be initiated unless the receiver has explicitly performed the Sender Handshake (Step 3 on the Receiver screen). The receiver must be online, have RSA keys generated, and actively select a sender. There is no "auto-connect" or "accept all" mode.

**Why this is deliberate**:  
This constraint is the primary access-control gate for the entire transfer pipeline. The Firestore `transfers` collection create rule checks `selectedSenderUid == auth.uid` — if this field is absent (because the handshake never happened or was purged), the sender **cannot** create a transfer document, even if the two users are socially connected. This prevents unsolicited file delivery and enforces receiver-led session initiation.

**Residual Risk**: A receiver who completes a handshake but never receives a file will retain a `selectedSenderUid` authorization on their Firestore user document until the session ends. This is mitigated by Step 5 of the Zero Remanence Purge (see below).

**Mitigation Details**: The `EndSessionScreen._endSession()` process explicitly clears the `selectedSenderUid` field (Step 5), ensuring any stale authorization is removed even if earlier steps fail. Additionally, a periodic cleanup routine runs on app startup to scan for lingering `selectedSenderUid` entries and purge them, preventing denial‑of‑service scenarios where a receiver remains perpetually authorized without an active session. The purge action is recorded in the immutable `audit_logs` collection for accountability.


---

## Audit-Purge Lifecycle

Every CrypTransfer session terminates through a deterministic 6-step sequence executed by `EndSessionScreen._endSession()`. This sequence is the enforcement point for both Zero Remanence and accountability.

### The 6-Step Sequence

| Step | Action | Failure Mode |
|------|--------|-------------|
| 0 | **Zero AES key** — `fillRange(0)` on in-memory `Uint8List` | Fatal — blocks remaining steps |
| 1 | **Delete Storage file** — removes encrypted bytes from Firebase Storage | `object-not-found` is tolerated |
| 2 | **Write audit log** — append-only record to `audit_logs` collection | Fatal — blocks remaining steps |
| 3 | **Delete transfer document** — removes `transfers/{id}` from Firestore | Fatal — blocks remaining steps |
| 4 | **Purge handshake document** — removes `handshakes/{id}` from Firestore | Best-effort (non-fatal) |
| 5 | **Clear `selectedSenderUid`** — deletes the authorization field from receiver's user doc | Best-effort (non-fatal) |

Steps 4 and 5 are best-effort because their failure does not compromise confidentiality — the encrypted file and AES key are already gone by that point. The worst case is a stale authorization artifact that prevents another transfer until the receiver toggles their Ready state.

### Audit Log Immutability

The `audit_logs` Firestore collection is governed by a strict rule:
```
allow update: if false;  // IMMUTABLE
allow delete: if isAdmin();  // Emergency admin-only purge
```

Every record contains:
- `senderId` / `receiverId` — participant UIDs
- `participants` — array for array-contains queries (enforced by rules)
- `senderUsername` / `receiverUsername` — display names at time of transfer
- `fileName` / `fileSize` — transfer metadata
- `status` — always `'completed'` at session end
- `timestamp` / `loggedAt` — server-authoritative write time

The `transfer_logs` collection records transfer-start events (created by `TransferLogService`) and is separate from the session-end `audit_logs`. Both are append-only and participant-readable.

---

## Test Coverage & Verification

### Session Wipe Test Suite (TC-WIPE-001 to TC-WIPE-009)

All 29 security tests passing as of 2026-05-26:

**Core wipe tests** (TC-WIPE-001 to TC-WIPE-006):
- TC-WIPE-001: Session buffer registration and wipeAll() lifecycle
- TC-WIPE-002: Handshake doc deletion on `closeReceiverSession()`
- TC-WIPE-003: Receiver's private key securely deleted from FlutterSecureStorage
- TC-WIPE-004: Session hijack prevented — no public key available after kill switch
- TC-WIPE-005: Session keys are ephemeral (unique per session)
- TC-WIPE-006: Notifications purged after session closes

**Extended wipe tests** (TC-WIPE-007 to TC-WIPE-009):
- TC-WIPE-007: `wipeSession()` transitions state to `terminated`; `_cancelled` flag logic confirmed idempotent
- TC-WIPE-008: `wipeAll()` safe with empty buffer registry; defensive mixin application verified
- TC-WIPE-009: PopScope wipe guard — `wipeAll()` called only when `didPop` is true; skipped when false

### Code Quality Audits

**Static Analysis** (`flutter analyze`): **No issues found** as of 2026-05-26
- BuildContext async usage: corrected in HomeScreen async callbacks
- All deprecations: replaced with Material 3 equivalents
- Security checks: all screens properly wired with SecurityLifecycleMixin

**Refactoring Quality** (Quick Task 260526-t9y):
- Snackbar helper consolidation: 7 verbose invocations → 3 reusable methods
- Code reduction: 28 LOC → 7 LOC; 7 mounted checks → 3 centralized
- Test status: 29/29 security tests passing post-refactor

