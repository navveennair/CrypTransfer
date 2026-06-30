import docx
from docx.shared import Inches, Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH

def create_swimlane_diagrams():
    doc = docx.Document()
    
    # Page Setup
    sections = doc.sections
    for section in sections:
        section.top_margin = Inches(0.5)
        section.bottom_margin = Inches(0.5)
        section.left_margin = Inches(0.5)
        section.right_margin = Inches(0.5)

    def add_swimlane_page(id_title, user_actions, system_actions, diag_art):
        # Title
        t = doc.add_paragraph()
        t.alignment = WD_ALIGN_PARAGRAPH.CENTER
        run = t.add_run(id_title)
        run.font.name = 'Arial'
        run.font.size = Pt(14)
        run.font.bold = True
        
        doc.add_paragraph("\n")
        
        # Diagram Container
        p = doc.add_paragraph()
        run_d = p.add_run(diag_art)
        run_d.font.name = 'Courier New'
        run_d.font.size = Pt(8.5)
        
        doc.add_page_break()

    # --- AD001: Login Account ---
    login_art = """
+---------------------------------------------------------------------------------------+
|                                  AD001 : Login Account                                |
+---------------------------------------+-----------------------------------------------+
|                 User                  |               System / Database               |
+---------------------------------------+-----------------------------------------------+
|                                       |                    (Start)                    |
|                                       |                       |                       |
|                                       |                       v                       |
|         [Enter credentials] <---------------------------------+                       |
|                  |                    |                                               |
|                  v                    |                                               |
|         [Click onto "login"] ----------------------------> [Validate]                 |
|                                       |                       |                       |
|                                       |                _______v_______                |
|                                       |               /               \\               |
|                                       |              |  isValid?       |              |
|                                       |               \\_______________/               |
|                                       |                /             \\                |
|                                       |          (No) /               \\ (Yes)         |
|                                       |              v                 v              |
|         [Show Error/Retry] <------------------ [Creds False]     [Creds Correct]      |
|                                       |                                |              |
|                                       |                                v              |
|                                       |                              (End)            |
+---------------------------------------+-----------------------------------------------+
"""
    add_swimlane_page("AD001: Login Account", "", "", login_art)

    # --- AD005: Encrypt File ---
    encrypt_art = """
+---------------------------------------------------------------------------------------+
|                                   AD005 : Encrypt File                                |
+---------------------------------------+-----------------------------------------------+
|                 User                  |                    System                     |
+---------------------------------------+-----------------------------------------------+
|                                       |                    (Start)                    |
|                                       |                       |                       |
|                                       |                       v                       |
|         [Select File] -----------------------------------> [Register]                 |
|                                       |                    [Buffers ]                 |
|                                       |                       |                       |
|                                       |                       v                       |
|                                       |                [Generate AES]                 |
|                                       |                [Key and IV  ]                 |
|                                       |                       |                       |
|                                       |                       v                       |
|                                       |                [Encrypt File]                 |
|                                       |                [ (AES-GCM)  ]                 |
|                                       |                       |                       |
|                                       |                       v                       |
|                                       |                [Wipe RAM    ]                 |
|                                       |                [Plaintext   ]                 |
|                                       |                       |                       |
|         [Biometric Auth] <------------------------------------+                       |
|                  |                    |                                               |
|                  v                    |                                               |
|         [Touch ID / Face ID] ----------------------------> [Validate ]                |
|                                       |                    [Biometrics]               |
|                                       |                       |                       |
|                                       |                       v                       |
|                                       |                [Encrypt Key ]                 |
|                                       |                [ (RSA-OAEP) ]                 |
|                                       |                       |                       |
|                                       |                       v                       |
|                                       |                     (End)                     |
+---------------------------------------+-----------------------------------------------+
"""
    add_swimlane_page("AD005: Encrypt File", "", "", encrypt_art)

    # --- AD007: Transfer File ---
    transfer_art = """
+---------------------------------------------------------------------------------------+
|                                  AD007 : Transfer File                                |
+---------------------------------------+-----------------------------------------------+
|                 User                  |                    System                     |
+---------------------------------------+-----------------------------------------------+
|                                       |                    (Start)                    |
|                                       |                       |                       |
|                                       |                       v                       |
|         [Select Recipient] ------------------------------> [Upload   ]                 |
|                                       |                    [Ciphertext]                 |
|                                       |                       |                       |
|                                       |                       v                       |
|                                       |                [Write Doc   ]                 |
|                                       |                [(Firestore) ]                 |
|                                       |                       |                       |
|                                       |                       v                       |
|                                       |                [Notify      ]                 |
|                                       |                [Receiver    ]                 |
|                                       |                       |                       |
|         [Monitor Progress] <------------------------------+                       |
|                  |                    |                       |                       |
|                  v                    |                       v                       |
|         [Complete View] <--------------------------------- [Listen   ]                 |
|                                       |                    [Status   ]                 |
|                                       |                       |                       |
|                                       |                       v                       |
|                                       |                     (End)                     |
+---------------------------------------+-----------------------------------------------+
"""
    add_swimlane_page("AD007: Transfer File", "", "", transfer_art)

    # --- AD008: Receive File ---
    receive_art = """
+---------------------------------------------------------------------------------------+
|                                  AD008 : Receive File                                 |
+---------------------------------------+-----------------------------------------------+
|                 User                  |                    System                     |
+---------------------------------------+-----------------------------------------------+
|                                       |                    (Start)                    |
|                                       |                       |                       |
|                                       |                       v                       |
|         [Receive Notif] <--------------------------------- [Stream    ]                 |
|                                       |                    [Metadata  ]                 |
|                                       |                       |                       |
|                                       |                       v                       |
|         [Accept Transfer] -------------------------------> [Download  ]                 |
|                                       |                    [Ciphertext]                 |
|                                       |                       |                       |
|                                       |                       v                       |
|                                       |                [Retrieve   ]                 |
|                                       |                [Private Key]                 |
|                                       |                       |                       |
|                                       |                       v                       |
|                                       |                [Decrypt Key]                 |
|                                       |                [(RSA-OAEP) ]                 |
|                                       |                       |                       |
|                                       |                       v                       |
|                                       |                [Decrypt File]                 |
|                                       |                [(AES-GCM)  ]                 |
|                                       |                       |                       |
|                                       |                       v                       |
|                                       |                     (End)                     |
+---------------------------------------+-----------------------------------------------+
"""
    add_swimlane_page("AD008: Receive File", "", "", receive_art)

    # --- AD010: Cleanup Temporary Memory ---
    cleanup_art = """
+---------------------------------------------------------------------------------------+
|                          AD010 : Cleanup Temporary Memory                             |
+---------------------------------------+-----------------------------------------------+
|                 User                  |                    System                     |
+---------------------------------------+-----------------------------------------------+
|                                       |                    (Start)                    |
|                                       |                       |                       |
|                                       |                       v                       |
|         [View File] <------------------------------------- [Decrypt  ]                 |
|                                       |                       |                       |
|                                       |                       v                       |
|         [Close Session] ---------------------------------> [Wipe All ]                 |
|                                       |                    [Buffers  ]                 |
|                                       |                       |                       |
|                                       |                       v                       |
|                                       |                [Zero Out   ]                 |
|                                       |                [Uint8Lists ]                 |
|                                       |                       |                       |
|                                       |                       v                       |
|                                       |                [Hint GC    ]                 |
|                                       |                [(Native)   ]                 |
|                                       |                       |                       |
|                                       |                       v                       |
|                                       |                [Update Stat]                 |
|                                       |                       |                       |
|                                       |                       v                       |
|                                       |                     (End)                     |
+---------------------------------------+-----------------------------------------------+
"""
    add_swimlane_page("AD010: Cleanup Temporary Memory", "", "", cleanup_art)

    # --- AD011: Generate and Transfer RSA Public Key ---
    rsa_art = """
+---------------------------------------------------------------------------------------+
|                  AD011 : Generate and Transfer RSA Public Key                         |
+---------------------------------------+-----------------------------------------------+
|                 User                  |                    System                     |
+---------------------------------------+-----------------------------------------------+
|                                       |                    (Start)                    |
|                                       |                       |                       |
|                                       |                       v                       |
|         [Open Mailbox] ----------------------------------> [Check     ]                 |
|                                       |                    [Storage   ]                 |
|                                       |                       |                       |
|         [Biometric Auth] <------------------------------------+                       |
|                  |                    |                                               |
|                  v                    |                                               |
|         [Touch ID / Face ID] ----------------------------> [Unlock    ]                 |
|                                       |                    [Vault     ]                 |
|                                       |                       |                       |
|                                       |                _______v_______                |
|                                       |               /               \\               |
|                                       |              |  Exists?        |              |
|                                       |               \\_______________/               |
|                                       |                /             \\                |
|                                       |          (No) /               \\ (Yes)         |
|                                       |              v                 v              |
|                                       |       [Generate Pair]      [Load Key]         |
|                                       |              |                 |              |
|                                       |              v                 |              |
|                                       |       [Save Private] <---------+              |
|                                       |              |                                |
|                                       |              v                                |
|                                       |       [Upload Public]                         |
|                                       |              |                                |
|                                       |              v                                |
|                                       |       [Set Ready    ]                         |
|                                       |              |                                |
|                                       |              v                                |
|                                       |            (End)                              |
+---------------------------------------+-----------------------------------------------+
"""
    add_swimlane_page("AD011: Generate and Transfer RSA Public Key", "", "", rsa_art)

    # Save
    filename = "CrypTransfer_Swimlane_Activity_Diagrams_v2.docx"
    doc.save(filename)
    print(f"Success! {filename} generated.")

if __name__ == "__main__":
    create_swimlane_diagrams()
