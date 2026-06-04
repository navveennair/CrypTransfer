# CrypTransfer — Project Roadmap

### Phase 11: Admin Dashboard Security & Efficiency Hardening

**Goal:** Harden the admin dashboard layer across 7 identified issues: close the CRITICAL unguarded /admin-dashboard route (AdminGuard widget), fix SERIOUS missing adminUid in setUserActiveStatus audit log, replace MEDIUM fake TransferVolumeChart sawtooth with real 7-day Dart aggregation, consolidate MEDIUM N parallel Firestore streams in ConnectionNodeMap to a single FutureBuilder, add MEDIUM .limit() pagination to unbounded admin streams, add MEDIUM snapshot.hasError branches to all admin StreamBuilders, and MINOR remove 3 dead AdminRepository methods.
**Requirements**: D-01 through D-12 (locked decisions in 11-CONTEXT.md)
**Depends on:** Phase 10
**Plans:** 5 plans

Plans:
- [ ] 11-01-PLAN.md — Wave 0: Test scaffold (admin_guard_test.dart, admin_repository_test.dart, chart_aggregation_test.dart)
- [ ] 11-02-PLAN.md — Wave 1: AdminRepository hardening (D-04 adminUid, D-08 fetchUserConnections, D-11 dead method removal, D-12 limits)
- [ ] 11-03-PLAN.md — Wave 2: Presentation hasError branches + TransferVolumeChart real aggregation (D-05/D-06/D-10)
- [ ] 11-04-PLAN.md — Wave 2 (parallel): ConnectionNodeMap FutureBuilder conversion (D-07/D-08/D-09)
- [ ] 11-05-PLAN.md — Wave 3: AdminGuard route guard — new file + main.dart wire-up (D-01/D-02/D-03)

---

## Milestone v1.0: milestone

### Phase 02: ReceiverTransferScreen Hardening & Memory Safety
**Goal:** Harden the receiver-side transfer flow with session propagation, memory safety, and lifecycle kill-switch integration.
**Status:** Complete

### Phase 03: Managed Profile & RSA Vault
**Goal:** Implement a biometric-gated RSA Key Manager (Vault) as a zero-remanence proof-check, initialize a `profile` subcollection on user creation, and harden Firestore security rules for the new `rsa_key_manager` subcollection.
**Status:** Complete

**Depends on:** Phase 02

**Plans:**
- [x] 03-01: Analyzer fix + test scaffold (Wave 0) — 21 errors resolved, test/vault/ created with 5 Nyquist stubs
- [x] 03-02: Profile subcollection + auth registration (Wave 1) — FirebaseConstants rsaKeyManager/profile constants + WriteBatch atomic profile init
- [x] 03-03: RSA Vault key lifecycle (Wave 2) — computeFingerprint (SHA-256), regenerateKeyPair (3-doc WriteBatch), deleteKeyPair (2-doc WriteBatch), updateLastVaultAccess (merge-safe upsert)
- [x] 03-04: RsaKeyManagerScreen + biometric gate (Wave 3) — biometric-gated vault UI, StreamBuilder key status, CrypButton Regenerate/Delete, fingerprint via AuthRepository.computeFingerprint()
- [x] 03-05: ReceiverScreen banner + Firestore rules hardening (Wave 4) — amber no-keys banner, Key Vault drawer entry, rsa_key_manager/profile Firestore rules
- [x] 03-06: Gap closure — deploy Firestore rules + fix deleteKeyPair() ordering (UAT tests 3/4/5 blocker)

### Phase 4: Zero Remanence reactive session termination: Receiver as Master Cleanup (WriteBatch atomic delete of Transfer + AESKey docs, purge local RSA keys + handshake from secure storage, redirect to SessionEndedScreen). Sender Reactive Listener (StreamListener on Transfers/{sessionId} — when document no longer exists, zero AES key from local memory/secure storage, navigate to SessionEndedScreen). No 'End Session' button on sender side.

**Goal:** [To be planned]
**Requirements**: TBD
**Depends on:** Phase 3
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 4 to break down)

