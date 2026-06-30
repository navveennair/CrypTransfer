<!-- converted from CrypTransfer_Database_Design_ERD_Corrected_v3.docx -->

# CrypTransfer: Database Design (ERD) - Corrected
Reflects the actual Firestore (NoSQL document) data model as implemented in the codebase. Verified against firebase_constants.dart, transfer_model.dart, user_model.dart, transfer_repository.dart, admin_repository.dart and key_repository.dart (2026-06-11). The full data model — all 11 entities and their relationships — is shown on a single landscape diagram below.

## Entity Relationship Diagram (Complete Data Model — Single Page)


Figure 1 — CrypTransfer Firestore data model: all 11 entity collections, key/foreign-key fields, and primary relationships, consolidated on a single page.
## Data Entities and Relationships
User: Stores Firestore profile data only. Authentication credentials (password) are managed entirely by Firebase Auth and are never written to Firestore. The RSA public key is stored as a raw string directly on the user document; the RSA private key is generated on-device and stored only in FlutterSecureStorage, never synced to the backend.
### User - users/{uid}

Transfer: The central transaction document. Combines what the original ERD split into TransferSession + File + AESKey into a single Firestore document - this is idiomatic for NoSQL (denormalized, single round-trip read).
### Transfer - transfers/{transferId}

Handshake: This is the real-world equivalent of the original ERD's "RSAKeys" entity, but it models a per-pair key exchange event rather than a per-user key-pair record. There is no "keyID", "publicKeyID" or "privateKeyID" - the public key value itself is stored inline.
### Handshake - handshakes/{autoId}

NeutralHandshake: Connection proposal layer, prior to RSA key exchange.
### NeutralHandshake - neutral_handshakes/{proposerId}_{partnerId}

Connection: Per-user accepted-friend records (subcollection, written symmetrically to both users).
### Connection - users/{uid}/friendships/{otherUid}

AuditLog: Immutable transfer history. Written to the requesting user's and the counterpart's users/{uid}/audit_logs subcollection in a single WriteBatch (one record each, identical payload). This is now the single canonical audit trail: HomeScreen reads a user's own subcollection for "Recent Transfers", and the Admin Dashboard reads the audit_logs collection group (across all users, ordered by loggedAt) for the "TRANSFERS" stat and the "TRANSFER LOG" feed. Because every event is written twice (once per participant), the Admin Dashboard halves the raw collection-group doc count to report a true transfer count.
### AuditLog - users/{uid}/audit_logs/{autoId}

KillSwitchLog: Narrow, append-only security event log - separate from AuditLog and NOT part of the general transfer history. The only writer is EncryptionService.closeReceiverSession(), fired when a receiver's mailbox is forcibly closed (kill switch) while a sender was actively authorized (selectedSenderUid was set). One record per kill-switch event.
### KillSwitchLog - transfer_logs/{autoId}
Notification: In-app notification inbox (subcollection per user).
### Notification - users/{uid}/notifications/{autoId}

