import docx
from docx.shared import Inches, Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH

def create_sequence_diagrams():
    doc = docx.Document()
    
    # Page Setup
    sections = doc.sections
    for section in sections:
        section.top_margin = Inches(0.5)
        section.bottom_margin = Inches(0.5)
        section.left_margin = Inches(0.5)
        section.right_margin = Inches(0.5)

    def add_sequence_page(id_title, diagram_text):
        # Title
        t = doc.add_paragraph()
        t.alignment = WD_ALIGN_PARAGRAPH.CENTER
        run = t.add_run(id_title)
        run.font.name = 'Arial'
        run.font.size = Pt(14)
        run.font.bold = True
        
        doc.add_paragraph("\n")
        
        # Diagram
        p = doc.add_paragraph()
        run_d = p.add_run(diagram_text)
        run_d.font.name = 'Courier New'
        run_d.font.size = Pt(8)
        
        doc.add_page_break()

    # SD001: Login Account
    sd001 = """
    User              SystemController             Database
      |                      |                        |
      |--enterCredentials()-->|                        |
      |                      |----validate(creds)---->|
      |                      |                        |
      |                      |<---authStatus(valid)---|
      |                      |                        |
      |<---accessGranted()---|                        |
      |                      |                        |
"""
    add_sequence_page("SD001: Login Account", sd001)

    # SD002: Register Account
    sd002 = """
    User              SystemController             Database
      |                      |                        |
      |---provideInfo()----->|                        |
      |                      |---checkUniqueness()--->|
      |                      |                        |
      |                      |<------unique(true)-----|
      |                      |                        |
      |                      |----createAccount()---->|
      |                      |                        |
      |                      |<----accountCreated()---|
      |                      |                        |
      |<---regSuccess()------|                        |
      |                      |                        |
"""
    add_sequence_page("SD002: Register Account", sd002)

    # SD003: Choose File
    sd003 = """
    User              SystemController             FileSystem
      |                      |                        |
      |--selectFileRequest()->|                        |
      |                      |------openPicker()----->|
      |                      |                        |
      |                      |<----fileSelected()-----|
      |                      |                        |
      |<---displayFile()-----|                        |
      |                      |                        |
"""
    add_sequence_page("SD003: Choose File", sd003)

    # SD004: Generate AES Key
    sd004 = """
    SystemController       EncryptionService
      |                            |
      |-----requestAESKey()------->|
      |                            |
      |                            |---generateRandomBytes()
      |                            |
      |<---------aesKey()----------|
      |                            |
"""
    add_sequence_page("SD004: Generate AES Key", sd004)

    # SD005: Encrypt File
    sd005 = """
    SystemController       EncryptionService
      |                            |
      |-------encrypt(file)------->|
      |                            |
      |                            |---aesGcmProcess()
      |                            |
      |<------encryptedFile--------|
      |                            |
"""
    add_sequence_page("SD005: Encrypt File", sd005)

    # SD006: Generate RSA Key
    sd006 = """
    SystemController       EncryptionService         SecureStorage
      |                            |                        |
      |----requestRSAKeyPair()---->|                        |
      |                            |                        |
      |                            |---generateRSA(2048)    |
      |                            |                        |
      |<--------keyPair()----------|                        |
      |                            |                        |
      |-----------savePrivate(priv)------------------------>|
      |                            |                        |
"""
    add_sequence_page("SD006: Generate RSA Key", sd006)

    # SD007: Transfer File
    sd007 = """
    SystemController       EncryptionService       TLSChannel             Database
      |                            |                    |                    |
      |---encryptAESKey(key)------>|                    |                    |
      |                            |                    |                    |
      |<-------encAESKey-----------|                    |                    |
      |                            |                    |                    |
      |---------initiateConnection()------------------->|                    |
      |                            |                    |                    |
      |<-----------status(OK)---------------------------|                    |
      |                            |                    |                    |
      |---------sendData(payload)---------------------->|                    |
      |                            |                    |                    |
      |                            |                    |---writeSession()-->|
      |                            |                    |                    |
"""
    add_sequence_page("SD007: Transfer File", sd007)

    # SD008: Receive File (Reference Match)
    sd008 = """
    User        SystemController      TLSChannel      TransferSession      File
      |                |                  |                  |               |
      |--requestRec()->|                  |                  |               |
      |                |--initConnect()-->|                  |               |
      |                |<-connStatus(OK)--|                  |               |
      |                |---receiveData()->|                  |               |
      |                |                  |--getSession()--->|               |
      |                |                  |                  |---fetchFile()->|
      |                |                  |                  |<--filePath-----|
      |                |                  |<--returnPath-----|               |
      |                |<---deliver()-----|                  |               |
      |<---success-----|                  |                  |               |
"""
    add_sequence_page("SD008: Receive File", sd008)

    # SD009: Decrypt File
    sd009 = """
    SystemController       SecureStorage       EncryptionService
      |                            |                    |
      |----getRSAPrivateKey()----->|                    |
      |                            |                    |
      |<-------privateKey----------|                    |
      |                            |                    |
      |----decryptAESKey(key)-------------------------->|
      |                            |                    |
      |<----------aesKey--------------------------------|
      |                            |                    |
      |----decryptFile(file)--------------------------->|
      |                            |                    |
      |<---------plainFile------------------------------|
      |                            |                    |
"""
    add_sequence_page("SD009: Decrypt File", sd009)

    # SD010: Cleanup Temporary Memory
    sd010 = """
    SystemController       EncryptionService         FileSystem
      |                            |                        |
      |-----triggerCleanup()------>|                        |
      |                            |                        |
      |                            |---fillRange(0)         |
      |                            |                        |
      |-----deleteTempFiles()------------------------------>|
      |                            |                        |
      |<-------status(secure)------|                        |
      |                            |                        |
"""
    add_sequence_page("SD010: Cleanup Temporary Memory", sd010)

    # SD011: Generate and Transfer RSA Public Key
    sd011 = """
    User              SystemController       EncryptionService       Database
      |                      |                        |                    |
      |----openMailbox()---->|                        |                    |
      |                      |-----generateRSA()----->|                    |
      |                      |                        |                    |
      |                      |<------rsaPubKey--------|                    |
      |                      |                        |                    |
      |                      |--------uploadPubKey()---------------------->|
      |                      |                        |                    |
      |                      |<-------status(stored)-----------------------|
      |                      |                        |                    |
      |<---mailboxReady()----|                        |                    |
"""
    add_sequence_page("SD011: Generate and Transfer RSA Public Key", sd011)

    # SD012: Manage User Profiles
    sd012 = """
    User              SystemController             Database
      |                      |                        |
      |----viewProfile()---->|                        |
      |                      |---fetchUserDetails()-->|
      |                      |                        |
      |                      |<-------userData--------|
      |                      |                        |
      |---updateProfile()--->|                        |
      |                      |-----saveChanges()----->|
      |                      |                        |
      |                      |<------updateOK---------|
      |                      |                        |
"""
    add_sequence_page("SD012: Manage User Profiles", sd012)

    # SD013: Biometric Authentication Gate (Enhancement)
    sd013 = """
    User              SystemController          BiometricModule        SecureStorage
      |                      |                        |                     |
      |--requestSensitive()->|                        |                     |
      |                      |---triggerBiometrics()->|                     |
      |                      |                        |                     |
      |---[Fingerprint/Face]-|                        |                     |
      |                      |                        |                     |
      |                      |<------authSuccess()----|                     |
      |                      |                        |                     |
      |                      |----accessKeyMaterial()---------------------->|
      |                      |                        |                     |
      |<---actionUnlocked()--|                        |                     |
"""
    add_sequence_page("SD013: Biometric Authentication Gate", sd013)

    # SD014: Silent Guardian Session Kill-Switch (Enhancement)
    sd014 = """
    ReceiverSession       Firestore (DB)         SenderSession         Notification
      |                        |                      |                     |
      |---abortSession()------>|                      |                     |
      |                        |                      |                     |
      |                        |----notifyAbort()---->|                     |
      |                        |                      |                     |
      |                        |                      |---triggerWipe()---->|
      |                        |                      |                     |
      |                        |<---confirmCleanup----|                     |
      |                        |                      |                     |
      |                        |------------------------------------------->|
      |                        |                      |           [Push: Session Terminated]
"""
    add_sequence_page("SD014: Silent Guardian Session Kill-Switch", sd014)

    # SD015: Zero-Remanence RAM Wiping Protocol (Enhancement)
    sd015 = """
    SystemController       SecurityMixin          DartHeap (RAM)        NativeOS (GC)
      |                        |                      |                     |
      |---onDispose()--------->|                      |                     |
      |                        |                      |                     |
      |                        |---fillRange(0)------>|                     |
      |                        |                      |                     |
      |                        |---clearRegistry()--->|                     |
      |                        |                      |                     |
      |                        |---requestNativeGC()----------------------->|
      |                        |                      |                     |
      |<---memoryCleaned()-----|                      |                     |
"""
    add_sequence_page("SD015: Zero-Remanence RAM Wiping Protocol", sd015)

    # Save
    filename = "CrypTransfer_Enhanced_Sequence_Diagrams_v3.docx"
    doc.save(filename)
    print(f"Success! {filename} generated.")

if __name__ == "__main__":
    create_sequence_diagrams()
