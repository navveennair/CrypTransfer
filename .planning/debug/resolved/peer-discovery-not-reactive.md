---
status: resolved
slug: peer-discovery-not-reactive
trigger: "Peer discovery not reactive on Mailbox and Connection screens. User not detected until screen is closed and reopened. Suspected causes: .get() instead of .snapshots() for peer discovery, stream not initialized in initState or not disposed, Firestore query filtering too restrictive, RSA key write lag to rsa_key_manager delaying peer visibility. Need to switch to real-time StreamBuilder or Obx implementation."
created: 2026-05-10T00:00:00Z
updated: 2026-05-10T00:00:00Z
---

## Symptoms

expected: "When a Sender or Receiver enters the Mailbox or Connection screen, the other user (peer/friend) is detected immediately in real-time without any manual refresh"
actual: "The other user is not detected until the screen is manually closed and reopened — forcing a retry. The peer discovery is not reactive."
error_messages: "No visible error — just stale/empty UI until manual screen refresh"
timeline: "Unclear if this ever worked correctly"
reproduction: "1. User A enters Mailbox (ReceiverScreen) or Connection screen. 2. User B is present as a friend/peer. 3. User A's screen does not show User B. 4. User A closes the screen and reopens it — now User B appears."
suspected_causes:
  - ".get() used instead of .snapshots() for peer discovery query"
  - "Stream listener not initialized in initState or not properly disposed"
  - "Firestore query filtering too restrictive for receiverId/senderId"
  - "RSA key write lag to rsa_key_manager sub-collection preventing peer visibility"

## Current Focus

hypothesis: "getConnectedFriends() uses .get() (one-time fetch) in both ReceiverScreen._loadConnectedFriends() and FindFriendsScreen._loadFriends(). Called once in initState, results never update. Fix: add streamConnectedFriends() to KeyRepository using .snapshots(), wire StreamSubscription in both screens."
test: "flutter analyze lib/data/repositories/key_repository.dart lib/presentation/receiver/receiver_screen.dart lib/presentation/home/find_friends_screen.dart"
expecting: "No issues found"
next_action: "complete"

## Evidence

- timestamp: 2026-05-10T00:00:00Z
  finding: "KeyRepository.getConnectedFriends() at line 126-138 uses .get() — one-time fetch, returns Future not Stream"
  file: lib/data/repositories/key_repository.dart
  lines: 126-138

- timestamp: 2026-05-10T00:00:00Z
  finding: "ReceiverScreen._loadConnectedFriends() at line 265-270 calls getConnectedFriends().get() once in initState, result stored in _connectedFriends list, never refreshed"
  file: lib/presentation/receiver/receiver_screen.dart
  lines: 60-66, 265-270

- timestamp: 2026-05-10T00:00:00Z
  finding: "FindFriendsScreen._loadFriends() at line 51-60 calls getConnectedFriends().get() once in initState, result stored in _friends list, never refreshed. _loadingFriends bool controlled loading indicator."
  file: lib/presentation/home/find_friends_screen.dart
  lines: 29-35, 51-60

- timestamp: 2026-05-10T00:00:00Z
  finding: "_FindSenderSheet (inside ReceiverScreen) takes initialConnected list from parent and copies into local _connectedList. No live update mechanism."
  file: lib/presentation/receiver/receiver_screen.dart
  lines: 706-720

- timestamp: 2026-05-10T00:00:00Z
  finding: "flutter analyze passes — No issues found — after fix applied to all three files"

## Eliminated

- RSA key write lag to rsa_key_manager sub-collection: not the cause. The friendships sub-collection is separate from handshakes and was just never queried reactively.
- Firestore query filtering too restrictive: the query itself (status==accepted) is correct. The bug was the transport mechanism (.get vs .snapshots).

## Resolution

root_cause: "Both ReceiverScreen and FindFriendsScreen called KeyRepository.getConnectedFriends() (a .get() one-time fetch) in initState with no mechanism to receive subsequent Firestore updates. The friendship sub-collection never pushed updates to the UI after initial load, so new connections were invisible until the screen was rebuilt from scratch."
fix: "Added KeyRepository.streamConnectedFriends() which queries the same friendships sub-collection with .snapshots() and maps each QuerySnapshot to List<UserModel>. ReceiverScreen replaced _loadConnectedFriends() with _subscribeToFriends() (a StreamSubscription stored as _friendsSub, cancelled in dispose). FindFriendsScreen replaced _loadFriends() and the _loadingFriends bool with _subscribeFriends() using the same pattern. _FindSenderSheet inside ReceiverScreen also gained its own _friendsSub so the Active Connections list in the sheet updates while the sheet is open. Manual _loadFriends() calls after disconnect/accept were removed as they are now redundant."
verification: "flutter analyze on all three changed files: No issues found."
files_changed:
  - lib/data/repositories/key_repository.dart
  - lib/presentation/receiver/receiver_screen.dart
  - lib/presentation/home/find_friends_screen.dart
