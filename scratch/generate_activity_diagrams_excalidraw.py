"""
Generates an .excalidraw file containing 15 swimlane activity diagrams
(AD001-AD015), one per SD in cryptransfer_sequence_diagrams_v2.excalidraw,
reflecting the real Flutter+Firebase implementation.

Style: lanes = vertical columns with header + tinted body, rounded-rect
action nodes, orange diamond decisions, black filled start node, ringed end
node. Arrow color signals branch type: black = sequential, green = continue/
happy path, red = fail/exit path.
"""
import json
import random

random.seed(7)
_counter = 0


def next_id():
    global _counter
    _counter += 1
    return f"ad{_counter:07d}"


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
    return base("rectangle", x, y, w, h, strokeColor=stroke, backgroundColor=bg,
                roundness={"type": 3} if rounded else None)


def diamond(x, y, w, h, stroke="#e8590c", bg="#ffffff"):
    return base("diamond", x, y, w, h, strokeColor=stroke, backgroundColor=bg)


def ellipse(x, y, w, h, stroke="#1e1e1e", bg="transparent"):
    return base("ellipse", x, y, w, h, strokeColor=stroke, backgroundColor=bg)


def text(x, y, s, fontSize=12, fontFamily=2, color="#1e1e1e", align="left"):
    lines = s.split("\n")
    width = max(40.0, max(len(line) for line in lines) * fontSize * 0.56)
    height = len(lines) * fontSize * 1.25
    return base("text", x, y, width, height, strokeColor=color, text=s,
                fontSize=fontSize, fontFamily=fontFamily, textAlign=align,
                verticalAlign="top", baseline=fontSize, containerId=None,
                originalText=s, lineHeight=1.25)


def arrow(x1, y1, x2, y2, stroke="#1e1e1e", dashed=False):
    dx, dy = x2 - x1, y2 - y1
    return base("arrow", x1, y1, abs(dx), abs(dy), strokeColor=stroke,
                strokeStyle="dashed" if dashed else "solid",
                points=[[0, 0], [dx, dy]], lastCommittedPoint=None,
                startBinding=None, endBinding=None, startArrowhead=None,
                endArrowhead="triangle", roundness={"type": 2})


LANE_W = 270
HEADER_H = 50
ROW_H = 130
NODE_W = LANE_W - 36
NODE_H = 54
DIA_W, DIA_H = 96, 70
START_D = 26
END_OUTER, END_INNER = 30, 16

COLOR_SEQ = "#1e1e1e"
COLOR_GO = "#2f9e44"
COLOR_STOP = "#c92a2a"


def wrap(s, width=26):
    words = s.split(" ")
    lines, cur = [], ""
    for w in words:
        # hard-break tokens with no spaces (e.g. method calls) that exceed width on their own
        while len(w) > width:
            head, w = w[:width], w[width:]
            if cur:
                lines.append(cur)
                cur = ""
            lines.append(head)
        trial = (cur + " " + w).strip()
        if len(trial) > width and cur:
            lines.append(cur)
            cur = w
        else:
            cur = trial
    if cur:
        lines.append(cur)
    return "\n".join(lines)


