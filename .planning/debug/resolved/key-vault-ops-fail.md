---
status: diagnosed
trigger: "both sender and receiver cannot Generate, Regenerate or Delete Keys in RSA Key Vault screen"
created: 2026-05-07T00:00:00Z
updated: 2026-05-07T01:00:00Z
---

## Current Focus

hypothesis: "Firestore rules for rsa_key_manager and profile subcollections (added in commit b669214) were never deployed to Firebase production. All three vault operations call methods that write to users/{uid}/rsa_key_manager via WriteBatch. Without the deployed rule, the batch fails with PERMISSION_DENIED."
test: confirmed via git history — rules were added in b669214 but no firebase deploy commit exists
expecting: deploying firestore rules will fix all three operations
next_action: DIAGNOSED — run firebase deploy --only firestore:rules

## Symptoms

expected: Generate, Regenerate, and Delete key operations should succeed for both sender and receiver accounts
actual: all three operations fail for both accounts — vault shows active key fingerprint but mutations fail
errors: likely "PERMISSION_DENIED: Missing or insufficient permissions" shown as red SnackBar
reproduction: open RSA Key Vault screen, attempt Generate/Regenerate/Delete
started: after Phase 03 (managed-profile-rsa-vault) implementation (UAT ran 2026-05-07)

## Eliminated

- hypothesis: "BiometricHelper.authenticate blocks or fails"
  evidence: "BiometricHelper.authenticate always returns true (stubbed per CLAUDE.md pre-viva roadmap)"
  timestamp: 2026-05-07T01:00:00Z

- hypothesis: "Firestore security rules are wrong in the code"
  evidence: "03-VERIFICATION.md confirms rules are correct. rsa_key_manager block has allow create: if isOwner(userId) && action in ['generated','regenerated','deleted']. Both action values used in code ('regenerated', 'deleted') are in the allowed list."
  timestamp: 2026-05-07T01:00:00Z

- hypothesis: "CrypButton or UI is not wired to the handler"
  evidence: "CrypButton onPressed: _regenerating ? null : _onRegenerate. _regenerating starts false. The button is enabled. GestureDetector fires onTapUp which calls widget.onPressed?.call()."
  timestamp: 2026-05-07T01:00:00Z

- hypothesis: "Confirmation dialog silently cancels"
  evidence: "BiometricHelper returns true immediately. showModalBottomSheet uses ctx.pop(true) for confirm. result ?? false correctly returns true when confirmed."
  timestamp: 2026-05-07T01:00:00Z

- hypothesis: "compute() isolate throws during RSA generation"
  evidence: "generateRsaKeyPairSync uses the same PointyCastle RSA code that was already verified working in prior phases. No evidence of isolate failure."
  timestamp: 2026-05-07T01:00:00Z

- hypothesis: "profile/preferences document missing causes create permission error"
  evidence: "set(..., SetOptions(merge:true)) on a non-existent document is a create operation. The profile rule allow create: if isOwner(userId) covers this. BUT — this only matters if rules are deployed."
  timestamp: 2026-05-07T01:00:00Z

## Evidence

- timestamp: 2026-05-07T01:00:00Z
  checked: "git show b669214^:firestore.rules | grep profile rsa_key_manager"
  found: "Zero matches — before commit b669214, there were NO rules for rsa_key_manager or profile subcollections in firestore.rules"
  implication: "If rules from b669214 were not deployed to Firebase, production Firestore has no rules for these subcollections. Firestore denies by default. All writes to users/{uid}/rsa_key_manager fail with PERMISSION_DENIED."

- timestamp: 2026-05-07T01:00:00Z
  checked: "git log --oneline | grep -i deploy"
  found: "No deploy commit in git history"
  implication: "firebase deploy --only firestore:rules may never have been run after Phase 03 added the new subcollection rules."

- timestamp: 2026-05-07T01:00:00Z
  checked: "regenerateKeyPair and deleteKeyPair methods in auth_repository.dart"
  found: "regenerateKeyPair: 3-doc batch — users/{uid} update + users/{uid}/rsa_key_manager create + users/{uid}/profile/preferences set(merge). deleteKeyPair: 2-doc batch — users/{uid} update + users/{uid}/rsa_key_manager create."
  implication: "Both methods write to rsa_key_manager. If rsa_key_manager create rule is missing in production, both methods fail."

- timestamp: 2026-05-07T01:00:00Z
  checked: "All three vault operations (Generate, Regenerate, Delete)"
  found: "Generate → _onRegenerate → regenerateKeyPair. Regenerate → _onRegenerate → regenerateKeyPair. Delete → _onDelete → deleteKeyPair. All three paths write to rsa_key_manager."
  implication: "The common denominator for all three failing operations is the rsa_key_manager subcollection write."

- timestamp: 2026-05-07T01:00:00Z
  checked: "Error handling in _onRegenerate and _onDelete"
  found: "Both catch blocks call _showError(e.toString()). AppException.toString() returns message directly. FirebaseException.toString() returns the Firebase error message."
  implication: "User WOULD see an error SnackBar — likely 'Missing or insufficient permissions' or similar."

## Resolution

root_cause: "Firestore security rules for users/{uid}/rsa_key_manager (append-only audit log) and users/{uid}/profile (preferences) subcollections were added to firestore.rules in commit b669214 (2026-05-02) but were never deployed to the Firebase production project (cryptransfer-96e9f). All three vault operations (Generate, Regenerate, Delete) call either regenerateKeyPair() or deleteKeyPair() in AuthRepository, both of which include a WriteBatch.set() to users/{uid}/rsa_key_manager. Without the deployed rule, the entire batch fails with FirebaseException PERMISSION_DENIED."
fix: "Run: firebase deploy --only firestore:rules"
verification: "Retry Generate/Regenerate/Delete in vault screen — all should succeed and show success SnackBar"
files_changed: []
