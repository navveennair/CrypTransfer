---
phase: 05-neutral-handshake-model
plan: 04
subsystem: presentation
tags: [flutter, home_screen, handshake, connection-hub, overlay, streambuilder]
status: complete
self_check: PASSED
dependency_graph:
  requires:
    - 05-02 (HandshakeRepository with 9 stream/write methods)
    - 05-03 (SenderScreen.preFilledPartnerUid, ReceiverScreen.preFilledSenderUid)
  provides:
    - HomeScreen connection hub: Active Connections, Pending Requests, _ProposalBanner, _RolePickerSheet
  affects:
    - lib/presentation/home/home_screen.dart
tech_stack:
  added: []
  patterns:
    - OverlayEntry proposal banner (Accept/Reject) — extends _NotifBanner pattern
    - Nested StreamBuilder triple-merge for connections+pending sections
    - Per-doc outcome StreamSubscription map (_outcomeSubs) for D-08 proposer banner
    - showModalBottomSheet _RolePickerSheet with pre-fill navigation to session screens
key_files:
  created: []
  modified:
    - lib/presentation/home/home_screen.dart
decisions:
  - "_outcomeSubs stored as final Map<String, StreamSubscription> — entries added/removed reactively but the map reference is never reassigned"
  - "Active Connections section uses three nested StreamBuilders (proposer + partner + outgoing pending) rather than a merged stream — avoids Firestore OR query limitation"
  - "_ProposalBanner created as separate StatefulWidget (not a variant of _NotifBanner) — different action row (Accept/Reject vs. onTap); keeps _NotifBanner untouched"
  - "Deduplication in _ActiveConnectionsSection uses a seenUids Set<String> — prevents same person appearing twice when mutual proposals both accepted"
  - "Pre-existing TC010 test failure (auth_test.dart binding init) is out of scope — confirmed pre-existing before this plan"
metrics:
  duration: "~25 minutes"
  completed_date: "2026-05-12"
  tasks_completed: 2
  files_changed: 1
---

# Phase 5 Plan 04: HomeScreen Connection Hub Summary

## What was built

HomeScreen restructured from a simple role-button launcher into a full connection-management hub implementing all 14 locked decisions (D-01 through D-14) of the neutral handshake model. The role buttons ("I am a Sender" / "I am a Receiver") are permanently retired. All file transfer sessions now flow through the Active Connections layer.

## Key changes

### `lib/presentation/home/home_screen.dart`

**Infrastructure additions (Task 1):**
- `_handshakeRepo`: `HandshakeRepository()` field — single instance for all connection operations
- `_pendingProposalSub`: `StreamSubscription<QuerySnapshot>?` — incoming pending proposals listener
- `_lastSeenProposalId`: deduplication guard (mirrors `_lastBannerDocId` from existing notification listener)
- `_outcomeSubs`: `Map<String, StreamSubscription>` — per-doc outcome subscription map for D-08 proposer banner
- `_startHandshakeListener()`: streams `streamIncomingPending()`, fires `_showProposalBanner()` on `DocumentChangeType.added` only
- `_startOutcomeListener()`: watches `streamOutgoingPending()` docChanges, opens per-doc `streamProposalOutcome()` sub; fires `_showNotifBanner` when status becomes `connected` or `rejected`; cleans up finished subs
- `_showProposalBanner()`: inserts `_ProposalBanner` OverlayEntry; Accept calls `acceptProposal`; Reject calls `rejectProposal`; Dismiss leaves proposal pending (D-03)
- `_ProposalBanner`: StatefulWidget with `onAccept`/`onReject`/`onDismiss`, 5-second auto-dismiss Timer, per-button loading state (`_accepting`/`_rejecting`), deep-purple GlassContainer styling
- `_NotifBanner` class: **unchanged** — existing RSA key and file-received notifications continue to work

