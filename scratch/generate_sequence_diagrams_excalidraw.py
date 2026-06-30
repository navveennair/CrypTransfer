"""
Generates an .excalidraw file containing all 15 CrypTransfer sequence diagrams
(SD001-SD015), updated to reflect the real Flutter+Firebase implementation
instead of the original thesis's Python+Kivy+SQL Server design.

Visual style matches cryptransfer_erd.excalidraw / cryptransfer_usecase_v2.excalidraw:
blue (#1971c2) rectangles/arrows, black (#1e1e1e) text, Helvetica body font,
hand-drawn title font, "Design notes" callouts explaining deviations.
"""
import json
import random

random.seed(42)
_counter = 0


def next_id():
    global _counter
    _counter += 1
    return f"sd{_counter:07d}"


def base(el_type, x, y, w, h, **overrides):
    el = {
        "id": next_id(),
        "type": el_type,
        "x": x,
        "y": y,
        "width": w,
        "height": h,
        "angle": 0,
        "strokeColor": "#1e1e1e",
        "backgroundColor": "transparent",
        "fillStyle": "solid",
        "strokeWidth": 2,
        "strokeStyle": "solid",
        "roughness": 1,
        "opacity": 100,
        "groupIds": [],
        "frameId": None,
        "roundness": None,
        "seed": random.randint(1, 2_000_000_000),
        "version": 1,
        "versionNonce": random.randint(1, 2_000_000_000),
        "isDeleted": False,
        "boundElements": None,
        "updated": 1782145952822,
        "link": None,
        "locked": False,
    }
    el.update(overrides)
    return el


def rect(x, y, w, h, stroke="#1971c2", bg="transparent", rounded=True):
    return base(
        "rectangle", x, y, w, h,
        strokeColor=stroke, backgroundColor=bg,
        roundness={"type": 3} if rounded else None,
    )


def text(x, y, s, fontSize=13, fontFamily=2, color="#1e1e1e", align="left"):
    lines = s.split("\n")
    width = max(50.0, max(len(line) for line in lines) * fontSize * 0.56)
    height = len(lines) * fontSize * 1.25
    return base(
        "text", x, y, width, height,
        strokeColor=color,
        text=s,
        fontSize=fontSize,
        fontFamily=fontFamily,
        textAlign=align,
        verticalAlign="top",
        baseline=fontSize,
        containerId=None,
        originalText=s,
        lineHeight=1.25,
    )


def vline(x, y, length, dashed=True, stroke="#1971c2"):
    return base(
        "line", x, y, 0, length,
        strokeColor=stroke,
        strokeStyle="dashed" if dashed else "solid",
        points=[[0, 0], [0, length]],
        lastCommittedPoint=None,
        startBinding=None,
        endBinding=None,
        startArrowhead=None,
        endArrowhead=None,
        roundness=None,
    )


def arrow(x1, y, x2, dashed=False, stroke="#1e1e1e"):
    dx = x2 - x1
    return base(
        "arrow", x1, y, abs(dx), 0,
        strokeColor=stroke,
        strokeStyle="dashed" if dashed else "solid",
        points=[[0, 0], [dx, 0]],
        lastCommittedPoint=None,
        startBinding=None,
        endBinding=None,
        startArrowhead=None,
        endArrowhead="triangle",
        roundness={"type": 2},
    )


def self_loop(x, y, stroke="#1e1e1e"):
    w, h = 46, 22
    return base(
        "arrow", x, y, w, h,
        strokeColor=stroke,
        points=[[0, 0], [w, 0], [w, h], [0, h]],
        lastCommittedPoint=None,
        startBinding=None,
        endBinding=None,
        startArrowhead=None,
        endArrowhead="triangle",
        roundness={"type": 2},
    )


LIFELINE_SPACING = 230
HEADER_W = 175
HEADER_H = 46
MSG_SPACING = 56
TITLE_BLOCK_H = 0


