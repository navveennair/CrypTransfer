# Clear Cache (Stale Key Cleanup) — Design

**Date:** 2026-06-22
**Status:** Approved, ready for implementation plan

## Problem

RSA and AES key material can outlive the session that created it when a
receiver session ends improperly (e.g. the app process is force-killed via
IDE/emulator controls rather than backgrounded gracefully — see the
`receiver_screen.dart` Step-1 regression fixed earlier this session). The
reactive kill-switch (`SessionManager` → `EncryptionService.closeReceiverSession`)
only fires off `AppLifecycleState.paused`/`detached`, which a hard process
kill skips entirely, leaving:

- A receiver's RSA private key (local secure storage) and/or `publicKey`
  (Firestore `users/{uid}`) behind after the session that owned it ended.
- `transfers` documents in a terminal status (`completed`, `aborted`,
  `failed`, `cancelled`, `connection_lost`) whose `encryptedAESKey` field was
  never wiped because the normal end-of-session deletion never ran.

There's currently no user-facing way to detect or clear this leftover key
material — `RsaKeyManagerScreen`'s "Delete Keys" requires the user to already
suspect something is wrong, and it only covers the user's *own current* RSA
key, not stale transfers.

This adds a "Clear Cache" action to the sidebar that scans Firestore (the
source of truth — not just local secure storage) for stale key material tied
to the signed-in account, reports what it finds, and clears it on
confirmation.

## Scope

In scope:
- A `StaleKeyScanResult` model and two new `KeyRepository` methods:
  `scanForStaleKeys()` (read-only) and `clearStaleKeys(scan)` (acts on the
  exact scan result passed in).
- A new sidebar item "Clear Cache" between "Key Vault" and "Settings".
- A scan → confirm → clear bottom-sheet flow, with a distinct "already
  clean" path that needs no confirmation step.
- Unit tests covering clean state, RSA-only staleness, transfer-only
  staleness, both combined, and — critically — that an active
  session/transfer is never flagged or touched.

Explicitly out of scope (considered and deferred during brainstorming):
- **Literal multi-device tracking.** "Each device" in the original request
  was clarified to mean "check Firestore as source of truth for this
  account," not tracking multiple physical devices per account. No new data
  modeling for device identity is introduced.
- **New Firestore rules or indexes.** Confirmed empirically against the
  emulator (see "Firestore rules" below) — every query/delete this feature
  needs is already covered by rules deployed earlier this session. Staleness
  filtering by `status` happens client-side in Dart after a plain equality
  fetch specifically to avoid needing a new composite index.
- **Reusing `EncryptionService.closeReceiverSession()` for RSA remediation.**
  Considered and rejected — its unconditional `handshakes` and
  `connection_request`/`rsa_key_received` notification purge is a bigger
  blast radius than "stale key cleanup" implies (see Architecture below for
  the narrower remediation actually used instead).

## Architecture

### Data model

```dart
class StaleKeyScanResult {
  final bool hasStaleRsaSession;
  final List<String> staleTransferIds;
  bool get isClean => !hasStaleRsaSession && staleTransferIds.isEmpty;
}
```

Lives alongside the other small models in `lib/data/models/`.

### `KeyRepository` additions

**`Future<StaleKeyScanResult> scanForStaleKeys()`** (read-only, uses the
existing `_uid` getter):
1. Read `users/{_uid}` once. `hasStaleRsaSession` is true when
   `isReadyToReceive` (the same field `AuthRepository.getIsReadyToReceive()`
   already reads elsewhere — the canonical check, not `sessionActive`,
   though both are always set in tandem by `setupReceiverSession`/
   `closeReceiverSession` today) is not `true`, AND either `publicKey`
   (Firestore) is non-empty OR the local secure-storage entry at
   `FirebaseConstants.privateKeyStorageKey` is non-null. (`KeyRepository`
   already holds a `FlutterSecureStorage` instance — no new dependency.)
2. Query `transfers` where `senderId == _uid`, and separately where
   `receiverId == _uid` (two plain equality queries — already covered by the
   `allow list` rule from the earlier fix; no composite index needed).
3. Merge both result sets, filter in Dart for `status` in
   `{completed, aborted, failed, cancelled, connection_lost}` AND non-empty
   `encryptedAESKey`. Collect matching doc IDs into `staleTransferIds`.

