# Concerns & Technical Debt
_Last updated: 2026-06-15_

---

## Critical Issues

### C-01: Static `_sessionSub` on `EncryptionService` (global singleton leak risk)
- **Files:** `lib/data/services/encryption_service.dart:378`
- **Issue:** `_sessionSub` is a `static` field on `EncryptionService`. If a user opens `ReceiverScreen` twice in the same app session (e.g., back-navigates and re-enters), `bindSession()` cancels the old sub and replaces it — but any concurrent `ReceiverScreen` instances would share the same static slot. A second `bindSession()` call silently cancels the first screen's kill-switch subscription, leaving session 1 without reactive crypto cleanup.
- **Impact:** Kill-switch may silently fail to fire `closeReceiverSession()` for the first session if two `ReceiverScreen` instances coexist in the navigation stack.
- **Fix approach:** Convert to an instance field, or assert that only one `ReceiverScreen` can be active at a time via a global guard.

### C-02: `ReceiverTransferScreen` lifecycle not observed by `SessionManager`
- **Files:** `lib/presentation/receiver/receiver_transfer_screen.dart`, `lib/presentation/receiver/receiver_screen.dart`
- **Issue:** Documented in CLAUDE.md (Known Open Issues). `ReceiverTransferScreen` receives `SessionManager` as a constructor argument and listens to `stateNotifier` for terminated state, but it does not call `didChangeAppLifecycleState`. If the user backgrounds the app while `ReceiverTransferScreen` is on screen, `ReceiverScreen.didChangeAppLifecycleState` fires `wipeSession()` but `ReceiverTransferScreen` has no observer — its crypto state (download buffers) may not be wiped before the OS suspends the process.
- **Impact:** Potential remanence of in-flight decrypt buffers when app is backgrounded mid-decrypt.
- **Fix approach:** Add `WidgetsBindingObserver` to `_ReceiverTransferScreenState`, or pass the existing `ReceiverScreen` lifecycle observer down as a callback.

### C-03: `compute()` isolate ciphertext is not zeroed
- **Files:** `lib/data/services/encryption_service.dart:73`, `lib/presentation/sender/sender_screen.dart:331`
- **Issue:** Documented in CLAUDE.md (Known Open Issues). After `compute(runAesGcmEncrypt, ...)` returns, a copy of the plaintext and an intermediate AES ciphertext live in the background isolate's heap. Dart isolates do not expose their heap for `fillRange` zeroing from the main isolate. The main-isolate copy is zeroed, but the isolate's copy survives until GC.
- **Impact:** Short-lived plaintext remanence window in compute isolate (seconds to minutes depending on GC timing). Accepted risk per CLAUDE.md.
- **Fix approach:** Platform limitation — no complete fix available without a C FFI crypto backend. Mitigation is already maximised (main-isolate zero-wipe + Kotlin GC hint).

---

## Security Concerns

### S-01: `allow list: if true` on `/users` collection (unauthenticated user enumeration)
- **Files:** `firestore.rules:24`
- **Issue:** The `users` collection allows `list` for all callers (no auth check) to support username availability checks during registration. Any unauthenticated actor can enumerate all usernames and UIDs by listing the collection.
- **Impact:** Email-to-UID mapping, username harvesting, reconnaissance for targeted attacks.
- **Mitigation in place:** `allow get` requires auth; `list` only returns the fields written to the doc (username, email, phone, publicKey). No password hashes or tokens are stored here.
- **Fix approach:** Move username availability check to a Firebase Function that performs the query server-side, then restrict `list: if isAuthenticated()`. This removes the unauthenticated surface without breaking UX.

### S-02: Username search returns exact-only match (broken prefix search)
- **Files:** `lib/data/repositories/key_repository.dart:41-43`
- **Issue:** `searchUsers()` uses `isGreaterThanOrEqualTo: q` AND `isLessThanOrEqualTo: q` with the same value. This is an exact-match query, not a prefix search. The intended Firestore prefix pattern would be `isLessThanOrEqualTo: q + ''`.
- **Impact:** Users cannot discover friends by typing a partial username. The feature appears functional but silently requires exact matches. A confused user may send connection requests to the wrong person if names are similar.
- **Fix approach:** Change to `isLessThanOrEqualTo: '${q}'` for correct prefix search.