def build_diagram(ad_id, title, note, lanes, nodes, edges):
    """
    nodes: dict id -> {lane, row, kind, label}; kind in start/end/action/decision
    edges: list of (from_id, to_id, label, color)
    Returns (elements, width, height)
    """
    els = []
    max_row = max(n["row"] for n in nodes.values())
    n_lanes = len(lanes)

    title_h = 0
    els.append(text(0, 0, f"{ad_id}: {title}", fontSize=18, fontFamily=1, color="#1971c2"))
    title_h += 24
    if note:
        note_text = wrap(f"Note: {note}", 150)
        els.append(text(0, title_h, note_text, fontSize=12, fontFamily=2, color="#495057"))
        title_h += 18 * (note_text.count("\n") + 1) + 8

    top_y = title_h + 10
    body_top = top_y + HEADER_H
    body_h = max_row * ROW_H + NODE_H + 60
    total_h = body_top + body_h

    # lane backgrounds + headers + dividers
    for i, name in enumerate(lanes):
        lx = i * LANE_W
        bg = "#f8f9fa" if i % 2 == 0 else "#ffffff"
        els.append(rect(lx, body_top, LANE_W, body_h, stroke="#dee2e6", bg=bg, rounded=False))
        els.append(rect(lx + 4, top_y, LANE_W - 8, HEADER_H, stroke="#1971c2", bg="#ffffff"))
        els.append(text(lx + 4, top_y + (HEADER_H - 15) / 2, name, fontSize=13,
                        fontFamily=2, align="center"))
        els[-1]["width"] = LANE_W - 8

    def lane_cx(i):
        return i * LANE_W + LANE_W / 2

    centers = {}
    for nid, n in nodes.items():
        cx = lane_cx(n["lane"])
        cy = body_top + 30 + n["row"] * ROW_H
        kind = n["kind"]
        label = n.get("label", "")
        if kind == "start":
            els.append(ellipse(cx - START_D / 2, cy - START_D / 2, START_D, START_D,
                                stroke="#1e1e1e", bg="#1e1e1e"))
            centers[nid] = (cx, cy, START_D / 2)
        elif kind == "end":
            els.append(ellipse(cx - END_OUTER / 2, cy - END_OUTER / 2, END_OUTER, END_OUTER,
                                stroke="#1e1e1e", bg="transparent"))
            els.append(ellipse(cx - END_INNER / 2, cy - END_INNER / 2, END_INNER, END_INNER,
                                stroke="#1e1e1e", bg="#1e1e1e"))
            els.append(text(cx - 60, cy + END_OUTER / 2 + 4, label, fontSize=11,
                            fontFamily=2, align="center"))
            els[-1]["width"] = 120
            centers[nid] = (cx, cy, END_OUTER / 2)
        elif kind == "decision":
            els.append(diamond(cx - DIA_W / 2, cy - DIA_H / 2, DIA_W, DIA_H))
            wl = wrap(label, 16)
            els.append(text(cx - DIA_W / 2 + 6, cy - 12, wl, fontSize=11, fontFamily=2, align="center"))
            els[-1]["width"] = DIA_W - 12
            centers[nid] = (cx, cy, DIA_H / 2)
        else:  # action
            wl = wrap(label, 22)
            n_lines = len(wl.split("\n"))
            th = n_lines * 12 * 1.25
            node_h = max(NODE_H, th + 22)
            els.append(rect(cx - NODE_W / 2, cy - node_h / 2, NODE_W, node_h,
                            stroke="#1971c2", bg="#ffffff"))
            els.append(text(cx - NODE_W / 2 + 6, cy - th / 2, wl, fontSize=12,
                            fontFamily=2, align="center"))
            els[-1]["width"] = NODE_W - 12
            centers[nid] = (cx, cy, node_h / 2)

    for frm, to, label, color in edges:
        x1, y1, r1 = centers[frm]
        x2, y2, r2 = centers[to]
        import math
        ang = math.atan2(y2 - y1, x2 - x1)
        sx, sy = x1 + math.cos(ang) * r1, y1 + math.sin(ang) * r1
        ex, ey = x2 - math.cos(ang) * r2, y2 - math.sin(ang) * r2
        els.append(arrow(sx, sy, ex, ey, stroke=color))
        if label:
            mx, my = (sx + ex) / 2, (sy + ey) / 2
            els.append(text(mx + 6, my - 16, label, fontSize=11, fontFamily=2, color=color))

    width = n_lanes * LANE_W
    return els, width, total_h


def translate(els, dx, dy):
    for el in els:
        el["x"] += dx
        el["y"] += dy


# ---------------------------------------------------------------------------
# Diagram data
# ---------------------------------------------------------------------------

DIAGRAMS = []


def add(ad_id, title, note, lanes, node_specs, edge_specs):
    """node_specs: list of (id, lane, row, kind, label); edge_specs: list of (from,to,label,color)"""
    nodes = {nid: {"lane": lane, "row": row, "kind": kind, "label": label}
             for nid, lane, row, kind, label in node_specs}
    DIAGRAMS.append((ad_id, title, note, lanes, nodes, edge_specs))


