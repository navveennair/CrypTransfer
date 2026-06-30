# Clear Cache (Stale Key Cleanup) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a signed-in user scan Firestore (the source of truth, not just local secure storage) for RSA/AES key material left behind by a session that ended without proper cleanup, and clear it on confirmation, via a new "Clear Cache" sidebar action.

**Architecture:** Two new read-only/write `KeyRepository` methods (`scanForStaleKeys()`, `clearStaleKeys(scan)`) operating on a small `StaleKeyScanResult` model, surfaced through a new stateful bottom-sheet widget (`ClearCacheSheet`) wired into the existing sidebar between "Key Vault" and "Settings".

**Tech Stack:** Flutter/Dart, `cloud_firestore`, `flutter_secure_storage`, `fake_cloud_firestore` + `firebase_auth_mocks` for tests (matches every other repository test in this codebase).

**Source spec:** `docs/superpowers/specs/2026-06-22-clear-cache-stale-keys-design.md` (Approved).

## Global Constraints

- No new Firestore rules or indexes — every query/delete this feature needs is already covered by rules deployed this session (`allow get`/`allow list` split on `transfers`; `allow update: if isOwner(userId) || isAdmin()` on `users`).
- `clearStaleKeys(scan)` must operate on the exact `StaleKeyScanResult` passed in, never a fresh re-scan — avoids a race with legitimate data created between scan and confirm.
- Do NOT call `EncryptionService.closeReceiverSession()` for the RSA-remediation step — its unconditional `handshakes` and `connection_request`/`rsa_key_received` notification purge has a wider blast radius than "stale key cleanup" implies (this was explicitly considered and rejected during brainstorming). Duplicate the few necessary lines instead.
- Deleting a `transfers/{id}` doc must delete the whole document, not just `encryptedAESKey` — matches what should have happened at normal session end. "Recent Transfers" history is unaffected; it reads from `users/{uid}/audit_logs`, a separate permanent subcollection.
- Staleness filtering by `status` happens client-side in Dart after a plain equality fetch (`where('senderId'/'receiverId', isEqualTo: uid)`), not server-side, specifically to avoid needing a new composite index.

---

### Task 1: `StaleKeyScanResult` model + `KeyRepository.scanForStaleKeys()`

**Files:**
- Create: `lib/data/models/stale_key_scan_result.dart`
- Modify: `lib/data/repositories/key_repository.dart` (add method; insert near the other session/cleanup methods, e.g. after `wipeAllSessionKeys` around line 793)
- Test: Create `test/key_repository/clear_cache_test.dart`

**Interfaces:**
- Produces: `class StaleKeyScanResult { final bool hasStaleRsaSession; final List<String> staleTransferIds; bool get isClean; const StaleKeyScanResult({required this.hasStaleRsaSession, required this.staleTransferIds}); }`
- Produces: `Future<StaleKeyScanResult> KeyRepository.scanForStaleKeys()` — read-only, uses `_uid`.
- Consumes (existing, unmodified): `KeyRepository(db:, auth:, secure:)` constructor; `FirebaseConstants.users`, `FirebaseConstants.transfers`, `FirebaseConstants.privateKeyStorageKey`.

- [ ] **Step 1: Create the model**

```dart
// lib/data/models/stale_key_scan_result.dart

/// Result of KeyRepository.scanForStaleKeys() — what key material exists
/// for the current account that no longer belongs to an active session.
class StaleKeyScanResult {
  final bool hasStaleRsaSession;
  final List<String> staleTransferIds;

  const StaleKeyScanResult({
    required this.hasStaleRsaSession,
    required this.staleTransferIds,
  });

  bool get isClean => !hasStaleRsaSession && staleTransferIds.isEmpty;
}
```

- [ ] **Step 2: Write the failing tests**

