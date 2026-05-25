# Codebase Concerns

**Analysis Date:** 2026-05-25

## Session Propagation & Lifecycle Gap

**ReceiverTransferScreen not propagated with SessionManager:**
- Issue: `ReceiverTransferScreen` is navigation-pushed automatically from `ReceiverScreen` and receives `SessionManager` as a constructor parameter (`widget.sessionManager`), but does not propagate it further. If an app backgrounding event occurs mid-transfer (in `ReceiverTransferScreen`), the `ReceiverScreen`'s `didChangeAppLifecycleState` will fire and call `SessionManager.handleLifecycleState()` → `wipeSession()`, marking `SessionState.terminated`. However, `ReceiverTransferScreen` only listens to `stateNotifier` for the kill-switch — it does NOT listen to the Firestore `EncryptionService.bindSession()` reactive cleanup. If the user backgrounds during decryption, the session is marked terminated, but the Firestore binding may have stale state.
- Files: `lib/presentation/receiver/receiver_screen.dart` (line 212, bindSession call), `lib/presentation/receiver/receiver_transfer_screen.dart` (line 21, sessionManager param), `lib/core/utils/session_manager.dart` (line 39–48, stateStream)
- Impact: Decryption-in-progress state is not observed by the reactive EncryptionService binding if the user closes the app via back navigation while in `ReceiverTransferScreen`. The `SessionManager.terminated` transition fires locally, but if `ReceiverScreen.dispose()` is skipped (e.g., activity destroyed before pop), the binding cleanup may not fire as expected.
- Test coverage: `test/security/session_wipe_test.dart` tests the kill-switch from `ReceiverScreen` directly but does not cover app pause/detach while in the nested `ReceiverTransferScreen`. The test suite assumes the user never backgrounds mid-transfer.
- Fix approach: Pass `sessionManager` to `ReceiverTransferScreen` and explicitly call `EncryptionService.bindSession()` again in its `initState()` (idempotent — binding will replace the prior subscription), and `unbindSession()` in its `dispose()`. Alternatively, use an `InheritedWidget` at the home-screen level to propagate `SessionManager` to all nested screens without threading it through navigation parameters.

---

## Platform Limitation: Compute Isolate Ciphertext Zeroing

**Encrypted bytes in isolate heap are not zeroed:**
- Issue: RSA-OAEP encrypted AES key and AES-256-GCM ciphertext are generated inside `compute()` isolates (`lib/presentation/sender/sender_screen.dart` line 327–328 for RSA, `lib/data/services/encryption_service.dart` line 73 for AES). The isolate returns the result as a `Uint8List`, which is copied back to the main isolate. However, the isolate's heap copy (and any intermediate allocations during encryption) remain in the isolate process memory and cannot be accessed by the main isolate for zeroing via `fillRange()`.
- Files: `lib/presentation/sender/sender_screen.dart` (line 327–328, `compute(_rsaOaepEncryptIsolate, ...)`), `lib/data/services/encryption_service.dart` (line 73, `compute(runAesGcmEncrypt, ...)`), `lib/presentation/receiver/decrypt_screen.dart` (line 231–232, `compute(_decryptAesKeyIsolate, ...)`)
- Cause: Dart's `compute()` function spawns a temporary isolate, which is garbage-collected by the Dart VM after the function returns. No explicit cleanup hook is available to userland code to wipe the isolate's heap before GC.
- Risk: Residual ciphertext on the isolate heap could theoretically be recovered via memory forensics on a physically-captured device or VM escape. This is an inherited platform limitation — Dart/Flutter do not provide memory-clearing compute() variants.
- Acceptance: **Accepted risk** — documented in `CLAUDE.md` Known Open Issues. The Dart VM's GC is best-effort; requesting native GC via `System.gc()` in `MainActivity.kt` (wired in `SecurityLifecycleMixin.requestNativeClear()`) provides a GC pressure hint but offers no guarantees.
- Mitigation: Do not use `compute()` for post-decryption plaintext (the plaintext bytes from the isolate would also be left on the isolate heap). Current codebase correctly uses `compute()` only for key generation and symmetric encryption — plaintexts are handled in the main isolate and registered with `SecurityLifecycleMixin.registerBuffer()` for explicit zeroing. Decryption isolates (`_decryptAesKeyIsolate`, `runAesGcmDecrypt`) take ciphertext as input and return plaintext only — plaintext is then immediately registered for zeroing in the main isolate.

---

## Firestore Security Rule Complexity