add("AD001", "Login Account",
    "No SystemController - LoginScreen calls AuthRepository directly; failures branch out early instead of looping through a generic 'access denied' state.",
    ["User", "LoginScreen", "AuthRepository", "Firebase"],
    [
        ("s", 0, 0, "start", ""),
        ("n1", 0, 1, "action", "enterCredentials(username, pwd)"),
        ("n2", 1, 2, "action", "loginWithUsername(username, pwd)"),
        ("n3", 2, 3, "action", "_ensureAuthenticated() [anon pre-auth]"),
        ("n4", 3, 4, "action", "query users.where(username) -> email"),
        ("d1", 2, 5, "decision", "username found?"),
        ("efail1", 1, 6, "action", "show 'user not found'"),
        ("eend1", 1, 7, "end", "Fail"),
        ("n5", 3, 6, "action", "signInWithEmailAndPassword(email,pwd)"),
        ("d2", 2, 7, "decision", "credentials valid?"),
        ("efail2", 1, 8, "action", "show 'invalid credentials'"),
        ("eend2", 1, 9, "end", "Fail"),
        ("n6", 0, 8, "action", "navigate to Home"),
        ("eend3", 0, 9, "end", "Success"),
    ],
    [
        ("s", "n1", "", COLOR_SEQ), ("n1", "n2", "", COLOR_SEQ), ("n2", "n3", "", COLOR_SEQ),
        ("n3", "n4", "", COLOR_SEQ), ("n4", "d1", "", COLOR_SEQ),
        ("d1", "efail1", "no", COLOR_STOP), ("efail1", "eend1", "", COLOR_STOP),
        ("d1", "n5", "yes", COLOR_GO), ("n5", "d2", "", COLOR_SEQ),
        ("d2", "efail2", "no", COLOR_STOP), ("efail2", "eend2", "", COLOR_STOP),
        ("d2", "n6", "yes", COLOR_GO), ("n6", "eend3", "", COLOR_GO),
    ])

add("AD002", "Register Account",
    "Username-uniqueness check and account creation happen in one register() call; profile/preferences subcollection seeded at registration time.",
    ["User", "RegisterScreen", "AuthRepository", "Firebase"],
    [
        ("s", 0, 0, "start", ""),
        ("n1", 0, 1, "action", "submit(username,email,phone,pwd)"),
        ("d1", 1, 2, "decision", "input format valid?"),
        ("efail1", 1, 3, "action", "show inline validation error"),
        ("eend1", 1, 4, "end", "Fail"),
        ("n2", 2, 3, "action", "isUsernameTaken(username)"),
        ("d2", 3, 4, "decision", "username taken?"),
        ("efail2", 1, 5, "action", "show 'username taken'"),
        ("eend2", 1, 6, "end", "Fail"),
        ("n3", 2, 5, "action", "createUserWithEmailAndPassword()"),
        ("n4", 3, 6, "action", "batch.set(users + profile/preferences)"),
        ("n5", 1, 7, "action", "navigate to Home"),
        ("eend3", 1, 8, "end", "Success"),
    ],
    [
        ("s", "n1", "", COLOR_SEQ), ("n1", "d1", "", COLOR_SEQ),
        ("d1", "efail1", "no", COLOR_STOP), ("efail1", "eend1", "", COLOR_STOP),
        ("d1", "n2", "yes", COLOR_GO), ("n2", "d2", "", COLOR_SEQ),
        ("d2", "efail2", "yes", COLOR_STOP), ("efail2", "eend2", "", COLOR_STOP),
        ("d2", "n3", "no", COLOR_GO), ("n3", "n4", "", COLOR_SEQ),
        ("n4", "n5", "", COLOR_SEQ), ("n5", "eend3", "", COLOR_GO),
    ])

