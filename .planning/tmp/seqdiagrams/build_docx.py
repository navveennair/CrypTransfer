# -*- coding: utf-8 -*-
import docx
from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
from docx.oxml import OxmlElement
import os

BASE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(r"C:\Users\navve\projects\cryptransfer", "CrypTransfer_Sequence_Diagrams_v4.docx")

DIAGRAMS = [
    ("SD001", "Login Account",
     "Username/email + password sign-in via FirebaseAuth, with a Google Sign-In alternative path "
     "and first-time-user onboarding branch."),
    ("SD002", "Register Account",
     "New account creation: username uniqueness check, FirebaseAuth user creation, and an atomic "
     "WriteBatch creating the user profile + preferences documents."),
    ("SD003", "Choose File",
     "Sender picks a file via file_picker after a pre-flight wipe of any previously held sensitive "
     "buffers (SecurityLifecycleMixin)."),
    ("SD004", "Generate AES Key",
     "AES-256 key and 96-bit GCM IV generation via PointyCastle FortunaRandom, invoked as part of "
     "encryptAesGcm()."),
    ("SD005", "Encrypt File",
     "Full sender-side encryption pipeline: FLAG_SECURE pre-flight check, 64 KB chunked file read "
     "via TransferService, AES-GCM encryption in a compute() isolate, and eager zero-wipe of the "
     "plaintext buffer."),
    ("SD006", "Generate RSA Key (Vault)",
     "Biometric-gated RSA-2048 key vault: keypair generation in a compute() isolate, secure storage "
     "of the private key, and an atomic WriteBatch updating the public key plus key-manager audit "
     "trail. Includes the separate Delete Keys flow."),
    ("SD007", "Transfer File",
     "Sender encrypts the AES key with the receiver's RSA public key (with a TOFU freshness "
     "re-check and biometric gate), then uploads the ciphertext to Firebase Storage and writes the "
     "transfer descriptor document to Firestore with progress streaming."),
    ("SD008", "Receive File",
     "Receiver-side reactive detection of an incoming transfer via a Firestore stream, automatic "
     "session locking, and navigation through the connection-establishing screen into the decrypt "
     "screen."),
    ("SD009", "Decrypt File",
     "Receiver downloads the ciphertext, unwraps the AES key with its RSA private key, performs "
     "AES-GCM decryption in a compute() isolate, writes the plaintext to a temp file, and runs a "
     "120-second watchdog for connection-loss handling."),
    ("SD010", "Cleanup Temporary Memory",
     "Two-part zero-remanence cleanup: (A) the 'Save & Suicide' pattern that saves the file then "
     "wipes RAM/temp files, and (B) the synchronized four-turn session-end protocol between "
     "receiver and sender that deletes Firestore/Storage artifacts in a strict security order."),
    ("SD011", "Generate and Transfer RSA Public Key (Mailbox Setup)",
     "Receiver opens its 'mailbox' (RSA keypair generation + publish to Firestore), the receiver "
     "explicitly authorizes a sender via an atomic handshake WriteBatch, the sender reactively "
     "detects the handshake with TOFU verification, and the mailbox-close kill-switch path."),
    ("SD012", "Manage User Profiles",
     "No dedicated profile-management feature exists in the current codebase. The closest "
     "implemented flow is Settings -> Appearance -> Theme, shown here, alongside a note on the "
     "profile-adjacent Firestore fields that currently have no edit UI."),
    ("SD013", "Biometric Authentication Gate",
     "There is no app-launch biometric gate. BiometricHelper.authenticate() is invoked at three "
     "distinct points: RSA Key Vault entry (twice, defense in depth) and AES-key encryption before "
     "sending a file."),
    ("SD014", "Silent Guardian Session Kill-Switch",
     "Reactive kill-switch: any of (app backgrounded/killed, back navigation, manual mailbox close) "
     "drives SessionManager into the 'terminated' state, which EncryptionService.bindSession() "
     "picks up to atomically wipe Firestore key material, secure storage, handshakes and "
     "notifications, and write a security audit log."),
    ("SD015", "Zero-Remanence RAM Wiping Protocol",
     "The SecurityLifecycleMixin buffer registry: registration of sensitive Uint8List buffers, the "
     "wipeAll() zero-fill sweep triggered from multiple lifecycle points, native FLAG_SECURE "
     "pre-flight checks, and the documented compute()-isolate remanence limitation."),
]

BLACK = RGBColor(0x00, 0x00, 0x00)


def set_cell_shading(cell, fill):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement('w:shd')
    shd.set(qn('w:fill'), fill)
    tcPr.append(shd)


def set_cell_borders(cell):
    tcPr = cell._tc.get_or_add_tcPr()
    borders = OxmlElement('w:tcBorders')
    for edge in ('top', 'left', 'bottom', 'right'):
        el = OxmlElement(f'w:{edge}')
        el.set(qn('w:val'), 'single')
        el.set(qn('w:sz'), '4')
        el.set(qn('w:space'), '0')
        el.set(qn('w:color'), '000000')
        borders.append(el)
    tcPr.append(borders)


def add_heading_bw(doc, text, level=1):
    h = doc.add_heading(text, level=level)
    for run in h.runs:
        run.font.color.rgb = BLACK
    return h


doc = Document()

# Document-wide default font
style = doc.styles['Normal']
style.font.name = 'Segoe UI'
style.font.size = Pt(10.5)
style.font.color.rgb = BLACK

title = doc.add_heading('CrypTransfer', level=0)
for run in title.runs:
    run.font.color.rgb = BLACK

sub = doc.add_paragraph('Enhanced Sequence Diagrams (v4)')
sub.alignment = WD_ALIGN_PARAGRAPH.CENTER
sub.runs[0].font.size = Pt(16)
sub.runs[0].font.color.rgb = BLACK

note = doc.add_paragraph(
    'This revision redraws SD001-SD015 as UML sequence diagrams generated from the current '
    'CrypTransfer codebase (verified against lib/data, lib/presentation and lib/core sources). '
    'All diagrams are rendered in black and white only.'
)
note.runs[0].italic = True
note.runs[0].font.color.rgb = BLACK

doc.add_page_break()

for sd_id, title_text, desc in DIAGRAMS:
    add_heading_bw(doc, f'{sd_id}: {title_text}', level=1)

    # Description / metadata table (2 columns, black & white)
    table = doc.add_table(rows=2, cols=2)
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = True

    cells = [
        ('Diagram ID', sd_id),
        ('Description', desc),
    ]
    for i, (label, value) in enumerate(cells):
        c0, c1 = table.rows[i].cells
        c0.text = label
        c1.text = value
        for cell in (c0, c1):
            set_cell_borders(cell)
            for p in cell.paragraphs:
                for r in p.runs:
                    r.font.color.rgb = BLACK
        set_cell_shading(c0, 'F2F2F2')
        set_cell_shading(c1, 'FFFFFF')
        c0.paragraphs[0].runs[0].bold = True
        c0.width = Inches(1.4)
        c1.width = Inches(5.6)

    doc.add_paragraph()

    # Diagram image
    img_path = os.path.join(BASE, f'{sd_id}.png')
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run()
    run.add_picture(img_path, width=Inches(6.8))

    if sd_id != 'SD015':
        doc.add_page_break()

doc.save(OUT)
print('Saved to', OUT)