def build_diagram(sd_id, title, note, participants, messages):
    """All elements positioned relative to local origin (0,0). Returns (elements, width, height)."""
    els = []

    els.append(text(0, 0, f"{sd_id}: {title}", fontSize=18, fontFamily=1, color="#1971c2"))
    note_y = 26
    if note:
        els.append(text(0, note_y, f"Note: {note}", fontSize=12, fontFamily=2, color="#495057"))
        note_y += 18 * (note.count("\n") + 1) + 6

    top_y = note_y + 14
    lifeline_top = top_y + HEADER_H

    n_msgs = len(messages)
    lifeline_bottom = lifeline_top + 28 + n_msgs * MSG_SPACING + 20

    actor_cx = {}
    for i, name in enumerate(participants):
        bx = i * LIFELINE_SPACING
        cx = bx + HEADER_W / 2
        actor_cx[i] = cx
        els.append(rect(bx, top_y, HEADER_W, HEADER_H, stroke="#1971c2"))
        els.append(text(bx, top_y + (HEADER_H - 15) / 2, name, fontSize=13, fontFamily=2, align="center"))
        # re-anchor text x to actor center by adjusting width to header width
        els[-1]["x"] = bx
        els[-1]["width"] = HEADER_W
        els.append(vline(cx, lifeline_top, lifeline_bottom - lifeline_top, dashed=True))

    y = lifeline_top + 28
    for frm, to, label, kind in messages:
        if kind == "self":
            x = actor_cx[frm]
            els.append(self_loop(x, y))
            els.append(text(x + 52, y, label, fontSize=12, fontFamily=2))
        else:
            x1, x2 = actor_cx[frm], actor_cx[to]
            dashed = kind == "return"
            lo, hi = min(x1, x2), max(x1, x2)
            els.append(text(lo, y - 17, label, fontSize=12, fontFamily=2, align="center"))
            # center the label text within the arrow span
            els[-1]["x"] = lo
            els[-1]["width"] = max(hi - lo, 60)
            els.append(arrow(x1, y, x2, dashed=dashed))
        y += MSG_SPACING

    width = (len(participants) - 1) * LIFELINE_SPACING + HEADER_W
    height = lifeline_bottom
    return els, width, height


def translate(els, dx, dy):
    for el in els:
        el["x"] += dx
        el["y"] += dy


# ---------------------------------------------------------------------------
# Diagram data: (sd_id, title, note, participants, messages)
# messages: (from_idx, to_idx, label, kind)  kind in {sync, return, self}
# ---------------------------------------------------------------------------

