# CrypTransfer — Project Roadmap

## Milestone v1.0: milestone

### Phase 02: ReceiverTransferScreen Hardening & Memory Safety
**Goal:** Harden the receiver-side transfer flow with session propagation, memory safety, and lifecycle kill-switch integration.
**Status:** Complete

### Phase 02.1: Identity & Networking — Professional Standards
**Goal:** Upgrade the Identity and Networking modules to professional standards: integrate Google Sign-In, replace the search-only friend model with a full `friendships` collection (pending/accepted/blocked), add a first-login theme-selection onboarding overlay, and standardize Login/Register form validation.

**Scope:**
1. **Google Authentication** — Integrate `google_sign_in` package. Add "Continue with Google" button to Login and Register screens. Firebase Auth flow handles Google identity tokens and auto-creates a `users` document for new accounts.
2. **Friendships Collection** — Refactor friend logic from search-only to a `friendships/{docId}` Firestore collection with `participants: [uid1, uid2]`, `status: pending|accepted|blocked`, `createdAt`. Query via `arrayContains: currentUser.uid` for a complete two-way friends list.
3. **My Connections Screen** — New screen showing accepted friends with a per-user "Disconnect" button. Disconnect deletes the friendship document and all shared handshake history (`rsa_key_transfers` docs for that pair) to maintain privacy.
4. **First-Login Theme Onboarding** — Onboarding overlay/dialog shown only on first login after registration (or when no preference is saved). Asks "Choose your experience: Dark Mode or Light Mode?". Saves preference to Firestore user profile and locally via `shared_preferences`. Theme updates instantly app-wide.
5. **Form Validation** — Login/Register forms get email-format validation, password-strength validation, and obscure-text toggles for password fields.

**Firestore schema:**
```
friendships/{docId}
  participants: [uid1, uid2]   // arrayContains query for two-way list
  status: "pending" | "accepted" | "blocked"
  createdAt: Timestamp
```

**Verification:**
- Google Sign-In authenticates and creates users doc on first login
- Disconnect deletes friendship doc + shared rsa_key_transfers docs
- Theme changes instantly on onboarding choice and persists across restarts
- Login/Register forms reject invalid email + weak passwords

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

**Plans:** 5 plans

Plans:
- [x] 05-01-PLAN.md — Wave 0 test scaffold: handshake_repository_test.dart (HAND-01–05), sender_prefill_test.dart (HAND-07), receiver_prefill_test.dart (HAND-08)
- [x] 05-02-PLAN.md — Wave 1 data layer: HandshakeRepository (CRUD + streams), FirebaseConstants.neutralHandshakes, Firestore neutral_handshakes rules block
- [x] 05-03-PLAN.md — Wave 1 (parallel) session screen integration: SenderScreen.preFilledPartnerUid, ReceiverScreen.preFilledSenderUid pre-fill params
- [x] 05-04-PLAN.md — Wave 2 HomeScreen restructure: Active Connections + Pending Requests sections, _ProposalBanner listener, _RolePickerSheet, retire role buttons
- [x] 05-05-PLAN.md — Gap closure: transfers Firestore rule neutral_handshakes auth (CR-01), repo/UI hardening (WR-01–07), stream tests (IN-01, IN-02, IN-04)
