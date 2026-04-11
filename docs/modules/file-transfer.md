---
tags: [module, file-transfer, agent-active]
status: complete
---

# Module: File Transfer

## Responsibility
Handles encrypted file upload to Firebase Storage, transfer metadata in Firestore,
real-time progress tracking, non-repudiation status updates, and post-session cleanup.

## Files Owned
- `lib/data/repositories/transfer_repository.dart` — upload, download, status, audit log
- `lib/data/repositories/key_repository.dart` — `getAvailableReceivers()` used by SenderScreen for receiver discovery
- `lib/data/models/transfer_model.dart` — `TransferModel` + `TransferStatus` enum
- `lib/presentation/sender/sender_screen.dart` — file selection + RSA key fetch + encrypt + upload
- `lib/presentation/sender/transfer_progress_screen.dart` — real-time progress + non-repudiation listener
- `lib/presentation/receiver/receiver_screen.dart` — pending transfer Firestore listener
- `lib/presentation/receiver/receiver_transfer_screen.dart` — receiver-side transfer view
- `lib/presentation/receiver/decrypt_screen.dart` — download + AES decrypt (save-and-suicide)
- `lib/presentation/receiver/download_confirm_screen.dart` — file saved confirmation + path display
- `lib/presentation/session/end_session_screen.dart` — wipe + audit log + session end

## Dependencies
- `firebase_storage` — encrypted file storage
- `cloud_firestore` — transfer metadata, status, audit log
- `path_provider` — save decrypted file to device Downloads

## Transfer Flow

```
Sender: file_pick → fetch receiver pubKey → AES-GCM encrypt → upload Storage
      → write Firestore doc (status: pending) → notify receiver
      
Receiver: Firestore onSnapshot (pending) → banner → navigate → download
        → RSA-OAEP unwrap AES key → AES-GCM decrypt in isolate
        → save to /storage/emulated/0/Download → show path
        → session end → delete Storage file + Firestore doc
```

## Non-Repudiation Status Fields
`receiverStatus` on the transfer document is updated at each phase:

| Value | Set in | Meaning |
|-------|--------|---------|
| `downloading` | DecryptScreen init | Receiver started download |
| `decrypting` | Post-download | Receiver is decrypting |
| `decrypted` | Post-decrypt | Decryption complete |
| `saved` | Post-save | File written to device |

TransferProgressScreen listens to these updates and shows live status to the sender.

## Transfer Document Schema (Firestore: `transfers/{transferId}`)
```
senderId:          String
receiverId:        String
encryptedAESKey:   String   — base64, RSA-OAEP wrapped AES key  ← uppercase AES
encryptedFileUrl:  String   — Firebase Storage download URL
fileName:          String
fileSize:          int
iv:                String   — base64, 96-bit GCM nonce
status:            String   — 'pending' | 'received' | 'completed'
sessionActive:     bool
receiverStatus:    String?  — 'downloading' | 'decrypting' | 'decrypted' | 'saved'
createdAt:         Timestamp
receivedAt:        Timestamp?
```

> **Field name convention**: Firestore field is `encryptedAESKey` (uppercase AES).
> Dart identifiers across all files now consistently use `encryptedAESKey` to match.
> `TransferModel.encryptedAESKey` → Firestore `data['encryptedAESKey']`.

## TransferStatus Enum (Dart: `TransferModel`)
| Value | Firestore string | Meaning |
|-------|-----------------|---------|
| `TransferStatus.pending` | `'pending'` | Upload complete, awaiting receiver |
| `TransferStatus.received` | `'received'` | Receiver acknowledged |
| `TransferStatus.completed` | `'completed'` | Session ended, cleaned up |

## Firebase Storage Path
```
transfers/{transferId}/encrypted_file
```
Defined in `FirebaseConstants.transfersStorageRoot` + `FirebaseConstants.encryptedFileName`.
Max download: 100 MB (`FirebaseConstants.maxDownloadBytes`).

## RSA Key Transfer Document Schema (Firestore: `rsa_key_transfers/{docId}`)
```
fromUserId:    String    — sender UID
toUserId:      String    — recipient UID
publicKey:     String    — RSA-2048 public key PEM
sentAt:        Timestamp — last upsert time
fromUsername:  String?   — only set via sendPublicKey() (not _writePublicKeyTo())
status:        String?   — 'pending', only set via sendPublicKey()
```
Written by `KeyRepository._upsertKeyTransfer()` (upsert — updates if doc exists for the pair).
Batch-deleted by `EncryptionService.closeReceiverSession()` and `KeyRepository.wipeAllSessionKeys()`.