DIAGRAMS = [
    ("SD001", "Login Account",
     "No central SystemController/Database - LoginScreen calls AuthRepository directly against FirebaseAuth + Firestore.",
     ["User", "LoginScreen", "AuthRepository", "FirebaseAuth", "Firestore\n(users)"],
     [
         (0, 1, "enterCredentials(username, pwd)", "sync"),
         (1, 2, "loginWithUsername(username, pwd)", "sync"),
         (2, 2, "_ensureAuthenticated() [anon pre-auth]", "self"),
         (2, 4, "where(username==...) -> email", "sync"),
         (4, 2, "email", "return"),
         (2, 3, "signInWithEmailAndPassword(email, pwd)", "sync"),
         (3, 2, "User (idToken)", "return"),
         (2, 1, "accessGranted()", "return"),
         (1, 0, "navigate to Home", "return"),
     ]),
    ("SD002", "Register Account",
     "Username-uniqueness check and account creation happen in one register() call; profile/preferences subcollection is seeded at registration time.",
     ["User", "RegisterScreen", "AuthRepository", "FirebaseAuth", "Firestore\n(users)"],
     [
         (0, 1, "submit(username, email, phone, pwd)", "sync"),
         (1, 2, "isUsernameTaken(username) [debounced]", "sync"),
         (2, 4, "query users.where(username)", "sync"),
         (4, 2, "exists: false", "return"),
         (1, 2, "register(username, email, phone, pwd)", "sync"),
         (2, 3, "createUserWithEmailAndPassword(email, pwd)", "sync"),
         (2, 4, "batch.set(users/{uid}, profile/preferences)", "sync"),
         (2, 1, "regSuccess()", "return"),
         (1, 0, "navigate to Home", "return"),
     ]),
    ("SD003", "Choose File",
     "Selected file lives only in SenderState.file (PlatformFile); nothing is persisted to Firestore at this step.",
     ["User", "SenderScreen", "SenderController", "FilePicker"],
     [
         (0, 1, "tapSelectFile()", "sync"),
         (1, 2, "pickFile()", "sync"),
         (2, 3, "pickFiles(withData: kIsWeb)", "sync"),
         (3, 2, "PlatformFile", "return"),
         (2, 2, "validateSize() [<= 100MB]", "self"),
         (2, 1, "state.copyWith(file)", "return"),
         (1, 0, "displaySelectedFile()", "return"),
     ]),
    ("SD004", "Generate AES Key",
     "Key generation is inlined inside encryptAesGcm() - there is no standalone keygen API as the thesis assumed.",
     ["SenderController", "EncryptionService"],
     [
         (0, 1, "encryptAesGcm(plaintext)", "sync"),
         (1, 1, "secureRandomBytes(32) -> key", "self"),
         (1, 1, "secureRandomBytes(12) -> iv", "self"),
         (1, 0, "key, iv (in AesEncryptResult)", "return"),
     ]),
    ("SD005", "Encrypt File",
     "AES-256-GCM runs inside a compute() isolate so it never blocks the UI thread; buffers are zeroed in a finally block.",
     ["SenderController", "EncryptionService", "Isolate\n(compute)"],
     [
         (0, 0, "readFileWithProgress() [0-70%]", "self"),
         (0, 1, "encryptAesGcm(plaintext)", "sync"),
         (1, 2, "runAesGcmEncrypt([plaintext,key,iv])", "sync"),
         (2, 2, "GCMBlockCipher.process() -> ciphertext+tag", "self"),
         (2, 1, "ciphertext (with GCM tag appended)", "return"),
         (1, 1, "fillRange(0) wipe plaintext/key/iv copies", "self"),
         (1, 0, "AesEncryptResult(ciphertext, key, iv)", "return"),
     ]),
    ("SD006", "Generate RSA Key",
     "Keypair generation runs in a compute() isolate; private key never leaves the device, public key is pushed straight to Firestore.",
     ["AuthRepository", "Isolate\n(compute)", "EncryptionService", "SecureStorage", "Firestore\n(users)"],
     [
         (0, 1, "compute(_generateKeyPairIsolate)", "sync"),
         (1, 2, "generateRsaKeyPairSync()", "sync"),
         (2, 2, "RSAKeyGenerator(2048, e=65537)", "self"),
         (2, 1, "RSAKeyPair", "return"),
         (1, 0, "RSAKeyPair", "return"),
         (0, 3, "write('rsa_private_key', encodedPrivate)", "sync"),
         (0, 4, "update(publicKey: encodedPublic)", "sync"),
     ]),
    ("SD007", "Transfer File",
     "Firebase Storage SDK handles chunking internally; the transfer doc stores the RSA-encrypted AES key, never the raw key.",
     ["SenderController", "TransferRepository", "Firebase\nStorage", "Firestore\n(transfers)", "Firestore\n(notifications)"],
     [
         (0, 1, "uploadAndCreate(encryptedBytes, encAESKey, iv)", "sync"),
         (1, 2, "putData(transfers/{id}/encrypted_file)", "sync"),
         (2, 1, "bytesTransferred (progress stream)", "return"),
         (2, 1, "downloadURL", "return"),
         (1, 3, "set(transfers/{id}: encAESKey, iv, url, pending)", "sync"),
         (1, 4, "add(users/{receiverId}/notifications: fileReceived)", "sync"),
         (1, 0, "transferId", "return"),
     ]),
    ("SD008", "Receive File",
     "Receiver never talks to the sender directly - the transfers/{id} document is the sole source of truth for key material and file URL.",
     ["ReceiverScreen", "TransferRepository", "Firestore\n(transfers)", "Firebase\nStorage"],
     [
         (0, 1, "getTransfer(transferId)", "sync"),
         (1, 2, "get(transfers/{id})", "sync"),
         (2, 1, "TransferModel(encAESKey, iv, url)", "return"),
         (1, 3, "getData(transfers/{id}/encrypted_file)", "sync"),
         (3, 1, "Uint8List encryptedBytes", "return"),
         (1, 2, "update(status: received, receivedAt)", "sync"),
         (1, 0, "encryptedBytes + TransferModel", "return"),
     ]),
    ("SD009", "Decrypt File",
     "Two-phase decrypt: RSA-OAEP unwraps the AES key first, then AES-GCM decrypts the file - both phases run in compute() isolates.",
     ["DecryptScreen", "AuthRepository\n(SecureStorage)", "EncryptionService", "Isolate\n(compute)"],
     [
         (0, 1, "getPrivateKeyJson()", "sync"),
         (1, 0, "rsa_private_key (JSON)", "return"),
         (0, 2, "decryptAesKeyWithPrivateKeyJson(priv, encAESKey)", "sync"),
         (2, 2, "rsaDecrypt() [OAEP]", "self"),
         (2, 0, "aesKey", "return"),
         (0, 2, "decryptAesGcm(ciphertext, aesKey, iv)", "sync"),
         (2, 3, "runAesGcmDecrypt([ciphertext,key,iv])", "sync"),
         (3, 2, "plaintext (GCM tag verified)", "return"),
         (2, 0, "plaintext", "return"),
         (0, 0, "registerBuffer(plaintext) + writeAsBytes()", "self"),
     ]),
    ("SD010", "Cleanup Temporary Memory",
     "Cleanup is a multi-turn protocol (initiate -> watch -> complete -> closeSession), not one atomic call as the thesis assumed.",
     ["ReceiverEndSessionScreen", "CleanupRepository", "KeyRepository", "EncryptionService", "Firestore", "SecureStorage"],
     [
         (0, 1, "initiateReceiverCleanup(transferId)", "sync"),
         (1, 4, "update(cleanup_initiated: true)", "sync"),
         (0, 1, "completeReceiverCleanup() [after sender confirms]", "sync"),
         (1, 4, "batch: audit_logs + delete transfers/{id}", "sync"),
         (0, 2, "endSessionCleanup(transferId, handshakeId)", "sync"),
         (2, 4, "batch.delete(handshakes/{id}) + clear selectedSenderUid", "sync"),
         (0, 3, "closeReceiverSession(uid)", "sync"),
         (3, 5, "delete('rsa_private_key')", "sync"),
         (3, 4, "delete publicKey + pending transfers/handshakes", "sync"),
     ]),
    ("SD011", "Generate and Transfer RSA Public Key",
     "Two independent layers: neutral_handshakes (connection request) is separate from handshakes (per-transfer RSA exchange), both Firestore-mediated.",
     ["ReceiverScreen", "HandshakeRepository", "Firestore\n(neutral_\nhandshakes)", "KeyRepository", "Firestore\n(handshakes)", "SenderScreen"],
     [
         (0, 1, "sendProposal(partnerUid) [connection layer]", "sync"),
         (1, 2, "set({proposerId, partnerId, status: pending})", "sync"),
         (5, 1, "acceptProposal(docId)", "sync"),
         (1, 2, "update(status: connected) + friendships", "sync"),
         (0, 3, "selectSenderHandshake(senderUid) [RSA layer]", "sync"),
         (3, 4, "set({publicKey, status: handshake_complete})", "sync"),
         (5, 3, "fetchHandshakePublicKey(receiverUid)", "sync"),
         (4, 3, "publicKey", "return"),
         (3, 5, "receiver's RSA public key", "return"),
     ]),
    ("SD012", "Manage User Profiles",
     "friendships subcollection (not a 'connections' table) is the source of truth for who a user is connected to.",
     ["User", "ProfileScreen", "AuthRepository /\nUserRepository", "Firestore\n(users)"],
     [
         (0, 1, "viewProfile()", "sync"),
         (1, 2, "streamUserProfile(uid)", "sync"),
         (3, 2, "UserModel snapshot", "return"),
         (2, 1, "userData", "return"),
         (0, 1, "updateProfile(fields)", "sync"),
         (1, 2, "updateUser(uid, fields)", "sync"),
         (2, 3, "update(fields)", "sync"),
         (2, 1, "updateOK", "return"),
     ]),
    ("SD013", "Biometric Authentication Gate",
     "Gate is integrated directly into SenderController.encryptAesKey(); falls back to device PIN/password when no biometric hardware exists.",
     ["User", "SenderController", "BiometricHelper", "LocalAuthentication"],
     [
         (0, 1, "requestSensitiveAction() [encryptAesKey]", "sync"),
         (1, 2, "authenticate(reason)", "sync"),
         (2, 3, "isDeviceSupported()", "sync"),
         (3, 2, "true/false", "return"),
         (2, 3, "authenticate(biometricOnly: false)", "sync"),
         (0, 3, "[Fingerprint / Face / PIN]", "sync"),
         (3, 2, "true", "return"),
         (2, 1, "authenticated", "return"),
         (1, 0, "proceed with RSA encryption", "return"),
     ]),
    ("SD014", "Silent Guardian Session Kill-Switch",
     "Trigger is local app-lifecycle only (paused/detached) - no remote push; sender detects the loss via the handshake-doc deletion stream.",
     ["ReceiverScreen", "SessionManager", "EncryptionService", "Firestore", "SecureStorage"],
     [
         (0, 1, "didChangeAppLifecycleState(paused/detached)", "sync"),
         (1, 1, "wipeSession()", "self"),
         (1, 1, "stateStream.emit(terminated)", "self"),
         (1, 2, "closeReceiverSession(uid)", "sync"),
         (2, 4, "delete('rsa_private_key')", "sync"),
         (2, 3, "delete publicKey + handshakes + pending transfers", "sync"),
         (2, 1, "cleanupComplete", "return"),
     ]),
    ("SD015", "Zero-Remanence RAM Wiping Protocol",
     "Wipe is registry-based (explicit register/unregister), covering Dart heap, secure storage and Firestore fields; OS frame-buffer wipe is out of scope (handled by FLAG_SECURE).",
     ["Sensitive\nScreen", "SecurityLifecycleMixin", "Uint8List\n(buffers)", "Isolate\n(compute)", "NativeOS\n(Kotlin)"],
     [
         (0, 1, "registerBuffer(sensitiveBytes)", "sync"),
         (3, 3, "defensive copy of isolate inputs", "self"),
         (3, 3, "finally { fillRange(0) on key/iv/plaintext }", "self"),
         (0, 1, "dispose() -> wipeAll()", "sync"),
         (1, 2, "fillRange(0, length, 0) per registered buffer", "sync"),
         (1, 4, "requestNativeClear() via MethodChannel", "sync"),
     ]),
]


