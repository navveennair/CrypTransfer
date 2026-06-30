---
slug: permission-denied-saving-downloads
status: resolved
trigger: PERMISSION_DENIED from Cloud Firestore when tapping End Session button
created: 2026-06-04
updated: 2026-06-04
---

## Symptoms

- **Expected:** End Session completes — cleans up Firestore docs, wipes keys, navigates away
- **Actual:** Cloud Firestore PERMISSION_DENIED exception thrown when End Session is tapped
- **Trigger point:** End Session button on ReceiverEndSessionScreen (_runFinalCleanup → writeFinalAuditLog batch commit)
- **Timeline:** Broke in commit 09cf34d (2026-06-03) — "feat(home): Transfer Summary page, notification outcomes, section pill buttons"
- **Error:** Cloud Firestore PERMISSION_DENIED
- **Reproduction:** Complete a file receive flow, tap End Session

## Current Focus

hypothesis: RESOLVED
test: N/A
expecting: N/A
next_action: Deploy updated firestore rules (already correct); test end session flow end-to-end

## Evidence

- timestamp: 2026-06-04T00:00:00Z
  observation: writeFinalAuditLog() in transfer_repository.dart calls _addTransferNotifications() in the same WriteBatch
  file: lib/data/repositories/transfer_repository.dart
  significance: The batch commit fails if any operation in the batch fails

- timestamp: 2026-06-04T00:00:00Z
  observation: _addTransferNotifications wrote payload {'type', 'message', 'read', 'createdAt'} — NO toUserId field
  file: lib/data/repositories/transfer_repository.dart lines 301-326 (pre-fix)
  significance: Missing toUserId field caused Firestore rule evaluation to fail

- timestamp: 2026-06-04T00:00:00Z
  observation: Firestore notifications create rule: allow create if request.resource.data.toUserId == userId
  file: firestore.rules lines 34-36
  significance: Rule requires toUserId to match the subcollection owner userId — null != senderId → DENIED → entire batch aborted

- timestamp: 2026-06-04T00:00:00Z
  observation: _addTransferNotifications is called from writeFinalAuditLog AND writeAbortAuditLog — both were broken
  file: lib/data/repositories/transfer_repository.dart
  significance: Same bug affected abort cleanup path too

- timestamp: 2026-06-04T00:00:00Z
  observation: Commit 09cf34d (2026-06-03) introduced _addTransferNotifications() — matches "broke recently" symptom
  file: lib/data/repositories/transfer_repository.dart
  significance: Regression introduced 1 day before bug report; previously End Session used no notifications

## Eliminated

- WRITE_EXTERNAL_STORAGE / file storage path — confirmed NOT the issue (user clarified)
- transfers delete rule — confirmed allows receiverId to delete (commit 8fca91a)
- audit_logs create rule — allows participants to write; both senderId and receiverId appear in payload
- handshakes delete rule — allows either party; no issue here
- users update rule — isOwner applies; no issue here
- Undeployed firestore.rules — rules are correct and deployed; the bug is in Dart code, not rules

## Resolution

root_cause: _addTransferNotifications() in transfer_repository.dart wrote notification documents to users/{senderId}/notifications and users/{receiverId}/notifications without including a toUserId field in the payload. The Firestore notifications create rule requires request.resource.data.toUserId == userId. Since toUserId was absent (evaluates as null), the rule evaluated to false for the sender notification write, causing PERMISSION_DENIED that aborted the entire WriteBatch in writeFinalAuditLog(). Regression introduced in commit 09cf34d.
fix: Added 'toUserId': senderId to the sender notification payload and 'toUserId': receiverId to the receiver notification payload in _addTransferNotifications(). Both notifications now satisfy the Firestore create rule. flutter analyze passes with no issues.
verification: flutter analyze lib/data/repositories/transfer_repository.dart — No issues found. End-to-end test of complete receive flow + End Session button required on device.
files_changed: lib/data/repositories/transfer_repository.dart
