import docx
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH

def create_diagrams_docx():
    doc = docx.Document()
    
    # Page Setup
    sections = doc.sections
    for section in sections:
        section.top_margin = Inches(0.5)
        section.bottom_margin = Inches(0.5)
        section.left_margin = Inches(0.5)
        section.right_margin = Inches(0.5)

    # Styles
    style_normal = doc.styles['Normal']
    font = style_normal.font
    font.name = 'Courier New'
    font.size = Pt(9)

    # Title
    title = doc.add_paragraph()
    title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run_title = title.add_run("CrypTransfer: Activity & Sequence Diagrams")
    run_title.font.name = 'Arial'
    run_title.font.size = Pt(18)
    run_title.font.bold = True

    doc.add_paragraph("\n")

    # --- ACTIVITY DIAGRAM ---
    doc.add_heading('1. Activity Diagram: Sender-Receiver Lifecycle', level=1)
    
    activity_diagram = """
[START]
  |
  v
+-----------------------+
| Receiver opens Mailbox|
+-----------+-----------+
            |
            v
+-----------------------+      +-----------------------+
| Generate RSA Key Pair | ---> | Store Private locally |
+-----------+-----------+      +-----------------------+
            |
            v
+-----------------------+
| Upload Public Key     |
+-----------+-----------+
            |
            v
+-----------------------+      +-----------------------+
| Wait for Sender       | <--- | Sender selects Partner|
+-----------+-----------+      +-----------+-----------+
            |                              |
            v                              v
+-----------------------+      +-----------------------+
| Detect Handshake      | <--- | Start Handshake       |
+-----------+-----------+      +-----------+-----------+
            |                              |
            v                              v
+-----------------------+      +-----------------------+
| Mark Ready            | ---> | Encrypt File (AES)    |
+-----------+-----------+      +-----------+-----------+
            |                              |
            v                              v
+-----------------------+      +-----------------------+
| Detect Transfer       | <--- | Encrypt AES Key (RSA) |
+-----------+-----------+      +-----------+-----------+
            |                              |
            v                              v
+-----------------------+      +-----------------------+
| Download & Decrypt    | <--- | Upload to Storage     |
+-----------+-----------+      +-----------+-----------+
            |
            v
+-----------------------+
| Zero-Wipe Buffers     |
+-----------+-----------+
            |
            v
+-----------------------+
| Initiate Cleanup      |
+-----------+-----------+
            |
            v
+-----------------------+
| [END]                 |
+-----------------------+
"""
    p1 = doc.add_paragraph()
    run1 = p1.add_run(activity_diagram)
    run1.font.name = 'Courier New'

    doc.add_page_break()

    # --- SEQUENCE DIAGRAM ---
    doc.add_heading('2. Sequence Diagram: Detailed Handshake & Transfer', level=1)
    
    sequence_diagram = """
Sender (S)             Firestore (DB)            Receiver (R)
    |                      |                        |
    |                      |---- 1. Open Mailbox -->|
    |                      |                        |
    |                      |<-- 2. PubKey Upload ---|
    |                      |                        |
    |--- 3. Select R ----->|                        |
    |                      |                        |
    |--- 4. Handshake ---->|                        |
    |                      |                        |
    |                      |--- 5. Detect Handshake>|
    |                      |                        |
    |                      |<-- 6. Mark Ready ------|
    |                      |                        |
    |<-- 7. Detect Ready --|                        |
    |                      |                        |
    |--- 8. Encrypt File ->|                        |
    |                      |                        |
    |--- 9. Encrypt Key -->|                        |
    |                      |                        |
    |--- 10. Upload ------>|                        |
    |                      |                        |
    |                      |--- 11. Detect Payload->|
    |                      |                        |
    |                      |<-- 12. Download -------|
    |                      |                        |
    |                      |--- 13. Decrypt (RSA)-->|
    |                      |                        |
    |                      |--- 14. Decrypt (AES)-->|
    |                      |                        |
    |                      |<-- 15. Cleanup Init ---|
    |                      |                        |
    |<-- 16. Detect Cleanup|                        |
    |                      |                        |
    |--- 17. Final Wipe -->|                        |
    |                      |                        |
    |                      |<-- 18. Delete Doc -----|
    |                      |                        |
    |                      |                        |
"""
    p2 = doc.add_paragraph()
    run2 = p2.add_run(sequence_diagram)
    run2.font.name = 'Courier New'

    # Save Document
    filename = "CrypTransfer_Architecture_Diagrams.docx"
    doc.save(filename)
    print(f"Success! {filename} generated.")

if __name__ == "__main__":
    create_diagrams_docx()
