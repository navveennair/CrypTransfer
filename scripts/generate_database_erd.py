import docx
from docx.shared import Inches, Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH

def create_database_erd_docx():
    doc = docx.Document()
    
    # Page Setup
    sections = doc.sections
    for section in sections:
        section.top_margin = Inches(0.5)
        section.bottom_margin = Inches(0.5)
        section.left_margin = Inches(0.5)
        section.right_margin = Inches(0.5)

    # Title
    t = doc.add_paragraph()
    t.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = t.add_run("CrypTransfer: Database Design (ERD)")
    run.font.name = 'Arial'
    run.font.size = Pt(18)
    run.font.bold = True
    
    doc.add_paragraph("\n")

    # The ERD ASCII Art
    erd_art = """
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
"""

    p = doc.add_paragraph()
    run_d = p.add_run(erd_art)
    run_d.font.name = 'Courier New'
    run_d.font.size = Pt(8.5)

    doc.add_page_break()

    # Data Dictionary / Entity Descriptions
    doc.add_heading('Data Entities & Relationships', level=1)
    
    entities = [
        ("User", "Stores core user credentials and roles. Initiates TransferSessions and generates RSA KeyPairs."),
        ("TransferSession", "The central transaction log. Links a sender, a receiver, a file, and the encryption keys used for a specific event."),
        ("File", "Contains metadata for the shared file. Every file is strictly associated with one TransferSession."),
        ("RSAKeys", "Stores the RSA-2048 keypair IDs. Used to wrap (encrypt) the session-specific AES key."),
        ("AESKey", "The symmetric key used for the actual file payload encryption. It is unique per file and per session.")
    ]

    for name, desc in entities:
        p = doc.add_paragraph(style='List Bullet')
        run = p.add_run(f"{name}: ")
        run.bold = True
        p.add_run(desc)

    # Save
    filename = "CrypTransfer_Database_Design_ERD.docx"
    doc.save(filename)
    print(f"Success! {filename} generated.")

if __name__ == "__main__":
    create_database_erd_docx()
