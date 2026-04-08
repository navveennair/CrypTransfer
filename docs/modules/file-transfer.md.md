---
tags: [module, file-transfer, agent-active]
status: in-progress
---

# Module: File Transfer

## Responsibility
Handles encrypted file upload to Firebase Storage, transfer progress tracking,
session integrity enforcement, and auto-deletion post-session.

## Files Owned
- lib/src/features/transfer/

## Dependencies
- Firebase Storage
- Firebase Firestore (metadata)

## Current Status
✅ Encrypted file upload done
✅ Transfer progress screen done
✅ Session cancellation wipes files
✅ Auto-deletion of encrypted files post-session
✅ TLS 1.3 via Firebase satisfies TLSChannel requirement

## Agent Instructions
1. Encrypted files must NEVER be stored undeleted after session ends
2. Session integrity must be enforced — cancellation triggers full wipe
3. Update this doc after any transfer flow changes

## Open Tasks
- [ ] Test edge case: app killed mid-transfer
- [ ] Verify TransferScreen triggers on Sender AND Receiver simultaneously via Firestore listener
- [ ] Receiver Transfer Session must only initialize on confirmed file receipt
- [ ] Verify decrypted file is saved to local device storage and accessible outside app