### S-03: `closeReceiverSession()` uses multiple serial Firestore reads/batches
- **Files:** `lib/data/services/encryption_service.dart:238-351`
- **Issue:** The kill-switch performs 4 sequential Firestore read-then-batch operations (user doc read, handshake delete, sender-handshake delete, transfers delete, notifications delete). Each is a separate round trip. If the device loses network after step 2, steps 3–5 are not rolled back, leaving orphaned handshake docs or stale transfer records.
- **Impact:** Stale handshake documents in Firestore; sender may appear to still have an authorized receiver after a network-interrupted kill-switch. The sender stream would not revert to waiting state.
- **Fix approach:** Convert the sequential cleanup into a Firestore batch or transaction where possible. Add a server-side Cloud Function triggered by `isReadyToReceive = false` to clean up orphaned docs.

### S-04: `BiometricHelper.authenticate()` falls back to `true` when no biometrics enrolled
- **Files:** `lib/core/utils/biometric_helper.dart:32-35`
- **Issue:** When `canCheckBiometrics` returns `false` (no enrolled biometrics, PIN-only device), the method returns `true` without any authentication — the AES-key RSA encryption step is silently skipped. This means the sender can encrypt the AES key without any authentication gate on devices without biometrics.
- **Impact:** On devices with PIN-only lock screens (or emulators), the biometric gate offers no protection. An attacker with temporary physical access to an unlocked device can send an encrypted file without biometric confirmation.
- **Fix approach:** On `canAuth == false`, prompt for device credential (PIN/pattern) using `local_auth`'s `deviceCredential` option, or show a warning dialog requiring explicit user acknowledgment.

### S-05: `debugPrint` in `EncryptionService._logSecurityEvent` leaks event details to console in production
- **Files:** `lib/data/services/encryption_service.dart:411`
- **Issue:** `debugPrint('🛡️ [$timestamp] $event | $details')` is called on every security lifecycle event. `debugPrint` is compiled into release builds (it only no-ops if `kDebugMode` is `false` in Flutter, but the call site does not gate on `kDebugMode`). Security event names (not key material) appear in logcat on release builds.
- **Impact:** Low severity — event names only, no key bytes. However, logcat-reading malware or ADB-connected devices can observe session open/close timing.
- **Fix approach:** Wrap with `if (kDebugMode) debugPrint(...)` or remove entirely since events are already persisted to Firestore.

### S-06: Extensive use of silent `catch (_) {}` swallows security-critical failures
- **Files:** `lib/presentation/receiver/decrypt_screen.dart` (6 instances), `lib/presentation/receiver/receiver_transfer_screen.dart` (7 instances), `lib/presentation/sender/sender_transfer_screen.dart` (6 instances), `lib/data/services/encryption_service.dart:384,420`
- **Issue:** Cleanup steps critical to zero-remanence (e.g., `await _transferRepo.deleteStorageFile(...)`, `await EncryptionService.closeReceiverSession(...)`) are inside `try { ... } catch (_) {}` blocks that swallow all exceptions silently. A Firestore permission error, network failure, or code bug during cleanup is invisible — no log, no audit event, no user feedback.
- **Impact:** Silent cleanup failures mean encrypted files may remain in Firebase Storage, handshake docs may persist in Firestore, and the receiver's public key may not be deleted — without any indication to the user or admin.
- **Fix approach:** Replace `catch (_) {}` with `catch (e) { _logSecurityEvent('cleanup_failed', uid, e.toString()); }` for all zero-remanence cleanup paths.

