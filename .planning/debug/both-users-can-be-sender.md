---
slug: both-users-can-be-sender
status: resolved
trigger: "When one user clicks Send File, another user is still able to click Send File too. Both users can simultaneously act as Sender or Receiver - there is no role exclusivity enforcement."
created: "2026-06-04"
updated: "2026-06-04"
---

# Debug Session: both-users-can-be-sender

## Symptoms

- **Expected:** User A clicks Send File → becomes Sender. User B's Send File button should be disabled/hidden — role is exclusive.
- **Actual:** Both users can tap Send File independently and both enter the Sender flow silently.
- **Errors:** No errors, no crashes — both just enter Sender flow with no conflict detection.
- **Repro:** Two devices, both tap Send File before connecting (race condition at the role-selection step).
- **Timeline:** Unknown when this started; may be a missing feature rather than a regression.

## Current Focus

hypothesis: "ROOT CAUSE CONFIRMED — assignTransferRole() transaction only reads selectedSenderUid to detect conflicts, but the sender role never writes any Firestore field. So when both users claim isSender:true, both see partnerSelectedSender==null, no conflict is thrown, and both enter SenderScreen."
test: "Verified by reading key_repository.dart lines 660-678 and 647-699."
expecting: "Fix: inside the transaction, when isSender:true, write a new field (e.g. pendingSenderFor: partnerUid) to signal the claim. The conflict check for receiver/sender reads this field."
next_action: "apply fix"
reasoning_checkpoint: "The transaction has all the machinery it needs — it already does txn.update inside the isSender block. It just needs to write the sender claim and have the partner's isSender check read it."

## Evidence

- timestamp: 2026-06-04T00:00:00Z
  file: lib/data/repositories/key_repository.dart
  lines: 660-699
  note: "assignTransferRole isSender:true path — transaction reads partnerSelectedSender but only throws if partnerSelectedSender != null && partnerSelectedSender != _uid. When partner is also sender (no selectedSenderUid written), partnerSelectedSender is null so condition is false. No Firestore write is made for the sender claim."

- timestamp: 2026-06-04T00:00:01Z
  file: lib/data/repositories/key_repository.dart
  lines: 700-705
  note: "assignTransferRole returns '' (empty string) — no Firestore state written for sender role. The receiver role writes selectedSenderUid in selectSenderHandshake(), but the sender role has no equivalent flag."

- timestamp: 2026-06-04T00:00:02Z
  file: lib/presentation/home/home_screen.dart
  lines: 300-326
  note: "onSendFile calls assignTransferRole(isSender: true) then navigates to SenderScreen. RoleConflictException is caught and shown as dialog — the UI plumbing is already correct. The bug is purely in the transaction logic."

## Eliminated

- UI layer: home_screen.dart already catches RoleConflictException and shows dialog. Not the bug.
- Missing exception class: RoleConflictException exists in app_exceptions.dart.
- Missing dialog: _showRoleConflictDialog exists and is wired.

## Resolution

root_cause: "assignTransferRole() transaction detects both-receiver conflicts by checking selectedSenderUid, but has no equivalent Firestore field to detect both-sender conflicts. When isSender:true, the transaction writes nothing to Firestore, so the partner's concurrent isSender:true call also sees no conflict signal and proceeds unchallenged."

fix: "Add a pendingSenderFor field to the user doc inside the transaction when isSender:true (written as partnerUid — 'I am claiming sender role toward this partner'). Add a corresponding conflict check: if partner already has pendingSenderFor == myUid, both are trying to be sender → throw RoleConflictException. Clear the field on role completion or screen exit."

verification: "Two simultaneous Send File taps on the same connection should now result in one user getting RoleConflictException and the role-conflict dialog."

files_changed: lib/data/repositories/key_repository.dart
