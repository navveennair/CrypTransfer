"""
Generates an .excalidraw file containing the CrypTransfer class diagram
(v2 — codebase-accurate), replacing the original thesis class diagram
(RSAKeys/SystemController/User/TransferSession/CleanupManager/
EncryptionService/File/TLSChannel/Database).

Style: UML 3-compartment class boxes (name / attributes / methods), blue
#1971c2 strokes, fontFamily 1 for the doc title + class names, fontFamily 2
for everything else. Solid arrows = association (with multiplicity),
dashed arrows = dependency <<uses>>.
"""
import json
import random

random.seed(11)
_counter = 0


def next_id():
    global _counter
    _counter += 1
    return f"cd{_counter:07d}"


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


def rect(x, y, w, h, stroke="#1971c2", bg="#ffffff", rounded=True):
    return base("rectangle", x, y, w, h, strokeColor=stroke, backgroundColor=bg,
                roundness={"type": 3} if rounded else None)


def hline(x, y, w, stroke="#1971c2"):
    return base("arrow", x, y, w, 0, strokeColor=stroke,
                points=[[0, 0], [w, 0]], lastCommittedPoint=None,
                startBinding=None, endBinding=None, startArrowhead=None,
                endArrowhead=None, roundness={"type": 2})


def text(x, y, s, fontSize=13, fontFamily=2, color="#1e1e1e", align="left", width=None):
    lines = s.split("\n")
    w = width if width is not None else max(40.0, max(len(line) for line in lines) * fontSize * 0.56)
    h = len(lines) * fontSize * 1.25
    return base("text", x, y, w, h, strokeColor=color, text=s,
                fontSize=fontSize, fontFamily=fontFamily, textAlign=align,
                verticalAlign="top", baseline=fontSize, containerId=None,
                originalText=s, lineHeight=1.25)


def wrap(s, width=110):
    words = s.split(" ")
    lines, cur = [], ""
    for w in words:
        trial = (cur + " " + w).strip()
        if len(trial) > width and cur:
            lines.append(cur)
            cur = w
        else:
            cur = trial
    if cur:
        lines.append(cur)
    return "\n".join(lines)


def polyline_arrow(points, stroke="#1e1e1e", dashed=False):
    """Sharp-cornered (no roundness) multi-point orthogonal connector."""
    x0, y0 = points[0]
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    rel = [[px - x0, py - y0] for px, py in points]
    return base("arrow", x0, y0, max(xs) - min(xs), max(ys) - min(ys),
                strokeColor=stroke, strokeStyle="dashed" if dashed else "solid",
                points=rel, lastCommittedPoint=None, startBinding=None,
                endBinding=None, startArrowhead=None, endArrowhead="triangle",
                roundness=None)


CLASS_W = 300
PAD = 10
LINE_H = 18
NAME_H = 36
STEREO_H = 16


class ClassBox:
    def __init__(self, name, attrs, methods, stereotype=None):
        self.name = name
        self.attrs = attrs
        self.methods = methods
        self.stereotype = stereotype
        self.x = 0
        self.y = 0
        self.w = CLASS_W
        header_h = NAME_H + (STEREO_H if stereotype else 0)
        attr_h = (PAD * 2 + len(attrs) * LINE_H) if attrs else 0
        meth_h = PAD * 2 + max(1, len(methods)) * LINE_H
        self.header_h = header_h
        self.attr_h = attr_h
        self.meth_h = meth_h
        self.h = header_h + attr_h + meth_h

    def center(self):
        return (self.x + self.w / 2, self.y + self.h / 2)

    def build(self):
        els = []
        els.append(rect(self.x, self.y, self.w, self.h))
        cy = self.y
        if self.stereotype:
            els.append(text(self.x, cy + 4, self.stereotype, fontSize=12,
                            fontFamily=2, color="#495057", align="center", width=self.w))
            cy += STEREO_H
        els.append(text(self.x, cy + (NAME_H - 18) / 2, self.name, fontSize=17,
                        fontFamily=1, color="#1971c2", align="center", width=self.w))
        cy = self.y + self.header_h
        els.append(hline(self.x, cy, self.w))
        if self.attrs:
            attr_text = "\n".join(self.attrs)
            els.append(text(self.x + PAD, cy + PAD - 4, attr_text, fontSize=13,
                            fontFamily=2, width=self.w - PAD * 2))
            cy += self.attr_h
            els.append(hline(self.x, cy, self.w))
        meth_text = "\n".join(self.methods) if self.methods else " "
        els.append(text(self.x + PAD, cy + PAD - 4, meth_text, fontSize=13,
                        fontFamily=2, width=self.w - PAD * 2))
        return els


