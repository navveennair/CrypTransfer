import base64
import urllib.request
import zlib
import string
import os
import shutil

# ----------------- PLANTUML: Original Thesis ERD -----------------
# Based exactly on the user's thesis wording:
# User --> TransferSession (via senderID, receiverID FK)
# TransferSession --> File (via transferSessionID FK)
# User --> RSAKeys (via userID FK)
# TransferSession --> RSAKeys (two RSA keys per session)
# RSAKeys --> AESKey (RSA encrypts the AES key)
# File --> AESKey (via aesKeyID FK)
# AESKey --> User (via userID FK)

plantuml_code = """@startuml
skinparam BackgroundColor #FFFFFF
skinparam dpi 150
skinparam shadowing false
skinparam classAttributeIconSize 0
skinparam linetype ortho

skinparam class {
    BackgroundColor #FFFFFF
    BorderColor #000000
    ArrowColor #000000
    FontName Arial
    FontSize 10
    FontColor #000000
    HeaderBackgroundColor #FFFFFF
    BorderThickness 1
}

skinparam ArrowColor #000000
skinparam ArrowFontName Arial
skinparam ArrowFontSize 10

class User {
    - userID (PK)
    - username
    - password
    - email
    - role
}

class TransferSession {
    - sessionID (PK)
    - senderID (FK)
    - receiverID (FK)
    - timestamp
}

class File {
    - fileID (PK)
    - fileName
    - fileSize
    - fileType
    - filePath
    - transferSessionID (FK)
    - aesKeyID (FK)
}

class RSAKeys {
    - keyID (PK)
    - userID (FK)
    - publicKeyID
    - privateKeyID
    - transferSessionID
}

class AESKey {
    - aesKeyID (PK)
    - userID (FK)
    - transferSessionID (FK)
}

' User initiates TransferSession (1..* sessions)
User "1" -right-> "0..*" TransferSession : initiates

' User generates RSAKeys (0..*) 
User "1" -down-> "0..*" RSAKeys : generates

' TransferSession contains File (1 or more files)
TransferSession "1" -right-> "1" File : contains

' TransferSession uses RSAKeys (for session AES key exchange)
TransferSession "1" -down-> "1" RSAKeys : uses

' File has AESKey (each file encrypted with one AES key)
File "1" -down-> "1" AESKey : has

' RSAKeys encryptedBy AESKey (RSA used to encrypt AES key)
RSAKeys "1" -right-> "1" AESKey : encryptedBy

' AESKey belongs to User
AESKey "1" -up-> "1" User : create

@enduml
"""

def get_plantuml_url(uml_text):
    plantuml_alphabet = string.digits + string.ascii_uppercase + string.ascii_lowercase + '-_'
    base64_alphabet = string.ascii_uppercase + string.ascii_lowercase + string.digits + '+/'
    b64_to_plantuml = bytes.maketrans(base64_alphabet.encode('utf-8'), plantuml_alphabet.encode('utf-8'))
    zlibbed = zlib.compress(uml_text.encode('utf-8'))
    compressed = zlibbed[2:-4]
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
        out_path = "scratch/erd_thesis_original.png"
        with open(out_path, "wb") as f:
            f.write(img_data)
        print(f"Success! Image saved to {out_path}")
except Exception as e:
    print(f"Failed: {e}")