Create `test/key_repository/clear_cache_test.dart` with this content (this task's tests only — Task 2 appends more to the same file):

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cryptransfer/core/constants/firebase_constants.dart';
import 'package:cryptransfer/data/repositories/key_repository.dart';

import '../mocks/mock_firebase.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('KeyRepository.scanForStaleKeys', () {
    late FakeFirebaseFirestore db;
    late MockFirebaseAuth auth;
    late FakeSecureStorage secure;
    const uid = 'user1';

    setUp(() {
      db = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid));
      secure = FakeSecureStorage();
    });

    KeyRepository repo() => KeyRepository(db: db, auth: auth, secure: secure);

    // ─── TC-CC-01 ──────────────────────────────────────────────────────────

    test('TC-CC-01: clean state returns isClean == true', () async {
      await db.collection(FirebaseConstants.users).doc(uid).set({
        'isReadyToReceive': false,
      });

      final scan = await repo().scanForStaleKeys();

      expect(scan.isClean, true,
          reason: 'no publicKey, no local key, no transfers → clean');
      expect(scan.hasStaleRsaSession, false);
      expect(scan.staleTransferIds, isEmpty);
    });

    // ─── TC-CC-02 ──────────────────────────────────────────────────────────

    test(
      'TC-CC-02: stale RSA via Firestore publicKey (isReadyToReceive false)',
      () async {
        await db.collection(FirebaseConstants.users).doc(uid).set({
          'isReadyToReceive': false,
          'publicKey': 'LEFTOVER_PUBLIC_KEY',
        });

        final scan = await repo().scanForStaleKeys();

        expect(scan.hasStaleRsaSession, true,
            reason: 'publicKey present + isReadyToReceive=false = stale');
        expect(scan.staleTransferIds, isEmpty);
      },
    );

    // ─── TC-CC-03 ──────────────────────────────────────────────────────────

    test(
      'TC-CC-03: stale RSA via local secure-storage key only '
      '(no Firestore publicKey)',
      () async {
        await db.collection(FirebaseConstants.users).doc(uid).set({
          'isReadyToReceive': false,
        });
        await secure.write(
          key: FirebaseConstants.privateKeyStorageKey,
          value: 'LEFTOVER_PRIVATE_KEY_PEM',
        );

        final scan = await repo().scanForStaleKeys();

        expect(scan.hasStaleRsaSession, true,
            reason: 'the OR branch — local private key alone must also '
                'count as stale, per the design doc\'s "either ... OR" rule');
      },
    );

    // ─── TC-CC-04 ──────────────────────────────────────────────────────────

    test(
      'TC-CC-04: active session (isReadyToReceive true) is NOT flagged',
      () async {
        await db.collection(FirebaseConstants.users).doc(uid).set({
          'isReadyToReceive': true,
          'publicKey': 'ACTIVE_PUBLIC_KEY',
        });
        await secure.write(
          key: FirebaseConstants.privateKeyStorageKey,
          value: 'ACTIVE_PRIVATE_KEY_PEM',
        );

        final scan = await repo().scanForStaleKeys();

        expect(scan.hasStaleRsaSession, false,
            reason: 'isReadyToReceive=true means this is a live session, '
                'regardless of what key material exists');
      },
    );

    // ─── TC-CC-05 ──────────────────────────────────────────────────────────

    test(
      'TC-CC-05: stale transfers — only terminal-status docs with a '
      'non-empty encryptedAESKey are returned',
      () async {
        await db.collection(FirebaseConstants.users).doc(uid).set({
          'isReadyToReceive': false,
        });

        // Stale: terminal status, key present.
        final staleDoc = await db.collection(FirebaseConstants.transfers).add({
          'senderId': uid,
          'receiverId': 'other1',
          'status': 'completed',
          'encryptedAESKey': 'LEFTOVER_AES_KEY',
        });
        // Not stale: terminal status, but key already wiped.
        await db.collection(FirebaseConstants.transfers).add({
          'senderId': uid,
          'receiverId': 'other2',
          'status': 'completed',
          'encryptedAESKey': '',
        });
        // Not stale: not terminal.
        await db.collection(FirebaseConstants.transfers).add({
          'senderId': uid,
          'receiverId': 'other3',
          'status': 'in-progress',
          'encryptedAESKey': 'IN_PROGRESS_KEY',
        });

        final scan = await repo().scanForStaleKeys();

        expect(scan.staleTransferIds, [staleDoc.id]);
      },
    );

    // ─── TC-CC-06 ──────────────────────────────────────────────────────────

    test(
      'TC-CC-06: active transfer (status pending, key set) is NOT flagged, '
      'NOT a candidate for deletion',
      () async {
        await db.collection(FirebaseConstants.users).doc(uid).set({
          'isReadyToReceive': false,
        });
        await db.collection(FirebaseConstants.transfers).add({
          'senderId': uid,
          'receiverId': 'other1',
          'status': 'pending',
          'encryptedAESKey': 'ACTIVE_AES_KEY',
        });

        final scan = await repo().scanForStaleKeys();

        expect(scan.staleTransferIds, isEmpty);
      },
    );

    // ─── TC-CC-07 ──────────────────────────────────────────────────────────

    test(
      'TC-CC-07: both stale RSA and stale transfers detected in one scan',
      () async {
        await db.collection(FirebaseConstants.users).doc(uid).set({
          'isReadyToReceive': false,
          'publicKey': 'LEFTOVER_PUBLIC_KEY',
        });
        final staleDoc = await db.collection(FirebaseConstants.transfers).add({
          'senderId': uid,
          'receiverId': 'other1',
          'status': 'aborted',
          'encryptedAESKey': 'LEFTOVER_AES_KEY',
        });

        final scan = await repo().scanForStaleKeys();

        expect(scan.hasStaleRsaSession, true);
        expect(scan.staleTransferIds, [staleDoc.id]);
        expect(scan.isClean, false);
      },
    );
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/key_repository/clear_cache_test.dart`
Expected: FAIL — `scanForStaleKeys` is not a member of `KeyRepository` (compile error).

- [ ] **Step 4: Implement `scanForStaleKeys()`**

Add to `lib/data/repositories/key_repository.dart`, right after the closing brace of `wipeAllSessionKeys` (the method ending at line 793 in the current file):

```dart
  /// Scans Firestore (the source of truth, not just local secure storage)
  /// for RSA/AES key material left behind by a session that ended without
  /// proper cleanup. Read-only — does not modify any state.
  Future<StaleKeyScanResult> scanForStaleKeys() async {
    final userDoc =
        await _db.collection(FirebaseConstants.users).doc(_uid).get();
    final userData = userDoc.data();
    final isReady = userData?['isReadyToReceive'] as bool? ?? false;
    final publicKey = userData?['publicKey'] as String?;
    final hasFirestorePublicKey = publicKey != null && publicKey.isNotEmpty;
    final localPrivateKey =
        await _secure.read(key: FirebaseConstants.privateKeyStorageKey);
    final hasLocalPrivateKey = localPrivateKey != null;
    final hasStaleRsaSession =
        !isReady && (hasFirestorePublicKey || hasLocalPrivateKey);

    const staleStatuses = {
      'completed',
      'aborted',
      'failed',
      'cancelled',
      'connection_lost',
    };

    final asSender = await _db
        .collection(FirebaseConstants.transfers)
        .where('senderId', isEqualTo: _uid)
        .get();
    final asReceiver = await _db
        .collection(FirebaseConstants.transfers)
        .where('receiverId', isEqualTo: _uid)
        .get();

    final staleTransferIds = <String>{};
    for (final doc in [...asSender.docs, ...asReceiver.docs]) {
      final data = doc.data();
      final status = data['status'] as String?;
      final encryptedAESKey = data['encryptedAESKey'] as String?;
      if (status != null &&
          staleStatuses.contains(status) &&
          encryptedAESKey != null &&
          encryptedAESKey.isNotEmpty) {
        staleTransferIds.add(doc.id);
      }
    }

    return StaleKeyScanResult(
      hasStaleRsaSession: hasStaleRsaSession,
      staleTransferIds: staleTransferIds.toList(),
    );
  }
