import docx
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH

def create_flowchart_docx():
    doc = docx.Document()
    
    # Page Setup: Standard margins
    sections = doc.sections
    for section in sections:
        section.top_margin = Inches(1.0)
        section.bottom_margin = Inches(1.0)
        section.left_margin = Inches(1.0)
        section.right_margin = Inches(1.0)

    # Styles Setup
    style_normal = doc.styles['Normal']
    font = style_normal.font
    font.name = 'Courier New'  # Monospaced font ensures structural layout matches perfectly
    font.size = Pt(10.5)
    font.color.rgb = RGBColor(0, 0, 0)

    # Title
    title = doc.add_paragraph()
    title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run_title = title.add_run("CrypTransfer: Complete Operational Flowchart")
    run_title.font.name = 'Arial'
    run_title.font.size = Pt(16)
    run_title.font.bold = True
    
    # Subtitle
    subtitle = doc.add_paragraph()
    subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run_sub = subtitle.add_run("Cryptographic Key Lifecycle and Data Transfer Architecture")
    run_sub.font.name = 'Arial'
    run_sub.font.size = Pt(12)
    run_sub.font.italic = True
    
    doc.add_paragraph("\n") # Spacer

    # The Flowchart String
    flowchart_text = """======================================================================================
1. SETUP PHASE (One-time per user)
======================================================================================

  [ User Registers ]
          │
          ▼
  ┌────────────────────────────────────────────────────────┐
  │ Compute Isolate: Generate RSA-2048 Key Pair            │
  └───────────────────────┬────────────────────────────────┘
                          │
          ┌───────────────┴───────────────┐
          ▼                               ▼
┌───────────────────┐           ┌────────────────────────────────┐
│ Private Key       │           │ Public Key                     │
│ Saved locally to  │           │ Uploaded to Firestore          │
│ Secure Storage    │           │ (users/{uid}.publicKey)        │
└───────────────────┘           └────────────────────────────────┘


======================================================================================
2. CONNECTION & TOFU CHECK PHASE (Handshake & Identity Safeguard)
======================================================================================

  [ Receiver toggles "Open Mailbox" ]
          │
          ▼
  ┌────────────────────────────────────────────────────────┐
  │ setupReceiverSession() writes public key to            │
  │ rsa_key_transfers document                             │
  └───────────────────────┬────────────────────────────────┘
                          │
                          ▼
  [ Receiver searches for Sender & Taps "Send" ]
          │
          ▼
  ┌────────────────────────────────────────────────────────┐
  │ WriteBatch: Updates selectedSenderUid on receiver doc  │
  │ Sets status: 'handshake_complete' on key transfers doc │
  └───────────────────────┬────────────────────────────────┘
                          │
                          ▼
  [ Sender's streamHandshakesForSender() triggers ]
          │
          ▼
  ┌────────────────────────────────────────────────────────┐
  │ _checkTofuStatus(receiverUid, publicKey) executed      │
  └───────────────────────┬────────────────────────────────┘
                          │
                          ▼
             Is PIN found in Sender's 
              FlutterSecureStorage?
             /                      \
      (No)  /                        \  (Yes)
           /                          \
          ▼                            ▼
   [ firstContact ]              Does PIN match 
  ┌───────────────────────┐      stored fingerprint?
  │ Pin SHA-256 fingerprint│     /                  \
  │ into Secure Storage   │    / (Yes)               \ (No)
  └───────┬───────────────┘   /                       \
          │                  ▼                         ▼
          │           [ trusted/verified ]      [ keyChanged ]
          │          ┌───────────────────┐    ┌─────────────────────────────────┐
          │          │ Green/Amber banner│    │ Red Non-Dismissible Dialog      │
          │          │ Displayed         │    │ (Potential MITM / Key Changed)  │
          │          └───────┬───────────┘    └───────────────┬─────────────────┘
          │                  │                                │ User Choice?
          ▼                  │                                │
   ┌──────────────┐          │               ┌────────────────┴────────────────┐
   │ Amber Banner │          │               ▼                                 ▼
   │ displayed    │          │      [ Re-verify & Trust ]                  [ Cancel ]
   └──────┬───────┘          │    ┌──────────────────────┐           ┌──────────────────┐
          │                  │    │ Replace stored pin   │           │ _revertToWaiting()│
          │                  │    │ via repin()          │           │ State wiped.     │
          │                  │    └──────────┬───────────┘           │ Transfer BLOCKED │
          ▼                  ▼               ▼                       └──────────────────┘
    (Optional Out-of-Band Verification) ◄────┘
     • Sender taps "Verify" -> displays public key fingerprint
     • Receiver opens Key Vault -> displays local fingerprint
     • In-person/voice call check -> If matched, Sender marks "Verified" 
     • Banner switches to GREEN
          │
          ▼
  ┌────────────────────────────────────────────────────────┐
  │ Receiver sets receiverReady: true on rsa_key_transfers │
  ├────────────────────────────────────────────────────────┤
  │ Sender UI unlocks Steps 1-4 input elements             │
  └───────────────────────┬────────────────────────────────┘
                          │
                          ▼
                     (Next Section)

======================================================================================
3. ENCRYPTION & DATA TRANSFER PHASE (Sender Side)
======================================================================================

  [ Step 1: Sender selects file via FilePicker ]
          │
          ▼
  [ Step 2: _encryptFile() ]
  ┌────────────────────────────────────────────────────────┐
  │ • Read plaintext in 64 KB chunks                       │
  │ • Register buffer in Zero-Wipe memory safety net       │
  │ • Isolate: encryptAesGcm(plaintext) -> AES-256-GCM     │
  │ • Zero out memory: plaintext.fillRange(0)              │
  └───────────────────────┬────────────────────────────────┘
                          │
                          ▼
  [ Step 3: _encryptAesKey() ]
  ┌────────────────────────────────────────────────────────┐
  │ • Biometric Gate authentication prompt                 │
  │ • Isolate: RSA-OAEP encrypts AES Key with Receiver's   │
  │   Public Key                                           │
  └───────────────────────┬────────────────────────────────┘
                          │
                          ▼
  [ Step 4: _send() ]
  ┌────────────────────────────────────────────────────────┐
  │ • _wipeSensitiveData() zero-wipes AES Key and IV from  │
  │   the main isolate memory                              │
  │ • Routes UI to TransferProgressScreen                  │
  └───────────────────────┬────────────────────────────────┘
                          │
                          ▼
  ┌────────────────────────────────────────────────────────┐
  │ • Upload Ciphertext to Firebase Cloud Storage          │
  │ • Write payload metadata to Firestore transfers/ doc  │
  │   (Encrypted AES Key, IV, Receiver ID, status: pending)│
  └───────────────────────┬────────────────────────────────┘
                          │
                          ▼
                     (Next Section)

======================================================================================
4. DECRYPTION & SESSION TEARDOWN PHASE (Receiver Side & Cleanup)
======================================================================================

  [ Receiver detects transfer payload via Firestore stream ]
          │
          ▼
  ┌────────────────────────────────────────────────────────┐
  │ Auto-navigates to DecryptScreen & triggers             │
  │ _runDecryption()                                       │
  └───────────────────────┬────────────────────────────────┘
                          │
                          ▼
  ┌────────────────────────────────────────────────────────┐
  │ • Fetch RSA Private Key from local FlutterSecureStorage│
  │ • Isolate 1: Decrypt Encrypted AES Key (RSA-OAEP)      │
  │ • Isolate 2: Decrypt Ciphertext using restored AES Key  │
  └───────────────────────┬────────────────────────────────┘
                          │
                          ▼
  [ _saveAndWipe() ]
  ┌────────────────────────────────────────────────────────┐
  │ • Save plaintext file to local device storage          │
  │ • Zero out memory: AES Key, IV, and Plaintext buffers  │
  │ • Delete Public Key from Firestore                     │
  │ • WriteBatch: Wipes local rsa_key_transfers & state    │
  │ • Hint native Garbage Collection: NativeClear()        │
  └───────────────────────┬────────────────────────────────┘
                          │
                          ▼
  ┌────────────────────────────────────────────────────────┐
  │ Receiver sets cleanup_initiated: true on transfers doc │
  └───────────────────────┬────────────────────────────────┘
                          │
                          ▼
  ┌────────────────────────────────────────────────────────┐
  │ Sender perceives cleanup signal -> completely purges   │
  │ and zero-wipes structural bytes from local RAM         │
  └───────────────────────┬────────────────────────────────┘
                          │
                          ▼
  ┌────────────────────────────────────────────────────────┐
  │ Receiver deletes transfer document completely via      │
  │ WriteBatch connection close                            │
  └───────────────────────┬────────────────────────────────┘
                          │
                          ▼
  [ Both devices return safely to HomeScreen - No residual key data in RAM ]
"""

    # Add the text to the document paragraph by paragraph to ensure proper formatting
    p = doc.add_paragraph()
    p.paragraph_format.line_spacing = 1.05
    p.paragraph_format.space_after = Pt(0)
    
    run_flowchart = p.add_run(flowchart_text)
    run_flowchart.font.name = 'Courier New'
    run_flowchart.font.size = Pt(9.5)

    # Save Document
    filename = "CrypTransfer_Architecture_Flowchart.docx"
    doc.save(filename)
    print(f"Success! {filename} generated successfully.")

if __name__ == "__main__":
    create_flowchart_docx()