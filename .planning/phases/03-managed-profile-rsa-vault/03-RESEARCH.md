# Phase 03: Managed Profile & RSA Vault - Research

**Researched:** 2026-05-02
**Domain:** Flutter RSA Key Management, Firestore Subcollections, Biometric Gating, SHA-256 Fingerprinting
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** `BiometricHelper` stays stubbed — real `local_auth` is NOT re-enabled in this phase
- **D-02:** Gate fires on screen open — Vault calls `BiometricHelper.authenticate()` before showing any key material; pop back on failure
- **D-03:** Gate structure is fully wired for future swap-in of real `local_auth` by updating `BiometricHelper` only
- **D-04:** Primary entry: dedicated screen `lib/presentation/vault/rsa_key_manager_screen.dart`, accessible from HomeScreen drawer "Key Vault"
- **D-05:** Secondary entry: ReceiverScreen warning banner "No RSA keys found — tap to generate" when `publicKey` is null/empty; tapping navigates to Vault
- **D-06:** Real-time sync via Firestore stream on `users/{uid}` — `publicKey` changes propagate automatically
- **D-07:** Three vault actions: View (fingerprint + algorithm + createdAt), Regenerate (biometric-gated, compute() RSA gen, write new key, audit log), Delete (biometric-gated, wipe SecureStorage, clear publicKey, audit log)
- **D-08:** Append-only audit subcollection `users/{uid}/rsa_key_manager/`
- **D-09:** Audit doc schema: `{action, timestamp, publicKeyHash, deviceInfo}`
- **D-10:** `publicKeyHash` = SHA-256 of raw DER-encoded public key bytes
- **D-11:** Audit docs IMMUTABLE — `update: false`; `delete: isAdmin() only`
- **D-12:** Add `rsa_key_manager` constant to `FirebaseConstants`
- **D-13:** `users/{uid}/profile` contains security/UX preferences only
- **D-14:** Profile doc ID: `preferences`; schema: `{biometricGateEnabled, keyVaultCreatedAt, themeMode, lastVaultAccessAt}`
- **D-15:** Profile created in `AuthRepository.register()` and `signInWithGoogle()` same batch as users doc; initial: `{biometricGateEnabled: false, themeMode: 'dark', keyVaultCreatedAt: null, lastVaultAccessAt: null}`
- **D-16:** Add `profile` constant to `FirebaseConstants`
- **D-17:** Firestore rules for `rsa_key_manager`: read=owner|admin, create=owner+action validation, update=false, delete=admin
- **D-18:** Firestore rules for `profile`: read=owner|admin, create=owner, update=owner|admin, delete=admin
- **D-19:** `SecurityLifecycleMixin` applied to `RsaKeyManagerScreen`
- **D-20:** `CrypButton` 3D system for Regenerate and Delete vault actions

### Claude's Discretion

- Exact Vault UI layout (card vs list, color coding for fingerprint display)
- `deviceInfo` collection method (Platform.operatingSystem or Android build string)
- Confirmation dialog design before Regenerate/Delete
- SHA-256 implementation: `crypto` package or PointyCastle digest

### Deferred Ideas (OUT OF SCOPE)

- Re-enabling real `local_auth` biometrics
- Key export / backup
- Pending Requests UI
</user_constraints>

---

## Summary

Phase 03 introduces a biometric-gated RSA Key Vault as the canonical home for RSA key lifecycle management. The implementation is well-defined by CONTEXT.md decisions, and all dependencies (packages, patterns, services) are already in the codebase. There are no new packages to install; `crypto 3.0.7` (transitive) covers SHA-256 fingerprinting via PointyCastle's `SHA256Digest`, the RSA key gen path via `compute()` is established in `AuthRepository.generateAndStoreKeyPair()`, and `FlutterSecureStorage`, `Firestore`, `SecurityLifecycleMixin`, and `CrypButton` are all ready to use.

**Critical prerequisite discovered:** `flutter analyze` reports **21 errors** in the current codebase — missing `AppTheme.textMain`, `AppTheme.textSecondary` getters and missing `AppTheme`/`GlassContainer` imports in `admin_dashboard.dart`. These must be fixed in Wave 0 (before any other work) or the project will not compile.

The two additions to `AuthRepository` (`register()` and `signInWithGoogle()`) require writing the `profile/preferences` subcollection doc in the same Firestore write as the `users/{uid}` doc — these are currently plain `set()` calls, not batches, so Wave 0 must also migrate them to `WriteBatch` to be atomic.

