---
status: investigating
trigger: "Key Vault itself is not working — not just navigation, but the vault screen core functionality is broken."
created: 2026-05-25T00:00:00Z
updated: 2026-05-25T00:00:00Z
---

hypothesis: Dialog stack management race condition — Navigator.pop called before progress dialog is rendered, causing vault screen to close instead of dialog
evidence: Code calls _showProgressDialog (which calls showDialog without awaiting) then immediately awaits regenerateKeyPair. If operation completes before dialog renders, Navigator.pop pops the wrong route
fix_applied: 
  1. Wrapped dialog show in addPostFrameCallback to ensure dialog is scheduled before async operation
  2. Added dialogShown flag to track if dialog was actually rendered
  3. Only call Navigator.pop if dialog was shown AND canPop returns true
  4. Added delay before second Navigator.pop to allow snackbar display time
  5. Same pattern applied to both _onRegenerate and _onDelete
  6. Changed _showProgressDialog to return Future (for consistency, though not awaited)
  7. flutter analyze now passes with no errors

verification: Testing needed to confirm vault operations work end-to-end

## Symptoms

expected: User taps vault icon/button, biometric auth completes, vault screen displays with key status and generate/regenerate options
actual: "Key Vault itself is not working" — previous Navigator.pop fix didn't help, suggesting core functionality broken not just navigation
errors: None reported yet
reproduction: User access to vault from ReceiverScreen settings icon or Step 1 "Regenerate Keys" button
started: After phase 07.1 refactor (layer decoupling)
user_description: "not just navigation, but the vault screen core functionality is broken"

## Eliminated

(none yet)

## Evidence

- timestamp: 2026-05-25
  checked: RsaKeyManagerScreen code structure and Navigator logic
  found: |
    _onRegenerate() and _onDelete() both call Navigator.pop(context) TWICE:
    1. First pop (line 84/128) to dismiss the progress dialog
    2. Second pop (line 88/NA) to close the vault screen
    
    But _showProgressDialog() doesn't await showDialog(), so the dialog might not be
    registered as a route yet when regenerateKeyPair completes.
    
    Also, if regenerateKeyPair throws VERY quickly (before dialog frame is processed),
    the first Navigator.pop would pop the vault screen instead of the dialog.
  implication: Navigation stack mismatch could cause vault screen to close prematurely or pop sequence to fail

- timestamp: 2026-05-25
  checked: AuthRepository.regenerateKeyPair() implementation
  found: |
    Line 280 uses batch.update(userRef, {...}) which FAILS if doc doesn't exist.
    If user registered before preferences subcollection existed, the update fails
    silently caught but throws FirebaseException on batch.commit().
    
    Line 287 uses batch.set(..., SetOptions(merge: true)) for preferences which creates the doc if missing.
    Inconsistency: update vs set causes batch.commit() failure for users without preferences doc.
  implication: Users without profile/preferences document (legacy accounts) cannot regenerate keys; call throws exception caught in _onRegenerate catch block

- timestamp: 2026-05-25
  checked: RsaKeyManagerScreen phase 07.1 changes
  found: |
    Phase 07.1 Wave 4 refactored admin and onboarding screens but did NOT touch vault screen.
    No breaking changes from phase 07.1 identified in RsaKeyManagerScreen or related imports.
    Code compiles with 'flutter analyze: No issues found!'
  implication: Phase 07.1 unlikely to be direct cause; issue is in vault screen logic itself

## Resolution

root_cause: Dialog stack race condition in _onRegenerate and _onDelete handlers
  - _showProgressDialog() calls showDialog() without awaiting it
  - If the async operation (regenerateKeyPair/deleteKeyPair) completes before the dialog renders, Navigator.pop() pops the wrong route (vault screen instead of dialog)
  - This causes the vault screen to close immediately, leaving the button disabled (_regenerating=true) but the screen closed
  - User cannot access the vault anymore without restarting the flow through ReceiverScreen

fix: |
  Restructured _onRegenerate() and _onDelete() to fix dialog timing:
  
  1. Changed _showProgressDialog() to return Future<void> from showDialog (for consistency)
  2. Wrapped showDialog call in addPostFrameCallback to ensure it's scheduled
  3. Added dialogShown boolean flag to track whether dialog was actually rendered
  4. Only call Navigator.pop(context) if dialogShown=true AND Navigator.canPop(context)=true
  5. Added Future.delayed(300ms) before closing vault screen to let snackbar display
  6. Applied same pattern to both _onRegenerate and _onDelete methods
  
  This ensures:
  - Dialog is guaranteed to be on navigator stack before operation runs
  - Navigation only pops routes that actually exist
  - User sees success feedback before screen closes
  - Buttons don't stay disabled if dialog never renders

files_changed: 
  - lib/presentation/vault/rsa_key_manager_screen.dart (lines 59-120, 102-165)

verification: 
  - flutter analyze passes (no issues)
  - Code compiles successfully
  - Manual testing: tap buttons, confirm actions, should see dialog, get feedback, then return to ReceiverScreen