```

Add the import at the top of `key_repository.dart`, alongside the existing `user_model.dart` import:

```dart
import '../models/stale_key_scan_result.dart';
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/key_repository/clear_cache_test.dart`
Expected: `All tests passed!` (7 tests).

- [ ] **Step 6: Run full analyze + suite**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: all tests pass (144 existing + 7 new = 151).

- [ ] **Step 7: Commit**

```bash
git add lib/data/models/stale_key_scan_result.dart lib/data/repositories/key_repository.dart test/key_repository/clear_cache_test.dart
git commit -m "feat(vault): add KeyRepository.scanForStaleKeys()

Read-only scan for RSA/AES key material left behind by a session that
ended without proper cleanup (e.g. force-killed before the reactive
kill-switch could run). Checks the user doc's publicKey/isReadyToReceive
in Firestore (source of truth) and the local secure-storage private key
together — either one present while isReadyToReceive is false counts as
stale. Separately flags transfers in a terminal status with a
non-empty encryptedAESKey still on the doc.

Part of the approved Clear Cache design
(docs/superpowers/specs/2026-06-22-clear-cache-stale-keys-design.md).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 2: `KeyRepository.clearStaleKeys(scan)`

**Files:**
- Modify: `lib/data/repositories/key_repository.dart` (add method, right after `scanForStaleKeys`)
- Modify: `test/key_repository/clear_cache_test.dart` (append a second `group`)

