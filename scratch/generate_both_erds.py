import base64
import urllib.request
import zlib
import string
import os

# ----------------- PLANTED UML DEFINITION -----------------
plantuml_code = """@startuml
skinparam linetype ortho
skinparam dpi 150
skinparam shadowing false
skinparam class {
    BackgroundColor #F9FAFB
    BorderColor #4B5563
    ArrowColor #6B7280
    FontName Arial
    FontSize 11
}
title CrypTransfer Firestore Data Model (NoSQL ERD)

entity "User Profile\nusers/{uid}" as User {
    * uid : string [PK]
    --
    username : string
    email : string
    phone : string
    publicKey : string [RSA-2048]
    isAdmin : bool
    isActive : bool
    isFirstTime : bool
    isReadyToReceive : bool
    readySince : timestamp
    selectedSenderUid : string [FK]
    pendingSenderFor : string [FK]
    pendingReceiverFor : string [FK]
    createdAt : timestamp
}

entity "User Preferences\nusers/{uid}/profile/preferences" as UserPreferences {
    * keyVaultCreatedAt : timestamp [PK]
    --
    lastVaultAccessAt : timestamp
}

entity "Friendship/Connection\nusers/{uid}/friendships/{otherUid}" as Connection {
    * uid : string [PK, FK]
    --
    username : string
    email : string
    status : string ("accepted")
    updatedAt : timestamp
}

entity "Neutral Handshake\nneutral_handshakes/{compositeId}" as NeutralHandshake {
    * proposerId : string [PK, FK]
    * partnerId : string [PK, FK]
    --
    status : string ("pending"|"connected"|"rejected")
}

entity "Notification Inbox\nusers/{uid}/notifications/{autoId}" as Notification {
    * id : string [PK]
    --
    toUserId : string [FK]
    fromUsername : string
    type : string [enum]
    message : string
    transferId : string [FK]
    read : bool
    createdAt : timestamp
}

entity "Key Exchange (Handshake)\nhandshakes/{autoId}" as Handshake {
    * id : string [PK]
    --
    senderId : string [FK]
    receiverId : string [FK]
    publicKey : string [PEM]
    status : string ("pending"|"handshake_complete")
    receiverReady : bool
    fromUsername : string
    receiverUsername : string
    sentAt : timestamp
}

entity "Active File Transfer\ntransfers/{transferId}" as Transfer {
    * id : string [PK]
    --
    senderId : string [FK]
    receiverId : string [FK]
    fileName : string
    fileSize : int
    encryptedFileUrl : string
    encryptedAESKey : string
    iv : string
    status : string [enum]
    sessionActive : bool
    receiverReady : bool
    senderCleanedUp : bool
    senderCleanedUpAt : timestamp
    receiverStatus : string
    receiverStatusUpdatedAt : timestamp
    cleanupInitiatedAt : timestamp
    createdAt : timestamp
    receivedAt : timestamp
}

entity "Historical Audit Log\nusers/{uid}/audit_logs/{autoId}" as AuditLog {
    * id : string [PK]
    --
    senderId : string [FK]
    receiverId : string [FK]
    senderUsername : string
    receiverUsername : string
    fileName : string
    fileSize : int
    status : string [enum]
    participants : array<string> [FK]
    loggedAt : timestamp
}

entity "RSA Key Lifecycle Log\nusers/{uid}/rsa_key_manager/{autoId}" as RsaKeyManagerLog {
    * id : string [PK]
    --
    action : string ("generated"|"regenerated"|"deleted")
    timestamp : timestamp
    publicKeyHash : string (nullable)
    deviceInfo : string
}

entity "Kill Switch Log\ntransfer_logs/{autoId}" as KillSwitchLog {
    * id : string [PK]
    --
    senderId : string [FK]
    receiverId : string [FK]
    participants : array<string> [FK]
    status : string ("kill_switch")
    loggedAt : timestamp
}

entity "Admin Security Audit Log\nsecurity_audit_log/{autoId}" as SecurityAuditLog {
    * id : string [PK]
    --
    event : string ("ADMIN_USER_RESTORE"|"ADMIN_USER_REVOKE")
    details : string
    adminUid : string [FK]
    timestamp : timestamp
}

' --- Relationships ---
User ||--o| UserPreferences : "profile preferences (1:1)"
User ||--o{ Connection : "friendships (1:N)"
User ||--o{ Notification : "receives (1:N)"
User ||--o{ AuditLog : "audit entries (1:N)"
User ||--o{ RsaKeyManagerLog : "tracks lifecycle (1:N)"

User ||--o{ Handshake : "acts as sender/receiver"
User ||--o{ Transfer : "acts as sender/receiver"
User ||--o{ NeutralHandshake : "proposes/receives"
User ||--o{ KillSwitchLog : "participates in"
User ||--o{ SecurityAuditLog : "administered by"

Transfer ||--o{ Notification : "referenced by"
Transfer .left.> AuditLog : "creates history log"

@enduml
"""

# ----------------- MERMAID DEFINITION -----------------
mermaid_code = """erDiagram
    User ||--o| UserPreferences : "has preferences"
    User ||--o{ Connection : "has friendship"
    User ||--o{ Notification : "receives notification"
    User ||--o{ AuditLog : "participates in audit trail"
    User ||--o{ RsaKeyManagerLog : "tracks key actions"
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

# ----------------- RENDER FUNCTIONS -----------------
def get_plantuml_url(uml_text):
    # PlantUML encoding mapping
    plantuml_alphabet = string.digits + string.ascii_uppercase + string.ascii_lowercase + '-_'
    base64_alphabet = string.ascii_uppercase + string.ascii_lowercase + string.digits + '+/'
    b64_to_plantuml = bytes.maketrans(base64_alphabet.encode('utf-8'), plantuml_alphabet.encode('utf-8'))
    
    # 1. Compress with zlib
    zlibbed = zlib.compress(uml_text.encode('utf-8'))
    # 2. Strip zlib header (2 bytes) and checksum (4 bytes)
    compressed = zlibbed[2:-4]
    # 3. Base64 encode and translate
    encoded = base64.b64encode(compressed).translate(b64_to_plantuml).decode('utf-8')
    return f"http://www.plantuml.com/plantuml/png/{encoded}"

def get_mermaid_url(mermaid_str, theme="light"):
    encoded_bytes = base64.urlsafe_b64encode(mermaid_str.encode("utf-8"))
    encoded_str = encoded_bytes.decode("ascii").strip("=")
    url = f"https://mermaid.ink/img/{encoded_str}"
    if theme == "dark":
        url += "?bgColor=0D1117"
    else:
        url += "?bgColor=ffffff"
    return url

def download_image(url, out_path):
    print(f"Downloading {url[:80]}...")
    try:
        req = urllib.request.Request(
            url, 
            headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}
        )
        with urllib.request.urlopen(req, timeout=30) as response:
            with open(out_path, "wb") as f:
                f.write(response.read())
        print(f"Successfully downloaded to {out_path}")
        return True
    except Exception as e:
        print(f"Error downloading: {e}")
        return False

# Ensure output directory exists
os.makedirs("scratch", exist_ok=True)

# Generate PlantUML PNG
puml_url = get_plantuml_url(plantuml_code)
download_image(puml_url, "scratch/erd_plantuml.png")

# Generate Mermaid PNG
mermaid_url = get_mermaid_url(mermaid_code, "light")
download_image(mermaid_url, "scratch/erd_mermaid.png")
