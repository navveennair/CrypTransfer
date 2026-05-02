# Phase 03: Managed Profile & RSA Vault - Context

**Gathered:** 2026-05-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Implement a biometric-gated RSA Key Manager (Vault) screen, initialize a `profile` subcollection on user creation, and harden Firestore security rules for the new `rsa_key_manager` subcollection.

This phase does NOT touch the crypto transfer flow, SessionManager, or encryption services.

</domain>

<decisions>
## Implementation Decisions

### Biometric Gate
- **D-01:** `BiometricHelper` stays stubbed (all methods return `true`) — real `local_auth` is NOT re-enabled in this phase
- **D-02:** Gate fires **on screen open** — the vault screen triggers `BiometricHelper.authenticate()` before displaying any key material; if auth fails, pop back to previous screen
- **D-03:** The gate structure is fully wired so a future phase can swap in real `local_auth` by updating `BiometricHelper` only, with zero screen-level changes

### Vault Screen Entry Points
- **D-04:** Primary: dedicated screen `lib/presentation/vault/rsa_key_manager_screen.dart`, accessible from HomeScreen (menu/drawer entry "Key Vault")
- **D-05:** Secondary: ReceiverScreen shows a warning banner "No RSA keys found — tap to generate" if `publicKey` is null/empty in the streamed user doc; tapping navigates to the Vault screen, then returns to ReceiverScreen to continue the stepper
- **D-06:** Real-time sync between screens via Firestore stream — ReceiverScreen already streams `users/{uid}` doc; `publicKey` changes (regenerate/delete) propagate automatically, no extra wiring needed

### Vault Key Actions
- **D-07:** Three actions exposed in the Vault: **View**, **Regenerate**, **Delete**
  - **View** — display public key fingerprint (SHA-256, first 16 hex chars displayed), algorithm (RSA-2048), `createdAt` timestamp from `rsa_key_manager` audit log
  - **Regenerate** — biometric-gated; generates new RSA pair via `compute()`, writes new public key to `users/{uid}.publicKey` in Firestore, writes new private key to `FlutterSecureStorage`, appends `{action: 'regenerated', ...}` doc to `rsa_key_manager`
  - **Delete** — biometric-gated; deletes private key from `FlutterSecureStorage`, clears `publicKey` field on `users/{uid}` doc, appends `{action: 'deleted', ...}` doc to `rsa_key_manager`; ReceiverScreen automatically shows the "no keys" banner via Firestore stream

### rsa_key_manager Subcollection
- **D-08:** Append-only audit log under `users/{uid}/rsa_key_manager/`
- **D-09:** Each document schema:
  ```
  {
    action: 'generated' | 'regenerated' | 'deleted',
    timestamp: Timestamp,
    publicKeyHash: string,   // SHA-256 hex fingerprint of the RSA public key bytes
    deviceInfo: string,      // Platform.operatingSystem + version if available
  }
  ```
- **D-10:** `publicKeyHash` is computed from the raw DER-encoded public key bytes using SHA-256 (not a PEM truncation)
- **D-11:** Documents are IMMUTABLE — `update: false` in Firestore rules; `delete: if isAdmin()` only
- **D-12:** Add `rsa_key_manager` constant to `FirebaseConstants`

### profile Subcollection
- **D-13:** `users/{uid}/profile` contains security/UX preferences only — identity fields stay on the main `users/{uid}` doc
- **D-14:** Single document schema (doc ID: `preferences`):
  ```
  {
    biometricGateEnabled: bool,    // true when local_auth is re-enabled
    keyVaultCreatedAt: Timestamp,  // when first key pair was generated
    themeMode: 'dark' | 'light',   // migrated from shared_preferences
    lastVaultAccessAt: Timestamp,  // updated on every vault screen open
  }
  ```
- **D-15:** Created in `AuthRepository.register()` and `signInWithGoogle()` — same batch as the `users/{uid}` doc write; initial values: `{biometricGateEnabled: false, themeMode: 'dark', keyVaultCreatedAt: null, lastVaultAccessAt: null}`
- **D-16:** Add `profile` constant to `FirebaseConstants`

### Firestore Security Rules
- **D-17:** `users/{userId}/rsa_key_manager/{logId}` rules:
  - `read`: owner or admin
  - `create`: owner only, provided `request.resource.data.action in ['generated', 'regenerated', 'deleted']`
  - `update`: `false` — IMMUTABLE
  - `delete`: admin only
- **D-18:** `users/{userId}/profile/{prefId}` rules:
  - `read`: owner or admin
  - `create`: owner (`isOwner(userId)`)
  - `update`: owner or admin
  - `delete`: admin only