# ---------------------------------------------------------------------------
# Orthogonal router — connections only ever travel through the empty "gutter"
# bands between rows/columns (guaranteed box-free across the whole grid),
# never across box interiors. Two deliberate anti-redundancy measures so
# distinct relationships stay readable instead of bundling into one fat line:
#   1. Diagonal connections (different row AND column) enter the target via
#      its LEFT/RIGHT edge — facing the source — instead of always top/bottom,
#      so a box's incoming arrows arrive from multiple directions.
#   2. Every box+side and every shared gutter is registered in a pre-pass, then
#      each connection takes a distinct, evenly-spaced slot along that edge/
#      gutter, so parallel connections fan out rather than overlapping exactly.
# ---------------------------------------------------------------------------

from collections import defaultdict

port_count = defaultdict(int)
port_index = defaultdict(int)
lane_count = defaultdict(int)
lane_index = defaultdict(int)


def sides_for(row_a, col_a, row_b, col_b):
    """Pure geometry: which edge of A we leave from, which edge of B we enter."""
    if row_a == row_b:
        a_side = "down" if row_a < N_ROWS - 1 else "up"
        b_side = "bottom" if row_a < N_ROWS - 1 else "top"
    elif col_a != col_b:
        a_side = "down" if row_a < row_b else "up"
        b_side = "left" if col_a < col_b else "right"
    else:
        a_side = "down" if row_a < row_b else "up"
        b_side = "bottom" if row_a > row_b else "top"
    return a_side, b_side


def compute_route(key_a, key_b):
    row_a, col_a = pos[key_a]
    row_b, col_b = pos[key_b]
    a_side, b_side = sides_for(row_a, col_a, row_b, col_b)
    diagonal = b_side in ("left", "right")
    gy_a = ROW_GUTTER_Y[row_a] if a_side == "down" else ROW_GUTTER_Y[row_a - 1]

    gy_b, gx = None, None
    if row_a == row_b:
        gy_b = gy_a
    elif diagonal:
        gx_idx = (col_b - 1) if b_side == "left" else col_b
        gx = COL_GUTTER_X[gx_idx]
    else:
        gy_b = ROW_GUTTER_Y[row_b - 1] if b_side == "top" else ROW_GUTTER_Y[row_b]
        if gy_a != gy_b:
            gx_idx = col_a - 1 if col_a > 0 else col_a
            gx = COL_GUTTER_X[gx_idx]
    return a_side, b_side, diagonal, gy_a, gy_b, gx


def register_route(key_a, key_b):
    row_a, _ = pos[key_a]
    row_b, _ = pos[key_b]
    a_side, b_side, diagonal, gy_a, gy_b, gx = compute_route(key_a, key_b)
    port_count[(key_a, a_side)] += 1
    port_count[(key_b, b_side)] += 1
    if row_a == row_b or gy_b == gy_a:
        lane_count[("row", gy_a)] += 1
    elif diagonal:
        lane_count[("row", gy_a)] += 1
        lane_count[("col", gx)] += 1
    else:
        lane_count[("row", gy_a)] += 1
        lane_count[("row", gy_b)] += 1
        lane_count[("col", gx)] += 1


def take_port(key, side):
    n = port_count[(key, side)]
    i = port_index[(key, side)]
    port_index[(key, side)] += 1
    if n <= 1:
        return 0.0
    box = classes[key]
    span = box.w if side in ("top", "bottom") else box.h
    margin = 26
    usable = max(span - 2 * margin, 10)
    return -usable / 2 + i * (usable / (n - 1))


def take_lane(key, gap):
    n = lane_count[key]
    i = lane_index[key]
    lane_index[key] += 1
    if n <= 1:
        return 0.0
    margin = 14
    usable = max(gap - 2 * margin, 10)
    return -usable / 2 + i * (usable / (n - 1))


