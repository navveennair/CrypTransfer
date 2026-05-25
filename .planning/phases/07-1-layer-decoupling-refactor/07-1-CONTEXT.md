# Phase 07.1: Layer Decoupling Refactor — Context

**Gathered:** 2026-05-25  
**Status:** Ready for planning  
**Source:** Architectural audit + layer leakage detection

---

## Phase Boundary

Fix critical layer coupling violations where the Presentation Layer calls `FirebaseFirestore.instance` directly instead of delegating to the Repository layer. This breaks three architectural guarantees:

1. **Maintainability** — Database schema changes require edits in 14 files instead of 1 Repository
2. **Security** — Data filters (like `sessionActive` checks) are scattered across UI instead of centralized
3. **Testability** — UI cannot be unit-tested because it's glued to the global Firebase singleton

**Outcome:** All UI files delegate database operations to Repositories. No `FirebaseFirestore.instance` calls in `lib/presentation/`.

---

## Implementation Decisions

### Layer Architecture (Locked)

**Presentation Layer (UI):** 
- NEVER calls `FirebaseFirestore.instance`, `FirebaseStorage.instance`, or `FirebaseAuth.instance` directly
- Only interacts with Repositories via dependency injection or provider pattern
- Screens receive repositories as constructor parameters or via `Provider`/`GetIt`

**Repository Layer (Data):**
- Acts as the "waiter" — all Firestore queries, reads, writes, batch operations happen here
- Responsible for security validation (filters, permission checks, data sanitization)
- Returns models or streams of models to UI
- Encapsulates collection names, Firestore rules, and schema details

**Service Layer (Crypto):**
- All cryptographic operations (AES, RSA) stay in `EncryptionService`
- No business logic here — crypto-only

### Violation Audit (Locked)

**14 files with direct Firestore calls:**
1. `home_screen.dart:46` — Recent transfers stream (should use TransferRepository)
2. `sender_screen.dart:366` — Generate transfer ID (TransferRepository.generateId() exists but not used)
3. `transfer_progress_screen.dart:104,165,212,287,340,366` — 6 direct calls (should use TransferRepository.watchTransferStatus, updateTransferStatus)
4. `sender_session_ended_screen.dart:65,70` — Direct reads and deletes (should use TransferRepository)
5. `receiver_transfer_screen.dart:112,175` — Direct stream + update (should use TransferRepository)
6. `decrypt_screen.dart:96,158` — Direct stream + update (should use TransferRepository)
7. `receiver_screen.dart:178,327` — Direct reads and streams (should use TransferRepository/UserRepository)
8. `receiver_end_session_screen.dart:117,204,207,216` — Direct stream + batch writes (NEW: CleanupRepository needed)
9. `onboarding_screen.dart:103` — Direct user doc update (should use UserRepository)
10. `admin_dashboard.dart:141,155,174` — Direct dashboard queries (should use AdminRepository)
11. `admin_dashboard_screen.dart:21` — Direct audit log query
12. `connection_node_map.dart:12,33` — Direct user/friendship queries
13. `security_pulse_feed.dart:14` — Direct audit log stream
14. `transfer_volume_chart.dart:22` — Direct transfer log stream

**Security Risk:** Multiple locations reading without centralized `sessionActive` filter = risk of displaying "ghost sessions" that should be wiped.

### Repository Methods Needed (Locked)

**TransferRepository (expand existing):**
- `watchTransferStatus(transferId)` → stream of transfer doc for reactive UI
- `streamRecentTransfers(userId)` → stream of recent transfers for HomeScreen
- `updateTransferField(transferId, field, value)` → generic update (replaces scattered .update() calls)
- `updateTransferStatus(transferId, status)` → encapsulate status validation
- `cancelTransfer(transferId)` → abort transfer with proper cleanup
- `getTransferDoc(transferId)` → check if doc exists (for cleanup verification)