**Complex rule evaluation path with nested get() calls:**
- Issue: The `transfers` collection create rule (`firestore.rules` lines 98–106) performs two nested `get()` calls in a single rule evaluation:
  1. `get(/databases/.../documents/users/$(request.resource.data.receiverId)).data['selectedSenderUid']`
  2. `exists(/databases/.../documents/neutral_handshakes/...)`
  
  Each `get()` and `exists()` call is a separate Firestore read operation charged to the user's quota. A failed `get()` (e.g., receiver document not found) will cause the rule to fail with a PERMISSION_DENIED error rather than gracefully falling back to the `exists()` check.
- Files: `firestore.rules` (lines 98–106)
- Impact: If a receiver's user document is deleted between the time the handshake is accepted and the transfer is initiated, the create rule will fail even if a valid `neutral_handshake` document exists. The sender sees PERMISSION_DENIED instead of being able to initiate a fallback transfer path.
- Recommendation: Wrap the `get()` call with a defensive check: `(get(/databases/.../users/$(request.resource.data.receiverId)).data?.get('selectedSenderUid') == request.auth.uid)` to safely handle missing receiver documents, or use `exists()` exclusively for the handshake check if receiver authorization is optional.

---

## Circular Dependency Risk: SessionManager & SecurityLifecycleMixin

**Potential re-entrancy if both trigger cleanup:**
- Issue: `SessionManager` (owned by `ReceiverScreen` state) calls `SecurityLifecycleMixin.wipeAll()` when `wipeSession()` is invoked. `SecurityLifecycleMixin` is also a mixin on the same `ReceiverScreen` state. If `SessionManager.wipeSession()` is called from `didChangeAppLifecycleState` AND the widget is disposed simultaneously (e.g., OS kills the activity), both `handleLifecycleState()` and `dispose()` will call `wipeAll()` in close succession.
- Files: `lib/core/utils/session_manager.dart` (lines 98–110, `wipeSession()` method), `lib/core/utils/security_lifecycle_mixin.dart` (lines 84–94, `wipeAll()` method), `lib/presentation/receiver/receiver_screen.dart` (line 135, `didChangeAppLifecycleState` handler)
- Impact: `wipeAll()` is idempotent (zeroing an already-zero buffer is safe), but the double-call consumes extra CPU cycles and may delay app shutdown on low-end devices. No data corruption risk.
- Fix approach: Add a boolean flag `_wipedComplete` to `SecurityLifecycleMixin` to track if `wipeAll()` has run, and skip the second invocation if true. Or, make `SessionManager.wipeSession()` check if `stateNotifier.value == SessionState.terminated` before calling `onBuffersWipe()` to avoid re-entrance.

---

## Large Screen Files & Cognitive Complexity

**High line counts in presentation screens:**
- Issue: `lib/presentation/home/home_screen.dart` (1484 lines), `lib/presentation/sender/sender_screen.dart` (1324 lines), `lib/presentation/receiver/receiver_screen.dart` (1048 lines) exceed typical single-file readability thresholds. Each integrates state management, Firestore listeners, navigation, and business logic.
- Files: `lib/presentation/home/home_screen.dart`, `lib/presentation/sender/sender_screen.dart`, `lib/presentation/receiver/receiver_screen.dart`
- Impact: Difficult to review security-critical sections (e.g., `_encryptFile()` in SenderScreen, kill-switch binding in ReceiverScreen) without scrolling through unrelated UI code. Increases risk of overlooking subtle bugs during code review.
- Fix approach: Extract stateless widget sub-components and stream-listener wrappers into separate files. For example:
  - `lib/presentation/home/active_connections_widget.dart` — Active Connections section (currently inline in HomeScreen)
  - `lib/presentation/home/pending_requests_widget.dart` — Pending Requests section
  - `lib/presentation/sender/encryption_progress_widget.dart` — Encryption phase logic from SenderScreen
  - This reduces per-file line count to <800 without changing behavior.

---

## Firestore Listener Leaks Risk: Search Result Tiles

**Per-tile StreamSubscription management in FindFriendsScreen:**
- Issue: `lib/presentation/home/find_friends_screen.dart` creates a `_SearchResultTile` StatefulWidget for each search result. Each tile subscribes to `HandshakeRepository.streamHandshakeWithUser()` in `initState()` and cancels in `dispose()`. If a search result is filtered out (e.g., user updates the search text), the list is rebuilt, old tiles are removed, and their `dispose()` methods should run — but if the widget tree is not properly cleaned up (e.g., during rapid re-builds), subscriptions may leak.
- Files: `lib/presentation/home/find_friends_screen.dart` (implementation of `_SearchResultTile` StatefulWidget)
- Impact: Each leaked subscription holds a reference to a Firestore `StreamController` from `HandshakeRepository.streamHandshakeWithUser()`, which holds references to the two directional handshake docs. Over time (e.g., user searching 20+ users), this can accumulate 20+ active subscriptions, increasing memory usage and Firebase billing for reads.
- Mitigation: Current implementation appears correct (tile `dispose()` cancels the subscription), but worth monitoring with a memory profiler. Consider adding a `debugPrint` in `_SearchResultTile.dispose()` during development to verify cleanup is running.
- Recommendation: Add automated testing for subscription cleanup during rapid list rebuilds. Alternatively, use `Builder` or `Consumer` with a `ChangeNotifier` at the parent level to manage subscriptions centrally rather than per-tile.