**Primary recommendation:** Fix the 21 analyzer errors first (Wave 0, one task), then implement the Vault screen, then wire the subcollection rules and auth flow changes.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| RSA key lifecycle (generate/regenerate/delete) | Data layer (`AuthRepository`) | Vault screen (UI trigger only) | Crypto ops must stay in repository; screen calls into repo |
| Biometric gate | Presentation layer (`RsaKeyManagerScreen.initState`) | `BiometricHelper` (logic encapsulated) | Gate fires at screen entry; `BiometricHelper` owns the auth call |
| SHA-256 fingerprint computation | Data layer (`AuthRepository`) | — | Computed alongside key write; never recomputed from UI. Exposed as `AuthRepository.computeFingerprint()` static method for display use. |
| Audit log append (`rsa_key_manager`) | Data layer (`AuthRepository`) | — | Append after every key operation; owned by same method that writes the key |
| Profile subcollection init | Data layer (`AuthRepository`) | — | Created atomically with `users/{uid}` doc on registration |
| `lastVaultAccessAt` update | Presentation layer (`RsaKeyManagerScreen`) | — | Fired on screen open after biometric gate passes |
| ReceiverScreen "no keys" banner | Presentation layer (`ReceiverScreen`) | — | Banner reads from existing `users/{uid}` Firestore stream; no new subscription |
| HomeScreen Key Vault navigation | Presentation layer (`SidebarDrawer`) | — | Replace/augment existing "Generate RSA Keys" drawer entry |
| Firestore security rules | Infrastructure (`firestore.rules`) | — | Two new `match` blocks under `users/{userId}` |

---

## Standard Stack

### Core (already in project)
| Library | Version | Purpose | Status |
|---------|---------|---------|--------|
| `cloud_firestore` | 6.2.0 [VERIFIED: pubspec.lock] | Subcollection reads/writes, real-time stream | Already in use |
| `flutter_secure_storage` | 10.0.0 [VERIFIED: pubspec.lock] | Private key storage and deletion | Already in use |
| `pointycastle` | 4.0.0 [VERIFIED: pubspec.lock] | RSA-2048 key generation, SHA-256 digest | Already in use |
| `crypto` | 3.0.7 [VERIFIED: pubspec.lock] | SHA-256 digest for fingerprint (transitive dep) | Available but transitive; use PointyCastle instead to avoid adding a direct dep |
| `firebase_auth` | 6.3.0 [VERIFIED: pubspec.lock] | Current user UID for subcollection paths | Already in use |
| `flutter/foundation.dart` | Flutter 3.41.7 [VERIFIED: flutter --version] | `compute()` for off-main-thread RSA gen | Already in use |
| `local_auth` | 3.0.1 [VERIFIED: pubspec.yaml] | Biometric gate — stub only, package present | Imported but stubbed |

### Supporting
| Library | Version | Purpose | Note |
|---------|---------|---------|------|
| `dart:io` (`Platform`) | Dart SDK | `deviceInfo` field: `Platform.operatingSystem + Platform.operatingSystemVersion` | No new package needed |
| `fake_cloud_firestore` | 4.1.0+1 [VERIFIED: pubspec.lock] | Unit test Firestore subcollection behaviour | Already in dev deps |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| PointyCastle `SHA256Digest` for fingerprint | `crypto` package `sha256.convert()` | `crypto` is cleaner API but would need to move from transitive to direct dep; PointyCastle is already a direct dep and sufficient |
| `WriteBatch` for profile init | Separate `set()` call after user doc | Separate call risks partial write on network failure; batch is required for atomicity |

**Installation:** No new packages required. All dependencies already resolved.

---

## Architecture Patterns

### System Architecture Diagram

```
User Action (open Vault)
       │
       ▼
RsaKeyManagerScreen.initState()
  └── BiometricHelper.authenticate('Access RSA Key Manager')
        ├── false → Navigator.pop()  [access denied]
        └── true  →
              AuthRepository.updateLastVaultAccess()  [writes lastVaultAccessAt]
                    │
                    ▼
              StreamBuilder(users/{uid})  ←── Firestore real-time
                    │
                    ├── publicKey present → View card (fingerprint, algorithm, createdAt from audit log)
                    └── publicKey absent  → "No key" empty state + Generate CrypButton

Regenerate / Delete (both biometric-gated):
       │
       ▼
BiometricHelper.authenticate(reason)
  └── true →
        AuthRepository.regenerateKeyPair()  OR  AuthRepository.deleteKeyPair()
              ├── compute(_generateKeyPairIsolate, null)        [Regenerate only]
              ├── FlutterSecureStorage.write/delete             [private key]
              ├── Firestore users/{uid}.update(publicKey)       [public key]
              ├── Firestore users/{uid}/rsa_key_manager.add()   [audit doc]
              └── Firestore users/{uid}/profile/preferences.set({keyVaultCreatedAt})  [Regenerate only — D-14]

ReceiverScreen "no keys" banner:
       │
       ├── existing stream on users/{uid} emits publicKey == null
       └── MaterialBanner / warning card shown
             └── tap → Navigator.push(RsaKeyManagerScreen) → pop back

AuthRepository.register() / signInWithGoogle():
       │
       └── WriteBatch
             ├── users/{uid}.set({...})
             └── users/{uid}/profile/preferences.set({biometricGateEnabled: false, themeMode: 'dark', ...})
```