**Interfaces:**
- Consumes: `StaleKeyScanResult` (Task 1), `KeyRepository._uid`, `EncryptionService.clearLiveSession(String uid)` (already exists — added this session in `lib/data/services/encryption_service.dart`).
- Produces: `Future<void> KeyRepository.clearStaleKeys(StaleKeyScanResult scan)`.

- [ ] **Step 1: Write the failing tests**

Append this second group to `test/key_repository/clear_cache_test.dart`, inside the same `main()`, after the `scanForStaleKeys` group's closing `});`:

```dart
  group('KeyRepository.clearStaleKeys', () {
    late FakeFirebaseFirestore db;
    late MockFirebaseAuth auth;
    late FakeSecureStorage secure;
    const uid = 'user1';

    setUp(() {
      db = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid));
      secure = FakeSecureStorage();
    });

    KeyRepository repo() => KeyRepository(db: db, auth: auth, secure: secure);

    // ─── TC-CC-08 ──────────────────────────────────────────────────────────

    test(
      'TC-CC-08: stale RSA only — wipes Firestore publicKey + local key, '
      'sets isReadyToReceive/sessionActive false',
      () async {
        await db.collection(FirebaseConstants.users).doc(uid).set({
          'isReadyToReceive': false,
          'sessionActive': true,
          'publicKey': 'LEFTOVER_PUBLIC_KEY',
        });
        await secure.write(
          key: FirebaseConstants.privateKeyStorageKey,
          value: 'LEFTOVER_PRIVATE_KEY_PEM',
        );

        final scan = await repo().scanForStaleKeys();
        expect(scan.hasStaleRsaSession, true);

        await repo().clearStaleKeys(scan);

        final userDoc =
            await db.collection(FirebaseConstants.users).doc(uid).get();
        expect(userDoc.data()!.containsKey('publicKey'), false);
        expect(userDoc.data()!['isReadyToReceive'], false);
        expect(userDoc.data()!['sessionActive'], false);
        expect(
          await secure.read(key: FirebaseConstants.privateKeyStorageKey),
          isNull,
        );
      },
    );

    // ─── TC-CC-09 ──────────────────────────────────────────────────────────

    test(
      'TC-CC-09: stale transfers only — deletes exactly those docs, '
      'leaves others untouched',
      () async {
        await db.collection(FirebaseConstants.users).doc(uid).set({
          'isReadyToReceive': false,
        });
        final staleDoc = await db.collection(FirebaseConstants.transfers).add({
          'senderId': uid,
          'receiverId': 'other1',
          'status': 'completed',
          'encryptedAESKey': 'LEFTOVER_AES_KEY',
        });
        final activeDoc = await db.collection(FirebaseConstants.transfers).add({
          'senderId': uid,
          'receiverId': 'other2',
          'status': 'pending',
          'encryptedAESKey': 'ACTIVE_AES_KEY',
        });

        final scan = await repo().scanForStaleKeys();
        await repo().clearStaleKeys(scan);

        expect(
          (await db.collection(FirebaseConstants.transfers).doc(staleDoc.id).get())
              .exists,
          false,
        );
        expect(
          (await db.collection(FirebaseConstants.transfers).doc(activeDoc.id).get())
              .exists,
          true,
        );
      },
    );

    // ─── TC-CC-10 ──────────────────────────────────────────────────────────

    test(
      'TC-CC-10: both stale RSA and stale transfers cleaned in one call',
      () async {
        await db.collection(FirebaseConstants.users).doc(uid).set({
          'isReadyToReceive': false,
          'publicKey': 'LEFTOVER_PUBLIC_KEY',
        });
        final staleDoc = await db.collection(FirebaseConstants.transfers).add({
          'senderId': uid,
          'receiverId': 'other1',
          'status': 'failed',
          'encryptedAESKey': 'LEFTOVER_AES_KEY',
        });

        final scan = await repo().scanForStaleKeys();
        await repo().clearStaleKeys(scan);

        final userDoc =
            await db.collection(FirebaseConstants.users).doc(uid).get();
        expect(userDoc.data()!.containsKey('publicKey'), false);
        expect(
          (await db.collection(FirebaseConstants.transfers).doc(staleDoc.id).get())
              .exists,
          false,
        );
      },
    );

    // ─── TC-CC-11 ──────────────────────────────────────────────────────────

    test(
      'TC-CC-11: unrelated connection_request notification and handshakes '
      'doc survive clearStaleKeys untouched (locks in the decision not to '
      'reuse closeReceiverSession)',
      () async {
        await db.collection(FirebaseConstants.users).doc(uid).set({
          'isReadyToReceive': false,
          'publicKey': 'LEFTOVER_PUBLIC_KEY',
        });
        final notif = await db
            .collection(FirebaseConstants.users)
            .doc(uid)
            .collection(FirebaseConstants.notifications)
            .add({'type': 'connection_request', 'read': false});
        final handshake = await db.collection(FirebaseConstants.handshakes).add({
          'senderId': 'someoneElse',
          'receiverId': uid,
          'status': 'handshake_complete',
        });

        final scan = await repo().scanForStaleKeys();
        await repo().clearStaleKeys(scan);

        expect(
          (await db
                  .collection(FirebaseConstants.users)
                  .doc(uid)
                  .collection(FirebaseConstants.notifications)
                  .doc(notif.id)
                  .get())
              .exists,
          true,
          reason: 'clearStaleKeys must not touch notifications — that is '
              "closeReceiverSession's broader (and rejected-for-reuse) blast "
              'radius',
        );
        expect(
          (await db.collection(FirebaseConstants.handshakes).doc(handshake.id).get())
              .exists,
          true,
          reason: 'clearStaleKeys must not touch handshakes',
        );
      },
    );

    // ─── TC-CC-12 ──────────────────────────────────────────────────────────

    test(
      'TC-CC-12: clearStaleKeys clears the live-session marker for this uid',
      () async {
        await db.collection(FirebaseConstants.users).doc(uid).set({
          'isReadyToReceive': false,
          'publicKey': 'LEFTOVER_PUBLIC_KEY',
        });
        EncryptionService.markLiveSession(uid);
        expect(EncryptionService.isLiveSessionFor(uid), true);

        final scan = await repo().scanForStaleKeys();
        await repo().clearStaleKeys(scan);

        expect(
          EncryptionService.isLiveSessionFor(uid),
          false,
          reason: 'every code path that deletes the private key '
              '(AuthRepository.deleteKeyPair, EncryptionService.'
              'closeReceiverSession) also calls clearLiveSession — '
              'clearStaleKeys deletes the same key material and must too',
        );
      },
    );
  });
```

