# Zero-Remanence Analysis: Kill-Switch Execution Path

**Generated:** 2026-04-13  
**Graph source:** `graphify-out/graph.json` (140 nodes, 139 edges, 38 communities)  
**Scope:** AppLifecycleState.paused → Uint8List.fillRange(0) — full call stack trace

---

## 1. Executive Summary

CrypTransfer's kill-switch achieves **partial zero-remanence** on receiver-side session keys and Firestore credentials. The chain from `AppLifecycleState.paused` through `SessionManager` to `SecurityLifecycleMixin.wipeAll()` is correctly wired and sequentially ordered. However, **sender-side plaintext bytes returned by `TransferService.resolve()` are not registered with the buffer registry and are therefore not zeroed by `wipeAll()`**. This is the one honest architectural gap documented below.

---

## 2. Full Call Stack

```
AppLifecycleState.paused  (Android onPause / iOS willResignActive)
    │
    │  Flutter runtime → WidgetsBindingObserver
    ▼
ReceiverScreen.didChangeAppLifecycleState(AppLifecycleState state)
    lib/presentation/receiver/receiver_screen.dart : ~95
    Guard: if (_isReadyToReceive && uid != null)
    │
    ▼
SessionManager.handleLifecycleState(state, uid, onBuffersWipe: wipeAll)
    lib/core/utils/session_manager.dart : 94
    Fires only on paused | detached — all other states dropped.
    Return type: void  ← UNAWAITED (fire-and-forget at call site)
    │
    │  internally calls:
    ▼
SessionManager.wipeSession(uid, onBuffersWipe: wipeAll)
    lib/core/utils/session_manager.dart : 76
    ├── Guard: if (state == terminated) return;          ← idempotent
    ├── _set(SessionState.terminated)                    ← UI notified immediately
    ├── await EncryptionService.closeReceiverSession(uid) ← STEP A (awaited)
    │       .catchError((_) {})                          ← errors suppressed
    └── onBuffersWipe()                                  ← STEP B (after A completes)
    │
    │ STEP A — Firestore + SecureStorage wipe:
    ▼
EncryptionService.closeReceiverSession(uid)
    lib/data/services/encryption_service.dart : ~235
    Sequential steps (all awaited internally):
    1. Firestore: users/{uid}.publicKey  → FieldValue.delete()
    2. Firestore: users/{uid}.isReadyToReceive → false
    3. FlutterSecureStorage: delete(key: 'rsa_private_key_$uid')
    4. Firestore batch: delete all rsa_key_transfers/{uid}/transfers/*
    5. Firestore batch: delete all notifications/{uid}/items/*
    6. Firestore: writeAuditLog(event: 'session_closed', ...)
    Returns: Future<void>
    │
    │ STEP B — In-memory buffer zeroing:
    ▼
SecurityLifecycleMixin.wipeAll()          ← alias: onBuffersWipe callback
    lib/core/utils/security_lifecycle_mixin.dart : ~34
    for (final buffer in _radioactiveBuffers) {
        buffer.fillRange(0, buffer.length, 0);   ← overwrites every registered byte
    }
    _radioactiveBuffers.clear();
    onBuffersWiped();                            ← hook for subclass cleanup
    │
    ▼
Uint8List.fillRange(0, length, 0)
    dart:typed_data — writes 0x00 over every index in the buffer
    Operates on the Dart heap directly; no GC involvement until next collection cycle.
```

---

## 3. Ordering Guarantee: Sequential, Not Concurrent

`handleLifecycleState` calls `wipeSession(...)` without `await`. This is **intentional**: the Android process may be suspended by the OS microseconds after `onPause` fires. Awaiting the full chain from the lifecycle callback would risk the await never resuming if the process is killed before the event loop ticks.

The ordering guarantee is preserved **within** `wipeSession`:

```
terminated flag set   →   closeReceiverSession completes   →   onBuffersWipe() called
     (sync)                       (async, awaited)                    (sync)
```

`onBuffersWipe()` — i.e., `wipeAll()` — is always called **after** `closeReceiverSession` returns or rejects. Buffer zeroing never races against the Firestore/SecureStorage operations.

The `catchError((_) {})` on `closeReceiverSession` ensures that a Firestore timeout (common when the device is going offline mid-lifecycle) does not block the buffer wipe.

---

## 4. Honest Gap: TransferService Plaintext Is Not Registered

`TransferService.resolve()` returns a `Uint8List` of the full plaintext file. In `SenderScreen._encryptFile()`:

```dart
// sender_screen.dart
final plaintext = await TransferService.resolve(
  filePath: file.path,
  fallbackBytes: file.bytes,
);
final encrypted = await compute(_runAesGcm, [plaintext, key, iv]);
```

`plaintext` is **not passed to `registerBuffer()`** before `compute()` is called. As a result:

| Buffer | Registered? | Zeroed by wipeAll()? |
|--------|------------|----------------------|
| AES key (`_aesKey`) | Yes (SenderScreen.initState) | ✅ Yes |
| RSA public key bytes | Yes | ✅ Yes |
| `plaintext` from `TransferService.resolve()` | **No** | ❌ No |
| `encrypted` ciphertext | No (passed to compute isolate) | ❌ No |

### Why the 64KB chunking does not close this gap