**Build restructure (Task 2):**
- Removed: `Text('Actions')` header, `GlassButton('I am a Sender')`, `GlassButton('I am a Receiver')` (D-04)
- Added: Active Connections section header with `TextButton.icon('Add New Connection')` → `FindFriendsScreen` (D-06)
- Added: `_ActiveConnectionsSection` — three nested StreamBuilders merging proposer connections, partner connections, and outgoing pending; deduplicates by partner UID; empty state shows `_EmptyConnectionsPrompt`
- Added: `_PendingRequestsSection` — `streamIncomingPending()` StreamBuilder; returns `SizedBox.shrink()` when empty (D-03/D-05)
- Added: `_RolePickerSheet` — bottom sheet with [Send File] tile → `SenderScreen(preFilledPartnerUid:)` and [Receive File] tile → `ReceiverScreen(preFilledSenderUid:)` (D-11/D-13/D-14)
- Added: `_ActiveConnectionRow` — connected rows: full-width InkWell → `_openRolePicker`; pending rows: amber `_StatusBadge` + cancel `IconButton` → `_cancelProposal` confirmation sheet (D-07/D-10)
- Added: `_PendingRequestRow` — Accept Request (`CrypButton`) + Decline Request (`TextButton`) with per-button loading states (D-02/D-05)
- Added: `_EmptyConnectionsPrompt` — 'No connections yet' + 'Add New Connection' CTA (D-04)
- Added: `_StatusBadge` — green 'Connected' or amber 'Pending' badge widget
- Recent Transfers section: **unchanged**

## Commits

- `bb047bf` feat(05-04): restructure HomeScreen — handshake listeners, _ProposalBanner, Active Connections, _RolePickerSheet

## Verification

```
flutter analyze lib/presentation/home/home_screen.dart → No issues found
flutter analyze (full project) → No issues found
flutter test → 87 passed, 1 pre-existing failure (TC010 auth_test.dart binding init — unrelated to this plan)
```

Acceptance criteria verified:
- home_screen.dart does NOT contain 'I am a Sender': PASS
- home_screen.dart does NOT contain 'I am a Receiver': PASS
- class _ProposalBanner exists: PASS
- class _RolePickerSheet exists: PASS
- SenderScreen(preFilledPartnerUid:) navigation: PASS
- ReceiverScreen(preFilledSenderUid:) navigation: PASS
- 'Add New Connection' text present: PASS
- 'No connections yet' text present: PASS
- 'Active Connections' section header: PASS
- 'Pending Requests' section: PASS
- 'Send File' and 'Receive File' tile labels: PASS
- cancelProposal call path: PASS

## Deviations from Plan

**1. [Rule 2 - Missing] outcome banner handles 'outcome' type in _showNotifBanner**
- **Found during:** Task 1 implementation
- **Issue:** `_showNotifBanner` unconditionally calls `NotificationService.markRead()` for every banner type, but outcome banners (type='outcome') are driven by HandshakeRepository streams — not the NotificationService. Calling `markRead` with an outcome docId would attempt to mark a neutral_handshakes doc as read in the notifications collection.
- **Fix:** Added `if (type != 'outcome')` guard around `NotificationService.markRead()` calls in both `onDismiss` and `onTap` callbacks of `_showNotifBanner`.
- **Files modified:** `lib/presentation/home/home_screen.dart`
- **Commit:** `bb047bf`

**2. [Rule 2 - Missing] _EmptyConnectionsPrompt requires onAddPressed callback**
- **Found during:** Task 2 implementation
- **Issue:** Plan specified `_EmptyConnectionsPrompt` with an `onAddPressed` callback, but `_ActiveConnectionsSection` widget was not wired to pass it through.
- **Fix:** Added `onAddPressed` parameter to `_ActiveConnectionsSection` and threaded it through to `_EmptyConnectionsPrompt`.
- **Files modified:** `lib/presentation/home/home_screen.dart`
- **Commit:** `bb047bf`

## Known Stubs

None. All connection sections are wired to live HandshakeRepository streams. No hardcoded empty values or placeholder text in data paths.

## Threat Flags

None. No new network endpoints or auth paths introduced beyond those already tracked in the plan's threat model (T-05-04-01 through T-05-04-05).

## Self-Check: PASSED

Files created/modified:
- `lib/presentation/home/home_screen.dart` — FOUND (1028 insertions over base, ~1470 lines total)

Commits:
- `bb047bf` — FOUND

Key criteria:
- `class _ProposalBanner` — FOUND (2 occurrences: definition + State class)
- `class _RolePickerSheet` — FOUND
- `preFilledPartnerUid:` — FOUND
- `preFilledSenderUid:` — FOUND
- 'I am a Sender' — NOT FOUND (correct)
- 'I am a Receiver' — NOT FOUND (correct)
- `flutter analyze` — No issues found