### Phase 05: Neutral Handshake Model — Separate Connection from Role Assignment
**Goal:** Refactor the CrypTransfer connection architecture to a neutral Handshake model that decouples "Establishing a Connection" from "Defining Sender/Receiver Roles." Introduces `proposerId`/`partnerId` semantics, a pending-approval flow with global listener and approval UI, and defers role selection (Send/Receive) to the moment a user taps an active connection.

**Status:** Executing

**Depends on:** Phase 04

**Scope:**
1. **Neutral Handshake Data Model** — Rename `senderId`/`receiverId` in handshake logic to `proposerId` (initiator) and `partnerId` (recipient). Default `status: 'pending'`.
2. **Firestore Security Rules** — Update Handshakes collection rules: create allowed for `proposerId == auth.uid`; read for either party; update allowed for `partnerId` only, restricting new status to `connected` or `rejected`.
3. **Global Listener & Approval UI** — HomeController/NavigationWrapper listens for `partnerId == currentUser.uid && status == 'pending'`. Shows approval dialog; Accept → `connected`, Reject → `rejected`. Proposer sees 5-second fading notification of outcome.
4. **Role Bridge** — On `connected`, add to Active Connections list. Clicking an Active Connection presents [Send File] / [Receive File] choice. Role selection initializes the Transfer document (assigns `senderId`/`receiverId`) and triggers the Zero Remanence session.

**Status:** Complete

**Plans:** 7 plans

Plans:
- [x] 05-01-PLAN.md — Wave 0 test scaffold: handshake_repository_test.dart (HAND-01–05), sender_prefill_test.dart (HAND-07), receiver_prefill_test.dart (HAND-08)
- [x] 05-02-PLAN.md — Wave 1 data layer: HandshakeRepository (CRUD + streams), FirebaseConstants.neutralHandshakes, Firestore neutral_handshakes rules block
- [x] 05-03-PLAN.md — Wave 1 (parallel) session screen integration: SenderScreen.preFilledPartnerUid, ReceiverScreen.preFilledSenderUid pre-fill params
- [x] 05-04-PLAN.md — Wave 2 HomeScreen restructure: Active Connections + Pending Requests sections, _ProposalBanner listener, _RolePickerSheet, retire role buttons
- [x] 05-05-PLAN.md — Gap closure: transfers Firestore rule neutral_handshakes auth (CR-01), repo/UI hardening (WR-01–07), stream tests (IN-01, IN-02, IN-04)
- [x] 05-06-PLAN.md — Gap closure: home_screen.dart bug fixes — Accept spinner reset, hasError branch, stream deduplication, InkWell removal (UAT tests 4, 5, 8)
- [x] 05-07-PLAN.md — Gap closure: receiver prefill ordering fix — _pendingPrefilledSender deferred to _onToggleReady(true) (UAT test 10)

### Phase 06: Synchronized Readiness Gate
**Goal:** Ensure the Sender cannot encrypt or pick files until the Receiver has prepared their cryptographic environment. Bridges the Neutral Handshake model to the Transfer flow with a bidirectional readiness protocol.

**Depends on:** Phase 05

**Scope:**
1. **Data Model Update** — Add `receiverReady: false` and `senderReady: false` boolean fields to the Transfers model; initialize both when the transfer document is first created.
2. **Receiver-Side Trigger** — Once the receiver completes Stepper 3 (RSA keys generated and public key confirmed in Firestore), update the active Transfers document to set `receiverReady: true`.
3. **Sender-Side Gate** — Disable all navigation/Next buttons immediately after session init; add a real-time stream listener on the `receiverReady` field; show a pulsing "Waiting for Receiver to prepare secure vault..." UI while `false`; on `receiverReady == true` show a snackbar "Secure channel established. Receiver is ready." and auto-advance the sender stepper.
4. **Safety & Cleanup** — If the Transfers document is deleted or status becomes `rejected` while the Sender is waiting, kick the Sender back to HomeScreen with a "Session Terminated" notification after a 1-minute timer.

**Plans:** 3 plans

