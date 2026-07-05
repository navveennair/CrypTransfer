# CrypTransfer — Milestones

## v1.0 — Pre-Viva Thesis Demonstration Build

**Shipped:** 2026-07-05
**Phases:** 11 (02-11, incl. decimal insert 07.1) | **Plans:** 40 | **Commits:** 485
**Timeline:** 2026-03-18 → 2026-07-02 (~3.5 months)
**Codebase:** 18,463 LOC (`lib/`), 27 test files

### Delivered

A secure, end-to-end encrypted peer-to-peer file transfer app with zero-remanence guarantees — built as a thesis demonstration platform at the University of Hertfordshire.

### Key Accomplishments

1. **Zero-remanence session lifecycle** — receiver-as-master cleanup with WriteBatch-atomic Firestore deletes, reactive sender-side key wipe, and a synchronized 4-turn destruction protocol (Phases 02, 04, 07).
2. **Neutral Handshake connection model** — decoupled "establishing a connection" from "choosing sender/receiver role," with a pending-approval flow and deferred role selection (Phase 05).
3. **Synchronized crypto readiness gate** — sender cannot encrypt or pick files until the receiver's cryptographic environment is confirmed ready (Phase 06).
4. **Biometric-gated RSA Key Vault** — sole key lifecycle surface for regenerate/delete, with immutable Firestore audit trail (Phase 03).
5. **Full layer decoupling** — eliminated all 14 direct `FirebaseFirestore.instance` calls from the presentation layer, centralizing every Firestore operation in Repositories (Phase 07.1).
6. **Production Android packaging** — `applicationId` renamed to `com.navveennair.cryptransfer`, Play Store ready (Phase 08).
7. **Navigation & session-integrity hardening** — back-navigation confirmation during active sessions, stale-key invalidation on receiver key rotation (Phase 09/10).
8. **Admin dashboard security & efficiency overhaul** — closed an unguarded `/admin-dashboard` route, replaced fake chart data with real 7-day aggregation, consolidated N parallel Firestore streams into a single `FutureBuilder`, added pagination and error handling across all admin streams (Phase 11).

### Known Deferred Items at Close

Acknowledged and deferred at milestone close on 2026-07-05 (see `.planning/milestones/v1.0-ROADMAP.md` for full detail):

| Category | Item | Status |
|----------|------|--------|
| debug | Phase 11 ConnectionNodeMap "ISOLATED" status + tab-switch persistence | Needs new debug session |
| verification | Phase 09 browse-files re-lock after encryption | Code traced as already fixed, pending on-device re-confirm |
| tech debt | Phase 06 WR-02 missing `mounted` guard on retry closure | Non-blocking; original function refactored away |
| tech debt | Phase 07 WR-02–WR-05 (encryptedAESKey semantics, silent catches, stuck spinner, misleading timeout UI) | Referenced pre-rewrite code (`transfer_progress_screen.dart` → `sender_transfer_screen.dart`); not re-audited |
| housekeeping | Orphaned empty dir `.planning/phases/07-1-layer-decoupling-refactor/` | Left in place, not blocking |

Known deferred items at close: 5 (see above; none blocking).