**`Future<void> clearStaleKeys(StaleKeyScanResult scan)`**:
1. If `scan.hasStaleRsaSession`, delete the local secure-storage entry at
   `FirebaseConstants.privateKeyStorageKey` and update `users/{_uid}` to
   clear `publicKey` (`FieldValue.delete()`) and set `isReadyToReceive`/
   `sessionActive` to `false`. This is a **narrow, dedicated** remediation —
   deliberately *not* a call to `EncryptionService.closeReceiverSession()`.
   That function also unconditionally deletes **all** `handshakes` docs
   (any status, not just stale ones) and **all** `connection_request`/
   `rsa_key_received` notifications from the user's inbox — including
   currently-unread, unrelated connection requests. That blast radius is
   wider than "stale key cleanup" implies, so the few lines of overlap are
   duplicated here rather than reusing it. No new Firestore rule needed —
   the `users` collection's existing `allow update: if isOwner(userId)`
   already covers this write with no field-level restriction.
2. For each ID in `scan.staleTransferIds`, delete `transfers/{id}` in a
   single `WriteBatch` (mirrors the deletion `endSessionCleanup` already
   does for a normal clean end). Deleting the whole document — not just the
   `encryptedAESKey` field — matches what should have happened originally.
   "Recent Transfers" history is unaffected; it reads from the separate,
   permanent `users/{uid}/audit_logs` subcollection, not `transfers`.

Operates on the scan result passed in (not a fresh re-scan at clear time) so
the deletion targets exactly what the user confirmed, avoiding a race with
new legitimate data created between scan and confirm.

### UI flow

New `_DrawerItem` in `sidebar_drawer.dart`, wired to open a new stateful
bottom-sheet widget — `lib/presentation/home/clear_cache_sheet.dart` — kept
separate from `SidebarDrawer` (which stays a simple `StatelessWidget`) since
this flow has real async state (scanning, confirming, clearing).

1. Tap "Clear Cache" → bottom sheet opens, shows a brief loading state while
   `scanForStaleKeys()` runs.
2. `scan.isClean` → sheet shows "Already clean — no stale keys found." with
   a single dismiss action. No confirmation step.
3. Not clean → sheet shows what was found in plain language (e.g. "Found 1
   stale RSA session and 2 stale transfer(s) with leftover AES keys.") with
   Cancel / Clear buttons — same visual pattern as
   `RsaKeyManagerScreen._showConfirmDialog`.
4. Clear confirmed → progress state ("Clearing stale keys…") → calls
   `clearStaleKeys(scan)` → result snackbar summarizing what was cleared, or
   an error snackbar on failure (wrapped, consistent with this repo's
   `NetworkException` pattern elsewhere in `KeyRepository`).

### Firestore rules

No rule or index changes needed. Verified empirically against the Firestore
emulator running the `firestore.rules` already deployed to
`cryptransfer-96e9f` earlier this session (the `allow get`/`allow list`
split fix):
- `get users/{uid}` — covered by `allow get: if isAuthenticated()`.
- `list transfers where senderId == self` (no status filter) — passed.
- `list transfers where receiverId == self` (no status filter) — passed.
- `delete transfers/{id}` as sender or receiver — passed.
- `update users/{uid}` to clear `publicKey`/`isReadyToReceive`/
  `sessionActive` as the owner — covered by the existing
  `allow update: if isOwner(userId) || isAdmin()`, no field-level
  restriction; unchanged.

## Testing

Unit tests in `test/` (new file, e.g. `test/key_repository/clear_cache_test.dart`)
using `fake_cloud_firestore`, matching existing repo conventions:

- Clean state → `scanForStaleKeys()` returns `isClean == true`.
- Stale RSA only (`publicKey` set, `isReadyToReceive: false`) →
  `hasStaleRsaSession == true`; `clearStaleKeys` wipes Firestore `publicKey`
  and the local secure-storage key.
- Stale transfers only → returned IDs match exactly the terminal-status,
  non-empty-`encryptedAESKey` docs; non-matching docs are untouched.
- Both stale RSA and stale transfers → both cleaned in one `clearStaleKeys`
  call.
- Active session (`isReadyToReceive: true`, `publicKey` set) → NOT flagged.
- Active transfer (`status: 'pending'`, `encryptedAESKey` set) → NOT flagged,
  NOT deleted.
- Stale RSA session with an unrelated unread `connection_request`
  notification and an unrelated `handshakes` doc present → after
  `clearStaleKeys`, both are still present untouched (locks in the
  brainstorming decision not to reuse `closeReceiverSession()`).
