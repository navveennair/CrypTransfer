---
quick_id: 260525-kur
status: complete
commit: fdf8a84
date: 2026-05-25
---

# Summary: Fix duplicate _runAesGcm and move RSA-OAEP encrypt to compute isolate

## What changed

**`lib/presentation/sender/sender_screen.dart`** — net -26 lines:

- Removed `_runAesGcm` top-level isolate function (was a byte-for-byte duplicate of `runAesGcmEncrypt` in `encryption_service.dart`)
- Added `_rsaOaepEncryptIsolate` top-level function that delegates to `EncryptionService.decodePublicKey` + `EncryptionService.rsaEncrypt` — mirrors the receiver's `_decryptAesKeyIsolate` pattern
- `_encryptFile()` now calls `EncryptionService.encryptAesGcm(plaintext)` — key and IV generated inside the service, returned in `AesEncryptResult`; buffers registered after result
- `_encryptAesKey()` now awaits `compute(_rsaOaepEncryptIsolate, [publicKeyJson, aesKey])` instead of calling `_rsaOaepEncrypt()` synchronously on the main isolate
- Removed dead methods: `_secureBytes()`, `_decodePublicKey()`, `_rsaOaepEncrypt()`
- Removed unused imports: `dart:math`, `package:pointycastle/export.dart`
- Added import: `../../data/services/encryption_service.dart`

## Verification

`flutter analyze` — No issues found.