add("AD003", "Choose File",
    "Selected file lives only in SenderState.file; nothing is persisted to Firestore at this step.",
    ["User", "SenderScreen", "SenderController", "FilePicker"],
    [
        ("s", 0, 0, "start", ""),
        ("n1", 0, 1, "action", "tapSelectFile()"),
        ("n2", 2, 2, "action", "pickFile() -> pickFiles()"),
        ("d1", 3, 3, "decision", "file selected\n(not cancelled)?"),
        ("eend1", 1, 4, "end", "Cancelled"),
        ("d2", 2, 4, "decision", "size <= 100MB?"),
        ("efail1", 1, 5, "action", "show 'file too large'"),
        ("eend2", 0, 6, "end", "Fail"),
        ("n3", 2, 5, "action", "state.copyWith(file)"),
        ("n4", 1, 6, "action", "displaySelectedFile()"),
        ("eend3", 1, 7, "end", "Success"),
    ],
    [
        ("s", "n1", "", COLOR_SEQ), ("n1", "n2", "", COLOR_SEQ), ("n2", "d1", "", COLOR_SEQ),
        ("d1", "eend1", "no", COLOR_STOP), ("d1", "d2", "yes", COLOR_GO),
        ("d2", "efail1", "no", COLOR_STOP), ("efail1", "eend2", "", COLOR_STOP),
        ("d2", "n3", "yes", COLOR_GO), ("n3", "n4", "", COLOR_SEQ), ("n4", "eend3", "", COLOR_GO),
    ])

add("AD004", "Generate AES Key",
    "Key generation is inlined inside encryptAesGcm() - no standalone keygen API or branching as the thesis assumed.",
    ["SenderController", "EncryptionService"],
    [
        ("s", 0, 0, "start", ""),
        ("n1", 0, 1, "action", "call encryptAesGcm(plaintext)"),
        ("n2", 1, 2, "action", "secureRandomBytes(32) -> key"),
        ("n3", 1, 3, "action", "secureRandomBytes(12) -> iv"),
        ("n4", 1, 4, "action", "return key, iv to caller"),
        ("e", 0, 5, "end", "Success"),
    ],
    [
        ("s", "n1", "", COLOR_SEQ), ("n1", "n2", "", COLOR_SEQ), ("n2", "n3", "", COLOR_SEQ),
        ("n3", "n4", "", COLOR_SEQ), ("n4", "e", "", COLOR_GO),
    ])

add("AD005", "Encrypt File",
    "AES-256-GCM runs inside a compute() isolate; buffers are zeroed in a finally block regardless of outcome.",
    ["SenderController", "EncryptionService", "Isolate"],
    [
        ("s", 0, 0, "start", ""),
        ("n1", 0, 1, "action", "readFileWithProgress() [0-70%]"),
        ("n2", 1, 2, "action", "call encryptAesGcm(plaintext)"),
        ("n3", 2, 3, "action", "compute(runAesGcmEncrypt)"),
        ("n4", 2, 4, "action", "GCMBlockCipher.process()"),
        ("d1", 2, 5, "decision", "encryption\nsucceeded?"),
        ("efail1", 2, 6, "action", "wipe buffers in finally"),
        ("eend1", 1, 7, "end", "Fail"),
        ("n5", 1, 6, "action", "fillRange(0) wipe local copies"),
        ("n6", 0, 7, "action", "store AesEncryptResult"),
        ("eend2", 0, 8, "end", "Success"),
    ],
    [
        ("s", "n1", "", COLOR_SEQ), ("n1", "n2", "", COLOR_SEQ), ("n2", "n3", "", COLOR_SEQ),
        ("n3", "n4", "", COLOR_SEQ), ("n4", "d1", "", COLOR_SEQ),
        ("d1", "efail1", "no", COLOR_STOP), ("efail1", "eend1", "", COLOR_STOP),
        ("d1", "n5", "yes", COLOR_GO), ("n5", "n6", "", COLOR_SEQ), ("n6", "eend2", "", COLOR_GO),
    ])

add("AD006", "Generate RSA Key",
    "Keypair generation runs in a compute() isolate; private key never leaves the device.",
    ["AuthRepository", "Isolate", "SecureStorage", "Firestore"],
    [
        ("s", 0, 0, "start", ""),
        ("n1", 0, 1, "action", "compute(_generateKeyPairIsolate)"),
        ("n2", 1, 2, "action", "RSAKeyGenerator(2048, e=65537)"),
        ("n3", 0, 3, "action", "receive RSAKeyPair"),
        ("n4", 2, 4, "action", "write('rsa_private_key', encodedPrivate)"),
        ("n5", 3, 5, "action", "update(publicKey: encodedPublic)"),
        ("e", 3, 6, "end", "Success"),
    ],
    [
        ("s", "n1", "", COLOR_SEQ), ("n1", "n2", "", COLOR_SEQ), ("n2", "n3", "", COLOR_SEQ),
        ("n3", "n4", "", COLOR_SEQ), ("n4", "n5", "", COLOR_SEQ), ("n5", "e", "", COLOR_GO),
    ])