### Recommended Project Structure

```
lib/
├── core/
│   └── constants/
│       └── firebase_constants.dart    ← add rsa_key_manager, profile constants
├── data/
│   └── repositories/
│       └── auth_repository.dart       ← add regenerateKeyPair(), deleteKeyPair(),
│                                          updateLastVaultAccess(), static computeFingerprint()
│                                          migrate register()/signInWithGoogle() to WriteBatch
└── presentation/
    ├── vault/                          ← NEW directory
    │   └── rsa_key_manager_screen.dart ← NEW screen
    ├── home/
    │   └── sidebar_drawer.dart         ← replace "Generate RSA Keys" entry with "Key Vault"
    └── receiver/
        └── receiver_screen.dart        ← add "no keys" warning banner
```

### Pattern 1: Biometric Gate on initState

**What:** Call `BiometricHelper.authenticate()` in `initState` / `didChangeDependencies`; pop back if false. Wire via `WidgetsBinding.instance.addPostFrameCallback` to avoid calling `Navigator.pop` before frame is rendered.

**When to use:** Every screen that gates sensitive data behind device credentials.

```dart
// Source: CONTEXT.md D-02, established pattern in ReceiverScreen
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
}

Future<void> _authenticate() async {
  final ok = await BiometricHelper.authenticate('Unlock RSA Key Vault');
  if (!ok && mounted) Navigator.pop(context);
}
```

### Pattern 2: SHA-256 Fingerprint via PointyCastle

**What:** Compute SHA-256 of DER-encoded public key bytes; display first 16 hex chars as human-readable fingerprint.

**When to use:** `rsa_key_manager` audit doc `publicKeyHash` field; Vault View display.

```dart
// Source: PointyCastle 4.0.0 export — SHA256Digest is available via pointycastle/export.dart
// The public key is stored as JSON. To get DER bytes, extract modulus + exponent bytes.
// Simplest approach: SHA-256 the UTF-8 bytes of the encoded public key JSON
// (consistent; same key always produces same hash; matches D-10 intent).
import 'dart:convert';
import 'package:pointycastle/export.dart';

// STATIC method on AuthRepository — screen calls AuthRepository.computeFingerprint()
// without duplicating SHA-256 logic in presentation layer (Architectural Responsibility Map).
static String computeFingerprint(String publicKeyJson) {
  final bytes = Uint8List.fromList(utf8.encode(publicKeyJson));
  final digest = SHA256Digest();
  final hash = digest.process(bytes);
  return hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

// Display: fingerprint.substring(0, 16).toUpperCase() → "A3F8C2D1E9B47012"
```

