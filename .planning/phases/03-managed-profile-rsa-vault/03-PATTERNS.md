# Phase 03: Managed Profile & RSA Vault - Pattern Map

**Mapped:** 2026-05-02
**Files analyzed:** 9 new/modified files
**Analogs found:** 9 / 9

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `lib/presentation/vault/rsa_key_manager_screen.dart` | screen (stateful widget) | request-response + Firestore stream | `lib/presentation/receiver/receiver_screen.dart` | exact |
| `lib/data/repositories/auth_repository.dart` | repository | CRUD + batch write | self (extend existing) | exact |
| `lib/core/constants/firebase_constants.dart` | config | — | self (extend existing) | exact |
| `firestore.rules` | infrastructure / security rules | — | self — `audit_logs` block inside `users/{userId}` | exact |
| `lib/presentation/receiver/receiver_screen.dart` | screen (modify) | Firestore stream | self | exact |
| `lib/presentation/home/sidebar_drawer.dart` | navigation / UI (modify) | request-response | self | exact |
| `test/vault/vault_gate_test.dart` | test | — | `test/security/session_wipe_test.dart` | role-match |
| `test/vault/key_lifecycle_test.dart` | test | — | `test/security/session_wipe_test.dart` | role-match |
| `test/vault/profile_init_test.dart` | test | — | `test/security/session_wipe_test.dart` | role-match |
| `test/vault/receiver_banner_test.dart` | test | — | `test/security/mem_safety_test.dart` | role-match |
| `lib/app_theme.dart` | config / theme (Wave 0 fix) | — | self | exact |
| `lib/presentation/admin/admin_dashboard.dart` | screen (Wave 0 fix) | — | self | exact |

---

## Pattern Assignments

### `lib/presentation/vault/rsa_key_manager_screen.dart` (NEW screen, request-response + stream)

**Analog:** `lib/presentation/receiver/receiver_screen.dart`

**Imports pattern** (receiver_screen.dart lines 1-18):
```dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app_theme.dart';
import '../../core/constants/firebase_constants.dart';
import '../../core/utils/biometric_helper.dart';
import '../../core/utils/security_lifecycle_mixin.dart';
import '../../data/repositories/auth_repository.dart';
import '../widgets/shared_widgets.dart';
```

For the Vault screen, add `dart:io` for `Platform` and `package:pointycastle/export.dart` for `SHA256Digest`. Remove SessionManager and KeyRepository imports (not needed). Add the new screen import.

**SecurityLifecycleMixin application** (receiver_screen.dart lines 27-28):
```dart
class _ReceiverScreenState extends State<ReceiverScreen>
    with SecurityLifecycleMixin<ReceiverScreen>, WidgetsBindingObserver {
```

For the Vault screen (no WidgetsBindingObserver needed since no lifecycle kill-switch):
```dart
class _RsaKeyManagerScreenState extends State<RsaKeyManagerScreen>
    with SecurityLifecycleMixin<RsaKeyManagerScreen> {
```

**Biometric gate pattern** (receiver_screen.dart lines 57-65 and 378-394 — combine into initState gate):

The existing `_openKeyManager()` method (lines 378-394) is the direct model for the vault gate, but it uses `showModalBottomSheet` rather than `pop`. The correct Vault pattern from RESEARCH.md is:

```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
}

Future<void> _authenticate() async {
  final ok = await BiometricHelper.authenticate('Unlock RSA Key Vault');
  if (!ok && mounted) Navigator.pop(context);
  // gate passed — proceed to update lastVaultAccessAt
  if (ok) _updateLastVaultAccess();
}
```

CRITICAL: Never call `Navigator.pop` directly in `initState` — always via `addPostFrameCallback`. This is the anti-pattern documented in RESEARCH.md Pitfall 2.

**Firestore stream for real-time key status** (receiver_screen.dart lines 216-222 in auth_repository.dart):
```dart
// AuthRepository.streamUserProfile() — use this for the Vault StreamBuilder
Stream<UserModel?> streamUserProfile(String uid) {
  return _db
      .collection(FirebaseConstants.users)
      .doc(uid)
      .snapshots()
      .map((doc) => doc.exists ? UserModel.fromDoc(doc) : null);
}
```