Plans:
- [x] 06-01-PLAN.md — Wave 1: KeyRepository data layer — selectSenderHandshake returns Future<String>, new setReceiverReady() method
- [x] 06-02-PLAN.md — Wave 2: ReceiverScreen trigger — _onSenderSelected captures docId, _writeReceiverReady() with retry SnackBar
- [x] 06-03-PLAN.md — Wave 2 (parallel): SenderScreen gate — _receiverReady state, _WaitingForReceiverWidget, countdown timer, Steps 1-4 AnimatedOpacity gate, eject logic

### Phase 07: Sender Reactive Cleanup Sync
**Goal:** Implement a real-time stream on SenderScreen that listens to the receiver's cleanup status after a successful transfer. When the receiver (master) marks cleanup complete in Firestore, the sender verifies and wipes its own critical key/hashed data, then both parties navigate back to HomeScreen. Update Firebase security rules to grant the sender the necessary delete/write permissions for its cleanup documents.

**Depends on:** Phase 06

**Scope:**
1. **Firestore Cleanup Signal** — Define a cleanup status field or document that the receiver writes when its cleanup is complete (e.g., `cleanupComplete: true` on the transfer doc, or a dedicated `session_cleanup/{sessionId}` document). Sender streams this field.
2. **Sender Stream Listener** — On `TransferProgressScreen` / "File sent successfully" state, attach a `StreamSubscription` on the receiver's cleanup signal. While waiting, show a "Waiting for receiver to complete secure cleanup..." UI (pulsing indicator).
3. **Sender Cleanup Logic** — When the stream emits `cleanupComplete: true`, sender: (a) verifies AES key doc is deleted from Firestore; (b) wipes local AES key bytes from memory (zero-fill); (c) deletes its own sender-side transfer artifacts if any remain; (d) navigates to HomeScreen.
4. **Firebase Security Rules** — Extend Firestore rules to allow the sender to read the cleanup signal document and delete/update any sender-owned transfer artifacts needed for cleanup.
5. **Safety Timeout** — If the receiver cleanup signal is not received within a configurable timeout, sender auto-wipes local keys and navigates home with a "Session ended by timeout" notification.

**Status:** Complete

**Plans:** 1 plan

Plans:
- [x] 07-01-PLAN.md — Wave 1: pulsing waiting UI + 300s safety timeout — TransferProgressScreen + SenderSessionEndedScreen timeoutReason

### Phase 07.1: Layer Decoupling Refactor
**Goal:** Fix critical layer coupling violations where the Presentation Layer calls `FirebaseFirestore.instance` directly instead of delegating to the Repository layer. After this phase, all Firestore operations are centralized in Repositories, enabling schema changes without edits to 14 UI files, centralizing security filters, and enabling unit testing of screens.

**Status:** ✅ Complete

**Depends on:** Phase 07

**Plans:** 4 plans

Plans:
- [x] 07.1-01-PLAN.md — Wave 0: Repository expansion — CleanupRepository (3 methods), TransferRepository (6+1 methods), AdminRepository (4 methods), UserRepository (2 methods)
- [x] 07.1-02-PLAN.md — Wave 1: Transfer screens migration — transfer_progress_screen (6 calls), sender_session_ended_screen (2 calls), sender_screen (1 call), receiver_transfer_screen (2 calls), receiver_screen (2 calls), decrypt_screen (2 calls), home_screen (1 call)
- [x] 07.1-03-PLAN.md — Wave 2: Cleanup screen migration — receiver_end_session_screen (4 calls) using CleanupRepository, preserving D-03 order
- [x] 07.1-04-PLAN.md — Wave 3: Admin & misc screens — admin_dashboard (3 calls), admin_dashboard_screen (1 call), connection_node_map (2 calls), security_pulse_feed (1 call), transfer_volume_chart (1 call), onboarding_screen (1 call)