def connect_ortho(key_a, key_b, label="", color="#1971c2", dashed=False,
                   mult_a="", mult_b=""):
    box_a, box_b = classes[key_a], classes[key_b]
    row_a, col_a = pos[key_a]
    row_b, col_b = pos[key_b]
    a_side, b_side, diagonal, gy_a, gy_b, gx = compute_route(key_a, key_b)

    a_off = take_port(key_a, a_side)
    b_off = take_port(key_b, b_side)
    acx, _ = box_a.center()
    bcx, bcy = box_b.center()

    a_anchor = (acx + a_off, box_a.y + box_a.h) if a_side == "down" else (acx + a_off, box_a.y)
    if diagonal:
        b_anchor = (box_b.x if b_side == "left" else box_b.x + box_b.w, bcy + b_off)
    else:
        b_anchor = (bcx + b_off, box_b.y + box_b.h) if b_side == "bottom" else (bcx + b_off, box_b.y)

    if row_a == row_b or gy_b == gy_a:
        gy = gy_a + take_lane(("row", gy_a), ROW_GAP)
        points = [a_anchor, (a_anchor[0], gy), (b_anchor[0], gy), b_anchor]
    elif diagonal:
        gy_a2 = gy_a + take_lane(("row", gy_a), ROW_GAP)
        gx2 = gx + take_lane(("col", gx), COL_GAP)
        points = [a_anchor, (a_anchor[0], gy_a2), (gx2, gy_a2), (gx2, b_anchor[1]), b_anchor]
    else:
        gy_a2 = gy_a + take_lane(("row", gy_a), ROW_GAP)
        gy_b2 = gy_b + take_lane(("row", gy_b), ROW_GAP)
        gx2 = gx + take_lane(("col", gx), COL_GAP)
        points = [a_anchor, (a_anchor[0], gy_a2), (gx2, gy_a2), (gx2, gy_b2),
                  (b_anchor[0], gy_b2), b_anchor]

    els = [polyline_arrow(points, stroke=color, dashed=dashed)]
    if label:
        mx_i = len(points) // 2
        mx = (points[mx_i - 1][0] + points[mx_i][0]) / 2
        my = (points[mx_i - 1][1] + points[mx_i][1]) / 2
        els.append(text(mx + 6, my - 16, label, fontSize=11, fontFamily=2, color=color))
    if mult_a:
        ax, ay = a_anchor
        els.append(text(ax + 6, ay + (4 if a_side == "down" else -16), mult_a,
                        fontSize=10, fontFamily=2, color=color))
    if mult_b:
        bx, by = b_anchor
        if diagonal:
            els.append(text(bx + (6 if b_side == "right" else -30), by - 14, mult_b,
                            fontSize=10, fontFamily=2, color=color))
        else:
            els.append(text(bx + 6, by + (4 if b_side == "top" else -16), mult_b,
                            fontSize=10, fontFamily=2, color=color))
    return els


# ---------------------------------------------------------------------------
# Class definitions — attrs use "- name : Type" (UML private), methods use
# "+ name(args)" (UML public), mirroring the original thesis diagram's notation.
# ---------------------------------------------------------------------------

classes = {}


def add(key, name, attrs, methods, stereotype=None):
    classes[key] = ClassBox(name, attrs, methods, stereotype)


add("user_model", "UserModel", [
    "- uid : String",
    "- username : String",
    "- email : String",
    "- phone : String",
    "- publicKey : String?",
    "- isAdmin : bool",
    "- isActive : bool",
    "- createdAt : DateTime?",
], [
    "+ fromDoc(doc)",
    "+ toMap()",
    "+ hasPublicKey()",
], stereotype="<<model>>")

add("transfer_model", "TransferModel", [
    "- id : String",
    "- senderId : String",
    "- receiverId : String",
    "- fileName : String",
    "- fileSize : int",
    "- encryptedAESKey : String",
    "- iv : String",
    "- encryptedFileUrl : String",
    "- status : TransferStatus",
    "- sessionActive : bool",
], [
    "+ fromDoc(doc)",
    "+ toCreateMap(downloadUrl)",
], stereotype="<<model>>")

add("notification_model", "NotificationModel", [
    "- id : String",
    "- toUserId : String",
    "- fromUsername : String",
    "- message : String",
    "- type : NotificationType",
    "- transferId : String?",
    "- read : bool",
], [
    "+ fromMap(id, data)",
    "+ toCreateMap()",
], stereotype="<<model>>")

add("auth_repo", "AuthRepository", [
    "- currentUid : String?",
    "- currentUser : User?",
], [
    "+ register(username, email, ...)",
    "+ loginWithUsername(username, pwd)",
    "+ signInWithGoogle()",
    "+ generateAndStoreKeyPair()",
    "+ regenerateKeyPair(uid)",
    "+ getPrivateKeyJson()",
    "+ streamUserProfile(uid)",
], stereotype="<<repository>>")

add("key_repo", "KeyRepository", [], [
    "+ searchUsers(query)",
    "+ sendPublicKey(toUserId, ...)",
    "+ selectSenderHandshake(senderUid)",
    "+ assignTransferRole(partnerUid, ...)",
    "+ endSessionCleanup(...)",
    "+ wipeAllSessionKeys(uid)",
    "+ streamHandshakesForSender()",
], stereotype="<<repository>>")