add("AD007", "Transfer File",
    "Firebase Storage SDK handles chunking internally; transfer doc stores the RSA-encrypted AES key, never the raw key.",
    ["SenderController", "TransferRepository", "Firebase Storage", "Firestore"],
    [
        ("s", 0, 0, "start", ""),
        ("n1", 0, 1, "action", "uploadAndCreate(encryptedBytes,...)"),
        ("n2", 2, 2, "action", "putData(transfers/{id}/encrypted_file)"),
        ("d1", 2, 3, "decision", "upload\nsucceeded?"),
        ("efail1", 0, 4, "action", "show upload error"),
        ("eend1", 0, 5, "end", "Fail"),
        ("n3", 2, 4, "action", "getDownloadURL()"),
        ("n4", 3, 5, "action", "set(transfers/{id}: key,iv,url,pending)"),
        ("n5", 3, 6, "action", "add(notifications: fileReceived)"),
        ("eend2", 1, 7, "end", "Success"),
    ],
    [
        ("s", "n1", "", COLOR_SEQ), ("n1", "n2", "", COLOR_SEQ), ("n2", "d1", "", COLOR_SEQ),
        ("d1", "efail1", "no", COLOR_STOP), ("efail1", "eend1", "", COLOR_STOP),
        ("d1", "n3", "yes", COLOR_GO), ("n3", "n4", "", COLOR_SEQ),
        ("n4", "n5", "", COLOR_SEQ), ("n5", "eend2", "", COLOR_GO),
    ])

add("AD008", "Receive File",
    "Receiver never talks to the sender directly - transfers/{id} is the sole source of truth for key material and file URL.",
    ["ReceiverScreen", "TransferRepository", "Firestore", "Firebase Storage"],
    [
        ("s", 0, 0, "start", "notified"),
        ("n1", 0, 1, "action", "getTransfer(transferId)"),
        ("n2", 2, 2, "action", "get(transfers/{id}) -> TransferModel"),
        ("n3", 1, 3, "action", "getData(transfers/{id}/encrypted_file)"),
        ("d1", 3, 4, "decision", "download\nsucceeded?"),
        ("efail1", 0, 5, "action", "show download error"),
        ("eend1", 1, 6, "end", "Fail"),
        ("n4", 1, 5, "action", "update(status: received, receivedAt)"),
        ("n5", 0, 6, "action", "proceed to decrypt screen"),
        ("eend2", 0, 7, "end", "Success"),
    ],
    [
        ("s", "n1", "", COLOR_SEQ), ("n1", "n2", "", COLOR_SEQ), ("n2", "n3", "", COLOR_SEQ),
        ("n3", "d1", "", COLOR_SEQ),
        ("d1", "efail1", "no", COLOR_STOP), ("efail1", "eend1", "", COLOR_STOP),
        ("d1", "n4", "yes", COLOR_GO), ("n4", "n5", "", COLOR_SEQ), ("n5", "eend2", "", COLOR_GO),
    ])

add("AD009", "Decrypt File",
    "Two-phase decrypt (RSA unwrap then AES-GCM) - both phases run in compute() isolates; a failed GCM tag check means tampering/corruption, not just a wrong key.",
    ["DecryptScreen", "AuthRepository", "EncryptionService", "Isolate"],
    [
        ("s", 0, 0, "start", ""),
        ("n1", 0, 1, "action", "getPrivateKeyJson()"),
        ("d1", 1, 2, "decision", "private key\nexists?"),
        ("efail1", 0, 3, "action", "show 'no key in vault'"),
        ("eend1", 0, 4, "end", "Fail"),
        ("n2", 2, 3, "action", "decryptAesKeyWithPrivateKeyJson()"),
        ("n3", 2, 4, "action", "rsaDecrypt() [OAEP]"),
        ("n4", 0, 5, "action", "decryptAesGcm(ciphertext,key,iv)"),
        ("n5", 3, 6, "action", "runAesGcmDecrypt() verify GCM tag"),
        ("d2", 3, 7, "decision", "tag valid?"),
        ("efail2", 1, 8, "action", "show 'corrupted / tampered'"),
        ("eend2", 1, 9, "end", "Fail"),
        ("n6", 0, 8, "action", "writeAsBytes(plaintext) + registerBuffer"),
        ("eend3", 0, 9, "end", "Success"),
    ],
    [
        ("s", "n1", "", COLOR_SEQ), ("n1", "d1", "", COLOR_SEQ),
        ("d1", "efail1", "no", COLOR_STOP), ("efail1", "eend1", "", COLOR_STOP),
        ("d1", "n2", "yes", COLOR_GO), ("n2", "n3", "", COLOR_SEQ), ("n3", "n4", "", COLOR_SEQ),
        ("n4", "n5", "", COLOR_SEQ), ("n5", "d2", "", COLOR_SEQ),
        ("d2", "efail2", "no", COLOR_STOP), ("efail2", "eend2", "", COLOR_STOP),
        ("d2", "n6", "yes", COLOR_GO), ("n6", "eend3", "", COLOR_GO),
    ])

