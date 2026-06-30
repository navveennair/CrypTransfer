import base64
import urllib.request
import os

mermaid_code = """erDiagram
    User ||--o| UserPreferences : "has profile"
    User ||--o{ Connection : "has friendships"
    User ||--o{ Notification : "receives notifications"
    User ||--o{ AuditLog : "participates in audit trail"
    User ||--o{ RsaKeyManagerLog : "tracks key events"
    User ||--o{ Handshake : "acts as sender/receiver"
    User ||--o{ Transfer : "acts as sender/receiver"
    User ||--o{ NeutralHandshake : "proposes/receives"
    User ||--o{ KillSwitchLog : "acts as participant"
    User ||--o{ SecurityAuditLog : "administered by"
    Transfer ||--o{ Notification : "referenced by"

    User {
        string uid PK "Document ID (= Auth UID)"
        string username
        string email
        string phone
        string publicKey "RSA-2048 Public Key"
        bool isAdmin "Admin Dashboard access"
        bool isActive
        bool isFirstTime
        bool isReadyToReceive "Mailbox state"
        timestamp readySince
        string selectedSenderUid FK "users/{uid}"
        string pendingSenderFor FK "users/{uid}"
        string pendingReceiverFor FK "users/{uid}"
        timestamp createdAt
    }

    UserPreferences {
        timestamp keyVaultCreatedAt PK "Fixed ID 'preferences'"
        timestamp lastVaultAccessAt
    }

    Connection {
        string uid PK "Friend's User UID"
        string username
        string email
        string status "accepted"
        timestamp updatedAt
    }

    NeutralHandshake {
        string proposerId PK, FK "Composite PK element"
        string partnerId PK, FK "Composite PK element"
        string status "pending | connected | rejected"
    }

    Notification {
        string id PK "Auto-generated ID"
        string toUserId FK "users/{uid}"
        string fromUsername
        string type "enum: friend_request | ..."
        string message
        string transferId FK "transfers/{id}"
        bool read
        timestamp createdAt
    }

    Handshake {
        string id PK "Auto-generated ID"
        string senderId FK "users/{uid}"
        string receiverId FK "users/{uid}"
        string publicKey "PEM encoded key"
        string status "pending | handshake_complete"
        bool receiverReady
        string fromUsername
        string receiverUsername
        timestamp sentAt
    }

    Transfer {
        string id PK "Document ID"
        string senderId FK "users/{uid}"
        string receiverId FK "users/{uid}"
        string fileName
        int fileSize
        string encryptedFileUrl "Firebase Storage URL"
        string encryptedAESKey "RSA-wrapped AES key"
        string iv "AES nonce"
        string status "pending | received | completed | ..."
        bool sessionActive
        bool receiverReady
        bool senderCleanedUp
        timestamp senderCleanedUpAt
        string receiverStatus "downloading | decrypting | saved"
        timestamp receiverStatusUpdatedAt
        timestamp cleanupInitiatedAt
        timestamp createdAt
        timestamp receivedAt
    }

    AuditLog {
        string id PK "Auto-generated ID"
        string senderId FK "users/{uid}"
        string receiverId FK "users/{uid}"
        string senderUsername
        string receiverUsername
        string fileName
        int fileSize
        string status "completed | aborted | ..."
        string_array participants FK "Array of UIDs"
        timestamp loggedAt
    }

    RsaKeyManagerLog {
        string id PK "Auto-generated ID"
        string action "generated | regenerated | deleted"
        timestamp timestamp
        string publicKeyHash "Nullable hash"
        string deviceInfo
    }

    KillSwitchLog {
        string id PK "Auto-generated ID"
        string senderId FK "users/{uid}"
        string receiverId FK "users/{uid}"
        string_array participants FK "Array of UIDs"
        string status "kill_switch"
        timestamp loggedAt
    }

    SecurityAuditLog {
        string id PK "Auto-generated ID"
        string event "ADMIN_USER_RESTORE | ..."
        string details
        string adminUid FK "users/{uid}"
        timestamp timestamp
    }
"""

def generate_image_from_mermaid(mermaid_str, theme="dark"):
    # Encode the raw string
    encoded_bytes = base64.urlsafe_b64encode(mermaid_str.encode("utf-8"))
    encoded_str = encoded_bytes.decode("ascii").strip("=")
    
    url = f"https://mermaid.ink/img/{encoded_str}"
    if theme == "dark":
        url += "?bgColor=0D1117"
    
    print(f"Requesting URL: {url[:100]}...")
    
    try:
        req = urllib.request.Request(
            url, 
            headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}
        )
        with urllib.request.urlopen(req, timeout=30) as response:
            img_data = response.read()
            out_path = f"scratch/test_erd_mermaid_{theme}.png"
            with open(out_path, "wb") as f:
                f.write(img_data)
            print(f"Success! Image saved to {out_path}")
            return out_path
    except Exception as e:
        print(f"Failed to fetch image for theme {theme}: {e}")
        return None

generate_image_from_mermaid(mermaid_code, "dark")
generate_image_from_mermaid(mermaid_code, "light")