## Audit Log Document Schema (Firestore: `transfers_log/{docId}`)
```
senderId:      String
receiverId:    String
fileName:      String
transferDate:  String   — formatted date string
transferTime:  String   — formatted time string
status:        'completed'
loggedAt:      Timestamp
```
Written by `TransferRepository.writeAuditLog()` on EndSessionScreen.

> **⚠️ `participants` field — Implementation Gap**: `HomeScreen` queries `transfers_log` with
> `.where('participants', arrayContains: uid)` to show Recent Transfers. However,
> `writeAuditLog()` never writes a `participants` field — it only writes `senderId` / `receiverId`.
> **Result: Recent Transfers list on HomeScreen is always empty.**
> Fix: either add `participants: [senderId, receiverId]` to `writeAuditLog()`, or rewrite the
> HomeScreen query to use `senderId == uid || receiverId == uid` (requires two queries + merge).

## Key Repository Methods (TransferRepository)
| Method | Purpose |
|--------|---------|
| `uploadAndCreate()` | Stream<double> progress, creates transfer doc |
| `notifyReceiver()` | Writes `file_received` notification to `notifications` collection |
| `getTransfer()` | Fetches transfer doc by ID |
| `markReceived()` | Sets `status = received` |
| `downloadEncryptedFile()` | Downloads bytes from Storage |
| `deleteStorageFile()` | Removes encrypted file from Storage |
| `writeAuditLog()` | Writes to `transfers_log` collection |
| `deleteTransfer()` | Removes transfer doc from Firestore |
| `updateReceiverStatus()` | Updates `receiverStatus` field |
| `watchPendingTransfers()` | Real-time stream of pending transfers |

## KeyRepository Methods (receiver discovery — used by SenderScreen)
| Method | Purpose |
|--------|---------|
| `getAvailableReceivers()` | Returns users who sent their RSA public key to current user |

## DecryptScreen Phase Enum (`_Phase`)
`DecryptScreen` tracks download/decrypt state via the `_Phase` enum:

| Value | Meaning |
|-------|---------|
| `loading` | Fetching transfer doc from Firestore |
| `ready` | Transfer loaded, awaiting user action |
| `decrypting` | Download → RSA unwrap → AES-GCM decrypt in progress |
| `done` | Decryption complete, file written to device |
| `error` | Any failure state |

`receiverStatus` Firestore field is updated mid-`_Phase.decrypting` at 4 sub-points:
`downloading` → `decrypting` → `decrypted` → (post `_saveAndWipe()`) `saved`.
These sub-points map to the Non-Repudiation Status Fields table above.

## Current Status
✅ Encrypted file upload to Firebase Storage done  
✅ Transfer progress screen with real-time upload progress done  
✅ Firestore pending-transfer listener on ReceiverScreen done  
✅ Download + AES-GCM decrypt in compute isolate done  
✅ Save-and-suicide pattern in DecryptScreen (`_saveAndWipe()`)  
✅ DownloadConfirmScreen with file path display + clipboard copy  
✅ Decrypted file saved to Android `/storage/emulated/0/Download`  
✅ Non-repudiation `receiverStatus` listener in TransferProgressScreen  
✅ `writeAuditLog()` writes to `transfers_log` on session end  
✅ Post-session Firebase Storage delete (via EndSessionScreen)  
✅ TLS 1.3 via Firebase satisfies transport encryption requirement  
⚠️ Edge case: app killed mid-transfer — recovery not implemented

## Agent Instructions
1. Encrypted files MUST be deleted from Storage after session ends
2. Session integrity: cancellation must trigger full wipe
3. `receiverStatus` must be updated at every decrypt phase for non-repudiation
4. `decryptedBytes` must be zeroed via `SecurityLifecycleMixin` after file is saved
5. Update this doc after any transfer flow changes

## Open Tasks
- [ ] Test edge case: app killed mid-transfer
- [ ] Fix `participants` field gap: add `participants` array to `writeAuditLog()` so HomeScreen Recent Transfers list populates
