<!-- converted from CrypTransfer_Database_Design_ERD.docx -->

CrypTransfer: Database Design (ERD)

+-----------------------+       +-----------------------+       +-----------------------+
|         User          |       |    TransferSession    |       |         File          |
+-----------------------+       +-----------------------+       +-----------------------+
| - userID (PK)         | 1   1 | - sessionID (PK)      | 1   1 | - fileID (PK)         |
| - username            |-------| - senderID (FK)       |-------| - fileName            |
| - password            |       | - receiverID (FK)     |       | - fileSize            |
| - email               |       | - timestamp           |       | - fileType            |
| - role                |       +-----------+-----------+       | - filePath            |
+-----------+-----------+                   |                   | - transferSessionID(FK)|
            |                               |                   +-----------+-----------+
            | generates                     | uses                          |
            |                               |                               | encryptedWith
            | 1                             | 1                             |
            v                               v                               v
+-----------+-----------+       +-----------+-----------+       +-----------+-----------+
|        RSAKeys        |       |         AESKey        |       |        AESKey         |
+-----------------------+       +-----------------------+       | (Ref Shared Object)   |
| - keyID (PK)          | 1   1 | - aesKeyID (PK)       |       +-----------------------+
| - userID (FK)         |-------| - userID (FK)         |       | - aesKeyID (PK)       |
| - publicKeyID         |       | - transferSessionID(FK)|<------| - userID (FK)         |
| - privateKeyID        |       +-----------+-----------+       | - transferSessionID(FK)|
| - transferSessionID   |                   ^                   +-----------------------+
+-----------+-----------+                   |
            |                               |
            +---------- encryptedBy --------+

# Data Entities & Relationships
- User: Stores core user credentials and roles. Initiates TransferSessions and generates RSA KeyPairs.
- TransferSession: The central transaction log. Links a sender, a receiver, a file, and the encryption keys used for a specific event.
- File: Contains metadata for the shared file. Every file is strictly associated with one TransferSession.
- RSAKeys: Stores the RSA-2048 keypair IDs. Used to wrap (encrypt) the session-specific AES key.
- AESKey: The symmetric key used for the actual file payload encryption. It is unique per file and per session.