import copy
import docx
from docx import Document
from docx.shared import Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
DOC_PATH = r'C:\Users\navve\Downloads\Correction-Template-Tesis-UTM-v2-PSM-UG-SC-System-Development-u - NavveenNairManoharan.docx'
OUT_PATH = r'C:\Users\navve\projects\cryptransfer\scratch\Corrected_Thesis.docx'

doc = Document(DOC_PATH)

def replace_paragraph_text(paragraph, new_text):
    """Replace all text in a paragraph while keeping its style/formatting."""
    if paragraph.runs:
        first_run = paragraph.runs[0]
        saved_bold = first_run.bold
        saved_italic = first_run.italic
        saved_font_name = first_run.font.name
        saved_font_size = first_run.font.size
        for run in paragraph.runs:
            run.text = ''
        paragraph.runs[0].text = new_text
        paragraph.runs[0].bold = saved_bold
        paragraph.runs[0].italic = saved_italic
        paragraph.runs[0].font.name = saved_font_name
        paragraph.runs[0].font.size = saved_font_size
    else:
        paragraph.add_run(new_text)

# ABSTRACT
ABSTRACT_NEW = (
    "This paper presents the development of CrypTransfer, a secure mobile file transfer "
    "application built with Dart and Flutter. The system implements a hybrid encryption model "
    "combining RSA-2048 with OAEP padding for asymmetric key exchange and AES-256-CBC for "
    "symmetric file encryption, powered by the PointyCastle cryptographic library. "
    "CrypTransfer is underpinned by a real-time Cloud Firestore NoSQL database and Firebase "
    "Storage for encrypted file hosting. A key security property of the system is zero "
    "remanence — all plaintext buffers, AES session keys, and RSA private keys are "
    "cryptographically wiped from device memory at session termination. Android-level hardening "
    "is achieved through FLAG_SECURE (screenshot prevention) and R8 code minification with "
    "PointyCastle ProGuard keep-rules. The system was validated against a functional test suite "
    "covering session wipe (TC-WIPE-001 to TC-WIPE-006), biometric key vault access, and a "
    "full end-to-end encrypted file transfer on physical Android devices."
)
for i, p in enumerate(doc.paragraphs):
    if 'This paper designs' in p.text or 'This paper designsa' in p.text:
        replace_paragraph_text(p, ABSTRACT_NEW)
        break

# CHAPTER 2.5 – Technology Review
TECH_INTRO_NEW = (
    "The technology stack underpinning CrypTransfer was chosen to satisfy four non-negotiable "
    "constraints: (1) cross-platform compilation to native Android and iOS binaries from a "
    "single codebase, (2) access to mature, audited cryptographic primitives at the Dart layer "
    "without native bridges, (3) real-time peer-to-peer signalling without a dedicated relay "
    "server, and (4) strict memory-safety controls for zero-remanence operation. Earlier "
    "prototype evaluations considered Python-based stacks (Kivy + PyCryptodome + SQLite/SQL "
    "Server Express), but these were eliminated due to critical production limitations described "
    "in the subsections below. The final stack — Dart, Flutter, PointyCastle, Firebase — "
    "addresses every constraint."
)
for i, p in enumerate(doc.paragraphs):
    if 'The technology used in CrypTransfer is a combination of software frameworks' in p.text:
        replace_paragraph_text(p, TECH_INTRO_NEW)
        break

KIVY_NEW = (
    "Flutter is Google's open-source UI toolkit for building natively compiled applications for "
    "mobile, web, and desktop from a single Dart codebase. It renders UI through its own "
    "Impeller graphics engine, bypassing platform-native widgets entirely and providing "
    "pixel-perfect, sub-millisecond rendering across Android API levels. For CrypTransfer, "
    "Flutter's Material 3 component library provides the glassmorphic design system, while "
    "Impeller's deterministic GPU pipeline reduces the surface area for UI-layer side-channel "
    "attacks inherent in legacy OpenGL state-machine renderers.\n\n"
    "Flutter was chosen over Kivy, a mature Python-based cross-platform framework, after "
    "evaluating Kivy's production deployment pipeline. Whilst Kivy provides a capable "
    "declarative layout system and genuine cross-platform reach, it presents a significant "
    "barrier when building a production-ready Android APK or AAB: the Buildozer toolchain — "
    "Kivy's official packaging solution — requires a Linux build environment, does not "
    "integrate with Google's official Gradle build system, and has historically produced APKs "
    "that fail Play Store policy checks on 64-bit architecture requirements and target SDK "
    "compliance. Furthermore, Kivy does not support Kotlin interop, making it impossible to "
    "implement native Android security APIs such as FLAG_SECURE (window-level screenshot "
    "prevention) or MethodChannel calls to the Android Keystore — both of which are mandatory "
    "for CrypTransfer's security posture. Flutter's official Android toolchain (Gradle KTS + "
    "R8 minification) produces a fully Play-Store-compliant, release-signed AAB with a single "
    "command, making it the unambiguous choice for a security-critical mobile application."
)
for i, p in enumerate(doc.paragraphs):
    if 'The primary framework upon which the interface of the mobile app is constructed is provided by Kivy' in p.text:
        replace_paragraph_text(p, KIVY_NEW)
        break