### S-07: `sendConnectionRequest()` bypasses `neutral_handshakes` flow and sets `status: 'accepted'` directly
- **Files:** `lib/data/repositories/key_repository.dart:67-120`
- **Issue:** `sendConnectionRequest()` writes `status: 'accepted'` to both users' `friendships` sub-collections in a single `WriteBatch` without any consent from the target user. This is a legacy path that bypasses the proposal-acceptance flow in `HandshakeRepository`. It is not called from visible UI (the active connection flow uses `HandshakeRepository.sendProposal()`), but the method still exists and could be called from tests or future code.
- **Impact:** Potential unauthorized friendship creation if `sendConnectionRequest()` is called by mistake or re-wired. The Firestore rules (`friendships` write: `if uid == userId || uid == friendId`) would permit this write.
- **Fix approach:** Delete or `@Deprecated` the method to prevent accidental use; ensure all connection creation routes through `HandshakeRepository`.

### S-08: `getPendingRequests()` and `acceptConnectionRequest()` are empty stubs
- **Files:** `lib/data/repositories/key_repository.dart:122-124`
- **Issue:** `getPendingRequests() async => []` and `acceptConnectionRequest(String docId, String senderId) async {}` are no-op stubs. If any screen or test accidentally calls these, it silently succeeds with empty/no data.
- **Impact:** Dead code risk; any refactor that re-enables these paths would appear to work while doing nothing.
- **Fix approach:** Add `throw UnimplementedError('Use HandshakeRepository instead')` to prevent silent misuse.

---

## Performance Concerns

### P-01: N+1 Firestore reads in `getSentKeyTransfers()` and `getReceivedKeys()`
- **Files:** `lib/data/repositories/key_repository.dart:231-300`
- **Issue:** Both methods fetch a collection snapshot then loop over each doc, making one additional `users/{uid}.get()` call per document to resolve the username. With N handshake docs, this is N+1 sequential Firestore reads.
- **Impact:** On the RSA Key Manager screen (vault), load time scales linearly with the number of key transfers. At 20+ transfers, this can take 2–4 seconds on a slow connection.
- **Fix approach:** Denormalize `username` into the handshake doc at write time (already done for `receiverUsername`/`fromUsername` in newer paths) and read it directly without the extra user doc fetch.

### P-02: Admin dashboard `streamTotalTransfers()` and `streamTotalUsers()` download all documents
- **Files:** `lib/data/repositories/admin_repository.dart:32-42`
- **Issue:** Documented in code as `KNOWN LIMITATION (WR-02)`. Both streams download the full collection on every snapshot emission to count documents via `s.size`. As the platform grows, `audit_logs` collectionGroup and `users` collection become unbounded reads.
- **Impact:** At 10K users × 2 audit log entries each = 20K document reads per admin dashboard refresh. Firebase read cost scales linearly; Firestore billing impact becomes significant.
- **Fix approach:** Upgrade `cloud_firestore` to `>=4.0.0` and use `AggregateQuery.count()` for server-side counting. Already documented as the target fix in the TODO comments.

### P-03: `fetchUserConnections()` in admin makes up to 50 sequential sub-collection reads
- **Files:** `lib/data/repositories/admin_repository.dart:97-128`
- **Issue:** Batched in groups of 10 (good), but each group still fires 10 parallel sub-collection reads to `users/{uid}/friendships WHERE status=accepted`. At 50 users that is 50 Firestore reads per admin dashboard tab open.
- **Impact:** Slow connection node map load on the Admin Dashboard. Each read round-trip adds latency.
- **Fix approach:** Store `connectionCount` as a denormalized counter on the user document, updated via WriteBatch on connect/disconnect. Remove the sub-collection fan-out entirely.

### P-04: `getAvailableReceivers()` also has N+1 reads
- **Files:** `lib/data/repositories/key_repository.dart:382-415`
- **Issue:** Fetches `handshakes WHERE senderId==uid` then for each doc does a separate `users/{receiverId}.get()` to resolve user profile data.
- **Impact:** Used in RSA vault screen sender list. Same scaling issue as P-01.
- **Fix approach:** Same denormalization approach — include `receiverUsername` and `receiverEmail` in the handshake document at creation time.