`readFile()` pre-allocates `Uint8List(length)` once and fills it from 64KB stream pages. The chunking avoids a second copy during stream assembly (standard `File.readAsBytes` makes an internal copy), but the **assembled buffer** still occupies `length` bytes contiguously on the Dart heap. If the file is 200 MB, a 200 MB `Uint8List` exists in memory until GC collects it.

The 64KB chunk size caps peak memory at `file_size + 64 KB` during reading (versus `file_size × 2` with naive `readAsBytes`), which is a genuine memory stability improvement. But it does not zero the assembled plaintext — the buffer simply becomes GC-eligible after `_encryptFile` returns.

### Recommended fix

Register the plaintext buffer before `compute` and zero it after encryption completes:

```dart
// In SenderScreen._encryptFile():
final plaintext = await TransferService.resolve(...);
registerBuffer(plaintext);                          // ← add this
final encrypted = await compute(_runAesGcm, [plaintext, key, iv]);
plaintext.fillRange(0, plaintext.length, 0);        // ← explicit zero post-encrypt
// No need to unregister — wipeAll() handles it on session end
```

This closes the remanence window for the sender plaintext to the duration of the `compute()` call itself.

---

## 5. God Node Architecture — Why It Achieves More Than Standard Termination

The graphify BFS traversal identified `_ReceiverScreenState` as the god node with **15 edges** — the highest connectivity in the graph. This is not accidental over-coupling; it is a security-by-convergence pattern.

### Standard Flutter session termination

```
Activity.onStop()
    └── Navigator.pop() / route disposal
            └── State.dispose()
                    └── controller.dispose(), subscription.cancel()
```

Standard disposal cleans up UI resources. It does **not**:
- Wipe Firestore credentials
- Delete remote public keys
- Zero in-memory crypto buffers
- Block mid-transfer back-navigation
- React to lifecycle states independently of route lifecycle

### ReceiverScreen convergence point

`_ReceiverScreenState` aggregates four independent termination triggers into one consistent outcome:

| Trigger | Mechanism | Handler |
|---------|-----------|---------|
| App backgrounds / phone lock | `WidgetsBindingObserver.didChangeAppLifecycleState` | `_sessionManager.handleLifecycleState` |
| Back button / gesture | `PopScope.onPopInvokedWithResult` | `_sessionManager.wipeSession` |
| Manual session close (toggle) | `_onToggleReady(false)` | `closeReceiverSession` + `_sessionManager.reset()` |
| Incoming transfer lock | `_handleIncomingTransfer` | `_sessionManager.lock()` → blocks close |

Each path terminates through `SessionManager`, which enforces idempotency (`if (state == terminated) return`). No matter which trigger fires first, the session is wiped exactly once.

### What zero-remanence requires that standard termination misses

| Requirement | Standard dispose() | ReceiverScreen kill-switch |
|-------------|-------------------|---------------------------|
| Remote public key deleted from Firestore | ❌ | ✅ `closeReceiverSession` step 1 |
| Private key deleted from SecureStorage | ❌ | ✅ step 3 |
| Pending transfer docs batch-deleted | ❌ | ✅ steps 4–5 |
| In-memory AES/RSA buffers zeroed | ❌ | ✅ `SecurityLifecycleMixin.wipeAll` |
| Transfer blocked from completing after wipe | ❌ | ✅ `SessionState.terminated` blocks all CrypButton CTAs |
| Visual state reflects termination | ❌ | ✅ `ValueNotifier<SessionState>` → CrypButton red/block |
| Back-navigation blocked during active transfer | ❌ | ✅ `PopScope` guard on `SessionState.locked` |

The 15-edge god node is the cost of centralising all of this. The alternative — spreading these responsibilities across six independent `dispose()` calls — would require six separate lifecycle observers and could not guarantee the `closeReceiverSession → wipeAll` ordering proven in §3 above.

---

## 6. Graph Extraction Note

The graphify subagent extracted the edge:

```
EncryptionService.closeReceiverSession() --calls--> SessionManager.wipeSession()
```

This direction is **inverted**. The correct direction is:

```
SessionManager.wipeSession() --calls--> EncryptionService.closeReceiverSession()
```

`EncryptionService` has no dependency on `SessionManager`. The inversion is a known limitation of semantic subagent extraction when two nodes appear adjacent in the same code block — the subagent inferred the edge direction from proximity rather than caller-callee order. All other edges in the subgraph were confirmed EXTRACTED-correct against source.

---

## 7. Summary Table

| Property | Status |
|----------|--------|
| Lifecycle trigger wiring (`paused`/`detached`) | ✅ Confirmed |
| `handleLifecycleState` fires as unawaited void | ✅ Intentional — process suspension safety |
| `closeReceiverSession` awaited before buffer wipe | ✅ Sequential ordering guaranteed |
| Firestore public key deleted | ✅ `closeReceiverSession` step 1 |
| SecureStorage private key deleted | ✅ step 3 |
| Registered `Uint8List` buffers zeroed | ✅ `fillRange(0, length, 0)` |
| Sender plaintext `TransferService.resolve()` zeroed | ❌ Not registered — gap |
| `compute()` isolate ciphertext buffer zeroed | ❌ Isolate memory, not accessible |
| Idempotency (double-wipe safe) | ✅ `terminated` guard |
| UI reflects termination state | ✅ `SessionState.terminated` → CrypButton |