**CleanupRepository (new):**
- `initiateReceiverCleanup(transferId, receiverId, senderId)` → batch-write cleanup_initiated flag + audit log
- `watchTransferForDeletion(transferId)` → stream the transfer doc, emit when deleted
- `completeReceiverCleanup(transferId, receiverId, senderId)` → batch-delete transfer + write audit logs for both parties

**AdminRepository (expand existing):**
- `streamTransferLogs()` → dashboard audit log stream
- `streamActiveHandshakes()` → dashboard active sessions
- `streamUserConnections()` → connection node map
- `streamSecurityAuditLog()` → security pulse feed

**UserRepository (if doesn't exist):**
- `updateUser(userId, fields)` → user doc updates (onboarding, preferences)
- `streamUserWithFriendships(userId)` → user + friendships for connection node map

### Claude's Discretion

- **Dependency Injection strategy:** Use `Provider` package (already in pubspec.yaml) to inject repositories into screens
- **Error Handling:** Centralize in Repository — return AppExceptions, UI just displays them
- **Reactive updates:** Use streams throughout — UI uses StreamBuilder, no manual listeners
- **Batch writes:** All sensitive multi-step operations (cleanup, session end) use WriteBatch in Repository, never scatter across UI

---

## Specific Ideas

### File-by-File Migration Map

| UI File | Current Pattern | Target Pattern | New Repository Method |
|---------|-----------------|-----------------|----------------------|
| home_screen.dart:46 | `FirebaseFirestore.instance.collection('audit_logs').doc(uid).collection(...)` | `TransferRepository.streamRecentTransfers(uid)` | `streamRecentTransfers()` |
| sender_screen.dart:366 | `FirebaseFirestore.instance.collection('transfers').doc().id` | `TransferRepository.generateId()` | Use existing |
| transfer_progress_screen.dart | 6 direct Firestore calls | Mix of `watchTransferStatus()`, `updateTransferStatus()`, `updateTransferField()` | 3 new methods |
| receiver_end_session_screen.dart:204-216 | Raw `WriteBatch` + `FirebaseFirestore.instance` | `CleanupRepository.completeReceiverCleanup()` | New repository |
| admin_dashboard.dart | 3 direct collection streams | `AdminRepository.streamTransferLogs()`, `streamActiveHandshakes()`, `streamUserConnections()` | New methods in AdminRepository |

### Security Filters to Centralize

1. **sessionActive check** — should be in TransferRepository.streamRecentTransfers(), not UI
2. **cleanup_initiated handling** — should be in CleanupRepository, encapsulate the 4-turn protocol
3. **Audit log participants array** — should be built in Repository, not scattered across UI
4. **Permission-based visibility** — admin dashboard queries should include role checks

---

## Deferred Ideas

- **Complete userRepository refactor** — for now, only add methods needed for this phase; future refactor can consolidate all user doc access
- **Move all Firestore security rule names to constants** — good idea but out of scope; can be done in a follow-up code-quality phase
- **Provider setup refactor** — don't change DI strategy; just inject repositories into existing Provider tree

---

## Canonical References

**Downstream agents MUST read these before planning:**

- `lib/data/repositories/transfer_repository.dart` — existing TransferRepository (see available methods)
- `lib/data/repositories/admin_repository.dart` — existing AdminRepository
- `lib/core/constants/firebase_constants.dart` — Firestore collection name constants
- `lib/presentation/home/home_screen.dart` — example of current violation (lines 46–60)
- `lib/presentation/receiver/receiver_end_session_screen.dart` — example of scattered WriteBatch logic (lines 204–220)
- `CLAUDE.md` — "Strict Decoupling" mandate from project instructions
- `.planning/codebase/ARCHITECTURE.md` — current layered architecture map (for context on what each layer should do)

---

*Phase: 07.1 — Layer Decoupling Refactor*  
*Context generated: 2026-05-25 from architectural audit*