add("AD010", "Cleanup Temporary Memory",
    "Cleanup is a multi-turn protocol (initiate -> watch -> complete -> closeSession), not one atomic call.",
    ["ReceiverEndSessionScreen", "CleanupRepository", "KeyRepository", "EncryptionService"],
    [
        ("s", 0, 0, "start", ""),
        ("n1", 0, 1, "action", "initiateReceiverCleanup(transferId)"),
        ("n2", 1, 2, "action", "update(cleanup_initiated: true)"),
        ("n3", 0, 3, "action", "watchTransferForDeletion()"),
        ("d1", 0, 4, "decision", "sender confirmed\nwithin 120s?"),
        ("n4", 0, 5, "action", "(timeout) proceed anyway"),
        ("n5", 0, 6, "action", "completeReceiverCleanup()"),
        ("n6", 1, 7, "action", "batch: audit_logs + delete transfers"),
        ("n7", 2, 8, "action", "endSessionCleanup(handshakeId)"),
        ("n8", 3, 9, "action", "closeReceiverSession(uid)"),
        ("n9", 3, 10, "action", "delete private key + publicKey + handshakes"),
        ("e", 3, 11, "end", "Success"),
    ],
    [
        ("s", "n1", "", COLOR_SEQ), ("n1", "n2", "", COLOR_SEQ), ("n2", "n3", "", COLOR_SEQ),
        ("n3", "d1", "", COLOR_SEQ),
        ("d1", "n4", "no (timeout)", COLOR_STOP), ("n4", "n5", "", COLOR_SEQ),
        ("d1", "n5", "yes", COLOR_GO),
        ("n5", "n6", "", COLOR_SEQ), ("n6", "n7", "", COLOR_SEQ),
        ("n7", "n8", "", COLOR_SEQ), ("n8", "n9", "", COLOR_SEQ), ("n9", "e", "", COLOR_GO),
    ])

add("AD011", "Generate and Transfer RSA Public Key",
    "Two independent layers: neutral_handshakes (connection request) is separate from handshakes (per-transfer RSA exchange).",
    ["ReceiverScreen", "Firestore", "SenderScreen", "KeyRepository"],
    [
        ("s", 0, 0, "start", ""),
        ("n1", 0, 1, "action", "sendProposal(partnerUid) [connection]"),
        ("n2", 1, 2, "action", "set(neutral_handshakes: pending)"),
        ("n3", 2, 3, "action", "acceptProposal(docId)"),
        ("d1", 2, 4, "decision", "accepted?"),
        ("eend1", 2, 5, "end", "Rejected"),
        ("n4", 1, 5, "action", "update(status: connected) + friendships"),
        ("n5", 0, 6, "action", "selectSenderHandshake(senderUid) [RSA]"),
        ("n6", 3, 7, "action", "set(handshakes: publicKey, complete)"),
        ("n7", 2, 8, "action", "fetchHandshakePublicKey(receiverUid)"),
        ("eend2", 2, 9, "end", "Success"),
    ],
    [
        ("s", "n1", "", COLOR_SEQ), ("n1", "n2", "", COLOR_SEQ), ("n2", "n3", "", COLOR_SEQ),
        ("n3", "d1", "", COLOR_SEQ),
        ("d1", "eend1", "no", COLOR_STOP), ("d1", "n4", "yes", COLOR_GO),
        ("n4", "n5", "", COLOR_SEQ), ("n5", "n6", "", COLOR_SEQ),
        ("n6", "n7", "", COLOR_SEQ), ("n7", "eend2", "", COLOR_GO),
    ])

