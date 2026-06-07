---
status: complete
---

# Quick Task 260607-b3m: Fix RSA Key Vault first-time generate dialog

## What changed

**`lib/presentation/vault/rsa_key_manager_screen.dart`**

1. `_onRegenerate()` — added `{required bool hasKey}` parameter
2. `_showConfirmDialog` call inside `_onRegenerate` — all four args now branch on `hasKey`:
   - icon: `refresh_rounded` (regen) / `vpn_key_rounded` (generate)
   - title: "Regenerate RSA Keys?" / "Generate RSA Keys?"
   - message: regen copy mentions "old private key replaced" / generate copy explains Firestore publish
   - confirmLabel: "Regenerate" / "Generate"
3. Call site in `_buildVaultBody` — changed `_onRegenerate` → `() => _onRegenerate(hasKey: hasKey)` closure

## Firestore verification

`AuthRepository.regenerateKeyPair()` uses a 3-doc WriteBatch:
- `batch.update(userRef, {'publicKey': pubKeyJson})` — writes new public key to users collection
- audit doc in `rsa_key_manager` subcollection
- `keyVaultCreatedAt` stamp in profile/preferences

Public key in Firestore is updated atomically. Senders calling `streamHandshakesForSender()`
receive the new key immediately. No changes needed in the repository layer.

## Result

- First-time generate: "Generate RSA Keys?" + key icon + "Generate" button + no mention of "old key"
- Subsequent regenerate: "Regenerate RSA Keys?" + refresh icon + "Regenerate" button + old-key warning
- `flutter analyze`: No issues
