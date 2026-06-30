---
status: resolved
trigger: "Biometric Gate appears twice — once before entering RSA Key Vault and another when clicking Generate Keys. Remove Biometric Helper Gate when clicking Generate Keys."
created: 2026-06-04
updated: 2026-06-04
---

## Symptoms

- **Expected**: Biometric gate appears once — only before entering the RSA Key Vault screen
- **Actual**: Biometric gate triggers a second time when clicking "Generate Keys"
- **Fix requested**: Remove the BiometricHelper gate call from the Generate Keys click handler

## Current Focus

- hypothesis: "BiometricHelper.authenticate() is called in two places: once at RSA Key Vault entry (navigation guard) and once inside the Generate Keys button handler"
- next_action: "RESOLVED — fix applied"

## Evidence

- timestamp: 2026-06-04
  file: lib/presentation/vault/rsa_key_manager_screen.dart
  finding: >
    Two independent BiometricHelper.authenticate() calls existed in the flow.
    (1) _authenticate() called in initState via addPostFrameCallback — 'Unlock RSA Key Vault' — this is the correct entry guard.
    (2) _onRegenerate() called BiometricHelper.authenticate('Confirm: Regenerate RSA Keys') at lines 60-61 — this fires when 'Generate Keys' button is tapped, causing the second prompt.
    The 'Generate Keys' button (label when no key exists) and 'Regenerate Keys' button (label when key exists) both route to _onRegenerate(), so both cases were affected.

## Eliminated

- The _onDelete() biometric gate was intentionally kept — it guards a destructive permanent-delete action and is correct.
- receiver_screen.dart _openKeyManager() biometric gate was intentionally kept — it is the entry guard before navigation to RsaKeyManagerScreen from the ReceiverScreen gear button.

## Resolution

- root_cause: "_onRegenerate() contained a redundant BiometricHelper.authenticate() call ('Confirm: Regenerate RSA Keys') at the start of the handler, which fired after the vault-entry gate in _authenticate() had already passed. Since _gateChecked must be true for the UI to render at all, the vault entry biometric is sufficient."
- fix: "Removed the two lines (BiometricHelper.authenticate call and its guard check) from _onRegenerate() in lib/presentation/vault/rsa_key_manager_screen.dart. The existing _showConfirmDialog() bottom sheet still provides a user-intent confirmation before the destructive operation proceeds. flutter analyze: No issues."
- files_changed:
  - lib/presentation/vault/rsa_key_manager_screen.dart