### P-05: `FirestoreMigration.initializeCollections()` runs on every app startup
- **Files:** `lib/services/firestore_migration.dart`
- **Issue:** Called from `main.dart` on every app launch. It issues at least 2 Firestore reads (`handshakes.limit(1).get()` + `neutral_handshakes.limit(1).get()`) even after collections are confirmed to exist.
- **Impact:** Adds 2 cold-start Firestore reads per launch. Minor cost and latency, but unnecessary.
- **Fix approach:** Gate behind a `SharedPreferences` boolean `migrations_complete` that is set once and skipped thereafter.

---

## Technical Debt

### T-01: `SenderScreen` is 1572 lines — monolith screen widget
- **Files:** `lib/presentation/sender/sender_screen.dart`
- **Issue:** At 1572 lines, `SenderScreen` combines file picking, encryption orchestration, TOFU key verification, readiness timer, stream management, navigation, and 4-step UI all in one `StatefulWidget`. The `_SenderScreenState` carries 20+ instance fields.
- **Impact:** Hard to test individual concerns in isolation; PR reviews touch the whole file for small changes; high risk of regressions when modifying one flow.
- **Fix approach:** Extract into sub-widgets (`_WaitingForConnectionWidget` already exists as a start), dedicated `SenderViewModel`/controller, and move crypto orchestration to a coordinator class.

### T-02: `HomeScreen` is 1346 lines with mixed UI and business logic
- **Files:** `lib/presentation/home/home_screen.dart`
- **Issue:** `_HomeScreenState` manages 6 `StreamSubscription`s, overlay banner logic, connection stream merging, role picker navigation, snackbar helpers, and the full build tree. Business logic is interleaved with widget code.
- **Impact:** Fragile when adding features; `_outcomeSubs` map-based dynamic subscription management is easy to leak.
- **Fix approach:** Extract stream management to a `HomeViewModel` or `ChangeNotifier`; move banner overlay logic to a dedicated `BannerService`.

### T-03: `ReceiverScreen` state machine is implicit (20+ `bool` flags)
- **Files:** `lib/presentation/receiver/receiver_screen.dart`
- **Issue:** `_ReceiverScreenState` tracks session state through a large set of independent booleans: `_isReadyToReceive`, `_isTogglingReady`, `_handshaking`, `_handshakeDone`, `_sessionLocked`, `_incomingHandled`, `_senderPresenceConfirmed`. Invalid combinations (e.g., `_handshakeDone && !_isReadyToReceive`) are possible and not guarded.
- **Impact:** Subtle state bugs are hard to reproduce; the booleans do not enforce legal transitions. The existing `SessionState` enum in `SessionManager` covers only the crypto layer, not the UI layer.
- **Fix approach:** Introduce a `ReceiverUiState` sealed class / enum covering the full UI lifecycle: `initial → keysReady → mailboxOpen → senderSelected → handshakeDone → transferIncoming → locked`.

### T-04: `firestore_migration.dart` writes a sentinel doc on first run
- **Files:** `lib/services/firestore_migration.dart:40-49`
- **Issue:** Creates a `handshakes/_sentinel` document then immediately deletes it to "initialize" the collection. Firestore collections are created lazily on first real document write — the sentinel is unnecessary and creates a write that may trigger security rule evaluations.
- **Impact:** Wasteful write on first install; `_sentinel` delete may fail silently if Firestore rules deny it.
- **Fix approach:** Remove the sentinel initialization entirely; let the first real handshake doc creation initialize the collection.

### T-05: Legacy `sendConnectionRequest()` in `KeyRepository` co-exists with `HandshakeRepository`
- **Files:** `lib/data/repositories/key_repository.dart:67-120`
- **Issue:** Two parallel connection-creation systems exist: the legacy `sendConnectionRequest()` (sets `accepted` directly, no consent flow) and the active `HandshakeRepository.sendProposal()` (full accept/reject lifecycle). The legacy path is dead code from the UI perspective but still compiles.
- **Impact:** New developers may call the wrong method; future refactors may accidentally re-activate it.
- **Fix approach:** Delete `sendConnectionRequest()`, `getPendingRequests()`, and `acceptConnectionRequest()` from `KeyRepository`. Update any tests referencing them.

