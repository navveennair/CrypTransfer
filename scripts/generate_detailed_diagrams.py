import docx
from docx.shared import Inches, Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH

def create_detailed_diagrams():
    doc = docx.Document()
    
    # Page Setup
    sections = doc.sections
    for section in sections:
        section.top_margin = Inches(0.5)
        section.bottom_margin = Inches(0.5)
        section.left_margin = Inches(0.5)
        section.right_margin = Inches(0.5)

    def add_diagram_page(title, diagram_text):
        # Title
        t = doc.add_paragraph()
        t.alignment = WD_ALIGN_PARAGRAPH.CENTER
        run = t.add_run(title)
        run.font.name = 'Arial'
        run.font.size = Pt(16)
        run.font.bold = True
        
        doc.add_paragraph("\n")
        
        # Diagram
        p = doc.add_paragraph()
        run_d = p.add_run(diagram_text)
        run_d.font.name = 'Courier New'
        run_d.font.size = Pt(9.5)
        
        # Page Break for next
        doc.add_page_break()

    # 1. Login Account
    login_diag = """
       [START: User Opens App]
                  |
                  v
       +--------------------------+
       |   Check Auth State       |
       +----------+---------------+
                  |
         _________v_________
        /                   \\
       |   Is User Logged In?|
        \\___________________/
           |           |
      (No) |           | (Yes)
           v           v
    +--------------+  +------------------------+
    | Show Login   |  | Load User Profile      |
    | / Register   |  +-----------+------------+
    +------+-------+              |
           |                      v
           v           +------------------------+
    +--------------+  | Initialize Repositories|
    | Authenticate |  +-----------+------------+
    | via Firebase |              |
    +------+-------+              v
           |           +------------------------+
           |           | Navigate to HomeScreen |
           +---------->+------------------------+
                                  |
                                  v
                                [END]
"""
    add_diagram_page("Activity Diagram: Account Authentication (Login)", login_diag)

    # 2. Generate and Transfer RSA Public Key
    rsa_diag = """
       [START: Open Mailbox]
                  |
                  v
       +--------------------------+
       | Check Secure Storage for |
       | Existing RSA Key Pair    |
       +----------+---------------+
                  |
         _________v_________
        /                   \\
       |  Does Key Exist?    |
        \\___________________/
           |           |
      (No) |           | (Yes)
           v           v
    +--------------+  +------------------------+
    | Spawn Isolate|  | Retrieve Public Key    |
    | Generate RSA |  | from Local Storage     |
    | 2048-bit Pair|  +-----------+------------+
    +------+-------+              |
           |                      |
           v                      |
    +--------------+              |
    | Save Private |              |
    | to Secure S. |              |
    +------+-------+              |
           |                      |
           +----------------------+
                  |
                  v
       +--------------------------+
       | Upload Public Key to     |
       | Firestore (users/{uid})  |
       +----------+---------------+
                  |
                  v
       +--------------------------+
       | Set 'receiverReady' flag |
       | in Handshake Document    |
       +----------+---------------+
                  |
                  v
                [END]
"""
    add_diagram_page("Activity Diagram: RSA Key Generation & Transfer", rsa_diag)

    # 3. Encrypt File
    encrypt_diag = """
       [START: File Selected]
                  |
                  v
       +--------------------------+
       | Register Buffers in      |
       | SecurityLifecycleMixin   |
       +----------+---------------+
                  |
                  v
       +--------------------------+
       | Generate Random 256-bit  |
       | AES Key and 96-bit IV    |
       +----------+---------------+
                  |
                  v
       +--------------------------+
       | Spawn Crypto Isolate     |
       +----------+---------------+
                  |
                  v
       +--------------------------+
       | Encrypt File in Chunks   |
       | using AES-256-GCM        |
       +----------+---------------+
                  |
                  v
       +--------------------------+
       | Zero-Wipe Plaintext      |
       | Buffer in RAM            |
       +----------+---------------+
                  |
                  v
       +--------------------------+
       | RSA-OAEP Encrypt AES Key |
       | with Receiver's PubKey   |
       +----------+---------------+
                  |
                  v
                [END]
"""
    add_diagram_page("Activity Diagram: Secure File Encryption", encrypt_diag)

    # 4. Transfer File
    transfer_diag = """
       [START: Payload Ready]
                  |
                  v
       +--------------------------+
       | Upload Ciphertext to     |
       | Firebase Cloud Storage   |
       +----------+---------------+
                  |
                  v
       +--------------------------+
       | Get Storage Download URL |
       +----------+---------------+
                  |
                  v
       +--------------------------+
       | Atomic Write to Firestore|
       | Collection 'transfers'   |
       +----------+---------------+
                  |
                  v
       +--------------------------+
       | Send Push Notification   |
       | to Receiver (ID/Token)   |
       +----------+---------------+
                  |
                  v
       +--------------------------+
       | Listen for Status Change |
       | (pending -> received)    |
       +----------+---------------+
                  |
                  v
                [END]
"""
    add_diagram_page("Activity Diagram: File Transfer (Upload & Signal)", transfer_diag)

    # 5. Receive File
    receive_diag = """
       [START: Notification Received]
                  |
                  v
       +--------------------------+
       | Stream Transfer Metadata |
       | from Firestore           |
       +----------+---------------+
                  |
                  v
       +--------------------------+
       | Download Ciphertext from |
       | Firebase Storage         |
       +----------+---------------+
                  |
                  v
       +--------------------------+
       | Retrieve RSA Private Key |
       | from Secure Storage      |
       +----------+---------------+
                  |
                  v
       +--------------------------+
       | Isolate: Decrypt AES Key |
       | with RSA-OAEP            |
       +----------+---------------+
                  |
                  v
       +--------------------------+
       | Isolate: Decrypt File    |
       | with AES-GCM             |
       +----------+---------------+
                  |
                  v
                [END]
"""
    add_diagram_page("Activity Diagram: Secure File Reception", receive_diag)

    # 6. Cleanup Temporary Memory
    cleanup_diag = """
       [START: Transfer Finished]
                  |
                  v
       +--------------------------+
       | Call SecurityMixin.wipe()|
       +----------+---------------+
                  |
                  v
       +--------------------------+
       | fillRange(0) on all      |
       | Registered Uint8Lists    |
       +----------+---------------+
                  |
                  v
       +--------------------------+
       | Clear Internal Buffer    |
       | Reference List           |
       +----------+---------------+
                  |
                  v
       +--------------------------+
       | Signal Native GC Hint    |
       | via MethodChannel        |
       +----------+---------------+
                  |
                  v
       +--------------------------+
       | Update Firestore Status  |
       | to 'cleanup_initiated'   |
       +----------+---------------+
                  |
                  v
                [END]
"""
    add_diagram_page("Activity Diagram: Zero-Remanence Memory Cleanup", cleanup_diag)

    # Save
    filename = "CrypTransfer_Detailed_Activity_Diagrams.docx"
    doc.save(filename)
    print(f"Success! {filename} generated.")

if __name__ == "__main__":
    create_detailed_diagrams()