**Success Criteria Met:**
- [x] Zero `FirebaseFirestore.instance` calls in `lib/presentation/` (except 3 in security-critical Step 0 audit batch)
- [x] 15 new Repository methods created and tested
- [x] 14 UI files refactored to use Repositories
- [x] `flutter analyze` returns "No issues found"
- [ ] D-03 cleanup order preserved in receiver_end_session_screen.dart

**Plans:** 4 plans

Plans:
- [ ] 07.1-01-PLAN.md — Wave 0: Repository expansion — CleanupRepository (3 methods), TransferRepository (7 methods), AdminRepository (4 methods), UserRepository (2 methods)
- [ ] 07.1-02-PLAN.md — Wave 1: Transfer screens migration — transfer_progress_screen (6 calls), sender_session_ended_screen (2 calls), sender_screen (1 call), receiver_transfer_screen (2 calls), receiver_screen (2 calls), decrypt_screen (2 calls), home_screen (1 call)
- [ ] 07.1-03-PLAN.md — Wave 2: Cleanup screen migration — receiver_end_session_screen (4 calls) using CleanupRepository, preserving D-03 order
- [ ] 07.1-04-PLAN.md — Wave 3: Admin & misc screens — admin_dashboard (3 calls), admin_dashboard_screen (1 call), connection_node_map (2 calls), security_pulse_feed (1 call), transfer_volume_chart (1 call), onboarding_screen (1 call)

### Phase 8: applicationId rename — replace com.example.cryptransfer with production package across android/app/build.gradle.kts (applicationId), Kotlin package + directory (MainActivity.kt), MethodChannel namespace com.example.cryptransfer/security (referenced in MainActivity.kt and lib/core/utils/security_lifecycle_mixin.dart), regenerated google-services.json from Firebase project cryptransfer-96e9f, and any -keep rules in android/app/proguard-rules.pro that reference the old package. Pre-release Play Store blocker per .planning/codebase/CONCERNS.md §3. Must remain regression-free: flutter analyze clean, full test suite passes, FLAG_SECURE pre-flight still functional, kill-switch reactive binding intact.

**Goal:** Rename Android `applicationId` from `com.example.cryptransfer` to `com.navveennair.cryptransfer` across all coupled touchpoints (Gradle namespace/applicationId, Kotlin package + physical directory, MethodChannel namespaces decoupled per D-04 to package-independent `cryptransfer/{security,file}`, multi-app `google-services.json`, `firebase_options.dart` iosBundleId, delete old `com/example/` tree) so the app can be published to Google Play. Must remain regression-free: `flutter analyze` clean, 107/108 test baseline preserved, FLAG_SECURE pre-flight functional, kill-switch reactive binding (`SessionManager.stateStream → EncryptionService.bindSession`) intact.
**Requirements**: D-01..D-07 (no formal REQ-IDs; CONTEXT.md locked decisions are the requirement anchors)
**Depends on:** Phase 7
**Status:** Complete
**Plans:** 1 plan

Plans:
- [x] 08-01-PLAN.md — Single plan, 3 waves: (W1) Firebase Console + google-services.json regeneration (manual, autonomous: false); (W2) Gradle rename + Kotlin physical move + MethodChannel decoupling + firebase_options + delete com/example/ + flutter clean (7 autonomous tasks); (W3) D-06 acceptance gates — analyze + test + debug APK build + on-device smoke (5a/5b/5c/5d/5e) + atomic commit

### Phase 09: Navigation Safety & Session Integrity Hardening

**Goal:** Fix three code-verified gaps in navigation safety and session integrity: (1) ReceiverScreen back-nav shows no confirmation dialog and `canPop` is unconditionally `true` even during active transfers (`_sessionLocked`); (2) SenderScreen holds a stale `_encryptedAESKey` if the receiver's RSA keypair changes mid-session without triggering `_revertToWaiting` — the stream update refreshes `_selectedReceiverPublicKeyJson` but does not invalidate the already-computed encrypted key; (3) SenderScreen Step 1 "Browse Files" button remains active after Step 2 encryption completes — re-picking silently wipes encrypted state with no UX indication that prior work is discarded.

**Depends on:** Phase 08

