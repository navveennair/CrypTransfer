---
phase: quick-260526
plan: sxe
subsystem: data-layer
status: complete
duration: 22 minutes
completed_date: "2026-05-26"
commit: f9351db
tags: [cleanup, test-migration, audit-report]
---

# Quick Task 260526-sxe: Remove Unused Deterministic ID Implementation

## One-Liner

Migrated deprecated `rsa_key_transfers` collection references to `handshakes` (auto-ID) in tests and audit reports; preserved intentional deterministic patterns in `neutral_handshakes` connection layer.

## Summary

Successfully removed all references to the deprecated `rsa_key_transfers` collection from production code, test fixtures, and audit reports. The system is now unified on:
- **Auto-ID handshakes** (`handshakes` collection with `senderId`/`receiverId` fields)
- **Deterministic connection proposals** (`neutral_handshakes` collection with `${proposerId}_${partnerId}` doc IDs)

## Completed Tasks

| # | Task | Status | Details |
|----|------|--------|---------|
| 1 | Audit deprecated references | Complete | Found 7 rsa_key_transfers refs in TC-WIPE-002; 1 ref each in audit reports |
| 2 | Update TC-WIPE-002 test | Complete | Migrated to `handshakes` collection; changed `fromUserId`→removed, `toUserId`→`senderId` |
| 3 | Verify key_repository.dart | Clean | No stale rsa_key_transfers or deprecated field references found |
| 4 | Verify handshake_repository.dart | Intentional | Deterministic pattern documented and preserved by design |
| 5 | Update audit reports | Complete | security_audit_report.dart and write_obsidian_report.dart updated |
| 6 | Final verification | Passing | All 9 session wipe tests pass; flutter analyze clean |

## Files Modified

| File | Changes |
|------|---------|
| `test/security/session_wipe_test.dart` | TC-WIPE-002: collection `rsa_key_transfers`→`handshakes`; fields `fromUserId`/`toUserId`→`senderId`/`receiverId`; test description updated |
| `scripts/security_audit_report.dart` | Line 57: TC-WIPE-002 description updated from "rsa_key_transfers purged" to "handshakes purged" |
| `scripts/write_obsidian_report.dart` | Line 194: TC-SEC-002 description updated from "Private key not in rsa_key_transfers" to "Private key not in handshakes" |

## Success Verification

**Test Results:**
- TC-WIPE-001 through TC-WIPE-009: All 9 tests PASSED
- TC-WIPE-002 specifically: Confirms handshakes batch-delete works correctly with new field names

**Code Verification:**
- `grep -r "rsa_key_transfers" lib/ test/ scripts/` returns 0 matches
- `grep -c "collection(FirebaseConstants.handshakes)" lib/data/repositories/key_repository.dart` returns 17 (confirmed auto-ID pattern is active)
- `flutter analyze` reports 18 pre-existing info-level linter issues (no new errors introduced)

**Architecture Verification:**
- HandshakeRepository maintains deterministic `${proposerId}_${partnerId}` pattern (intentional, preserved)
- KeyRepository uses auto-ID handshakes exclusively (17 collection references)
- No Firestore field operations on deprecated `fromUserId`/`toUserId` patterns

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None - cleanup task contains no UI or data-wiring stubs.

## Threat Flags

None - cleanup task introduces no new threat surface.

## Commits

| Hash | Message |
|------|---------|
| f9351db | refactor(260526-sxe): remove unused rsa_key_transfers references and update test to use handshakes |

## Notes

- Task 3 (key_repository.dart audit) revealed the file was already clean; no stale comments remained
- Task 4 (handshake_repository.dart review) confirmed deterministic pattern is intentional for connection-layer proposals, not for transfer-layer authorization
- All tests recompiled and passed without modification to test logic—only collection/field names changed
- No breaking changes to public API; all method signatures and return types remain unchanged
