---
quick_id: 260525-kur
slug: fix-duplicate-runaesgcm-and-move-rsa-oae
description: Fix duplicate _runAesGcm and move RSA-OAEP encrypt to compute isolate
date: 2026-05-25
status: complete
must_haves:
  truths:
    - _runAesGcm top-level function removed from sender_screen.dart
    - sender_screen.dart uses EncryptionService.encryptAesGcm() for AES encryption
    - RSA-OAEP encrypt runs in a compute() isolate via _rsaOaepEncryptIsolate
    - No duplicate crypto logic between sender_screen.dart and encryption_service.dart
    - flutter analyze passes with no issues
---

# Quick Task 260525-kur: Fix duplicate _runAesGcm and move RSA-OAEP encrypt to compute isolate

## Tasks

### Task 1: Remove duplicate _runAesGcm, use EncryptionService.encryptAesGcm()
- **Files:** `lib/presentation/sender/sender_screen.dart`, `lib/data/services/encryption_service.dart`
- **Action:** Delete `_runAesGcm` top-level function. Add import for `encryption_service.dart`. Rewrite `_encryptFile()` to call `EncryptionService.encryptAesGcm(plaintext)` and register returned key/iv/ciphertext buffers. Remove now-dead `_secureBytes()` method.
- **Verify:** `flutter analyze` passes; no `_runAesGcm` references remain.

### Task 2: Move RSA-OAEP encrypt to compute() isolate
- **Files:** `lib/presentation/sender/sender_screen.dart`
- **Action:** Add top-level `_rsaOaepEncryptIsolate(List<dynamic>)` function that calls `EncryptionService.decodePublicKey` + `EncryptionService.rsaEncrypt`. Rewrite `_encryptAesKey()` to use `await compute(_rsaOaepEncryptIsolate, [publicKeyJson, aesKey])`. Remove dead `_decodePublicKey()` and `_rsaOaepEncrypt()` methods. Remove unused `pointycastle` import.
- **Verify:** `flutter analyze` passes; RSA encrypt is no longer synchronous on main isolate.
