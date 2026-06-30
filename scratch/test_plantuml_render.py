import base64
import urllib.request
import zlib
import string
import os

plantuml_code = """@startuml
skinparam BackgroundColor #FFFFFF
skinparam dpi 150
skinparam shadowing false
skinparam classAttributeIconSize 0

skinparam class {
    BackgroundColor #FFFFFF
    BorderColor #000000
    ArrowColor #000000
    FontName Arial
    FontSize 10
    FontColor #000000
    HeaderBackgroundColor #FFFFFF
}

class User {
    + uid : string (PK)
    + username : string
    + email : string
    + phone : string
    + publicKey : string (RSA-2048)
    + isAdmin : bool
    + isActive : bool
    + isFirstTime : bool
    + isReadyToReceive : bool
    + readySince : timestamp
    + selectedSenderUid : string (FK)
    + pendingSenderFor : string (FK)
    + pendingReceiverFor : string (FK)
    + createdAt : timestamp
}

class UserPreferences {
    + keyVaultCreatedAt : timestamp (PK)
    + lastVaultAccessAt : timestamp
}

class Connection {
    + uid : string (PK, FK)
    + username : string
    + email : string
    + status : string
    + updatedAt : timestamp
}

class NeutralHandshake {
    + proposerId : string (PK, FK)
    + partnerId : string (PK, FK)
    + status : string
}

class Notification {
    + id : string (PK)
    + toUserId : string (FK)
    + fromUsername : string
    + type : string
    + message : string
    + transferId : string (FK)
    + read : bool
    + createdAt : timestamp
}

class Handshake {
    + id : string (PK)
    + senderId : string (FK)
    + receiverId : string (FK)
    + publicKey : string (PEM)
    + status : string
    + receiverReady : bool
    + fromUsername : string
    + receiverUsername : string
    + sentAt : timestamp
}

class Transfer {
    + id : string (PK)
    + senderId : string (FK)
    + receiverId : string (FK)
    + fileName : string
    + fileSize : int
    + encryptedFileUrl : string
    + encryptedAESKey : string
    + iv : string
    + status : string
    + sessionActive : bool
    + receiverReady : bool
    + senderCleanedUp : bool
    + senderCleanedUpAt : timestamp
    + receiverStatus : string
    + receiverStatusUpdatedAt : timestamp
    + cleanupInitiatedAt : timestamp
    + createdAt : timestamp
    + receivedAt : timestamp
}

class AuditLog {
    + id : string (PK)
    + senderId : string (FK)
    + receiverId : string (FK)
    + senderUsername : string
    + receiverUsername : string
    + fileName : string
    + fileSize : int
    + status : string
    + participants : array<string> (FK)
    + loggedAt : timestamp
}

class RsaKeyManagerLog {
    + id : string (PK)
    + action : string
    + timestamp : timestamp
    + publicKeyHash : string
    + deviceInfo : string
}

class KillSwitchLog {
    + id : string (PK)
    + senderId : string (FK)
    + receiverId : string (FK)
    + participants : array<string> (FK)
    + status : string
    + loggedAt : timestamp
}

class SecurityAuditLog {
    + id : string (PK)
    + event : string
    + details : string
    + adminUid : string (FK)
    + timestamp : timestamp
}

User "1" --> "1" UserPreferences : has preferences >
User "1" --> "0..*" Connection : has friendships >
User "1" --> "0..*" Notification : receives >
User "1" --> "0..*" AuditLog : audit entries >
User "1" --> "0..*" RsaKeyManagerLog : tracks key lifecycle >

User "1" --> "0..*" Handshake : acts as sender/receiver >
User "1" --> "0..*" Transfer : acts as sender/receiver >
User "1" --> "0..*" NeutralHandshake : proposes/receives >
User "1" --> "0..*" KillSwitchLog : participates in >
User "1" --> "0..*" SecurityAuditLog : administered by >

Transfer "1" --> "0..*" Notification : referenced by >

@enduml
"""

def get_plantuml_url(uml_text):
    plantuml_alphabet = string.digits + string.ascii_uppercase + string.ascii_lowercase + '-_'
    base64_alphabet = string.ascii_uppercase + string.ascii_lowercase + string.digits + '+/'
    b64_to_plantuml = bytes.maketrans(base64_alphabet.encode('utf-8'), plantuml_alphabet.encode('utf-8'))
    
    # Compress with zlib
    zlibbed = zlib.compress(uml_text.encode('utf-8'))
    # Strip zlib header and checksum
    compressed = zlibbed[2:-4]
    # Base64 encode and translate
    encoded = base64.b64encode(compressed).translate(b64_to_plantuml).decode('utf-8')
    return f"http://www.plantuml.com/plantuml/png/{encoded}"

url = get_plantuml_url(plantuml_code)
print(f"Requesting URL: {url[:100]}...")

try:
    req = urllib.request.Request(
        url, 
        headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}
    )
    with urllib.request.urlopen(req, timeout=30) as response:
        img_data = response.read()
        out_path = "scratch/erd_plantuml_test.png"
        with open(out_path, "wb") as f:
            f.write(img_data)
        print(f"Success! Image saved to {out_path}")
except Exception as e:
    print(f"Failed: {e}")
