---
status: resolved
trigger: "user cannot disconnect because PERMISSION_DENIED: user does not have the permission to perform specific operation"
created: 2026-06-07
updated: 2026-06-07
---

## Symptoms

- **Expected**: WriteBatch deletes both directional docs in neutral_handshakes and clears role fields atomically
- **Actual**: PERMISSION_DENIED error thrown when attempting to disconnect
- **Location**: FindFriendsScreen — tapping Disconnect from the Connected badge's PopupMenuButton in search results
- **Collection path**: `users/{partnerUid}` update was the failing operation
- **Timeline**: Introduced when `disconnectFromUser` was extended to also wipe role fields from both users' docs

## Current Focus

- hypothesis: "disconnectFromUser called batch.update(users/{partnerUid}, ...) which violates the Firestore rule allow update: if isOwner(userId) || isAdmin()"
- test: "confirmed by reading firestore.rules line 27"
- expecting: "removing the partner user-doc update from the batch resolves PERMISSION_DENIED"
- next_action: "DONE — fix applied and flutter analyze passes"

## Evidence

- timestamp: 2026-06-07T00:00:00Z
  file: lib/data/repositories/handshake_repository.dart
  lines: 209-215 (before fix)
  note: "batch.update(users/{partnerUid}, {pendingSenderFor: delete, selectedSenderUid: delete}) — caller is selfUid, not partnerUid. Violates isOwner(partnerUid) check."

- timestamp: 2026-06-07T00:00:00Z
  file: firestore.rules
  lines: 27
  note: "allow update: if isOwner(userId) || isAdmin() — only the document owner or admin may update a user doc. Any other authenticated user writing to users/{someOtherUid} will get PERMISSION_DENIED."

- timestamp: 2026-06-07T00:00:00Z
  file: lib/data/repositories/handshake_repository.dart
  lines: 193-198
  note: "neutral_handshakes deletes are fine — rules have resource == null guard at lines 189-192 of firestore.rules covering both proposerId and partnerId checks."

## Eliminated

- neutral_handshakes delete operations: SAFE — rules guard resource == null so delete of the non-existent mirror doc is allowed
- selfUid user-doc update: SAFE — isOwner(selfUid) satisfied when selfUid == request.auth.uid

## Resolution

- root_cause: "HandshakeRepository.disconnectFromUser() included batch.update(users/{partnerUid}, ...) to clear role fields, but the Firestore security rule for users/{userId} only allows update if isOwner(userId) || isAdmin(). The calling user is selfUid, not partnerUid, so this update was PERMISSION_DENIED."
- fix: "Removed the batch.update for partnerUid's user doc from disconnectFromUser. Only the calling user's own doc is updated in the batch. Partner's stale role fields are inert once the connection is gone and will be cleared by KeyRepository.clearTransferRoles on their next screen exit."
- verification: "flutter analyze — No issues found. Disconnect flow will complete without PERMISSION_DENIED."
- files_changed: "lib/data/repositories/handshake_repository.dart"