### T-06: `print()` calls in production code (`biometric_helper.dart`, `firestore_migration.dart`)
- **Files:** `lib/core/utils/biometric_helper.dart:1,18,31,33,36,42,45`, `lib/services/firestore_migration.dart:24,26,49,51,54,64,66`
- **Issue:** Both files suppress the `avoid_print` lint with `// ignore_for_file: avoid_print` and use `print()` directly. These statements appear in release builds and pollute logcat output with internal auth flow details.
- **Impact:** Auth flow timing and biometric availability leaked to any logcat reader.
- **Fix approach:** Replace with `debugPrint()` wrapped in `if (kDebugMode)`, or remove entirely since the information is diagnostic-only.

### T-07: `TransferService.resolve()` falls back to loading the full file into memory on web
- **Files:** `lib/data/services/transfer_service.dart:104-111`
- **Issue:** When `filePath` is null (web platform), `resolve()` returns `fallbackBytes` directly — the entire file already in memory from `FilePicker.pickFiles(withData: true)`. No chunked reading is possible on web due to browser API limitations. The 64 KB chunking benefit is only available on mobile/desktop.
- **Impact:** Web users sending large files hit the same peak-memory problem that chunked reads were designed to solve. 100 MB file = 100 MB heap allocation on web.
- **Fix approach:** Document the web limitation explicitly; consider streaming encrypt-and-upload using browser `ReadableStream` API via `dart:js_interop` for future web support.

---

## Fragile Areas

### F-01: 60-second readiness timer in `SenderScreen` ejects user silently if receiver is slow
- **Files:** `lib/presentation/sender/sender_screen.dart:515-526`
- **Issue:** `_startReadinessTimer()` starts a 60-second countdown when a receiver is selected but `receiverReady == false`. If the receiver takes more than 60 seconds to open their mailbox, the sender is ejected to HomeScreen with only a snackbar. The timer restarts on `_revertToWaiting()` but not always — if the stream is in a settled state, the timer may not restart.
- **Impact:** UX surprise — sender loses all encryption progress without clear explanation.
- **Fix approach:** Make the timeout user-adjustable, or show a warning at T-10s before ejecting. Allow the sender to dismiss rather than auto-eject.

### F-02: Stale transfer doc timestamp filter relies on 30-second clock drift assumption
- **Files:** `lib/presentation/receiver/receiver_screen.dart:464-477`
- **Issue:** `_handleIncomingTransfer` rejects docs created more than 30 seconds before `_sessionStartedAt`. Server timestamps (`FieldValue.serverTimestamp()`) and client `DateTime.now()` are compared — on devices with significant clock drift, legitimate transfers may be rejected, or stale session docs may be accepted.
- **Impact:** Rare but possible: on a device with >30s clock drift, a transfer arrives from the current session but is rejected as "stale". User sees no transfer notification.
- **Fix approach:** Use `_sessionStartedAt` as set from a Firestore server timestamp (written by `setupReceiverSession`) instead of a client-side `DateTime.now()`.

### F-03: `_incomingHandled` flag not reset on partial session close
- **Files:** `lib/presentation/receiver/receiver_screen.dart:59,314`
- **Issue:** `_incomingHandled` is set to `true` when an incoming transfer is detected, blocking re-entry. It is reset in `_onToggleReady(false)` but NOT in `_sessionManager.reset()` or during sender-abandoned flows. If the sender abandons mid-handshake (before transfer creation), `_incomingHandled` may remain `true`, blocking detection of the next transfer in the same session.
- **Impact:** Receiver appears stuck after a sender abandons; a new transfer from a different sender in the same mailbox-open session is silently ignored.
- **Fix approach:** Reset `_incomingHandled = false` in the sender-abandoned path (`_startSenderPresenceWatch` handler) and in `_sessionManager.clearSender()`.

