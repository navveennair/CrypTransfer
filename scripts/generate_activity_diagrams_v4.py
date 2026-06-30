import docx
from docx.shared import Inches, Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH


def create_v4_corrections():
    doc = docx.Document()

    sections = doc.sections
    for section in sections:
        section.top_margin = Inches(0.5)
        section.bottom_margin = Inches(0.5)
        section.left_margin = Inches(0.5)
        section.right_margin = Inches(0.5)

    def add_title(text, size=16, bold=True):
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        run = p.add_run(text)
        run.font.name = "Arial"
        run.font.size = Pt(size)
        run.font.bold = bold

    def add_note(text):
        p = doc.add_paragraph()
        run = p.add_run(text)
        run.font.name = "Arial"
        run.font.size = Pt(10)
        run.font.italic = True

    def add_swimlane_page(id_title, note, diag_art, page_break=True):
        add_title(id_title, size=14)
        doc.add_paragraph()

        add_note(note)
        doc.add_paragraph()

        p = doc.add_paragraph()
        run_d = p.add_run(diag_art)
        run_d.font.name = "Courier New"
        run_d.font.size = Pt(8)

        if page_break:
            doc.add_page_break()

    # Cover
    add_title("CrypTransfer — Enhanced Activity Diagrams (v4 Corrections)")
    doc.add_paragraph()
    add_note(
        "This document supersedes AD007, AD008, AD012 and AD014 from "
        "CrypTransfer_Enhanced_Activity_Diagrams_v3.docx. All other diagrams "
        "(AD001-AD006, AD009-AD011, AD013, AD015) were verified against the "
        "codebase and remain unchanged in v3 — see the v3 document for those."
    )
    doc.add_page_break()

    # ── AD007: Transfer File (Receiver-Authorized Handshake) ──────────────
    ad007 = """
+---------------------------------------+-----------------------------------------------+
|                 Sender                 |              System / Firestore                |
+---------------------------------------+-----------------------------------------------+
|                                         |                    (Start)                     |
|         [Wait for Connection] <------------------------ [Listen: streamHandshakesFor-]   |
|         (pulsing animation)            |             [Sender(senderId == me)]            |
|                                         |                       ^                         |
|                                         |                       |                         |
|                                         |       (Receiver selects this Sender via         |
|                                         |        selectSenderHandshake() — atomic         |
|                                         |        WriteBatch: handshakes doc +             |
|                                         |        users/{receiver}.selectedSenderUid)      |
|                                         |                       |                         |
|         [Handshake Detected] <------------------------ [status: handshake_complete]      |
|                  |                      |                       |                         |
|                  v                      |                                                  |
|         [Encrypt File (AES-CBC,         |                                                  |
|          compute() isolate)]            |                                                  |
|                  |                      |                                                  |
|                  v                      |                                                  |
|         [Encrypt AES Key with           |                                                  |
|          Receiver's RSA Public Key      |                                                  |
|          (RSA-OAEP, compute())]         |                                                  |
|                  |                      |                                                  |
|                  v                      |                                                  |
|         [Upload Ciphertext] ------------------------------> [Write transfers/{id} doc]    |
|                                         |                    [ (IV, encryptedAESKey,       |
|                                         |                       receiverId, senderId,      |
|                                         |                       status: pending) ]         |
|                                         |                       |                          |
|         [Monitor Progress /             |                       v                          |
|          receiverStatus stream] <------------------------ [Receiver notified              |
|                                         |                    via Firestore stream]          |
|                                         |                     (End)                        |
+---------------------------------------+-----------------------------------------------+
"""
    add_swimlane_page(
        "AD007 (v4): Transfer File — Receiver-Authorized Handshake",
        "Corrected: v3 began with the Sender selecting a recipient from a list. "
        "Per the Receiver-Authorized Handshake refactor (CLAUDE.md), the Sender "
        "instead waits in a pulsing '_WaitingForConnectionWidget' until the "
        "Receiver explicitly selects them via KeyRepository.selectSenderHandshake() "
        "(atomic WriteBatch). Only then does encryption and upload begin.",
        ad007,
    )

    # ── AD008: Receive File (Reactive Auto-Navigation) ─────────────────────
    ad008 = """
+---------------------------------------+-----------------------------------------------+
|                Receiver                |              System / Firestore                |
+---------------------------------------+-----------------------------------------------+
|                                         |                    (Start)                     |
|         [Mailbox Open]                 |                                                 |
|         (isReadyToReceive = true)      |                                                 |
|                                         |                                                 |
|                                         |       (Sender uploads ciphertext + writes      |
|                                         |        transfers/{id} doc with                 |
|                                         |        receiverId == me, status: pending)      |
|                                         |                       |                         |
|         [_handleIncomingTransfer] <----------------------------+                         |
|         (StreamBuilder — automatic,    |                                                 |
|          NO user "Accept" action)      |                                                 |
|                  |                      |                                                 |
|                  v                      |                                                 |
|         [SessionManager                |                                                 |
|          .setDecrypting()] ------------------------------> [SessionState: locked ->     |
|                                         |                    decrypting]                  |
|                  |                      |                                                 |
|                  v                      |                                                 |
|         [Auto-navigate to              |                                                 |
|          ReceiverTransferScreen]       |                                                 |
|         (reactive push, no tap)        |                                                 |
|                  |                      |                                                 |
|                  v                      |                                                 |
|         [Download Ciphertext] <---------------------------------+                        |
|                  |                      |                                                 |
|                  v                      |                                                 |
|         [Prepare Decrypt /              |                                                 |
|          set receiverStatus]            |                                                 |
|                                         |                     (End)                       |
+---------------------------------------+-----------------------------------------------+
"""
    add_swimlane_page(
        "AD008 (v4): Receive File — Reactive Auto-Navigation",
        "Corrected: v3 included a manual [Accept Request] step between "
        "notification and download. Per the Active Session State refactor, this "
        "is now fully automatic: _handleIncomingTransfer() calls "
        "SessionManager.setDecrypting(), which reactively navigates the Receiver "
        "to ReceiverTransferScreen with no user interaction.",
        ad008,
    )

    # ── AD012: Manage RSA Key Vault (Biometric-Gated) ──────────────────────
    ad012 = """
+---------------------------------------+-----------------------------------------------+
|                  User                  |              System / Firestore                |
+---------------------------------------+-----------------------------------------------+
|                                         |                    (Start)                     |
|         [Open RSA Key Vault] ---------------------------> [BiometricHelper             |
|                                         |                   .authenticate()]              |
|                                         |                       |                         |
|                                         |                _______v_______                  |
|                                         |               /  Biometrics   \\                 |
|                                         |              /   Enrolled?     \\                |
|         [Deny / Retry] <---------- (Fail) ---------- \\_________________/ -- (Pass or    |
|                                         |                                  none enrolled   |
|                                         |                                  -> auto-pass)   |
|                                         |                                       |          |
|                                         |                                       v          |
|         [View Key Status] <------------------------------ [StreamBuilder:               |
|         (fingerprint, created date)    |                    users/{uid}.publicKey,        |
|                                         |                    keyVaultCreatedAt]            |
|                  |                      |                                                  |
|         [Regenerate Key] --------------------------------> [compute(): generate          |
|                                         |                    RSA keypair]                  |
|                                         |                       |                          |
|                                         |                       v                          |
|                                         |               [3-doc WriteBatch:                |
|                                         |                publicKey update +                |
|                                         |                rsa_key_manager audit +           |
|                                         |                keyVaultCreatedAt]                |
|                                         |                                                  |
|         [Delete Key] -------------------------------------> [2-doc WriteBatch:           |
|                                         |                    publicKey FieldValue.delete   |
|                                         |                    + audit log (action=deleted)] |
|                                         |                       |                          |
|                                         |                       v                          |
|                                         |               [Wipe Private Key from            |
|                                         |                FlutterSecureStorage              |
|                                         |                (after batch.commit() succeeds)]  |
|                                         |                     (End)                       |
+---------------------------------------+-----------------------------------------------+

NOTE: A general "edit profile details" screen (username/email/etc.) is not
implemented anywhere in lib/presentation/. UserModel.toMap() exists but no UI
calls it from an edit flow. The only profile-management surface that exists
is the biometric-gated RSA Key Manager (RsaKeyManagerScreen), depicted above.
"""
    add_swimlane_page(
        "AD012 (v4): Manage RSA Key Vault (Biometric-Gated)",
        "Corrected: v3 depicted a generic 'Manage User Profiles' edit flow "
        "(Edit Details -> Save Changes -> Update DB) that does not exist in the "
        "codebase. Replaced with the actual implemented profile-management "
        "surface: the biometric-gated RSA Key Vault "
        "(RsaKeyManagerScreen / AuthRepository.regenerateKeyPair / "
        "deleteKeyPair), including the 'no biometrics enrolled -> auto-pass' "
        "fallback in BiometricHelper.authenticate().",
        ad012,
    )

    # ── AD014: Reactive Session Kill-Switch (Closed Mailbox) ───────────────
    ad014 = """
+---------------------------------------+-----------------------------------------------+
|                Receiver                |              System / SessionManager           |
+---------------------------------------+-----------------------------------------------+
|                                         |                    (Start)                     |
|         [Trigger Close]                |                                                 |
|         (toggle off / back-nav /       |                                                 |
|          app backgrounded or killed)   |                                                 |
|                  |                      |                                                 |
|                  v                      |                                                 |
|         [SessionManager                |                                                 |
|          .wipeSession() /              |                                                 |
|          .handleLifecycleState()] ------------------------> [stateStream emits           |
|                                         |                    SessionState.terminated]     |
|                                         |                       |                         |
|                                         |                       v                         |
|                                         |               [EncryptionService               |
|                                         |                .bindSession() listener         |
|                                         |                 fires automatically]            |
|                                         |                       |                         |
|                                         |                       v                         |
|                                         |               [closeReceiverSession()]:        |
|                                         |                 1. Delete publicKey,            |
|                                         |                    isReadyToReceive=false        |
|                                         |                    (Firestore)                  |
|                                         |                 2. Wipe RSA private key          |
|                                         |                    (FlutterSecureStorage)        |
|                                         |                 3. Batch-delete handshakes       |
|                                         |                    (receiverId == me)           |
|                                         |                 4. Batch-delete notifications    |
|                                         |                    (rsa_key_received)           |
|                                         |                 5. Write audit log               |
|                                         |                    (status: kill_switch)         |
|                                         |                 6. requestNativeClear()          |
|                                         |                    (MethodChannel -> System.gc)  |
|                                         |                       |                         |
|                                         |                       v                         |
|         [SecurityLifecycleMixin        |                                                 |
|          .wipeAll()] <------------------------------------ [onBuffersWipe callback]      |
|         (zero every registered          |                                                 |
|          Uint8List buffer)             |                                                 |
|                  |                      |                                                 |
|                  v                      |                                                 |
|         [Sender's stream sees           |                                                 |
|          handshake deleted ->           |                                                 |
|          reverts to waiting state]      |                                                 |
|                                         |                     (End)                       |
+---------------------------------------+-----------------------------------------------+
"""
    add_swimlane_page(
        "AD014 (v4): Reactive Session Kill-Switch (Closed Mailbox)",
        "Corrected and renamed from 'Silent Guardian Session Kill-Switch'. In "
        "this codebase, 'Silent Guardian' refers exclusively to "
        "scripts/silent_guardian.ps1 (a headless static-analysis security "
        "scanner) — it is unrelated to session termination. The actual "
        "reactive kill-switch chain is "
        "SessionManager.stateStream -> EncryptionService.bindSession() -> "
        "closeReceiverSession() (the 'Closed Mailbox' rule), shown above. The "
        "v3 'Update Firestore -> Listen for Remote Kill -> Auto-Wipe -> Partner "
        "Notified' flow was conceptually close but did not name the real "
        "components or the 6-step closeReceiverSession() sequence.",
        ad014,
        page_break=False,
    )

    filename = "CrypTransfer_Enhanced_Activity_Diagrams_v4_corrections.docx"
    doc.save(filename)
    print(f"Success! {filename} generated.")


if __name__ == "__main__":
    create_v4_corrections()