Add this import at the top of the test file, alongside the existing ones:

```dart
import 'package:cryptransfer/data/services/encryption_service.dart';
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/key_repository/clear_cache_test.dart`
Expected: FAIL — `clearStaleKeys` is not a member of `KeyRepository` (compile error).

- [ ] **Step 3: Implement `clearStaleKeys()`**

Add to `lib/data/repositories/key_repository.dart`, directly after `scanForStaleKeys`:

```dart
  /// Clears exactly the stale key material captured in [scan] — not a
  /// fresh re-scan — so the deletion targets exactly what the user
  /// confirmed, avoiding a race with new legitimate data created between
  /// scan and confirm.
  ///
  /// Deliberately does NOT call EncryptionService.closeReceiverSession():
  /// that also purges ALL handshakes and connection_request/
  /// rsa_key_received notifications regardless of status, which is a wider
  /// blast radius than "stale key cleanup" implies.
  Future<void> clearStaleKeys(StaleKeyScanResult scan) async {
    try {
      if (scan.hasStaleRsaSession) {
        await _secure.delete(key: FirebaseConstants.privateKeyStorageKey);
        await _db.collection(FirebaseConstants.users).doc(_uid).update({
          'publicKey': FieldValue.delete(),
          'isReadyToReceive': false,
          'sessionActive': false,
        });
        EncryptionService.clearLiveSession(_uid);
      }

      if (scan.staleTransferIds.isNotEmpty) {
        final batch = _db.batch();
        for (final id in scan.staleTransferIds) {
          batch.delete(_db.collection(FirebaseConstants.transfers).doc(id));
        }
        await batch.commit();
      }
    } on FirebaseException catch (e) {
      throw NetworkException(
        'Failed to clear stale keys: ${e.message ?? e.code}',
        code: e.code,
      );
    }
  }
```

