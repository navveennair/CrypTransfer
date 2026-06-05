---
slug: stale-role-conflict-after-reconnect
status: resolved
trigger: "When both users navigate to their roles (Send File / Receive File), then navigate back to home, then go to connections, disconnect and reconnect — the app still shows role conflict when the user now wants to be a sender or receiver."
created: "2026-06-05"
updated: "2026-06-05"
---

# Debug Session: stale-role-conflict-after-reconnect

## Symptoms

- **Expected:** After disconnecting and reconnecting in the Connections screen, both users should be able to freely choose new roles (Send File or Receive File) without any role conflict errors.
- **Actual:** Role conflict error still appears even after disconnect + reconnect. The conflict persists as if both users still hold their previous roles.
- **Errors:** Role conflict error/message shown — exact text unknown (likely from `assignTransferRole()` throwing a conflict).
- **Repro:** (1) Both users pick roles → navigate to Send File / Receive File screens. (2) Both press back → return to home. (3) Go to Connections screen, disconnect, then reconnect. (4) Try to pick a role → role conflict shown.
- **Timeline:** Likely introduced alongside the `pendingSenderFor` fix for the both-users-can-be-sender bug (commit 76251aa).

## Current Focus

hypothesis: "Stale Firestore fields (pendingSenderFor and/or selectedSenderUid) are not cleared when users navigate back from the role screens or when they disconnect, causing assignTransferRole() to see a false conflict on the next role pick."
test: ""
expecting: ""
next_action: "RESOLVED — three-part fix applied"

## Evidence

- `assignTransferRole()` returns `''` (empty string) as a placeholder docId (FIX 2 comment in code).
- `HomeScreen` passes `handshakeDocId: ''` to both `SenderScreen` and `ReceiverScreen`.
- `ReceiverScreen.PopScope.canPop` was `_isReadyToReceive ? false : (_handshakeDocId == null)` — with `_handshakeDocId == ''` this evaluated to `false`, blocking the pop and preventing the `didPop==true` branch from ever running, so `clearTransferRoles` was never called.
- `SenderScreen.PopScope` called `clearTransferRoles(handshakeDocId: '')` which attempted a Firestore update on document ID `''` — silently fails, leaving `pendingSenderFor` stale.
- `HandshakeRepository.disconnectFromUser()` only deleted `neutral_handshakes` docs; it did NOT clear `pendingSenderFor` or `selectedSenderUid` from either user's Firestore document.
- On reconnect + role pick, `assignTransferRole` transaction reads `pendingSenderFor` still set from the previous session and fires `RoleConflictException`.

## Eliminated Hypotheses

- The conflict detection logic in `assignTransferRole()` itself is correct — it correctly guards against real concurrent conflicts.
- `clearSenderClaim()` / `clearTransferRoles()` APIs existed and were called, but their invocation paths were broken by the empty `handshakeDocId` returned from `assignTransferRole()`.

## Resolution

root_cause: "Three compounding gaps: (1) `clearTransferRoles` was called with an empty `handshakeDocId` (because `assignTransferRole` returns '' as a placeholder), causing it to hit a non-existent Firestore doc and silently skip the cleanup of `pendingSenderFor`; (2) `ReceiverScreen.PopScope.canPop` treated empty string as non-null, blocking the pop and bypassing the `clearTransferRoles` call entirely; (3) `disconnectFromUser` never cleared `pendingSenderFor` or `selectedSenderUid` from either user's Firestore doc, so stale role state survived across disconnect+reconnect cycles."

fix: "Three-part fix: (1) `clearTransferRoles` now always clears both `pendingSenderFor` and `selectedSenderUid` from the user doc first (unconditionally), and only attempts the handshake doc update when `handshakeDocId` is non-empty (best-effort); (2) `ReceiverScreen.PopScope.canPop` treats empty string the same as null (`hasRealHandshakeDoc` guard), so back-nav is allowed and `clearTransferRoles` is always called; (3) `HandshakeRepository.disconnectFromUser` now includes `pendingSenderFor` and `selectedSenderUid` FieldValue.delete() updates for both users in the same WriteBatch."

verification: "flutter analyze: 1 pre-existing info-level lint only (unnecessary_string_interpolations in searchUsers, present before this fix). No new issues introduced."

files_changed:
  - lib/data/repositories/key_repository.dart
  - lib/data/repositories/handshake_repository.dart
  - lib/presentation/receiver/receiver_screen.dart