The Vault screen wraps its body in a `StreamBuilder<UserModel?>` on this stream — same pattern as the existing ReceiverScreen `_transferStatusWidget` (lines 555-579) which uses `StreamBuilder` on a stable `Stream` field.

**Async operation + mounted guard pattern** (receiver_screen.dart lines 112-130):
```dart
Future<void> _checkKeyStatus() async {
  setState(() => _checkingStatus = true);
  try {
    final hasPriv = await _authService.hasKeyPair();
    final pubKey = await _authService.getPublicKey();
    if (mounted) {
      setState(() {
        _hasPrivateKey = hasPriv;
        _hasPublicKey = pubKey != null && pubKey.isNotEmpty;
        _checkingStatus = false;
      });
    }
  } catch (e) {
    if (mounted) {
      setState(() => _checkingStatus = false);
      _showError('Could not load key status: $e');
    }
  }
}
```

Every async gap in the Vault screen must check `if (mounted)` before `setState`.

**Confirmation dialog before destructive actions** (receiver_screen.dart lines 253-302 — `_showCloseSessionDialog`):
```dart
Future<bool> _showCloseSessionDialog() async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => GlassContainer(
      borderRadius: 24,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BottomSheetHandle(),
          const SizedBox(height: 10),
          const Icon(Icons.power_settings_new_rounded, size: 48, color: Colors.orange),
          const SizedBox(height: 16),
          Text('Close Mailbox?', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600)),
          // ... message + Cancel/Confirm row with GlassButton
        ],
      ),
    ),
  );
  return result ?? false;
}
```

Copy this pattern for the Vault's Regenerate and Delete confirmation dialogs. Use `Icons.warning_rounded` / `Colors.red` for Delete; `Icons.refresh_rounded` / `AppTheme.primaryBlue` for Regenerate.

**GlassButton for actions** (shared_widgets.dart lines 62-112):
```dart
GlassButton(
  icon: const Icon(Icons.vpn_key_rounded, size: 20),
  label: const Text('Generate RSA Keys'),
  onPressed: _generateKeys,
  color: AppTheme.primaryBlue,
)
```

Use `GlassButton` (not `FilledButton`) for all vault primary actions to match the app-wide 3D button system (D-20).

**Error display pattern** (receiver_screen.dart lines 412-419):
```dart
void _showError(String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg.replaceFirst('Exception: ', '')),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
}
```

**Progress dialog pattern** (receiver_screen.dart lines 396-410):
```dart
void _showProgressDialog(String message) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}
```

Use this pattern when showing the RSA key generation spinner (RSA-2048 `compute()` takes 1-4 seconds on mobile).

**Key status display card** (receiver_screen.dart lines 421-461 — `_step1Content`):
```dart
GlassContainer(
  padding: const EdgeInsets.all(14),
  color: Colors.green.withValues(alpha: 0.1),
  borderColor: Colors.green.withValues(alpha: 0.2),
  child: Column(
    children: [
      Row(
        children: [
          const Icon(Icons.verified_rounded, color: Colors.green, size: 18),
          const SizedBox(width: 8),
          Text('RSA-2048 Ready', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.green)),
        ],
      ),
      const SizedBox(height: 8),
      // _KeyInfoRow('Status', 'Local keypair verified'),
    ],
  ),
)
```

For the Vault's View section, extend `_KeyInfoRow` pattern (lines 627-643) to display fingerprint, algorithm, and createdAt.

---

### `lib/data/repositories/auth_repository.dart` (MODIFY — extend with new methods)

**Analog:** self — extend existing file

**Current structure** (auth_repository.dart lines 17-29):
```dart
class AuthRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final FlutterSecureStorage _secure;

  AuthRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? db,
    FlutterSecureStorage? secure,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance,
        _secure = secure ?? const FlutterSecureStorage();
```