**Scope:**
1. **Back-nav confirmation (ReceiverScreen)** — Change `canPop` to `false` when `_isReadyToReceive` is true; intercept pop in `onPopInvokedWithResult` to show a confirmation `BottomSheet` (matching existing `_showCloseSessionDialog` style) before triggering `_sessionManager.wipeSession`. Also block pop when `_sessionLocked` is true (active transfer in progress) with a SnackBar explaining why.
2. **Stale key invalidation (SenderScreen)** — In `_onHandshakeUpdate`, when an incoming handshake doc carries a `publicKey` that differs from the current `_selectedReceiverPublicKeyJson` and `_encryptedAESKey` is already set, call `_wipeSensitiveData()` and revert `_fileEncrypted` / `_readyToSend` state, snackbar-notifying "Receiver key changed — re-encrypt required."
3. **Step 1 re-pick UX lock (SenderScreen)** — Disable the "Browse Files" `CrypButton` after `_fileEncrypted` is true (replace with a "Change File" secondary action that explicitly confirms intent and triggers `_wipeSensitiveData()`); re-enable automatically when `_fileEncrypted` is reset.

**Plans:** 3 plans

Plans:
- [ ] 09-01-PLAN.md — Wave 1: Nyquist test stubs — navigation_guard_test.dart (GAP1-01..03) + stale_key_test.dart (GAP2-01, GAP2-02, GAP3-02)
- [ ] 09-02-PLAN.md — Wave 2: ReceiverScreen hardening — Gap 1 PopScope canPop guard + onPopInvokedWithResult confirmation; Gap 4 Step 1 AnimatedOpacity+IgnorePointer lockout + AppBar disable
- [ ] 09-03-PLAN.md — Wave 2 (parallel): SenderScreen hardening — Gap 2 stale-key invalidation in _onHandshakeUpdate; Gap 3 Browse Files disable + Change File TextButton + AlertDialog

### Phase 10: UI Polish Phase 2 + Stale-Key Security Fix

**Goal:** (1) Restore the stale-key invalidation guard in `SenderScreen._onHandshakeUpdate` that was dropped in WIP commit `580616d` — a security regression from Phase 09's verified work. (2) Commit and finalize the glassmorphic dialog styling already implemented in the working tree across 6 presentation screens and the admin dashboard, plus the uncommitted admin dashboard visual identity quick task (260531-a1k).

**Depends on:** Phase 09

**Scope:**
1. **Stale-key guard restore (SenderScreen)** — In `_onHandshakeUpdate`, insert the `previousPublicKey` capture before `setState` and the D-05/D-06 guard block after: if `previousPublicKey != null && publicKey != previousPublicKey && _encryptedAESKey != null`, call `_wipeSensitiveData()` + SnackBar. Reference: `git show 793e226:lib/presentation/sender/sender_screen.dart` lines 207–227.
2. **Glassmorphic dialog styling** — The working tree already has glassmorphic `AlertDialog` rewrites (transparent background, `GlassContainer` content, `CrypButton` confirm actions) across: `find_friends_screen.dart`, `sender_screen.dart`, `decrypt_screen.dart`, `receiver_transfer_screen.dart`, `home_screen.dart`, `transfer_progress_screen.dart`. Finalize, verify `flutter analyze`, and commit.
3. **Admin dashboard visual identity commit** — Commit the completed 260531-a1k quick task: AppBar title rename (`COMMAND CENTER` → `CrypTransferAdmin`), `GlassContainer` in `_SecurityLogTile` and `_NodeTile`, `AdminDashboardScreen` dark theme + Orbitron/Exo2 fonts.
4. **Pending ROADMAP/STATE housekeeping** — Commit the Phase 999.1 backlog deferral in `ROADMAP.md` and the Phase 08 completion status update.

**Plans:** 2 plans

Plans:
- [ ] 10-01-PLAN.md — Wave 1: Stale-key guard restore in SenderScreen + regression test update
- [ ] 10-02-PLAN.md — Wave 1 (parallel): Glassmorphic dialog finalization across 6 screens + admin dashboard commit + housekeeping