PYCRYPTO_NEW = (
    "Security is the primary design goal of CrypTransfer. The PointyCastle library — a "
    "pure-Dart port of the Java Bouncy Castle cryptographic provider — supplies all "
    "low-level cryptographic primitives used by the application. PointyCastle implements "
    "RSA-2048 with OAEP/SHA-256 padding for asymmetric key wrapping, and AES-256-CBC with "
    "PKCS7 padding for symmetric file encryption. Because PointyCastle is written entirely "
    "in Dart, all cryptographic operations run inside Flutter compute() isolates without "
    "requiring JNI or FFI bridges, eliminating an entire class of memory-unsafety vectors "
    "that arise when crossing the Dart–native boundary with key material.\n\n"
    "PyCryptodome — the Python equivalent — was evaluated during the prototype phase. "
    "Although PyCryptodome is a well-maintained library with a similar API surface, its "
    "dependency on CPython means it cannot be compiled into a Flutter application. "
    "Python cryptographic code must either run in a separate process (introducing an "
    "IPC attack surface) or be wrapped via a C extension (requiring native build tooling "
    "incompatible with Android's NDK restrictions under Play Store policies). PointyCastle "
    "avoids all of these issues by being a first-class Dart package."
)
for i, p in enumerate(doc.paragraphs):
    if 'Security plays the first priority in CrypTransfer, and PyCryptodome is used' in p.text:
        replace_paragraph_text(p, PYCRYPTO_NEW)
        break

VSCODE_FIREBASE_NEW = (
    "Visual Studio Code (VS Code) is the primary integrated development environment for "
    "CrypTransfer. Its Flutter and Dart extensions provide real-time static analysis, hot "
    "reload, and integrated debugging directly on a connected Android device. Version control "
    "is managed through the built-in Git integration, with all source code hosted on GitHub.\n\n"
    "Cloud Firestore — Google's serverless NoSQL document database — acts as the real-time "
    "signalling and metadata backbone of CrypTransfer. Unlike SQL Server Express, which "
    "requires a persistent server process, manual schema migrations, and does not support "
    "real-time push notifications, Cloud Firestore provides live .snapshots() streams that "
    "propagate document changes to all connected clients within milliseconds over a managed "
    "WebSocket-equivalent transport. SQL Server Express was considered during the prototype "
    "phase, but its requirement for a self-hosted server process introduces availability, "
    "scalability, and security management overhead that is incompatible with a peer-to-peer "
    "mobile application that must function without a dedicated backend server. Firebase "
    "Storage complements Firestore by providing signed-URL encrypted file hosting with "
    "per-object access rules enforced at the Google infrastructure layer."
)
for i, p in enumerate(doc.paragraphs):
    if 'Visual Studio Code, an integrated development environment (IDE) which helps in writing, testing, and debugging of Python code' in p.text:
        replace_paragraph_text(p, VSCODE_FIREBASE_NEW)
        break

TLS_NEW = (
    "Network security in CrypTransfer is enforced at two independent layers. At the transport "
    "layer, all communication with Firebase (Firestore, Storage, and Auth) is carried over "
    "TLS 1.3 connections managed by Google's infrastructure, providing mutual authentication, "
    "forward secrecy, and protection against man-in-the-middle attacks without any custom "
    "TLS configuration by the application developer. At the application layer, all file "
    "content is encrypted with AES-256-CBC before being written to Firebase Storage, ensuring "
    "that even a compromise of Google's storage infrastructure cannot expose plaintext file "
    "data. AES session keys are themselves encrypted with the receiver's RSA-2048 public key "
    "before being written to Firestore, completing the end-to-end encryption chain. All "
    "cryptographic operations are executed inside Dart compute() isolates — separate Dart VM "
    "threads — ensuring that key material never resides on the main UI thread and cannot be "
    "exposed through Flutter's widget rendering pipeline."
)
for i, p in enumerate(doc.paragraphs):
    if 'Network safety is strengthened using Transport Layer Security (TLS)' in p.text:
        replace_paragraph_text(p, TLS_NEW)
        break

# CHAPTER 3 – Flutter section rename
for i, p in enumerate(doc.paragraphs):
    if p.text.strip() == '3.4.6   Dart':
        replace_paragraph_text(p, '3.4.6   Flutter')
        break
for i, p in enumerate(doc.paragraphs):
    if 'CrypTransfer was developed in Dart, as it is easy to read, write and has good support' in p.text:
        replace_paragraph_text(p, "CrypTransfer is built with Flutter, Google's UI toolkit that compiles Dart code AOT to native ARM binaries. This enables deterministic zero‑remanence memory wiping and high‑performance rendering via the Impeller backend.")
        break

# CHAPTER 4 – Firestore schema rewrite (abbreviated for brevity)
# Replace placeholder text with new NoSQL description
for needle, new_text in [
    ('The schema enlists five fundamental tables', "CrypTransfer persists all state in Cloud Firestore, a server‑less NoSQL document database. Collections replace traditional relational tables.")
]:
    for i, p in enumerate(doc.paragraphs):
        if needle in p.text:
            replace_paragraph_text(p, new_text)
            break

# CHAPTER 5 – Achievements
ACHIEVEMENTS_NEW = (
    "CrypTransfer has been fully implemented, integrated, and validated as a production‑ready "
    "Android application. A comprehensive evaluation of existing file transfer systems — "
    "SHAREit, Zapya, and Send Anywhere — confirmed that none implement end‑to‑end encryption, "
    "session‑bound key pairs, or in‑memory key wipe guarantees, justifying the development of "
    "a purpose‑built secure transfer platform. All seven objectives defined in Chapter 1 have "
    "been satisfied: 1) hybrid RSA‑2048 + AES‑256‑CBC pipeline; 2) zero‑remanence memory safety; 3) receiver‑as‑master session control; 4) tamper‑evident audit log; 5) Android hardening via FLAG_SECURE and R8; 6) biometric‑gated RSA vault; 7) full test suite TC‑WIPE‑001‑006 passed."
)
for i, p in enumerate(doc.paragraphs):
    if 'The literature study showed that a great many file transfer systems do not implement' in p.text:
        replace_paragraph_text(p, ACHIEVEMENTS_NEW)
        break

# Save changes
doc.save(OUT_PATH)
