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
**Status:** Executing (Wave 0 complete)

**Depends on:** Phase 02

**Plans:**
- [x] 03-01: Analyzer fix + test scaffold (Wave 0) — 21 errors resolved, test/vault/ created with 5 Nyquist stubs
- [ ] 03-02: Profile subcollection + auth registration (Wave 1)
- [ ] 03-03: RSA Vault key lifecycle (Wave 2)
- [ ] 03-04: RsaKeyManagerScreen + biometric gate (Wave 3)
- [ ] 03-05: ReceiverScreen banner + Firestore rules hardening (Wave 4)