SecurityAuditLog: Append-only log of administrative actions taken from the Admin Dashboard (e.g. revoking/restoring user access). Readable only by admins; any authenticated client may create (the action itself is gated by Firestore rules on the target document, e.g. users.update requires isAdmin()).
### SecurityAuditLog - security_audit_log/{autoId}
RsaKeyManagerLog: Immutable per-user audit trail of RSA keypair lifecycle events (generation, regeneration, deletion). Written by AuthRepository alongside the publicKey update on the parent User document, in the same WriteBatch.
### RsaKeyManagerLog - users/{uid}/rsa_key_manager/{autoId}
UserPreferences: Per-user app/security preferences and vault-access timestamps. Single document at a fixed ID ('preferences'); written with set(merge: true) so it self-creates for users who registered before this subcollection existed.
### UserPreferences - users/{uid}/profile/preferences
## Removed dead "connections" Firestore-collection constant - the schema never wrote to users/{uid}/connections; the actual accepted-friend subcollection is users/{uid}/friendships/{otherUid} (written by sendConnectionRequest / acceptProposal). The "Connection" entity above has been corrected to this real path. Also documented three additional supporting collections present in the codebase but missing from this ERD: SecurityAuditLog, RsaKeyManagerLog, and UserPreferences.
## Key Corrections vs. Previous (Relational) ERD
- Removed "password" from User - Firebase Auth manages credentials; never stored in Firestore.
- Replaced "role" with "isAdmin" (bool) - matches actual privilege model used by the Admin Dashboard.
- Removed standalone "RSAKeys" table (keyID/publicKeyID/privateKeyID). Public key is an inline string field on User and on Handshake. Private key is device-only (FlutterSecureStorage) and is intentionally absent from any database schema - this is a security boundary, not an omission.
- Removed standalone "AESKey" / "AESKey (Ref Shared Object)" tables - the encrypted AES session key ("encryptedAESKey") is a field embedded directly in the Transfer document. There is no shared AES key object referenced by multiple entities.
- Added "iv" (AES initialization vector) field to Transfer - required for decryption, missing entirely from the original diagram.
- Removed standalone "File" table - fileName, fileSize and encryptedFileUrl (replaces filePath) are embedded directly in the Transfer document. fileType is not tracked.
- Renamed "TransferSession" to "Transfer" and expanded it with the real lifecycle/status fields used by the synchronized cleanup protocol (status, sessionActive, senderCleanedUp, receiverStatus, cleanupInitiatedAt, etc.).
- Added four entity types missing from the original ERD entirely: Handshake (RSA exchange), NeutralHandshake (connection proposals), Connection (accepted friendships), AuditLog (immutable history), and Notification (inbox).
- Corrected Admin Dashboard data source - previously the "Total Transfers" stat and "Transfer Log" feed read a top-level transfer_logs collection that was populated only by an unused dead-code path (TransferLogService.logTransferStart / TransferRepository.writeAuditLog, both removed). Both now read the audit_logs collection group, the same data HomeScreen already used, so admin metrics reflect real activity.
- Corrected cardinality - all relationships are 1:N (one User has many Transfers, Handshakes, Connections, AuditLogs), not the 1:1 chains shown in the original diagram.
| Field | Type / Reference | Notes |
| --- | --- | --- |
| uid | string (PK, = Firebase Auth UID) | Document ID |
| username | string |  |
| email | string |  |
| phone | string |  |
| publicKey | string (RSA-2048, raw, base64/PEM) | Embedded directly - no separate key table |
| isAdmin | bool | Replaces "role" - drives Admin Dashboard access |
| isActive / isFirstTime | bool |  |
| createdAt | timestamp |  |
| selectedSenderUid | string (FK -> users) | Receiver-authorized sender for active session |
| isReadyToReceive / readySince | bool / timestamp | Mailbox open/closed state |
| pendingSenderFor / pendingReceiverFor | string (FK -> users) | Transient role-claim during handshake |
| Field | Type / Reference | Notes |
| --- | --- | --- |
| id | string (PK, doc ID) |  |
| senderId / receiverId | string (FK -> users) |  |
| fileName / fileSize | string / int | Embedded file metadata - no separate File entity |
| encryptedFileUrl | string (Firebase Storage URL) | Replaces "filePath" |
| encryptedAESKey | string (RSA-wrapped AES key, raw) | No separate AESKey entity - embedded |
| iv | string (base64, AES IV) | NOT present in original ERD - required for decryption |
| status | enum: pending/received/completed/failed/cancelled/rejected/cleanup_initiated |  |
| sessionActive / receiverReady | bool |  |
| senderCleanedUp / senderCleanedUpAt | bool / timestamp | Synchronized cleanup protocol (Turn 2) |
| receiverStatus / receiverStatusUpdatedAt | string / timestamp | Synchronized cleanup protocol (Turn 1/3) |
| cleanupInitiatedAt | timestamp |  |
| createdAt / receivedAt | timestamp |  |
| Field | Type / Reference | Notes |
| --- | --- | --- |
| id | string (PK, doc ID, auto-generated) |  |
| senderId / receiverId | string (FK -> users) |  |
| publicKey | string (RSA public key, raw) | Receiver's key, published to sender |
| status | enum: pending | handshake_complete |  |
| receiverReady | bool |  |
| fromUsername / receiverUsername | string | Denormalized display names |
| sentAt | timestamp |  |
| Field | Type / Reference | Notes |
| --- | --- | --- |
| proposerId / partnerId | string (FK -> users) | Deterministic composite doc ID |
| status | enum: pending | connected | rejected |  |
| Field | Type / Reference | Notes |
| --- | --- | --- |
| uid | string (FK -> users, the other party) | Document ID |
| username / email | string | Denormalized |
| status | string ("accepted") |  |
| updatedAt | timestamp |  |
| Field | Type / Reference | Notes |
| --- | --- | --- |
| senderId / receiverId | string (FK -> users) |  |
| senderUsername / receiverUsername | string |  |
| fileName / fileSize | string / int |  |
| status | enum: completed | aborted | connection_lost |  |
| participants | array<string> (FK -> users) | Used by HomeScreen recent-activity query |
| timestamp / loggedAt | timestamp |  |
| Field | Type / Reference | Notes |
| --- | --- | --- |
| senderId / receiverId | string (FK -> users) | senderId = active sender, receiverId = the user who triggered the kill switch |
| participants | array<string> (FK -> users) | [senderId, receiverId] — kept for symmetry with AuditLog, not used for queries |
| status | string ("kill_switch") | Single fixed value — distinguishes this from AuditLog's status enum |
| loggedAt | timestamp | FieldValue.serverTimestamp(); write is fire-and-forget (.ignore()) |
| Field | Type / Reference | Notes |
| --- | --- | --- |
| toUserId | string (FK -> users) | Required by Firestore security rule on create |
| fromUsername | string |  |
| type | enum: friend_request | rsa_key_received | file_received | transfer_completed | transfer_aborted |  |
| message | string |  |
| transferId | string (FK -> transfers, optional) |  |
| read | bool |  |
| createdAt | timestamp |  |
| Field | Type / Reference | Notes |
| --- | --- | --- |
| event | string ("ADMIN_USER_RESTORE" | "ADMIN_USER_REVOKE") | Type of administrative action performed |
| details | string | Human-readable description, e.g. "User {uid} access status changed to {bool}" |
| adminUid | string (FK -> users) | UID of the admin who performed the action |
| timestamp | timestamp |  |
| Field | Type / Reference | Notes |
| --- | --- | --- |
| action | enum: generated | regenerated | deleted |  |
| timestamp | timestamp |  |
| publicKeyHash | string? (fingerprint, nullable) | null when action == 'deleted' — no key left to hash |
| deviceInfo | string | Platform name (defaultTargetPlatform.name) |
| Field | Type / Reference | Notes |
| --- | --- | --- |
| keyVaultCreatedAt | timestamp | Stamped on RSA key (re)generation |
| lastVaultAccessAt | timestamp | Stamped each time the user opens their key vault |