**Existing key gen pattern to extend** (auth_repository.dart lines 173-189):
```dart
Future<void> generateAndStoreKeyPair() async {
  final pair = await compute(_generateKeyPairIsolate, null);
  final pubKey = pair.publicKey as RSAPublicKey;
  final privKey = pair.privateKey as RSAPrivateKey;

  await _secure.write(
    key: FirebaseConstants.privateKeyStorageKey,
    value: EncryptionService.encodePrivateKey(privKey),
  );

  final uid = _auth.currentUser?.uid;
  if (uid == null) throw AuthException('Not authenticated.');

  await _db.collection(FirebaseConstants.users).doc(uid).update({
    'publicKey': EncryptionService.encodePublicKey(pubKey),
  });
}
```

New methods `regenerateKeyPair()` and `deleteKeyPair()` copy this skeleton, then add a `WriteBatch` for the audit log append (see RESEARCH.md Example 2 and 3).

**register() method to migrate to WriteBatch** (auth_repository.dart lines 60-71):
```dart
// CURRENT (plain set — no batch):
await _db.collection(FirebaseConstants.users).doc(credential.user!.uid).set({
  'username': username,
  'email': email,
  'phone': phone,
  'publicKey': null,
  'isAdmin': false,
  'isFirstTime': true,
  'createdAt': FieldValue.serverTimestamp(),
});
```

Replace with a `WriteBatch` that atomically adds the `profile/preferences` doc. Pattern from RESEARCH.md Pattern 4:
```dart
final batch = _db.batch();
batch.set(
  _db.collection(FirebaseConstants.users).doc(uid),
  { 'username': username, 'email': email, /* ... */ },
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

**signInWithGoogle() method — same migration** (auth_repository.dart lines 135-144):
```dart
// CURRENT (plain set inside !userDoc.exists block):
await _db.collection(FirebaseConstants.users).doc(user.uid).set({
  'username': username,
  'email': user.email,
  // ...
});
```

Replace the `set()` call with the same `WriteBatch` pattern as `register()`. The `profile/preferences` doc is only written here for NEW Google users (inside `!userDoc.exists` block). Use `SetOptions(merge: true)` in `updateLastVaultAccess()` for existing users who lack the doc (lazy creation — RESEARCH.md Pitfall 4).

**Existing error pattern** (auth_repository.dart lines 87-90):
```dart
} on FirebaseException catch (e) {
  throw NetworkException('Database error. Check your connection.',
      code: 'firestore-error:${e.code}');
}
```

New methods follow the same `throw AuthException` / `throw NetworkException` pattern from `../../core/errors/app_exceptions.dart`.

---

### `lib/core/constants/firebase_constants.dart` (MODIFY — add 2 constants)

**Analog:** self — extend existing file

**Current last constant** (firebase_constants.dart lines 21-22):
```dart
static const String privateKeyStorageKey = 'rsa_private_key';
static const String publicKeyStoragePrefix = 'rsa_public_key_';
```

Add after the existing Firestore collections block (after line 14, `securityAuditLog`):
```dart
static const String rsaKeyManager = 'rsa_key_manager';  // subcollection under users/{uid}
static const String profile = 'profile';                 // subcollection under users/{uid}
```

No other changes needed; follow the exact `static const String` pattern established in the file.

---

### `firestore.rules` (MODIFY — add 2 match blocks inside `users/{userId}`)

**Analog:** `audit_logs` block (firestore.rules lines 71-89)

**Existing audit_logs block to copy structure from** (firestore.rules lines 71-89):
```
match /audit_logs/{logId} {
  // Owner reads their own history; admin sees all.
  allow read: if isOwner(userId) || isAdmin();

  // A participant (sender or receiver) may create a log in any
  // user's sub-collection, provided they appear in the document.
  allow create: if isAuthenticated() &&
                   (request.resource.data.senderId == request.auth.uid ||
                    request.resource.data.receiverId == request.auth.uid);

  allow update: if false;       // IMMUTABLE — never modifiable by anyone
  allow delete: if isAdmin();   // Admin-only emergency purge
}
```

**New blocks to add immediately after the `audit_logs` block** (insert after line 89):
```
// ── users/{userId}/rsa_key_manager ───────────────────────────────────────
// Append-only RSA key lifecycle audit log. Owner creates; admin deletes.
// Documents are IMMUTABLE (update: false) — tamper-evident evidence trail.
match /rsa_key_manager/{logId} {
  allow read: if isOwner(userId) || isAdmin();
  allow create: if isOwner(userId) &&
                   request.resource.data.action in ['generated', 'regenerated', 'deleted'];
  allow update: if false;       // IMMUTABLE
  allow delete: if isAdmin();
}