add("AD012", "Manage User Profiles",
    "friendships subcollection (not a 'connections' table) is the source of truth for who a user is connected to.",
    ["User", "ProfileScreen", "UserRepository", "Firestore"],
    [
        ("s", 0, 0, "start", ""),
        ("n1", 0, 1, "action", "viewProfile()"),
        ("n2", 1, 2, "action", "streamUserProfile(uid)"),
        ("n3", 1, 3, "action", "display userData"),
        ("n4", 0, 4, "action", "updateProfile(fields)"),
        ("d1", 2, 5, "decision", "validation\npasses?"),
        ("efail1", 1, 6, "action", "show validation error"),
        ("eend1", 0, 7, "end", "Fail"),
        ("n5", 2, 6, "action", "update(fields)"),
        ("n6", 1, 7, "action", "show updateOK"),
        ("eend2", 1, 8, "end", "Success"),
    ],
    [
        ("s", "n1", "", COLOR_SEQ), ("n1", "n2", "", COLOR_SEQ), ("n2", "n3", "", COLOR_SEQ),
        ("n3", "n4", "", COLOR_SEQ), ("n4", "d1", "", COLOR_SEQ),
        ("d1", "efail1", "no", COLOR_STOP), ("efail1", "eend1", "", COLOR_STOP),
        ("d1", "n5", "yes", COLOR_GO), ("n5", "n6", "", COLOR_SEQ), ("n6", "eend2", "", COLOR_GO),
    ])

add("AD013", "Biometric Authentication Gate",
    "Gate is integrated into SenderController.encryptAesKey(); falls back to device PIN/password when no biometric hardware exists.",
    ["User", "SenderController", "BiometricHelper", "LocalAuthentication"],
    [
        ("s", 0, 0, "start", ""),
        ("n1", 0, 1, "action", "requestSensitiveAction()"),
        ("n2", 2, 2, "action", "isDeviceSupported()"),
        ("d1", 3, 3, "decision", "supported?"),
        ("n3", 1, 4, "action", "proceed without biometric (warning)"),
        ("eend1", 1, 5, "end", "Success"),
        ("n4", 2, 4, "action", "authenticate(biometricOnly:false)"),
        ("n5", 0, 5, "action", "[Fingerprint / Face / PIN]"),
        ("d2", 3, 6, "decision", "authenticated?"),
        ("efail1", 0, 7, "action", "cancel sensitive action"),
        ("eend2", 0, 8, "end", "Fail"),
        ("n6", 1, 7, "action", "proceed with RSA encryption"),
        ("eend3", 1, 8, "end", "Success"),
    ],
    [
        ("s", "n1", "", COLOR_SEQ), ("n1", "n2", "", COLOR_SEQ), ("n2", "d1", "", COLOR_SEQ),
        ("d1", "n3", "no", COLOR_STOP), ("n3", "eend1", "", COLOR_GO),
        ("d1", "n4", "yes", COLOR_GO), ("n4", "n5", "", COLOR_SEQ), ("n5", "d2", "", COLOR_SEQ),
        ("d2", "efail1", "no", COLOR_STOP), ("efail1", "eend2", "", COLOR_STOP),
        ("d2", "n6", "yes", COLOR_GO), ("n6", "eend3", "", COLOR_GO),
    ])

