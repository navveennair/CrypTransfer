# Phase 03: Managed Profile & RSA Vault - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-02
**Phase:** 03-managed-profile-rsa-vault
**Areas discussed:** Biometric gate scope, rsa_key_manager subcollection, profile subcollection, Vault screen design

---

## Biometric Gate Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Re-enable fully | Uncomment local_auth, restore real fingerprint/face/PIN auth | |
| Stub gate only | Keep local_auth bypassed; wire vault UI to call BiometricHelper.authenticate() structurally | ✓ |

**Gate trigger:**

| Option | Description | Selected |
|--------|-------------|----------|
| On screen open | User must pass biometric auth to even see the Vault screen | ✓ |
| Per-action | Gate fires only on destructive actions (Regenerate, Delete) | |
| On app launch only | Biometric check happens once on login | |

**User's choice:** Stub gate, fires on screen open. Real local_auth integration deferred to Pre-Viva task.

**Notes:** User initially answered the key hash question with a note about re-enabling local_auth ("Implement local_auth in the RSAKeyManagerScreen..."). On follow-up confirmation, user confirmed keeping the stub. The intent to eventually re-enable real biometrics is captured as a deferred idea.

---

## rsa_key_manager Subcollection

| Option | Description | Selected |
|--------|-------------|----------|
| Key audit log | Append-only docs per key lifecycle event | ✓ |
| Active key metadata only | Single doc describing current key state | |
| Both: metadata + audit log | 'current' doc + 'events' subcollection | |

**Key hash format:**

| Option | Description | Selected |
|--------|-------------|----------|
| SHA-256 fingerprint | Hash raw public key bytes with SHA-256 | ✓ |
| Full PEM string | Store entire PEM-encoded public key | |

**User's choice:** Append-only audit log with SHA-256 fingerprint.

---

## profile Subcollection

| Option | Description | Selected |
|--------|-------------|----------|
| Security preferences only | {biometricGateEnabled, keyVaultCreatedAt, themeMode, lastVaultAccessAt} | ✓ |
| Full profile extension | Move bio, avatar, displayName, themeMode here | |
| Just initialization marker | Placeholder doc with createdAt only | |

**Init timing:**

| Option | Description | Selected |
|--------|-------------|----------|
| On register/Google sign-in | Add to AuthRepository batch — same as users/{uid} doc | ✓ |
| On first vault open | Lazy creation when Vault is first opened | |

**User's choice:** Security preferences subcollection, created on auth.

---

## Vault Screen Design

**Entry point:**

**User's choice (freeform):** Both HomeScreen and ReceiverScreen. RSA key creation should be done at Home (via vault). ReceiverScreen should detect key existence and, if missing, show a banner to navigate to the Vault. Real-time information should be updated across both screens.

**Key actions:**

| Option | Description | Selected |
|--------|-------------|----------|
| View + Regenerate | Display fingerprint + regenerate action, no delete | |
| View only | Read-only screen, no destructive actions | |
| View + Regenerate + Delete | Full control | ✓ |

**ReceiverScreen integration:**

| Option | Description | Selected |
|--------|-------------|----------|
| Banner + navigate to Vault | Warning banner if no keys, taps navigate to Vault | ✓ |
| Inline generate button | Generate Keys button inline on ReceiverScreen | |
| Block toggle with prompt | Toggle disabled, dialog prompts to generate | |

**Real-time sync:**

| Option | Description | Selected |
|--------|-------------|----------|
| Stream from Firestore | publicKey changes propagate via existing users/{uid} stream | ✓ |
| Refresh on screen focus | Re-check on navigate-back | |

---

## Claude's Discretion

- Exact Vault UI layout (card vs list, fingerprint display styling)
- `deviceInfo` collection method
- Confirmation dialog design for destructive actions
- SHA-256 implementation library (crypto package vs PointyCastle digest)

## Deferred Ideas

- Real `local_auth` re-enable — Pre-Viva task
- Key export / backup — future phase