Add the import at the top of `key_repository.dart`:

```dart
import '../services/encryption_service.dart';
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/key_repository/clear_cache_test.dart`
Expected: `All tests passed!` (12 tests total in this file).

- [ ] **Step 5: Run full analyze + suite**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: all tests pass (144 existing + 12 new = 156).

- [ ] **Step 6: Commit**

```bash
git add lib/data/repositories/key_repository.dart test/key_repository/clear_cache_test.dart
git commit -m "feat(vault): add KeyRepository.clearStaleKeys()

Clears exactly the StaleKeyScanResult passed in (not a fresh re-scan,
to avoid a race with legitimate data created between scan and
confirm). RSA remediation duplicates the few necessary lines from
EncryptionService.closeReceiverSession() rather than calling it
directly — that method's unconditional handshakes/notifications purge
is a wider blast radius than stale-key cleanup implies (see design
doc Architecture section). Also calls EncryptionService.
clearLiveSession() to keep the invariant from this session's
live-session-tracking fix intact: every path that deletes the private
key clears the live-session marker.

flutter analyze: No issues found. Full suite: 156/156 passing.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 3: `ClearCacheSheet` widget

**Files:**
- Create: `lib/presentation/home/clear_cache_sheet.dart`

**Interfaces:**
- Consumes: `KeyRepository()` (default constructor — real Firebase in production, same pattern every other screen in this codebase uses), `StaleKeyScanResult` (Task 1), `GlassContainer`/`BottomSheetHandle`/`CrypButton` (`lib/presentation/widgets/shared_widgets.dart`, unmodified).
- Produces: `class ClearCacheSheet extends StatefulWidget` — a `const ClearCacheSheet({super.key})` constructor, no parameters, intended to be shown via `showModalBottomSheet`.

No automated test for this task — consistent with this codebase's existing convention of not widget-testing screens/sheets that construct their own Firebase-backed repository inline without DI (e.g. `RsaKeyManagerScreen`, the existing `_KeyManagerSheet` in `receiver_screen.dart` have no widget tests either; only their extracted logic gets unit-tested). Verified instead by `flutter analyze` and manual run in Task 4.

- [ ] **Step 1: Create the widget**

```dart
// lib/presentation/home/clear_cache_sheet.dart