add("AD014", "Silent Guardian Session Kill-Switch",
    "Trigger is local app-lifecycle only - no remote push; sender detects the loss via the handshake-doc deletion stream.",
    ["ReceiverScreen", "SessionManager", "EncryptionService", "Firestore"],
    [
        ("s", 0, 0, "start", "lifecycle event"),
        ("n1", 0, 1, "action", "didChangeAppLifecycleState()"),
        ("d1", 1, 2, "decision", "paused or\ndetached?"),
        ("eend1", 0, 3, "end", "Resume normal"),
        ("n2", 1, 3, "action", "wipeSession()"),
        ("n3", 1, 4, "action", "stateStream.emit(terminated)"),
        ("n4", 2, 5, "action", "closeReceiverSession(uid)"),
        ("n5", 3, 6, "action", "delete privKey + publicKey + handshakes"),
        ("e", 3, 7, "end", "Success"),
    ],
    [
        ("s", "n1", "", COLOR_SEQ), ("n1", "d1", "", COLOR_SEQ),
        ("d1", "eend1", "no", COLOR_GO),
        ("d1", "n2", "yes", COLOR_STOP), ("n2", "n3", "", COLOR_SEQ),
        ("n3", "n4", "", COLOR_SEQ), ("n4", "n5", "", COLOR_SEQ), ("n5", "e", "", COLOR_GO),
    ])

add("AD015", "Zero-Remanence RAM Wiping Protocol",
    "Wipe is registry-based (explicit register/unregister); OS frame-buffer wipe is out of scope (handled by FLAG_SECURE).",
    ["Sensitive Screen", "SecurityLifecycleMixin", "Uint8List Buffers", "NativeOS"],
    [
        ("s", 0, 0, "start", ""),
        ("n1", 0, 1, "action", "registerBuffer(sensitiveBytes)"),
        ("n2", 0, 2, "action", "...screen does sensitive work..."),
        ("n3", 0, 3, "action", "dispose() -> wipeAll()"),
        ("n4", 1, 4, "action", "iterate registered buffers"),
        ("n5", 2, 5, "action", "fillRange(0, length, 0)"),
        ("n6", 1, 6, "action", "requestNativeClear()"),
        ("n7", 3, 7, "action", "MethodChannel 'clearSession' [GC hint]"),
        ("e", 3, 8, "end", "Success"),
    ],
    [
        ("s", "n1", "", COLOR_SEQ), ("n1", "n2", "", COLOR_SEQ), ("n2", "n3", "", COLOR_SEQ),
        ("n3", "n4", "", COLOR_SEQ), ("n4", "n5", "", COLOR_SEQ),
        ("n5", "n6", "", COLOR_SEQ), ("n6", "n7", "", COLOR_SEQ), ("n7", "e", "", COLOR_GO),
    ])


def main():
    built = [build_diagram(*d) for d in DIAGRAMS]
    cols = 3
    col_widths = [0, 0, 0]
    for idx, (els, w, h) in enumerate(built):
        c = idx % cols
        col_widths[c] = max(col_widths[c], w)

    col_gap, row_gap = 140, 110
    col_offsets = [0]
    for c in range(1, cols):
        col_offsets.append(col_offsets[-1] + col_widths[c - 1] + col_gap)

    elements = []
    row_y = 0
    for row_start in range(0, len(built), cols):
        row = built[row_start:row_start + cols]
        max_h = max(h for _, _, h in row)
        for c, (els, w, h) in enumerate(row):
            translate(els, col_offsets[c], row_y)
            elements.extend(els)
        row_y += max_h + row_gap

    doc_title = text(0, -90, "CrypTransfer Activity Diagrams (v2 — codebase-accurate, swimlane)",
                      fontSize=22, fontFamily=1, color="#1e1e1e")
    doc_subtitle = text(
        0, -56,
        "Updated from the original thesis activity diagrams (only AD001/005/007/008/010/011 existed) to "
        "cover all 15 flows from the sequence diagrams, with swimlanes per responsible component. Black "
        "arrows = sequential flow, green = continue/happy path, red = fail/exit path.",
        fontSize=13, fontFamily=2, color="#495057",
    )
    elements.insert(0, doc_subtitle)
    elements.insert(0, doc_title)

    scene = {
        "type": "excalidraw",
        "version": 2,
        "source": "https://excalidraw.com",
        "elements": elements,
        "appState": {"viewBackgroundColor": "#ffffff", "gridSize": 20},
        "files": {},
    }

    out_path = r"C:\Users\navve\projects\cryptransfer\.claude\skills\excalidraw-diagram\references\cryptransfer_activity_diagrams_v2.excalidraw"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(scene, f, indent=2)
    print(f"Wrote {len(elements)} elements to {out_path}")


if __name__ == "__main__":
    main()
