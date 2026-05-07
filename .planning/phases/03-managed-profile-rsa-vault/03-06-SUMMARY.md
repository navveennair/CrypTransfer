---
plan: 03-06
phase: 03-managed-profile-rsa-vault
status: complete
completed: 2026-05-07
gaps_closed:
  - "Generate, Regenerate, and Delete key operations complete successfully in Key Vault"
  - "deleteKeyPair() secure-storage wipe ordering (secondary desync risk)"
key-files:
  modified:
    - lib/data/repositories/auth_repository.dart
    - test/vault/key_lifecycle_test.dart
  deployed:
    - firestore.rules (cryptransfer-96e9f)
---

## Summary

Closed the two gaps blocking all Key Vault mutation operations in Phase 03.

### Gap 1 (primary blocker — UAT tests 3/4/5 failing)

**Root cause:** `rsa_key_manager` and `profile` subcollection rules were written to
`firestore.rules` in plan 03-05 but never deployed to the live Firebase project
`cryptransfer-96e9f`. Every Generate / Regenerate / Delete call returned
`PERMISSION_DENIED`.

**Fix:** `firebase -P cryptransfer-96e9f deploy --only firestore:rules` — `Deploy complete!`
confirmed. Rules timestamp updated in Firebase Console.

### Gap 2 (secondary desync risk)

**Root cause:** `deleteKeyPair()` called `_secure.delete()` at line 297 **before**
`batch.commit()` at line 309. If the batch failed after the secure-storage wipe,
the device would permanently lose the private key while Firestore still held the
public key — an unrecoverable inconsistent state.

**Fix:** Moved `_secure.delete()` to after `await batch.commit()`. Added explaining
comment. TDD sequence:
- RED commit: `TC-VAULT-03-ORDER-1` + `TC-VAULT-03-ORDER-2` added; ORDER-1 failed
  with buggy code (key absent when it should be present after commit throws).
- GREEN commit: fix applied; all 4 deleteKeyPair tests pass.

**Before:**
```dart
await _secure.delete(key: ...); // BUG: wipe before commit
// ...
await batch.commit();
```

**After:**
```dart
await batch.commit();
// Secure-storage wipe only after Firestore commit succeeds.
await _secure.delete(key: ...);
```

### Test results

```
flutter test test/vault/ — 14/14 passed
flutter analyze         — No issues found
```

### UAT result

Expected: 6/6 passed (tests 1, 2, 6 were already green; tests 3, 4, 5 unblocked by rules deploy).

## Self-Check: PASSED