def main():
    elements = []
    cols = 3
    col_x = [0, 0, 0]
    row_heights = []
    built = [build_diagram(*d) for d in DIAGRAMS]

    col_widths = [0, 0, 0]
    for idx, (els, w, h) in enumerate(built):
        c = idx % cols
        col_widths[c] = max(col_widths[c], w)

    col_gap = 120
    row_gap = 100
    col_offsets = [0]
    for c in range(1, cols):
        col_offsets.append(col_offsets[-1] + col_widths[c - 1] + col_gap)

    row_y = 0
    for row_start in range(0, len(built), cols):
        row = built[row_start:row_start + cols]
        max_h = max(h for _, _, h in row)
        for c, (els, w, h) in enumerate(row):
            translate(els, col_offsets[c], row_y)
            elements.extend(els)
        row_y += max_h + row_gap

    doc_title = text(0, -90, "CrypTransfer Sequence Diagrams (v2 — codebase-accurate)",
                      fontSize=22, fontFamily=1, color="#1e1e1e")
    doc_subtitle = text(
        0, -56,
        "Updated from the original Python/Kivy/SQL Server thesis design (SD001-SD015) to match the "
        "real Flutter + Firebase implementation: no central SystemController, repositories call "
        "FirebaseAuth/Firestore/Storage directly, crypto runs in compute() isolates, and the RSA "
        "exchange is a two-layer Firestore handshake (neutral_handshakes + handshakes), not a single step.",
        fontSize=13, fontFamily=2, color="#495057",
    )
    elements.insert(0, doc_subtitle)
    elements.insert(0, doc_title)

    scene = {
        "type": "excalidraw",
        "version": 2,
        "source": "https://excalidraw.com",
        "elements": elements,
        "appState": {
            "viewBackgroundColor": "#ffffff",
            "gridSize": 20,
        },
        "files": {},
    }

    out_path = r"C:\Users\navve\projects\cryptransfer\.claude\skills\excalidraw-diagram\references\cryptransfer_sequence_diagrams_v2.excalidraw"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(scene, f, indent=2)
    print(f"Wrote {len(elements)} elements to {out_path}")


if __name__ == "__main__":
    main()