// ── users/{userId}/profile ────────────────────────────────────────────────
// Security/UX preferences. Owner reads/creates/updates; admin can manage.
match /profile/{prefId} {
  allow read: if isOwner(userId) || isAdmin();
  allow create: if isOwner(userId);
  allow update: if isOwner(userId) || isAdmin();
  allow delete: if isAdmin();
}
```

Both blocks go INSIDE the `match /users/{userId}` block (before the closing `}` at line 101), following the exact same indentation and comment style as `audit_logs` and `notifications`.

---

### `lib/presentation/receiver/receiver_screen.dart` (MODIFY — add no-keys banner)

**Analog:** self — add to `_step1Content()` (lines 421-461)

**Current `_step1Content()` pattern** (receiver_screen.dart lines 421-461):
```dart
Widget _step1Content() {
  if (_checkingStatus) return const LinearProgressIndicator();
  if (_step1Done) {
    return Column(/* ... verified card + regenerate button ... */);
  }
  return GlassButton(
    icon: const Icon(Icons.vpn_key_rounded, size: 20),
    label: const Text('Generate RSA Keys'),
    onPressed: _generateKeys,
    color: AppTheme.primaryBlue,
  );
}
```

Replace the final `return GlassButton(...)` with the no-keys warning banner that navigates to the Vault screen. Pattern from RESEARCH.md Example 5:
```dart
// When !_step1Done && !_checkingStatus — show banner instead of old GlassButton
return Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
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
  ],
);
```

The `.then((_) => _checkKeyStatus())` is the key wiring: after returning from the Vault, ReceiverScreen re-runs `_checkKeyStatus()` to update `_hasPrivateKey` / `_hasPublicKey`. This avoids any new Firestore subscription — RESEARCH.md Pitfall 5.

**Import to add** — add at top of receiver_screen.dart imports:
```dart
import '../vault/rsa_key_manager_screen.dart';
```

Also: the existing `_generateKeys()` method (lines 132-175) and `_openKeyManager()` method (lines 378-394) should be removed or redirected to the Vault screen per RESEARCH.md open questions recommendation.

---

### `lib/presentation/home/sidebar_drawer.dart` (MODIFY — replace "Generate RSA Keys" entry)

**Analog:** self — replace `ListTile` at lines 91-99

**Current "Generate RSA Keys" entry** (sidebar_drawer.dart lines 91-99):
```dart
ListTile(
  leading: Icon(Icons.vpn_key_outlined, color: cs.primary),
  title: const Text('Generate RSA Keys'),
  subtitle: const Text('Create your encryption key pair'),
  onTap: () {
    Navigator.pop(context);
    _showKeyGenDialog(context);
  },
),
```

Replace `onTap` to navigate to `RsaKeyManagerScreen` instead of the dialog:
```dart
ListTile(
  leading: Icon(Icons.vpn_key_outlined, color: cs.primary),
  title: const Text('Key Vault'),
  subtitle: const Text('Manage your RSA encryption keys'),
  onTap: () {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RsaKeyManagerScreen()),
    );
  },
),
```

Remove `_KeyGenDialog` class (lines 196-269) and `_Status` enum (line 270) — they become dead code after this change. Remove `_showKeyGenDialog` method (lines 187-193).

**Navigation pattern** (sidebar_drawer.dart lines 82-89 — Find Friends entry):
```dart
ListTile(
  leading: Icon(Icons.people_outline, color: cs.primary),
  title: const Text('Find Friends'),
  onTap: () {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FindFriendsScreen()),
    );
  },
),
```

The Vault `ListTile` copies this exact navigation pattern (`Navigator.pop` to close drawer, then `Navigator.push` to open screen).

**Import to add** at top of sidebar_drawer.dart:
```dart
import '../vault/rsa_key_manager_screen.dart';
```

---

### `test/vault/vault_gate_test.dart` + `key_lifecycle_test.dart` + `profile_init_test.dart` (NEW tests)

**Analog:** `test/security/session_wipe_test.dart`

**Test file structure** (session_wipe_test.dart lines 1-10):
```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';