add("handshake_repo", "HandshakeRepository", [], [
    "+ sendProposal(partnerUid, ...)",
    "+ acceptProposal(docId, proposerId)",
    "+ rejectProposal(docId)",
    "+ disconnectFromUser(partnerUid)",
    "+ streamIncomingPending()",
    "+ streamHandshakeWithUser(partnerUid)",
], stereotype="<<repository>>")

add("transfer_repo", "TransferRepository", [], [
    "+ generateId()",
    "+ uploadAndCreate(bytes, ...)",
    "+ getTransfer(transferId)",
    "+ markReceived(transferId)",
    "+ downloadEncryptedFile(transferId)",
    "+ writeAuditLog(...)",
    "+ watchPendingTransfers(uid)",
], stereotype="<<repository>>")

add("cleanup_repo", "CleanupRepository", [], [
    "+ initiateReceiverCleanup(...)",
    "+ watchTransferForDeletion(id)",
    "+ completeReceiverCleanup(...)",
], stereotype="<<repository>>")

add("user_repo", "UserRepository", [], [
    "+ updateUser(uid, fields)",
    "+ streamUser(userId)",
    "+ isFriend(userId, otherUserId)",
], stereotype="<<repository>>")

add("admin_repo", "AdminRepository", [], [
    "+ streamTotalTransfers()",
    "+ streamTotalUsers()",
    "+ streamAllUsers()",
    "+ setUserActiveStatus(uid, active)",
    "+ streamSecurityAuditLog()",
], stereotype="<<repository>>")

add("encryption_service", "EncryptionService", [
    "- _liveSessionUid : String?",
], [
    "+ secureRandomBytes(length)",
    "+ encryptAesGcm(plaintext)",
    "+ decryptAesGcm(ciphertext, key, iv)",
    "+ generateRsaKeyPairSync()",
    "+ rsaEncrypt(publicKey, data)",
    "+ rsaDecrypt(privateKey, ciphertext)",
    "+ setupReceiverSession(uid)",
    "+ closeReceiverSession(uid)",
], stereotype="<<utility, static>>")

add("transfer_service", "TransferService", [
    "- kChunkSize : int = 65536",
], [
    "+ readFile(filePath)",
    "+ readFileWithProgress(filePath, ...)",
    "+ readChunked(filePath)",
], stereotype="<<utility, static>>")

add("session_manager", "SessionManager", [
    "- state : SessionState",
], [
    "+ selectSender(uid, username)",
    "+ clearSender()",
    "+ wipeSession(onBuffersWipe)",
    "+ handleLifecycleState(state)",
    "+ bindEncryptionService(uid)",
])

add("security_mixin", "SecurityLifecycleMixin", [
    "- _radioactiveBuffers : List<Uint8List>",
], [
    "+ registerBuffer(buffer)",
    "+ unregisterBuffer(buffer)",
    "+ wipeAll()",
], stereotype="<<mixin>>")

add("biometric_helper", "BiometricHelper", [], [
    "+ authenticate(reason)",
], stereotype="<<utility, static>>")


# ---------------------------------------------------------------------------
# Layout — 4-column grid, grouped by architectural layer.
# ---------------------------------------------------------------------------

GRID = [
    ["user_model", "transfer_model", "notification_model", "auth_repo"],
    ["key_repo", "handshake_repo", "transfer_repo", "cleanup_repo"],
    ["user_repo", "admin_repo", "encryption_service", "transfer_service"],
    ["session_manager", "security_mixin", "biometric_helper", None],
]

COL_GAP = 110
ROW_GAP = 110
N_ROWS = len(GRID)
N_COLS = len(GRID[0])
col_x = [c * (CLASS_W + COL_GAP) for c in range(N_COLS)]
COL_GUTTER_X = [col_x[c] + CLASS_W + COL_GAP / 2 for c in range(N_COLS - 1)]

pos = {}
row_y = 30
row_top = []
row_bottom = []
elements = []
for r, row in enumerate(GRID):
    row_boxes = [classes[k] for k in row if k]
    max_h = max(b.h for b in row_boxes)
    row_top.append(row_y)
    row_bottom.append(row_y + max_h)
    for c, key in enumerate(row):
        if key is None:
            continue
        box = classes[key]
        box.x = col_x[c]
        box.y = row_y + (max_h - box.h) / 2  # vertically center within row band
        pos[key] = (r, c)
    row_y += max_h + ROW_GAP