import 'package:flutter/material.dart';

import '../../data/models/stale_key_scan_result.dart';
import '../../data/repositories/key_repository.dart';
import '../widgets/shared_widgets.dart';

/// Scan → confirm → clear flow for leftover RSA/AES key material.
/// Show via showModalBottomSheet — kept as its own StatefulWidget (not
/// folded into SidebarDrawer, which stays a plain StatelessWidget) because
/// this flow has real async state: scanning, confirming, clearing.
class ClearCacheSheet extends StatefulWidget {
  const ClearCacheSheet({super.key});

  @override
  State<ClearCacheSheet> createState() => _ClearCacheSheetState();
}

enum _Phase { scanning, clean, found, clearing }

class _ClearCacheSheetState extends State<ClearCacheSheet> {
  final _keyRepo = KeyRepository();
  _Phase _phase = _Phase.scanning;
  StaleKeyScanResult? _scan;
  String? _scanError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runScan());
  }

  Future<void> _runScan() async {
    try {
      final scan = await _keyRepo.scanForStaleKeys();
      if (!mounted) return;
      setState(() {
        _scan = scan;
        _phase = scan.isClean ? _Phase.clean : _Phase.found;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _scanError = e.toString());
    }
  }

  String _summaryMessage(StaleKeyScanResult scan) {
    final parts = <String>[];
    if (scan.hasStaleRsaSession) {
      parts.add('1 stale RSA session');
    }
    final n = scan.staleTransferIds.length;
    if (n > 0) {
      parts.add('$n stale transfer${n == 1 ? '' : 's'} with leftover AES '
          'key${n == 1 ? '' : 's'}');
    }
    return 'Found ${parts.join(' and ')}.';
  }

  Future<void> _onClear() async {
    final scan = _scan;
    if (scan == null) return;
    setState(() => _phase = _Phase.clearing);
    try {
      await _keyRepo.clearStaleKeys(scan);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_summaryMessage(scan).replaceFirst('Found', 'Cleared')),
          backgroundColor: Theme.of(context).colorScheme.secondary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return GlassContainer(
      borderRadius: 24,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BottomSheetHandle(),
          const SizedBox(height: 16),
          ..._buildPhaseContent(cs, tt),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 8),
        ],
      ),
    );
  }

  List<Widget> _buildPhaseContent(ColorScheme cs, TextTheme tt) {
    if (_scanError != null) {
      return [
        Icon(Icons.error_outline_rounded, size: 48, color: cs.error),
        const SizedBox(height: 16),
        Text('Scan Failed', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Text(
          _scanError!.replaceFirst('Exception: ', ''),
          textAlign: TextAlign.center,
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        CrypButton(
          label: const Text('Dismiss'),
          onPressed: () => Navigator.pop(context),
          color: cs.onSurfaceVariant,
          height: 44,
        ),
      ];
    }

    switch (_phase) {
      case _Phase.scanning:
        return const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: CircularProgressIndicator(),
          ),
        ];

      case _Phase.clean:
        return [
          Icon(Icons.verified_rounded, size: 48, color: cs.secondary),
          const SizedBox(height: 16),
          Text('Already Clean', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text(
            'No stale keys found.',
            textAlign: TextAlign.center,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          CrypButton(
            label: const Text('Dismiss'),
            onPressed: () => Navigator.pop(context),
            color: cs.primary,
            height: 44,
          ),
        ];

      case _Phase.found:
        final scan = _scan!;
        return [
          Icon(Icons.warning_amber_rounded, size: 48, color: cs.tertiary),
          const SizedBox(height: 16),
          Text('Stale Keys Found', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text(
            _summaryMessage(scan),
            textAlign: TextAlign.center,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: CrypButton(
                  label: const Text('Cancel'),
                  onPressed: () => Navigator.pop(context),
                  color: cs.onSurfaceVariant,
                  height: 44,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CrypButton(
                  label: const Text('Clear'),
                  onPressed: _onClear,
                  color: cs.error,
                  height: 44,
                ),
              ),
            ],
          ),
        ];

      case _Phase.clearing:
        return [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: CircularProgressIndicator(),
          ),
          const SizedBox(height: 16),
          Text('Clearing stale keys…', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        ];
    }
  }
}
```

- [ ] **Step 2: Run analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/home/clear_cache_sheet.dart
git commit -m "feat(vault): add ClearCacheSheet scan/confirm/clear UI

Bottom sheet matching the existing GlassContainer/BottomSheetHandle/
CrypButton visual pattern used elsewhere in this codebase (e.g.
RsaKeyManagerScreen._showConfirmDialog). Not yet wired into the
sidebar — next commit.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 4: Wire into the sidebar

**Files:**
- Modify: `lib/presentation/home/sidebar_drawer.dart`

**Interfaces:**
- Consumes: `ClearCacheSheet` (Task 3).

- [ ] **Step 1: Add the import**

In `lib/presentation/home/sidebar_drawer.dart`, add to the import block (after the existing `auth_repository.dart` import):

```dart
import 'clear_cache_sheet.dart';
```

- [ ] **Step 2: Insert the drawer item**

Between the "Key Vault" `_DrawerItem` (ends at line 113) and the "Settings" `_DrawerItem` (starts at line 115), insert:

```dart
            _DrawerItem(
              icon: Icons.cleaning_services_outlined,
              label: 'Clear Cache',
              subtitle: 'Scan for leftover keys',
              onTap: () {
                Navigator.pop(context);
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const ClearCacheSheet(),
                );
              },
            ),