---

## Missing Test Coverage: App Backgrounding During Transfer

**No automated tests for lifecycle transitions mid-transfer:**
- Issue: `test/security/session_wipe_test.dart` (TC-WIPE-001–006) tests the kill-switch from `ReceiverScreen` directly, but does not simulate:
  1. App backgrounding (`didChangeAppLifecycleState(AppLifecycleState.paused)`) while in `ReceiverTransferScreen`
  2. Back navigation from `ReceiverTransferScreen` triggering `PopScope` + session wipe
  3. Rapid toggle-off while an incoming transfer is in-flight
- Files: `test/security/session_wipe_test.dart`, `test/receiver/receiver_transfer_screen_test.dart` (if it exists)
- Impact: Regression risk — future refactors may inadvertently break lifecycle handling mid-transfer without immediate test failure. Current test suite only covers the happy path and direct kill-switch scenarios.
- Fix approach: Add integration tests using `WidgetTester` to:
  - Push `ReceiverTransferScreen`, simulate `didChangeAppLifecycleState(paused)`, verify `SessionState.terminated` fires and EncryptionService cleanup runs
  - Push `ReceiverTransferScreen`, call `Navigator.pop()` via `PopScope`, verify same cleanup
  - Test rapid toggle-off (close mailbox) while a transfer is incoming

---

## Inconsistent Error Handling in Async Cleanup

**Some cleanup paths ignore errors; others propagate:**
- Issue: `EncryptionService.closeReceiverSession()` (line 354) uses `.catchError((_) {})` to silently swallow errors when closing the session reactively. However, `ReceiverScreen._onToggleReady(false)` (imperative close) may propagate errors to a SnackBar. Inconsistency means some cleanup failures are hidden from the user.
- Files: `lib/data/services/encryption_service.dart` (line 354, `closeReceiverSession(uid).catchError((_) {})`), `lib/presentation/receiver/receiver_screen.dart` (call site of `setupReceiverSession` / `closeReceiverSession`)
- Impact: If Firestore is temporarily offline and a reactive close fires, the error is silently swallowed, potentially leaving orphaned `selectedSenderUid` or `rsa_key_transfers` docs on the server. The user may not realize the cleanup failed and could attempt to re-authorize the sender, creating duplicate handshakes.
- Fix approach: Implement exponential backoff retry in `EncryptionService.closeReceiverSession()` for transient Firestore errors (network timeout, unavailable). For permanent failures (permission denied), log a security event and prompt the user to retry or contact support.

---

## Native Channel Return Type Ambiguity

**isFlagSecureActive() safe-fallback behavior may mask bugs:**
- Issue: `SecurityLifecycleMixin.isFlagSecureActive()` (lines 50–59) returns `true` on `MissingPluginException` and for any other exception. This is intentional ("safe fallback to assume flag is active"), but on a platform where the plugin is registered and the flag check suddenly fails (e.g., due to a bug in the Kotlin handler), the error is swallowed and returns `true`. If the Kotlin handler has a typo and crashes, the Dart layer assumes the window is protected and proceeds with encryption — a false sense of security.
- Files: `lib/core/utils/security_lifecycle_mixin.dart` (lines 50–59)
- Impact: Low risk in practice (the flag is set once in `MainActivity.onCreate()` and never changes), but a misbehaving Kotlin handler could silently fail without alerting the developer.
- Recommendation: In debug builds, log a `debugPrint()` when the exception fallback is taken, so developers notice the handler is not working as expected. For release builds, keep the silent fallback to avoid blocking transfers due to a non-critical probe failure.

---

## Sparse Documentation of Firestore Schema Evolution

**No versioning strategy for handshake/transfer document evolution:**
- Issue: `handshakes` collection schema (`receiverId`, `senderId`, `status`) and `transfers` collection schema (`encryptedAESKey`, `iv`, `receiverStatus`, `cleanup_initiated`) are undocumented beyond comments in `firestore.rules`. If a future phase needs to add new fields (e.g., `handshakeTimeout`, `transferVersion`), there is no migration guide or versioning scheme for apps running older code to gracefully handle new fields.
- Files: `firestore.rules`, `lib/data/models/transfer_model.dart`, `lib/data/models/user_model.dart`
- Impact: **Deferred risk** — relevant only if multi-version app support (old + new app users in the same ecosystem) becomes a requirement for future Play Store releases. Currently, the app auto-updates, so schema evolution is not a blocker.
- Recommendation: Document the current schema version in a root-level `FIRESTORE_SCHEMA.md` file. If future versions require backward compatibility, add a `schemaVersion` field to the Firestore collection metadata (top-level `_metadata` document) so the app can detect and migrate gracefully.

