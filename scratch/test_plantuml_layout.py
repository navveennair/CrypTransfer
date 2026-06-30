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

' Styling classes to match standard UML tool look (simple black/white)
skinparam class {
    BackgroundColor #FFFFFF
    BorderColor #000000
    ArrowColor #000000
    FontName Arial
    FontSize 10
    FontColor #000000
    HeaderBackgroundColor #FFFFFF
}

' --- Group 1: User Profile ---
class User {
    uid : string (PK)
    username : string
    email : string
    phone : string
    publicKey : string (RSA-2048)
    isAdmin : bool
    isActive : bool
    isFirstTime : bool
    isReadyToReceive : bool
    readySince : timestamp
    selectedSenderUid : string (FK)
    pendingSenderFor : string (FK)
    pendingReceiverFor : string (FK)
    createdAt : timestamp
}

class UserPreferences {
    keyVaultCreatedAt : timestamp (PK)
    lastVaultAccessAt : timestamp
}

class RsaKeyManagerLog {
    id : string (PK)
    action : string
    timestamp : timestamp
    publicKeyHash : string
    deviceInfo : string
}

' --- Group 2: Connections & proposals ---
class Connection {
    uid : string (PK, FK)
    username : string
    email : string
    status : string
    updatedAt : timestamp
}

class NeutralHandshake {
    proposerId : string (PK, FK)
    partnerId : string (PK, FK)
    status : string
}

' --- Group 3: Transactions & Sessions ---
class Handshake {
    id : string (PK)
    senderId : string (FK)
    receiverId : string (FK)
    publicKey : string (PEM)
    status : string
    receiverReady : bool
    fromUsername : string
    receiverUsername : string
    sentAt : timestamp
}

class Transfer {
    id : string (PK)
    senderId : string (FK)
    receiverId : string (FK)
    fileName : string
    fileSize : int
    encryptedFileUrl : string
    encryptedAESKey : string
    iv : string
    status : string
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

' --- Group 4: Signaling & Logging ---
class Notification {
    id : string (PK)
    toUserId : string (FK)
    fromUsername : string
    type : string
    message : string
    transferId : string (FK)
    read : bool
    createdAt : timestamp
}

class AuditLog {
    id : string (PK)
    senderId : string (FK)
    receiverId : string (FK)
    senderUsername : string
    receiverUsername : string
    fileName : string
    fileSize : int
    status : string
    participants : array<string> (FK)
    loggedAt : timestamp
}

class KillSwitchLog {
    id : string (PK)
    senderId : string (FK)
    receiverId : string (FK)
    participants : array<string> (FK)
    status : string
    loggedAt : timestamp
}

class SecurityAuditLog {
    id : string (PK)
    event : string
    details : string
    adminUid : string (FK)
    timestamp : timestamp
}

' Layout Direction Hints to form a grid around User
User -down-> UserPreferences : has preferences >
User -down-> RsaKeyManagerLog : tracks key lifecycle >

User -right-> Connection : has friendships >
User -right-> NeutralHandshake : proposes/receives >

User -left-> Handshake : acts as sender/receiver >
User -left-> Transfer : acts as sender/receiver >

User -up-> Notification : receives >
User -up-> AuditLog : audit entries >
User -up-> KillSwitchLog : participates in >
User -up-> SecurityAuditLog : administered by >

Transfer -up-> Notification : referenced by >

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
        out_path = "scratch/erd_plantuml_layout.png"
        with open(out_path, "wb") as f:
            f.write(img_data)
        print(f"Success! Image saved to {out_path}")
except Exception as e:
    print(f"Failed: {e}")