```

(Matches the existing `Navigator.pop(context)` then immediately open the next thing pattern already used by the "Key Vault" and "Settings" items above/below it, and the `isScrollControlled: true, useSafeArea: true, backgroundColor: Colors.transparent` options already used by `receiver_screen.dart`'s `_KeyManagerSheet` bottom sheet.)

- [ ] **Step 3: Run analyze + full suite**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: all tests still pass (156/156 — this task adds no new tests, pure UI wiring, consistent with how the existing "Key Vault"/"Settings" entries were wired with no dedicated test).

- [ ] **Step 4: Manual smoke test**

Run the app (`flutter run`), open the sidebar, tap "Clear Cache":
- Expect a brief loading spinner, then either "Already Clean" (if signed-in account has no leftover keys) or "Stale Keys Found" with a Cancel/Clear choice.
- If "Stale Keys Found" appeared, tap Clear and confirm the sheet closes with a "Cleared ..." snackbar, and tapping "Clear Cache" again now shows "Already Clean".

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/home/sidebar_drawer.dart
git commit -m "feat(vault): wire Clear Cache into sidebar

Adds the sidebar entry between Key Vault and Settings, per the
approved design spec. Completes the Clear Cache feature
(docs/superpowers/specs/2026-06-22-clear-cache-stale-keys-design.md).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```
