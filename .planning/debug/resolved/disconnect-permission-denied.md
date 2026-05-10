---
status: resolved
slug: disconnect-permission-denied
trigger: "In establish connection, check why users cannot disconnect from each other, causing to pop a permission denied banner"
created: 2026-05-10T00:00:00Z
updated: 2026-05-10T00:00:00Z
---

## Symptoms

expected: "Connection removed from both sides — both users' connection lists updated and UI reflects disconnected state immediately"
actual: "Permission denied banner pops immediately — Firestore write is rejected before any change takes effect"
error_messages: "Permission denied banner (Firestore security rules rejection suspected)"
timeline: "Never worked as far as I know"
reproduction: "Tap disconnect on a connected user in the establish connection / FindFriendsScreen"

## Current Focus

hypothesis: "disconnectFriend() WriteBatch deletes from the OTHER user's friendships sub-collection, which is blocked by the Firestore rule that only allows the owner to write to their own friendships docs"
test: "Read firestore.rules line 112-117 and key_repository.dart disconnectFriend() lines 151-161"
expecting: "Rule mismatch between bilateral batch-delete and single-owner write rule"
next_action: "Fix Firestore rule for friendships to allow a friend to delete their own mirror entry"

## Evidence

- timestamp: 2026-05-10T00:00:00Z
  file: firestore.rules
  lines: 112-117
  note: "friendships rule is `allow read, write: if request.auth.uid == userId;` — only the doc owner can write. No cross-user write allowed."

- timestamp: 2026-05-10T00:00:00Z
  file: lib/data/repositories/key_repository.dart
  lines: 151-161
  note: "disconnectFriend() calls batch.delete(_friendshipsOf(friendId).doc(_uid)) — this writes to userId=friendId's sub-collection while auth.uid=_uid, so auth.uid != userId → PERMISSION DENIED"

- timestamp: 2026-05-10T00:00:00Z
  file: lib/data/repositories/key_repository.dart
  lines: 84-102
  note: "sendConnectionRequest() also writes batch.set(_friendshipsOf(targetUserId).doc(_uid), ...) — same cross-user write, also blocked. But connections may have been seeded directly from Firestore console, which is why some connections exist."

## Eliminated

- Network issue: no, error is immediate
- Auth state missing: no, other Firestore writes from the same session work

## Resolution

root_cause: "Firestore security rule for users/{userId}/friendships/{friendId} only allows write if request.auth.uid == userId (the sub-collection owner). disconnectFriend() uses a WriteBatch that deletes from BOTH users' friendships sub-collections — the second delete (from the other user's sub-collection) fails because the authenticated user is not the owner of that path."
fix: "Add a narrower delete rule to friendships: allow authenticated users to delete the document whose ID equals their own UID (the mirror entry). Rule: `allow delete: if request.auth.uid == friendId;` This allows each user to remove their own mirror entry from the other user's sub-collection, enabling the bilateral WriteBatch to succeed."
verification: "After deploying the updated rule, tap Disconnect on a connected user — both sides should be removed and the UI should reflect disconnected state."
files_changed: [firestore.rules]
