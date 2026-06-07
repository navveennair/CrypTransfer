---
status: complete
---

# Quick Task 260607-a1k: Remove redundant biometric prompt on key delete

## What changed

Removed two lines from `_onDelete()` in `lib/presentation/vault/rsa_key_manager_screen.dart`:

```dart
// deleted:
final gateOk = await BiometricHelper.authenticate('Confirm: Delete RSA Keys');
if (!gateOk || !mounted) return;
```

The vault entry gate (`initState → _authenticate()`) already verifies the user before any
content is shown. The second biometric prompt on delete was redundant. The confirmation dialog
(`_showConfirmDialog`) remains as the delete guard.

`BiometricHelper` import kept — still used by `_authenticate()`.

## Result

- `flutter analyze`: No issues
- Delete flow: entry gate → content → "Delete Keys" button → confirmation sheet → delete