import 'package:cryptransfer/core/utils/session_manager.dart';

void main() {
  group('SESSION WIPE SECURITY TESTS', () {
    late FakeFirebaseFirestore fakeFirestore;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
    });
```

Copy this structure for all vault tests:
- Replace `session_manager.dart` import with `auth_repository.dart`
- Replace `FakeFirebaseFirestore` in `setUp` with same pattern
- Use `group('VAULT GATE TESTS', () { ... })` naming convention
- Use `test('TC-VAULT-01: ...', () async { ... })` naming (TC-VAULT-NN to match existing TC-WIPE-NN pattern)

**Firestore test assertion pattern** (session_wipe_test.dart lines 32-64):
```dart
// Setup Firestore doc
await fakeFirestore.collection('users').doc(userId).set({
  'username': 'test_user',
  'publicKey': 'FAKE_RSA_PUBLIC_KEY',
  'isReadyToReceive': true,
});

// Perform operation under test
await fakeFirestore.collection('users').doc(userId).update({
  'publicKey': FieldValue.delete(),
});

// Assert
final afterOp = await fakeFirestore.collection('users').doc(userId).get();
expect(
  afterOp.data()!.containsKey('publicKey'),
  false,
  reason: 'publicKey must be deleted after deleteKeyPair()',
);

// Status print
print('✅ TC-VAULT-XX PASSED: ...');
```

For `profile_init_test.dart`: assert that `users/{uid}/profile/preferences` subcollection doc exists AND has correct initial field values after calling the migrated `register()`. Use `fakeFirestore.collection('users').doc(uid).collection('profile').doc('preferences').get()`.

---

### `test/vault/receiver_banner_test.dart` (NEW test)

**Analog:** `test/security/mem_safety_test.dart` (pure logic test, no Firestore needed)

**Structure** (mem_safety_test.dart lines 1-12):
```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MEMORY SAFETY TESTS', () {
    test(
      'TC-MEM-001a: ...',
      () {
        // pure logic assertions, no async
        expect(kIsWeb, false, reason: '...');
        print('✅ TC-MEM-001a PASSED: ...');
      },
    );
```

For `receiver_banner_test.dart`, the test verifies banner visibility logic as a widget test. Use `flutter_test`'s `testWidgets` instead of `test` since it needs to pump a widget tree. Follow the group/test naming convention and `✅ TC-VAULT-06 PASSED:` print pattern.

---

### `lib/app_theme.dart` (MODIFY — Wave 0 fix: add `textMain` and `textSecondary` aliases)

**Analog:** self — extend existing file

**Current getters that cause 21 analyzer errors** (app_theme.dart lines 9-10 and 17-18):
```dart
static const Color lightTextMain = Color(0xFF0F172A);
static const Color lightTextSecondary = Color(0xFF64748B);
// ...
static const Color darkTextMain = Color(0xFFF8FAFC);
static const Color darkTextSecondary = Color(0xFF94A3B8);
```

Files referencing `AppTheme.textMain` and `AppTheme.textSecondary` (receiver_screen.dart lines 451, 508, 639, etc.) expect theme-unqualified aliases. Fix: add static const aliases after the existing dark palette constants:

```dart
// Theme-unqualified aliases — resolve to dark values (app uses dark theme by default)
static const Color textMain = darkTextMain;
static const Color textSecondary = darkTextSecondary;
```

This is a 2-line addition with no logic change.

---

### `lib/presentation/admin/admin_dashboard.dart` (MODIFY — Wave 0 fix: add missing imports)

**Analog:** self — add imports at top

**Current imports** (admin_dashboard.dart lines 1-10):
```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/firebase_constants.dart';
import 'widgets/security_pulse_feed.dart';
import 'widgets/transfer_volume_chart.dart';
import 'widgets/connection_node_map.dart';
import 'widgets/user_management_list.dart';
```

The file references `AppTheme.dark` (line 37) and `GlassContainer` (elsewhere) but neither is imported. Add:
```dart
import '../../app_theme.dart';
import '../widgets/shared_widgets.dart';
```

---

## Shared Patterns

### SecurityLifecycleMixin
**Source:** `lib/core/utils/security_lifecycle_mixin.dart` (entire file, 108 lines)
**Apply to:** `RsaKeyManagerScreen` (D-19)

```dart
// Declaration pattern:
class _RsaKeyManagerScreenState extends State<RsaKeyManagerScreen>
    with SecurityLifecycleMixin<RsaKeyManagerScreen> {

// Buffer registration (if any Uint8List key material is held briefly):
registerBuffer(someBuffer);

// Dispose is handled automatically by the mixin — no manual wipeAll() needed
// unless triggering early wipe on explicit close.
```

### GlassContainer + GlassButton
**Source:** `lib/presentation/widgets/shared_widgets.dart` lines 9-112
**Apply to:** `RsaKeyManagerScreen` for all cards and action buttons

```dart
// Card container:
GlassContainer(
  padding: const EdgeInsets.all(14),
  color: Colors.green.withValues(alpha: 0.1),
  borderColor: Colors.green.withValues(alpha: 0.2),
  child: /* ... */,
)

// Action button (Regenerate / Delete / Generate):
GlassButton(
  icon: const Icon(Icons.refresh_rounded, size: 20),
  label: const Text('Regenerate Keys'),
  onPressed: _onRegenerate,
  color: AppTheme.primaryBlue,  // or Colors.red for Delete
)
```

### FieldValue.serverTimestamp() for audit docs
**Source:** `lib/data/repositories/auth_repository.dart` lines 60-70 and `firestore.rules` lines 71-89
**Apply to:** All new Firestore writes in the `rsa_key_manager` subcollection

```dart
// Append audit doc:
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

### WriteBatch for atomic multi-doc writes
**Source:** Pattern established in RESEARCH.md Pattern 4; nearest codebase analog is the `KeyRepository.selectSenderHandshake()` method in `lib/data/repositories/key_repository.dart`
**Apply to:** `register()` + `signInWithGoogle()` in `auth_repository.dart`; `regenerateKeyPair()` + `deleteKeyPair()` audit log appends

```dart
final batch = _db.batch();
batch.set(docRef1, data1);
batch.set(docRef2, data2);
await batch.commit();
```

### compute() for off-thread RSA operations
**Source:** `lib/data/repositories/auth_repository.dart` lines 13-15 and 173-174

```dart
// Top-level function (must be top-level, not a closure):
AsymmetricKeyPair<PublicKey, PrivateKey> _generateKeyPairIsolate(dynamic _) =>
    EncryptionService.generateRsaKeyPairSync();

// Call site:
final pair = await compute(_generateKeyPairIsolate, null);
```

`regenerateKeyPair()` reuses the same top-level function — no new isolate function needed.

### mounted guard after async gaps
**Source:** `lib/presentation/receiver/receiver_screen.dart` lines 117-129 (every async method)
**Apply to:** All async methods in `RsaKeyManagerScreen`

```dart
if (mounted) {
  setState(() { /* ... */ });
}
```

### Snackbar error display
**Source:** `lib/presentation/receiver/receiver_screen.dart` lines 412-419
**Apply to:** `RsaKeyManagerScreen._showError()`

```dart
void _showError(String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg.replaceFirst('Exception: ', '')),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
}
```

---

## No Analog Found

All files have codebase analogs. No entries.

---

## Metadata

**Analog search scope:** `lib/`, `test/`, `firestore.rules`
**Files read:** auth_repository.dart, firebase_constants.dart, biometric_helper.dart, firestore.rules, receiver_screen.dart, app_theme.dart, admin_dashboard.dart (partial), shared_widgets.dart (partial), sidebar_drawer.dart, find_friends_screen.dart (partial), security_lifecycle_mixin.dart, session_wipe_test.dart (partial), mem_safety_test.dart (partial)
**Pattern extraction date:** 2026-05-02