---

## Unverified Kotlin Method Channel Handler Response

**MainActivity.kt clearSession handler does not return a value:**
- Issue: `SecurityLifecycleMixin.requestNativeClear()` invokes `_securityChannel.invokeMethod<void>('clearSession')` expecting a return value, but the `MainActivity.kt` handler may not return anything explicitly. Dart will treat `null` as a successful return, but if the Kotlin code throws an exception, it will be caught by the `catch (_) {}` block, silently hiding the failure.
- Files: `lib/core/utils/security_lifecycle_mixin.dart` (line 34, invokeMethod call)
- Impact: Best-effort GC hint failure is silent — does not affect security, only memory pressure after session close.
- Recommendation: Verify that `MainActivity.kt` explicitly returns `true` or calls `result.success(null)` for the `clearSession` method. Add a debug log in Dart if the result is not as expected.

---

## Orphaned References in UI State During Navigation

**PopScope back-navigation from nested screens may not trigger parent cleanup:**
- Issue: `ReceiverScreen` wraps its Scaffold in a `PopScope` that calls `SessionManager.wipeSession()` on back-nav. However, if the user navigates deeply (ReceiverScreen → ReceiverTransferScreen → DecryptScreen) and hits back from DecryptScreen, the `PopScope` on ReceiverScreen may not fire because the back navigation is handled by `DecryptScreen`'s own `PopScope` (if it has one). The nested screens' `PopScope` handlers will execute first, potentially consuming the back event before parent screens' handlers.
- Files: `lib/presentation/receiver/receiver_screen.dart` (PopScope implementation), `lib/presentation/receiver/receiver_transfer_screen.dart`, `lib/presentation/receiver/decrypt_screen.dart`
- Impact: If `DecryptScreen` has a `PopScope` that does not delegate to `SessionManager.wipeSession()`, back-navigation could bypass the parent kill-switch. However, current codebase appears to use navigation transitions (auto-push on transfer incoming) rather than nested PopScope chains, so risk is low.
- Recommendation: Document the navigation model clearly: are screens pushed/popped independently, or nested in a single Scaffold hierarchy? If nested, ensure each `PopScope` explicitly calls `SessionManager.wipeSession()` or delegates cleanly.

---

## Type Safety Gap: Firestore Data Casting

**Unsafe `as String?` casts when reading Firestore documents:**
- Issue: Throughout the codebase (e.g., `encryption_service.dart` line 245, `transfer_repository.dart` data reads), Firestore document data is cast to expected types without null-coalescing:
  ```dart
  final selectedSenderUid = userSnap.data()?['selectedSenderUid'] as String?;
  final status = snap.data()?['status'] as String?;
  ```
  If the Firestore document schema changes or a field is accidentally deleted, the cast will fail silently (returns `null`) rather than throwing a type error. A downstream comparison like `status == 'pending'` will be false, silently masking the missing field.
- Files: Multiple files — `lib/data/services/encryption_service.dart`, `lib/data/repositories/transfer_repository.dart`, `lib/presentation/receiver/receiver_transfer_screen.dart`
- Impact: Subtle bugs where missing fields are silently treated as null rather than surfacing as errors. For example, if `status` field is missing from a transfer doc, the receiver-status listener will not fire, and the sender will wait indefinitely for cleanup signals.
- Recommendation: Create typed Firestore models (e.g., `TransferModel`, `HandshakeModel`) with `.fromFirestore()` factory constructors that validate all required fields and throw `FormatException` if data is malformed. Replace all inline casts with `.fromFirestore()` calls.

---

## Pre-Release Checklist Items (from CLAUDE.md)

**Play Store Release Blockers:**
- [ ] Update `applicationId` from `com.example.cryptransfer` to final app ID (`android/app/build.gradle.kts`)
- Files: `android/app/build.gradle.kts`
- Impact: Current app ID is a placeholder. Play Store rejects re-releases with the same package name across different developer accounts. This must be updated before final submission.

**Thesis Documentation Pending:**
- [ ] Chapter 3 thesis update
- [ ] Chapter 5 testing results
- [ ] Fix figure numbering in thesis
- [ ] Fix shoutout in acknowledgements
- Impact: Thesis submission blockers, not app functionality.

---

*Concerns audit: 2026-05-25*