### F-04: `EncryptionService.bindSession()` swallows `closeReceiverSession` errors
- **Files:** `lib/data/services/encryption_service.dart:384`
- **Issue:** `closeReceiverSession(uid).catchError((_) {})` — if the kill-switch crypto cleanup fails (network error, Firestore permission denied), the error is silently ignored. The `_sessionSub` is cancelled, so no retry is attempted.
- **Impact:** On network interruption during kill-switch, the receiver's public key may not be deleted from Firestore, leaving the account in a falsely-ready state.
- **Fix approach:** Log the error to the security audit log and surface a retry mechanism (or schedule a background retry via `WorkManager`/iOS background task).

### F-05: `PopupMenuButton` disconnect in `FindFriendsScreen` has no confirmation spinner
- **Files:** `lib/presentation/home/find_friends_screen.dart`
- **Issue:** The disconnect flow shows a confirmation dialog, but after the user confirms, the `disconnectFromUser()` call is fired with no loading indicator. If the write takes >1s on a slow connection, the user sees no feedback and may tap again.
- **Impact:** Potential double-disconnect attempts; UI appears frozen.
- **Fix approach:** Add a `_disconnecting` state flag per tile, show a `CircularProgressIndicator`, and disable the button while in flight.

---

## Dependencies

### D-01: `cloud_firestore: ^6.2.0` — below the version that enables `AggregateQuery`
- **Package:** `cloud_firestore ^6.2.0`
- **Risk:** The `AggregateQuery.count()` API (already identified as the fix for WR-02) requires `cloud_firestore >=4.0.0` with the Firebase project's AggregateQuery API enabled. The version pinned is `^6.x`, so the package version is not the blocker — but the Firebase project-level API must be explicitly enabled in the Firebase Console.
- **Impact:** Admin dashboard WR-02 cannot be fixed without Firebase Console change. Current fix is a full document download for counts.
- **Migration plan:** Enable AggregateQuery in Firebase Console → replace `streamTotalTransfers()`/`streamTotalUsers()` with `collectionGroup.count().get()`.

### D-02: `pointycastle: ^4.0.0` — no native AES hardware acceleration
- **Package:** `pointycastle ^4.0.0`
- **Risk:** PointyCastle is a pure-Dart cryptography library. It does not use Android's hardware-backed keystore or iOS's Secure Enclave. AES-GCM encryption runs entirely in Dart, without hardware acceleration. For 100 MB files, AES-GCM in `compute()` takes 3–8 seconds on mid-range devices.
- **Impact:** Slower encryption on large files; keys are not protected by the hardware keystore (only `flutter_secure_storage` provides OS-level protection for the stored private key).
- **Migration plan:** Evaluate `cryptography` package or native FFI bridge to AES hardware for performance-critical path. RSA key operations could move to Android Keystore for hardware-backed private key storage.

### D-03: `file_picker: ^11.0.2` — web `withData: true` loads entire file into memory
- **Package:** `file_picker ^11.0.2`
- **Risk:** On web, `FilePicker.pickFiles(withData: true)` is required for byte access, loading the full file into browser memory before the app sees it. This is a package-level constraint, not addressable without replacing the package.
- **Impact:** 100 MB file = 200 MB peak browser memory (picked file + encrypt buffer). Web support for large files is inherently memory-constrained.
- **Migration plan:** Accept as a platform limitation for the current scope (mobile-first app).

### D-04: `local_auth: ^3.0.1` — `biometricOnly: false` parameter is deprecated
- **Package:** `local_auth ^3.0.1`
- **Risk:** `lib/core/utils/biometric_helper.dart:40` passes `biometricOnly: false`. In `local_auth` v2.x+, this parameter's behavior has shifted; the correct approach is to use `authMessages` and `options` parameters. A future version may remove `biometricOnly`.
- **Impact:** Biometric authentication may behave unexpectedly on future OS versions or when `local_auth` is upgraded.
- **Migration plan:** Migrate to the `options: AuthenticationOptions(biometricOnly: false)` API pattern on next `local_auth` upgrade.

---

## Known Bugs

