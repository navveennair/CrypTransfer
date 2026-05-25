---
name: sender-stream-no-receiverstatus-signals
status: resolved
trigger: "Phase 07 UAT test 1 failed — sender stream not receiving receiverStatus/cleanup signals after transfer completes"
created: 2026-05-23
updated: 2026-05-23
---

## Symptoms

- **Expected:** After file transfer completes, sender's Firestore stream listener receives `receiverStatus` updates and session cleanup signals from the receiver side
- **Actual:** Sender stream receives nothing — silent failure (no crash, no error, stream just doesn't fire)
- **Errors:** None — silent failure
- **Timeline:** First observed during phase 07 UAT test 1; may never have worked
- **Reproduction:** Complete a full transfer (sender sends file, receiver decrypts/saves), then observe sender side — receiverStatus/cleanup signals never arrive

## Current Focus

hypothesis: "Listener starts before doc exists → Firestore security rule denies first snapshot → subscription dies silently"
test: "Trace listener lifecycle vs doc creation sequence in transfer_progress_screen.dart"
expecting: "_startTransferListener() called before .set() in _startUpload(); rule resource.data.senderId fails on null resource for non-existent doc → listener subscription is cancelled"
next_action: "Move _startTransferListener() to fire after .set() completes in _startUpload()"
reasoning_checkpoint: "Confirmed: initState() calls both _startUpload() and _startTransferListener() concurrently. The Firestore .set() that creates the doc is at the END of _startUpload() (after Storage upload). Listener subscribes to a non-existent doc. Firestore security rule `allow read: resource.data.senderId == auth.uid` evaluates resource as null for non-existent doc → rule returns false → permission denied → stream errors → subscription silently dies. Subsequent receiver updates (receiverStatus, cleanup_initiated) never reach sender."
tdd_checkpoint: ""

## Evidence

- timestamp: 2026-05-23T18:00:00Z
  file: lib/presentation/sender/transfer_progress_screen.dart
  lines: 87-88
  note: "initState() calls _startUpload() AND _startTransferListener() concurrently — listener starts before doc exists"

- timestamp: 2026-05-23T18:00:00Z
  file: lib/presentation/sender/transfer_progress_screen.dart
  lines: 248-262
  note: "Firestore .set() that creates the transfers doc is at the END of _startUpload(), after Storage upload completes — can be seconds/minutes after listener started"

- timestamp: 2026-05-23T18:00:00Z
  file: firestore.rules
  lines: 140-142
  note: "allow read rule checks resource.data.senderId/receiverId — resource is null when doc doesn't exist, so rule evaluates false → permission denied on initial snapshot"

- timestamp: 2026-05-23T18:00:00Z
  file: lib/presentation/sender/transfer_progress_screen.dart
  lines: 101-105
  note: "Listener has no onError: handler — permission denied error causes stream subscription to cancel silently (no crash, no log)"

## Eliminated

- Firestore rules blocking receiver updates: rules correctly allow sender and receiver to read/update transfers doc — not the issue
- transferId mismatch: same ID used for listener, .set(), and receiver updates — not the issue
- receiverStatus field name drift: receiver writes 'receiverStatus' field, sender reads 'receiverStatus' field — names match

## Resolution

root_cause: "_startTransferListener() is called in initState() before the transfers Firestore document exists. The listener's initial snapshot hits a Firestore security rule that accesses resource.data.senderId on a null resource (doc doesn't exist), evaluating to false and denying the read. The stream subscription is silently cancelled. When the doc is later created by _startUpload() after Storage upload, the dead listener never receives any subsequent receiver updates."
fix: "Remove _startTransferListener() from initState(). Add a call to _startTransferListener() inside _startUpload() immediately after the await FirebaseFirestore.instance...set() call succeeds, so the listener only subscribes after the doc exists and the security rule can evaluate correctly."
verification: "After the fix, run UAT test 1: complete a transfer, verify sender sees 'Receiver successfully decrypted file' badge after receiver decrypts, then 'Receiver saved the file securely' badge + pulsing spinner after receiver saves."
files_changed: "lib/presentation/sender/transfer_progress_screen.dart"