### Applied Patterns
- **D-19:** `SecurityLifecycleMixin` applied to `RsaKeyManagerScreen` (established pattern for all screens)
- **D-20:** `CrypButton` 3D system used for Regenerate and Delete actions in the Vault

### Claude's Discretion
- Exact Vault UI layout (card vs list, color coding for fingerprint display)
- `deviceInfo` collection method (Platform.operatingSystem or Android build string)
- Confirmation dialog design before destructive actions (Regenerate/Delete)
- SHA-256 implementation: use `crypto` package (already in pubspec or add) or PointyCastle digest

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### RSA Key Management
- `lib/data/repositories/auth_repository.dart` — `generateAndStoreKeyPair()`, `hasKeyPair()`, `getPublicKey()`, `getPrivateKeyJson()`; extend with delete + regenerate + rsa_key_manager logging
- `lib/core/constants/firebase_constants.dart` — add `rsa_key_manager` and `profile` constants here
- `lib/core/utils/biometric_helper.dart` — gate implementation lives here; currently stubbed

### Firestore Rules
- `firestore.rules` — add `rsa_key_manager` and `profile` subcollection rules under `users/{userId}`

### UI Patterns
- `lib/presentation/receiver/receiver_screen.dart` — add no-keys warning banner, Firestore stream for `publicKey` already present
- `lib/presentation/home/home_screen.dart` — add Key Vault navigation entry
- `lib/presentation/widgets/shared_widgets.dart` — `CrypButton` 3D system for vault actions
- `lib/app_theme.dart` — GitHub Dark theme; new screen must follow the same palette

### Security Patterns
- `lib/core/utils/security_lifecycle_mixin.dart` — apply to `RsaKeyManagerScreen`

### Auth Flow
- `lib/data/repositories/auth_repository.dart` — `register()` and `signInWithGoogle()` must be extended to also write `users/{uid}/profile/preferences` doc on creation

### Prior Phase Context
- `.planning/phases/02.1-critical-auth-security-fix/02.1-CONTEXT.md` — theme onboarding writes `themeMode` to `shared_preferences`; Phase 03 adds it to the `profile` subcollection as well (Firestore source of truth)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `AuthRepository.generateAndStoreKeyPair()` — existing `compute()`-based RSA key gen; Regenerate action in the Vault calls this (or a new method that also logs to `rsa_key_manager`)
- `BiometricHelper.authenticate()` — stub gate entry point; Vault screen calls this on `initState`
- `SecurityLifecycleMixin` — apply to `RsaKeyManagerScreen` as with all other screens
- `CrypButton` — use for Regenerate and Delete vault actions (matches app-wide 3D button system)
- `FirebaseConstants` — single source of truth; add `rsa_key_manager` and `profile` here

### Established Patterns
- All key material in `FlutterSecureStorage`, public key identity in Firestore `users/{uid}.publicKey` — Vault screen does not change this architecture
- `compute()` for all crypto operations — key generation must stay off the main thread
- Append-only Firestore audit docs with `update: false` rules — same pattern as `audit_logs` already in `firestore.rules`
- GitHub Dark palette (`#0D1117` bg, `#161B22` surface, `#58A6FF` primary) — Vault screen follows this

### Integration Points
- `ReceiverScreen` → Vault: warning banner wires to `Navigator.push(RsaKeyManagerScreen)`; return pops back automatically
- `HomeScreen` → Vault: drawer/menu entry navigates to `RsaKeyManagerScreen`
- `AuthRepository.register()` and `signInWithGoogle()` → `profile` subcollection write added to existing Firestore batch

</code_context>

<specifics>
## Specific Ideas

- "Once a key pair is detected in ReceiverScreen, user needs to generate since the key can be automatically wired to be used to find 'Establish Connections'" — the no-keys banner is the on-ramp to the vault from the receiver flow
- Both HomeScreen and ReceiverScreen should have real-time visibility into key existence — achieved via the existing Firestore stream on `users/{uid}`, no new subscription needed
- RSA key generation is created/managed at the Vault level; ReceiverScreen and SenderScreen consume the key but do not own its lifecycle

</specifics>

<deferred>
## Deferred Ideas

- Re-enabling real `local_auth` biometrics — BiometricHelper stub stays in place; actual `local_auth` package integration is a Pre-Viva task listed in CLAUDE.md
- Key export / backup — not in this phase
- Pending Requests UI — deferred from Phase 02.1

</deferred>

---

*Phase: 03-managed-profile-rsa-vault*
*Context gathered: 2026-05-02*