ROW_GUTTER_Y = [(row_bottom[r] + row_top[r + 1]) / 2 for r in range(N_ROWS - 1)]

for box in classes.values():
    elements.extend(box.build())


# ---------------------------------------------------------------------------
# Relationships
# ---------------------------------------------------------------------------

# Associations — solid line, multiplicities, label describes the verb.
assoc = [
    ("auth_repo", "user_model", "creates / streams", "1", "0..1"),
    ("key_repo", "user_model", "searches", "1", "0..*"),
    ("handshake_repo", "user_model", "proposer / partner", "0..*", "0..*"),
    ("transfer_repo", "transfer_model", "creates / reads", "1", "0..*"),
    ("cleanup_repo", "transfer_model", "deletes", "1", "1"),
    ("transfer_repo", "notification_model", "creates", "1", "0..*"),
    ("key_repo", "notification_model", "creates", "1", "0..*"),
    ("handshake_repo", "notification_model", "creates", "1", "0..*"),
]

# Monitoring dependencies (admin dashboard reads, doesn't own the data).
monitor = [
    ("admin_repo", "user_model", "monitors"),
    ("admin_repo", "transfer_model", "monitors"),
]

# <<uses>> dependencies — dashed, gray-green to distinguish from associations.
uses = [
    ("auth_repo", "encryption_service", "<<uses>>"),
    ("transfer_repo", "transfer_service", "<<uses>>"),
    ("session_manager", "encryption_service", "<<uses>>"),
    ("session_manager", "security_mixin", "<<uses (callback)>>"),
]

# Pre-pass: register every connection's ports/gutters *before* building any of
# them, so take_port()/take_lane() know the true slot count up front and can
# space connections evenly instead of guessing as they go.
for a, b, *_ in assoc:
    register_route(a, b)
for a, b, *_ in monitor:
    register_route(a, b)
for a, b, *_ in uses:
    register_route(a, b)

for a, b, label, ma, mb in assoc:
    elements.extend(connect_ortho(a, b, label=label,
                                  color="#1971c2", dashed=False, mult_a=ma, mult_b=mb))
for a, b, label in monitor:
    elements.extend(connect_ortho(a, b, label=label, color="#e8590c", dashed=True))
for a, b, label in uses:
    elements.extend(connect_ortho(a, b, label=label, color="#2f9e44", dashed=True))


# ---------------------------------------------------------------------------
# Title, subtitle, design notes, legend
# ---------------------------------------------------------------------------

doc_title = text(0, -190, "Figure 4.X (Revised) — CrypTransfer Class Diagram",
                  fontSize=22, fontFamily=1, color="#1e1e1e")
doc_subtitle = text(
    0, -158,
    "Updated from the original thesis class diagram to match the live Flutter + "
    "Firebase implementation (Repository pattern over Cloud Firestore / Storage).",
    fontSize=14, fontFamily=2, color="#495057",
)
note_raw = (
    "Note: No central SystemController — UI screens/controllers (LoginScreen, SenderScreen, "
    "ReceiverScreen, AdminDashboard, ...) call repositories and services directly. No TLSChannel class — "
    "TLS is handled transparently by the Firebase SDKs over HTTPS. No persistent RSAKeys/AESKey/File "
    "entities — the RSA public key lives inline on UserModel.publicKey, the AES key+IV are ephemeral "
    "(never persisted in plaintext, only RSA-wrapped inside TransferModel.encryptedAESKey), and chunked "
    "file I/O is handled by static TransferService helpers rather than a File model. No generic Database "
    "facade — 7 specialized repositories wrap Cloud Firestore/Storage instead of one God class. The "
    "thesis CleanupManager became two collaborating classes: CleanupRepository (Firestore writes) + "
    "SecurityLifecycleMixin (in-memory zero-remanence buffer wipe)."
)
note = text(0, -130, wrap(note_raw, 150), fontSize=12, fontFamily=2, color="#495057")
legend = text(
    0, -10,
    "Solid arrow = association (multiplicity shown)      "
    "Dashed orange arrow = monitors / read-only dependency      "
    "Dashed green arrow = <<uses>> dependency",
    fontSize=12, fontFamily=2, color="#1e1e1e",
)

elements.insert(0, legend)
elements.insert(0, note)
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

out_path = r"C:\Users\navve\projects\cryptransfer\.claude\skills\excalidraw-diagram\references\cryptransfer_class_v2.excalidraw"
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(scene, f, indent=2)
print(f"Wrote {len(elements)} elements to {out_path}")