### B-01: Username search only returns exact matches (not prefix matches)
- **Symptoms:** Typing "alice" does not find user "alice_sender"; only `"alice"` exact match returns results.
- **Files:** `lib/data/repositories/key_repository.dart:41-43`
- **Trigger:** Any partial username typed in the `FindFriendsScreen` search bar.
- **Workaround:** Type the complete, exact username.

### B-02: `RsaKeyManagerScreen` progress dialog may appear before or after the generate operation
- **Files:** `lib/presentation/vault/rsa_key_manager_screen.dart:85-90`
- **Trigger:** `addPostFrameCallback` schedules `_showProgressDialog` one frame after `_onRegenerate` starts. If RSA generation (in `compute()`) completes before the frame renders, `dialogShown` is still `false` when the success branch runs, so the `Navigator.pop()` is skipped — the dialog may be shown and never dismissed.
- **Symptoms:** "Generating RSA-2048 keypair…" spinner appears and stays open after generation completes on fast devices.
- **Workaround:** Tap the back button to dismiss; the key was generated successfully.

### B-03: Sender `_revertToWaiting()` calls `_startReadinessTimer()` unconditionally
- **Files:** `lib/presentation/sender/sender_screen.dart:265`
- **Trigger:** When the receiver closes their mailbox while the sender is in the `_revertToWaiting()` flow, `_startReadinessTimer()` is called even when `_receiverId` is `null` (discovery mode, no receiver pre-filled). This starts a 60-second countdown that ejects the user to HomeScreen even though no receiver was ever paired.
- **Symptoms:** After a receiver abandons, sender is unexpectedly ejected after 60 seconds instead of staying on the screen.
- **Workaround:** Re-enter `SenderScreen` from Home to restart the session.

---

## Test Coverage Gaps

### G-01: No integration tests for the full sender → receiver transfer pipeline
- **What's not tested:** End-to-end flow: sender encrypts → uploads → receiver decrypts → zero-remanence cleanup. All tests use mocked Firestore (`fake_cloud_firestore`) which does not execute Firestore security rules.
- **Files:** `test/module_tests/transfer_test.dart`, `test/module_tests/session_test.dart`
- **Risk:** Security rule regressions (e.g., PERMISSION_DENIED breaking cleanup) go undetected until UAT.
- **Priority:** High

### G-02: `closeReceiverSession()` multi-step failure scenarios untested
- **What's not tested:** Behaviour when individual cleanup steps in `closeReceiverSession()` fail mid-sequence (e.g., handshake batch delete fails, but user doc update succeeded). The partial-failure state is not covered.
- **Files:** `lib/data/services/encryption_service.dart:238-351`
- **Risk:** Silent Firestore orphan docs with no recovery path.
- **Priority:** High

### G-03: `BiometricHelper` fallback path (no biometrics → returns `true`) untested
- **What's not tested:** That the sender can bypass biometric auth on devices without enrolled biometrics, and that this is intentional, not a regression.
- **Files:** `lib/core/utils/biometric_helper.dart`, `test/` (no biometric test file)
- **Risk:** If `local_auth` changes behavior on a platform update, the bypass may silently change to blocking.
- **Priority:** Medium

### G-04: Admin dashboard reads (unbounded count queries) untested for cost regression
- **What's not tested:** That `streamTotalTransfers()` and `streamTotalUsers()` stay within acceptable read limits as the dataset grows. No mock with large datasets.
- **Files:** `lib/data/repositories/admin_repository.dart`, `test/admin/admin_repository_test.dart`
- **Risk:** Surprise Firebase billing spike as user count grows.
- **Priority:** Medium

### G-05: TOFU `keyChanged` block path has no UI-level test
- **What's not tested:** When `TofuStatus.keyChanged` is detected in `SenderScreen`, the sender is supposed to be blocked from proceeding until explicit re-verification. No test confirms the UI blocks the encrypt-AES-key step.
- **Files:** `lib/core/utils/tofu_service.dart`, `lib/presentation/sender/sender_screen.dart`
- **Risk:** TOFU key-pinning bypass if the block condition is accidentally removed in a refactor.
- **Priority:** High (security-critical path)

---

*Concerns audit: 2026-06-15*