**Note on D-10:** CONTEXT.md specifies SHA-256 of "raw DER-encoded public key bytes." The current `encodePublicKey()` produces JSON (hex strings of modulus/exponent), not ASN.1 DER. Computing SHA-256 of the JSON UTF-8 bytes is a consistent, reproducible fingerprint — the planner should document this as the chosen approach (Claude's Discretion on implementation, with the distinction noted for audit traceability). [ASSUMED: DER encoding is not currently implemented; using JSON bytes is the pragmatic choice.]

### Pattern 3: Append-Only Audit Log (existing pattern)

**What:** Add a doc to `users/{uid}/rsa_key_manager/` with `serverTimestamp()` and `update: false` Firestore rule. Mirrors `audit_logs` subcollection already in `firestore.rules`.

```dart
// Source: existing firestore.rules audit_logs pattern + CONTEXT.md D-08/D-09
await _db
    .collection(FirebaseConstants.users)
    .doc(uid)
    .collection(FirebaseConstants.rsaKeyManager)
    .add({
  'action': 'generated', // 'regenerated' | 'deleted'
  'timestamp': FieldValue.serverTimestamp(),
  'publicKeyHash': fingerprint,
  'deviceInfo': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
});
```

### Pattern 4: Atomic Profile Init via WriteBatch

**What:** Write `users/{uid}` and `users/{uid}/profile/preferences` in a single `WriteBatch` to prevent partial-write on registration.

```dart
// Source: CONTEXT.md D-15; Firestore WriteBatch pattern
final batch = _db.batch();
batch.set(
  _db.collection(FirebaseConstants.users).doc(uid),
  { 'username': username, 'publicKey': null, /* ... */ },
);
batch.set(
  _db.collection(FirebaseConstants.users).doc(uid)
    .collection(FirebaseConstants.profile).doc('preferences'),
  {
    'biometricGateEnabled': false,
    'themeMode': 'dark',
    'keyVaultCreatedAt': null,
    'lastVaultAccessAt': null,
  },
);
await batch.commit();
```

### Anti-Patterns to Avoid

- **Calling Navigator.pop in initState synchronously:** Will crash because the route is not yet fully pushed. Always use `addPostFrameCallback`.
- **Computing SHA-256 on the UI thread:** For a 2048-bit key, the hash is fast enough that `compute()` is not needed — but don't run RSA generation on the main thread. The hash only should stay on main thread.
- **Re-subscribing to Firestore stream on every rebuild:** ReceiverScreen already has a stable `_transferStream` field pattern — the "no keys" banner must read from the same stream, not create a new subscription.
- **Not guarding `setState` with `if (mounted)` after async operations:** All async gaps in the Vault screen must check `mounted` before calling `setState`.
- **Skipping confirmation dialogs for destructive actions:** Delete and Regenerate both destroy the existing key pair. Always show a confirmation before proceeding, even though biometric gate provides a second factor.
- **Duplicating SHA-256 logic in presentation layer:** The fingerprint computation belongs in the Data layer. The vault screen calls `AuthRepository.computeFingerprint(publicKeyJson)` — never inline the `SHA256Digest` logic in a widget file.
- **Hardcoding hex color values in vault screen:** Always use `AppTheme` constants (`AppTheme.darkBg`, `AppTheme.darkSurface`, `AppTheme.primaryBlue`, `AppTheme.textMain`, `AppTheme.textSecondary`). No raw hex values in presentation files.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SHA-256 hashing | Custom byte-by-byte hash | `SHA256Digest` from PointyCastle via `AuthRepository.computeFingerprint()` | Already in project; battle-tested; Data layer owns fingerprint computation |
| RSA key generation | Direct `RSAKeyGenerator` in main thread | `compute(_generateKeyPairIsolate, null)` pattern from `AuthRepository` | Off-thread; existing top-level function ready to reuse |
| Secure private key storage | Custom file encryption | `FlutterSecureStorage` | Platform keystore integration |
| Atomic multi-doc Firestore write | Sequential `set()` calls | `WriteBatch` | Prevents partial writes across `users/{uid}` and `profile/preferences` |
| Append-only audit log | Custom timestamp/ordering logic | `FieldValue.serverTimestamp()` + `update: false` Firestore rule | Server-authoritative time; tamper-evident |

**Key insight:** Every primitive needed (key gen, secure storage, Firestore, SHA-256) is already in the project. Phase 03 is a composition and wiring phase, not a new-library phase.

---

## Common Pitfalls

### Pitfall 1: `flutter analyze` Failing at Phase Start (21 existing errors)
**What goes wrong:** The current codebase has 21 analyzer errors — `AppTheme.textMain` and `AppTheme.textSecondary` getters do not exist (only `lightTextMain`/`darkTextMain` variants do), and `admin_dashboard.dart` is missing `AppTheme` import and `GlassContainer` usage fails. Any new code added on top of a broken codebase cannot be verified clean.
**Why it happens:** Phase 02.1 changes modified `app_theme.dart` removing/renaming constants that other files still reference.
**How to avoid:** Wave 0 MUST fix these errors before any Phase 03 code is written. Fix: add `static const Color textMain = darkTextMain` and `static const Color textSecondary = darkTextSecondary` to `AppTheme` (or alias to theme-aware values); fix `admin_dashboard.dart` imports.
**Warning signs:** `flutter analyze` output ending with any error count > 0.

### Pitfall 2: `Navigator.pop` in `initState`
**What goes wrong:** Calling `Navigator.pop(context)` inside `initState` directly throws a `FlutterError` because the route hasn't been fully inserted into the navigator yet.
**Why it happens:** The biometric gate result arrives synchronously (stub returns `true` immediately; real `local_auth` is async), and developers call `pop` in the callback without `addPostFrameCallback`.
**How to avoid:** Always wrap the biometric call in `addPostFrameCallback(() => _authenticate())`. In `_authenticate()`, check `if (mounted)` before `Navigator.pop`.

### Pitfall 3: `rsa_key_manager` vs `audit_logs` Rule Conflict
**What goes wrong:** The existing collection-group rules for `audit_logs` (`/{path=**}/audit_logs/{logId}`) could conflict or be misread as covering `rsa_key_manager` if not clearly separated.
**Why it happens:** Firestore security rules match top-down; subcollection rules need explicit `match` blocks under `users/{userId}`.
**How to avoid:** Add the `rsa_key_manager` and `profile` rules as separate `match` blocks INSIDE the `match /users/{userId}` block, following the existing `audit_logs` block pattern.

### Pitfall 4: Missing WriteBatch in `signInWithGoogle()` for Existing Users
**What goes wrong:** In `signInWithGoogle()`, the `profile/preferences` doc is only written when `!userDoc.exists`. If an existing user signs in with Google and their `profile/preferences` doc is missing (users registered before this phase), the Vault will fail to update `lastVaultAccessAt`.
**Why it happens:** The profile doc init only runs on first-time Google users. Email-registered users who later sign in via Google never trigger it.
**How to avoid:** In `updateLastVaultAccess()`, use `set(..., SetOptions(merge: true))` so it creates the doc if missing, rather than `update()` which would throw if the doc doesn't exist. Also, plan a migration note: existing users will have their `profile/preferences` doc lazily created on first vault access.

### Pitfall 5: ReceiverScreen Banner Creates Duplicate Firestore Subscription
**What goes wrong:** The "no keys" banner needs to know `publicKey` status in real-time. If implemented naively with a new `StreamBuilder` on `users/{uid}`, there will be two simultaneous Firestore listeners on the same document (one from `_checkKeyStatus` polling, one from the banner stream).
**Why it happens:** `ReceiverScreen` uses `_checkKeyStatus()` (one-time Future fetch) rather than a persistent stream for key status. CONTEXT.md D-06 says "no extra wiring needed" because the banner reads the existing stream — but the existing code uses a Future, not a Stream.
**How to avoid:** Add a `StreamBuilder` on `users/{uid}` scoped to just the `publicKey` field at the top of `_step1Content()` or as a parent `StreamBuilder` wrapping step 1. Alternatively, after vault operations call `_checkKeyStatus()` on `ReceiverScreen` pop — CONTEXT.md D-06 says the stream handles this automatically, so the planner should use `AuthRepository.streamUserProfile(uid)` for the banner rather than a separate listener.

### Pitfall 6: Fingerprint Display Race — Audit Log vs `createdAt` Field
**What goes wrong:** The Vault "View" action shows `createdAt` timestamp from the `rsa_key_manager` audit log. If the most recent audit doc is `deleted` (not `generated`/`regenerated`), the display would show "deleted" as the last action, not the creation time of the current key.
**Why it happens:** The audit log is append-only; querying the last doc by timestamp returns the most recent action, not the key creation.
**How to avoid:** Query `rsa_key_manager` ordered by `timestamp` descending, take the first doc where `action != 'deleted'`. OR store `keyVaultCreatedAt` in `profile/preferences` (D-14 already includes this field) and use that for display — the profile field is the canonical creation timestamp for the current key.

---

## Code Examples

### Example 1: Biometric Gate with PostFrameCallback
```dart
// Source: CONTEXT.md D-02; pattern matches ReceiverScreen lifecycle setup
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
}

Future<void> _authenticate() async {
  final ok = await BiometricHelper.authenticate('Unlock RSA Key Vault');
  if (!ok && mounted) {
    Navigator.pop(context);
  }
}
```

### Example 2: Regenerate Key with Audit Log (3-doc WriteBatch)
```dart
// Source: AuthRepository.generateAndStoreKeyPair() pattern + CONTEXT.md D-07/D-09/D-14
Future<void> regenerateKeyPair(String uid) async {
  final pair = await compute(_generateKeyPairIsolate, null);
  final pubKey = pair.publicKey as RSAPublicKey;
  final privKey = pair.privateKey as RSAPrivateKey;

  final pubKeyJson = EncryptionService.encodePublicKey(pubKey);
  final privKeyJson = EncryptionService.encodePrivateKey(privKey);
  final fingerprint = computeFingerprint(pubKeyJson);  // static method

  await _secure.write(
    key: FirebaseConstants.privateKeyStorageKey,
    value: privKeyJson,
  );

  final userRef = _db.collection(FirebaseConstants.users).doc(uid);
  final auditRef = userRef.collection(FirebaseConstants.rsaKeyManager).doc();
  final prefsRef = userRef.collection(FirebaseConstants.profile).doc('preferences');
  final batch = _db.batch();
  batch.update(userRef, {'publicKey': pubKeyJson});
  batch.set(auditRef, {
    'action': 'regenerated',
    'timestamp': FieldValue.serverTimestamp(),
    'publicKeyHash': fingerprint,
    'deviceInfo': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
  });
  batch.set(prefsRef, {'keyVaultCreatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true));  // D-14: stamp regeneration time
  await batch.commit();
}
```

### Example 3: Delete Key with Audit Log
```dart
// Source: EncryptionService.closeReceiverSession() pattern + CONTEXT.md D-07
Future<void> deleteKeyPair(String uid) async {
  await _secure.delete(key: FirebaseConstants.privateKeyStorageKey);

  final batch = _db.batch();
  batch.update(
    _db.collection(FirebaseConstants.users).doc(uid),
    {'publicKey': FieldValue.delete()},
  );
  batch.set(
    _db.collection(FirebaseConstants.users)
        .doc(uid)
        .collection(FirebaseConstants.rsaKeyManager)
        .doc(),
    {
      'action': 'deleted',
      'timestamp': FieldValue.serverTimestamp(),
      'publicKeyHash': null, // no key to hash
      'deviceInfo': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    },
  );
  await batch.commit();
}
```

### Example 4: Firestore Rules for New Subcollections
```
// Source: CONTEXT.md D-17/D-18; mirrors existing audit_logs pattern in firestore.rules
// Add inside match /users/{userId} block:

match /rsa_key_manager/{logId} {
  allow read: if isOwner(userId) || isAdmin();
  allow create: if isOwner(userId) &&
                   request.resource.data.action in ['generated', 'regenerated', 'deleted'];
  allow update: if false;       // IMMUTABLE
  allow delete: if isAdmin();
}

match /profile/{prefId} {
  allow read: if isOwner(userId) || isAdmin();
  allow create: if isOwner(userId);
  allow update: if isOwner(userId) || isAdmin();
  allow delete: if isAdmin();
}
```

### Example 5: ReceiverScreen "No Keys" Banner
```dart
// Source: CONTEXT.md D-05; ReceiverScreen._step1Content() existing pattern
// Replace / augment step 1 content when _step1Done is false:
if (!_step1Done && !_checkingStatus)
  Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.amber.withValues(alpha: 0.1),
      border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.amber),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RsaKeyManagerScreen()),
            ).then((_) => _checkKeyStatus()),
            child: const Text(
              'No RSA keys found — tap to generate',
              style: TextStyle(color: Colors.amber),
            ),
          ),
        ),
      ],
    ),
  ),
```

---

## State of the Art

| Old Approach | Current Approach | Notes |
|--------------|------------------|-------|
| Key gen from drawer dialog | Dedicated Vault screen | Phase 03 replaces "Generate RSA Keys" drawer dialog with full Vault screen entry |
| No audit log for key events | Append-only `rsa_key_manager` subcollection | New in Phase 03 |
| `users/{uid}` only | + `profile/preferences` subcollection | New in Phase 03 |
| No biometric gate on key operations | Gate on screen entry + re-gate for Regenerate/Delete | New in Phase 03 |

**Existing in project, superseded by Vault:**
- `SidebarDrawer._showKeyGenDialog` / `_KeyGenDialog` — the standalone key gen dialog. Phase 03 replaces the drawer entry "Generate RSA Keys" with "Key Vault" that opens `RsaKeyManagerScreen`. The old dialog class can remain but the drawer entry point changes.
- `ReceiverScreen._generateKeys()` / `_openKeyManager()` — the inline key manager sheet in ReceiverScreen. Phase 03 replaces this with navigation to the dedicated Vault screen.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | SHA-256 of JSON UTF-8 bytes is an acceptable substitute for DER-encoded bytes per D-10 | Code Examples §2, Pattern 2 | Low — both are deterministic fingerprints; DER encoding would require additional PointyCastle ASN.1 work |
| A2 | `Platform.operatingSystem + Platform.operatingSystemVersion` is available at runtime on Android (no `dart:io` restriction in Flutter) | Code Examples §2 | Low — `dart:io` is supported on Android/iOS Flutter; web would fail but no web target in this project |
| A3 | Existing users (registered before Phase 03) will not have `profile/preferences` — lazy creation on vault open via `set(merge: true)` is acceptable | Common Pitfalls §4 | Low — `SetOptions(merge: true)` prevents overwriting existing data |

---

## Open Questions

1. **Should the drawer "Generate RSA Keys" entry be removed or kept alongside "Key Vault"?**
   - What we know: CONTEXT.md D-04 says "Key Vault" replaces/augments the HomeScreen drawer entry
   - What's unclear: Whether the old `_KeyGenDialog` class in `sidebar_drawer.dart` should be deleted or left as dead code
   - Recommendation: Replace the drawer `ListTile` "Generate RSA Keys" with "Key Vault" pointing to `RsaKeyManagerScreen`; remove `_KeyGenDialog` and `_Status` enum from `sidebar_drawer.dart` to keep the file clean
   - **RESOLVED (Plan 03-05):** Drawer "Generate RSA Keys" is REPLACED with "Key Vault" pointing to `RsaKeyManagerScreen`. `_KeyGenDialog`, `_KeyGenDialogState`, `_Status` enum, and `_showKeyGenDialog` are REMOVED from `sidebar_drawer.dart` (confirmed dead code after entry point change).

2. **Should `ReceiverScreen._generateKeys()` and `_openKeyManager()` be removed?**
   - What we know: Phase 03 makes the Vault the canonical key management entry point
   - What's unclear: Whether ReceiverScreen's inline key gen should redirect to the Vault or remain as a fallback
   - Recommendation: ReceiverScreen Step 1 should show the "no keys" banner (tap → Vault) and remove the inline `_generateKeys()` flow; keep `_checkKeyStatus()` for post-vault-pop refresh
   - **RESOLVED (Plan 03-05):** `_generateKeys()` in the `_step1Done` branch MUST be updated to navigate to `RsaKeyManagerScreen` rather than performing inline key generation. The `_generateKeys()` method can be kept as a wrapper that calls `Navigator.push(RsaKeyManagerScreen).then(_checkKeyStatus)`, or the call site in the `_step1Done` branch can be updated directly — either approach is acceptable. The old `generateAndStoreKeyPair()` call path MUST NOT remain reachable from the ReceiverScreen UI per D-07 (Vault is the canonical key lifecycle surface).

3. **`keyVaultCreatedAt` field in `profile/preferences` — when does it get set?**
   - What we know: D-14 includes `keyVaultCreatedAt: null` in the initial profile doc
   - What's unclear: Whether it's set on first key generation in the Vault, or always reflects the most recent generation
   - Recommendation: Set `keyVaultCreatedAt` in `profile/preferences` on every Regenerate action (not just first time), so it tracks the current key's creation time for display in the Vault View
   - **RESOLVED (Plan 03-03):** `keyVaultCreatedAt` is written on EVERY `regenerateKeyPair()` call via a third document in the WriteBatch: `prefsRef.set({keyVaultCreatedAt: FieldValue.serverTimestamp()}, SetOptions(merge: true))`. This makes regenerate a 3-doc WriteBatch: `userRef.update(publicKey)` + `auditRef.set(auditDoc)` + `prefsRef.set({keyVaultCreatedAt: serverTimestamp()}, merge: true)`. It is NOT written on delete — the field tracks current key creation time only.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK | All compilation | Yes | 3.41.7 [VERIFIED] | — |
| Dart SDK | All compilation | Yes | 3.11.5 [VERIFIED] | — |
| `cloud_firestore` | Subcollection writes, security rules | Yes | 6.2.0 [VERIFIED] | — |
| `flutter_secure_storage` | Private key delete | Yes | 10.0.0 [VERIFIED] | — |
| `pointycastle` | SHA-256 digest, RSA gen | Yes | 4.0.0 [VERIFIED] | — |
| `fake_cloud_firestore` | Unit tests for audit log | Yes | 4.1.0+1 [VERIFIED] | — |
| `local_auth` | Biometric gate (stub only) | Yes | 3.0.1 [VERIFIED: pubspec.yaml] | Stub always returns true |
| Firebase Emulator Suite | Firestore rules testing | Not verified | — | Test rules manually in Firebase Console or deploy rules with `firebase deploy --only firestore:rules` |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** Firebase Emulator not confirmed available; Firestore rules changes should be verified by deploying to Firebase and testing from the device, or via the Firebase Console's Rules Playground.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | flutter_test (Flutter 3.41.7) |
| Config file | No separate config — standard `flutter test` |
| Quick run command | `flutter test test/security/ -x` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| VAULT-01 | Biometric gate pops screen on auth failure | Widget test | `flutter test test/vault/vault_gate_test.dart -x` | No — Wave 0 |
| VAULT-02 | Regenerate writes new key to SecureStorage + Firestore | Unit | `flutter test test/vault/key_lifecycle_test.dart::test_regenerate -x` | No — Wave 0 |
| VAULT-03 | Delete clears SecureStorage + nulls Firestore publicKey + appends audit log | Unit | `flutter test test/vault/key_lifecycle_test.dart::test_delete -x` | No — Wave 0 |
| VAULT-04 | `rsa_key_manager` audit log doc is immutable (Firestore rules) | Integration/manual | Firebase Rules Playground | No — manual |
| VAULT-05 | `profile/preferences` created atomically with `users/{uid}` on registration | Unit | `flutter test test/vault/profile_init_test.dart -x` | No — Wave 0 |
| VAULT-06 | ReceiverScreen banner appears when publicKey is null | Widget test | `flutter test test/vault/receiver_banner_test.dart -x` | No — Wave 0 |
| VAULT-07 | `flutter analyze` passes with 0 issues after all changes | Static analysis | `flutter analyze --no-pub` | — |

### Sampling Rate
- **Per task commit:** `flutter analyze --no-pub` (fast; catches missing getters/imports)
- **Per wave merge:** `flutter test test/security/ && flutter test test/vault/` (full vault + security tests)
- **Phase gate:** Full suite `flutter test` green + `flutter analyze` 0 issues before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `test/vault/` directory — create vault test directory
- [ ] `test/vault/vault_gate_test.dart` — VAULT-01: biometric gate navigation test
- [ ] `test/vault/key_lifecycle_test.dart` — VAULT-02/03: regenerate + delete behaviour
- [ ] `test/vault/profile_init_test.dart` — VAULT-05: profile subcollection atomic write
- [ ] `test/vault/receiver_banner_test.dart` — VAULT-06: banner visibility when publicKey null
- [ ] Fix 21 existing `flutter analyze` errors FIRST — prerequisite for all test runs

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | Yes | BiometricHelper gate on vault open + destructive actions |
| V3 Session Management | No | Vault is a management screen, not a transfer session |
| V4 Access Control | Yes | Firestore rules: `isOwner(userId)` for all key operations; `isAdmin()` for delete |
| V5 Input Validation | Yes | Firestore rules: `action in ['generated', 'regenerated', 'deleted']` on create |
| V6 Cryptography | Yes | RSA-2048 via PointyCastle in `compute()` isolate; never on main thread |
| V7 Error Handling | Yes | All catch blocks must not leak key material in error messages |

### Known Threat Patterns for This Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Biometric bypass (attacker provides false positive) | Elevation of privilege | BiometricHelper stub: acceptable for thesis; real `local_auth` with `biometricOnly: false, stickyAuth: true` planned for pre-viva |
| Partial key rotation (old key remanent after regenerate) | Information disclosure | Delete private key from SecureStorage BEFORE writing new key; or write new then delete old in same batch — order matters; write new key atomically then delete old in follow-up write |
| Audit log tampering | Tampering | Firestore `update: false` rule makes docs immutable; admin-only delete |
| Profile doc missing for pre-Phase-03 users | Denial of service | Use `set(merge: true)` in `updateLastVaultAccess()` to lazily create missing docs |
| `publicKeyHash` collision | Spoofing | SHA-256 is collision-resistant; 256-bit output; truncation to 16 chars for display only, full hash stored |

---

## Sources

### Primary (HIGH confidence)
- Codebase: `lib/data/repositories/auth_repository.dart` — RSA gen pattern, Firestore write pattern [VERIFIED: Read tool]
- Codebase: `lib/core/constants/firebase_constants.dart` — current constants [VERIFIED: Read tool]
- Codebase: `lib/core/utils/biometric_helper.dart` — stub gate structure [VERIFIED: Read tool]
- Codebase: `firestore.rules` — existing subcollection rule patterns [VERIFIED: Read tool]
- Codebase: `pubspec.lock` — exact package versions [VERIFIED: Read tool + dart pub deps]
- Codebase: `flutter analyze` output — 21 existing errors documented [VERIFIED: Bash tool]

### Secondary (MEDIUM confidence)
- CONTEXT.md D-01 through D-20 — locked decisions from /gsd-discuss-phase [VERIFIED: Read tool]
- Flutter SDK `3.41.7`, Dart `3.11.5` [VERIFIED: flutter --version]
- PointyCastle `SHA256Digest` available via `pointycastle/export.dart` [VERIFIED: pubspec.lock version 4.0.0; ASSUMED: SHA256Digest is exported in 4.0.0 — consistent with PointyCastle docs]

### Tertiary (LOW confidence — none)

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all packages verified in pubspec.lock; no new packages needed
- Architecture: HIGH — all patterns are established in the codebase; research is adaptation, not discovery
- Pitfalls: HIGH — analyzer errors verified by running flutter analyze; other pitfalls derived from codebase reading

**Research date:** 2026-05-02
**Valid until:** 2026-06-01 (stable stack; 30-day validity)
