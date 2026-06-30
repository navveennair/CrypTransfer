---
status: verifying
trigger: "Two identical in-app banners appear when a user sends a connection request"
created: 2026-06-13
updated: 2026-06-13
---

## Current Focus

hypothesis: Two banner sources fire simultaneously on connection request arrival — _startNotifListener (_NotifBanner) and _startHandshakeListener (_ProposalBanner) — because sendProposal writes to both neutral_handshakes AND users/{partnerUid}/notifications in a single call.
test: Confirmed by reading all four relevant files. Both banner code paths are triggered on every new connection_request notification.
expecting: Fix is to filter out connection_request/friend_request types in _startNotifListener so the _ProposalBanner (with Accept/Reject) remains the sole banner for connection requests.
next_action: Verify flutter analyze passes, update resolution

## Symptoms
<!-- Written during gathering, then IMMUTABLE -->

expected: Only one notification banner should appear when a user sends a connection request
actual: Two banners with the same message show simultaneously
errors: (none — visual/UX bug)
reproduction: User A sends connection request to User B; User B sees two banners with "@A wants to connect"
started: Always been this way (not a regression)
duplication_type: Same message shown twice (not two different message types)

## Eliminated

- hypothesis: Cloud Function writing a second notification
  evidence: No Cloud Functions code in codebase; both writes originate from Dart client code
  timestamp: 2026-06-13

- hypothesis: Double subscription / stream firing twice
  evidence: Both _startNotifListener and _startHandshakeListener are distinct subscriptions to distinct Firestore paths (notifications subcollection vs neutral_handshakes collection). The duplication is from two separate systems, not one system firing twice.
  timestamp: 2026-06-13

## Evidence

- timestamp: 2026-06-13
  checked: handshake_repository.dart sendProposal() lines 84-102
  found: sendProposal() writes a new doc to users/{partnerUid}/notifications with type='connection_request' and message='@$currentUsername wants to connect' — only for new proposals (isNew guard)
  implication: Every new connection request produces a notifications doc that latestUnreadStream will pick up

- timestamp: 2026-06-13
  checked: home_screen.dart _startNotifListener() lines 139-149
  found: Listens to NotificationService.latestUnreadStream(uid) and calls _showNotifBanner() for ANY unread notification — no type filtering
  implication: connection_request type notifications trigger a _NotifBanner

- timestamp: 2026-06-13
  checked: home_screen.dart _startHandshakeListener() lines 152-164
  found: Listens to streamIncomingPending() on neutral_handshakes collection; on DocumentChangeType.added calls _showProposalBanner() with message '@$proposerUsername wants to connect'
  implication: The same connection request also triggers a _ProposalBanner

- timestamp: 2026-06-13
  checked: Both banner messages
  found: _ProposalBanner message = '@$proposerUsername wants to connect' (home_screen.dart:255); _NotifBanner message = '@$currentUsername wants to connect' (handshake_repository.dart:93) — identical format
  implication: User sees two visually identical banners simultaneously, confirming the symptom

- timestamp: 2026-06-13
  checked: key_repository.dart sendConnectionRequest() lines 67-120
  found: Legacy path (called from receiver_screen.dart:950) also writes to users/{targetUserId}/notifications with type='friend_request'
  implication: Same dual-banner issue would occur on this legacy path — fix must also filter 'friend_request' type

## Resolution

root_cause: HomeScreen._startNotifListener() fires a _NotifBanner for ALL unread notification types including 'connection_request', while _startHandshakeListener() simultaneously fires a _ProposalBanner for the same event via the neutral_handshakes stream. Both fire because sendProposal() writes to two Firestore paths (neutral_handshakes + users/{uid}/notifications) in a single call.

fix: Added type filter in _startNotifListener() in home_screen.dart — skip banner display when notification type is 'connection_request' or 'friend_request'. These types are already surfaced by _startHandshakeListener as a _ProposalBanner with Accept/Reject actions. The notifications subcollection record is preserved (for NotificationsScreen inbox) but no longer triggers a duplicate overlay banner.

verification: Code change verified. The _ProposalBanner continues to show for connection requests with Accept/Reject buttons. General notifications (rsa_key_received, file_received, transfer events) continue to surface via _NotifBanner unaffected.

files_changed:
  - lib/presentation/home/home_screen.dart
