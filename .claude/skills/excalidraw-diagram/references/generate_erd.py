import json, random, time, uuid

def rid():
    return uuid.uuid4().hex[:16]

def seed():
    return random.randint(1, 2**31 - 1)

NOW = int(time.time() * 1000)
elements = []

def rect(x, y, w, h, stroke="#1e1e1e", bg="transparent"):
    el = {
        "id": rid(), "type": "rectangle", "x": x, "y": y, "width": w, "height": h,
        "angle": 0, "strokeColor": stroke, "backgroundColor": bg, "fillStyle": "solid",
        "strokeWidth": 2, "strokeStyle": "solid", "roughness": 1, "opacity": 100,
        "groupIds": [], "frameId": None, "roundness": {"type": 3}, "seed": seed(),
        "version": 1, "versionNonce": seed(), "isDeleted": False, "boundElements": None,
        "updated": NOW, "link": None, "locked": False,
    }
    elements.append(el)
    return el

def diamond(x, y, w, h, stroke="#1e1e1e", bg="#fff9db"):
    el = {
        "id": rid(), "type": "diamond", "x": x, "y": y, "width": w, "height": h,
        "angle": 0, "strokeColor": stroke, "backgroundColor": bg, "fillStyle": "solid",
        "strokeWidth": 2, "strokeStyle": "solid", "roughness": 1, "opacity": 100,
        "groupIds": [], "frameId": None, "roundness": {"type": 2}, "seed": seed(),
        "version": 1, "versionNonce": seed(), "isDeleted": False, "boundElements": None,
        "updated": NOW, "link": None, "locked": False,
    }
    elements.append(el)
    return el

def text(x, y, s, size=16, align="left", color="#1e1e1e", family=2):
    lines = s.split("\n")
    w = max(len(l) for l in lines) * size * 0.55
    h = len(lines) * (size * 1.25)
    el = {
        "id": rid(), "type": "text", "x": x, "y": y, "width": w, "height": h,
        "angle": 0, "strokeColor": color, "backgroundColor": "transparent",
        "fillStyle": "solid", "strokeWidth": 2, "strokeStyle": "solid", "roughness": 1,
        "opacity": 100, "groupIds": [], "frameId": None, "roundness": None,
        "seed": seed(), "version": 1, "versionNonce": seed(), "isDeleted": False,
        "boundElements": None, "updated": NOW, "link": None, "locked": False,
        "text": s, "fontSize": size, "fontFamily": family, "textAlign": align,
        "verticalAlign": "top", "baseline": h * 0.8, "containerId": None,
        "originalText": s, "lineHeight": 1.25,
    }
    elements.append(el)
    return el

def line(points_abs, start_arrow=None, end_arrow=None, stroke="#1e1e1e", dash=False):
    x0, y0 = points_abs[0]
    pts = [[px - x0, py - y0] for px, py in points_abs]
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    el = {
        "id": rid(), "type": "arrow", "x": x0, "y": y0,
        "width": max(xs) - min(xs), "height": max(ys) - min(ys),
        "angle": 0, "strokeColor": stroke, "backgroundColor": "transparent",
        "fillStyle": "solid", "strokeWidth": 2,
        "strokeStyle": "dashed" if dash else "solid", "roughness": 1, "opacity": 100,
        "groupIds": [], "frameId": None, "roundness": {"type": 2}, "seed": seed(),
        "version": 1, "versionNonce": seed(), "isDeleted": False, "boundElements": None,
        "updated": NOW, "link": None, "locked": False, "points": pts,
        "lastCommittedPoint": None, "startBinding": None, "endBinding": None,
        "startArrowhead": start_arrow, "endArrowhead": end_arrow,
    }
    elements.append(el)
    return el

def entity(x, y, w, title, rows, stroke="#1971c2"):
    h_title = 38
    h_row = 24
    h = h_title + len(rows) * h_row + 10
    rect(x, y, w, h, stroke=stroke)
    line([(x, y + h_title), (x + w, y + h_title)], stroke=stroke)
    text(x + w / 2, y + 8, title, size=18, align="center", family=1, color=stroke)
    body = "\n".join(rows)
    text(x + 12, y + h_title + 8, body, size=14, family=2)
    return x, y, w, h

def rel(diamond_xy, w, h, label, color="#e8590c"):
    dx, dy = diamond_xy
    diamond(dx, dy, w, h, stroke=color)
    text(dx + w / 2, dy + h / 2 - 8, label, size=13, align="center", family=1, color=color)
    return dx, dy, w, h

def card(x, y, s, color="#e8590c"):
    text(x, y, s, size=13, color=color, family=2)

OPEN = "triangle_outline"

# ── Title ────────────────────────────────────────────────────────────
text(40, -50, "Figure 4.21 (Revised) — CrypTransfer Firestore Data Model", size=22, family=1)
text(40, -22, "Redesigned from the original conceptual ERD to match the live firestore.rules schema", size=14, family=2, color="#495057")

# ── Entities ─────────────────────────────────────────────────────────
ux, uy, uw, uh = entity(40, 40, 260, "User", [
    "userID (PK)",
    "username",
    "email",
    "publicKey",
    "isAdmin",
    "selectedSenderUid (FK -> User)",
])

tx, ty, tw, th = entity(460, 40, 300, "TransferSession", [
    "transferID (PK)",
    "senderID (FK -> User)",
    "receiverID (FK -> User)",
    "fileName, fileSize",
    "encryptedAESKey, iv",
    "status",
    "createdAt",
])

rx, ry, rw, rh = entity(940, 40, 300, "RoleHandshake", [
    "handshakeID (PK)",
    "receiverID (FK -> User)",
    "senderID (FK -> User)",
    "publicKey",
    "status",
    "sentAt",
])

nx, ny, nw, nh = entity(460, 460, 300, "NeutralHandshake", [
    "handshakeID (PK)",
    "proposerID (FK -> User)",
    "partnerID (FK -> User)",
    "status",
    "updatedAt",
])

ax, ay, aw, ah = entity(40, 460, 300, "AuditLog", [
    "logID (PK)",
    "participants[] (FK -> User)",
    "senderID, receiverID",
    "status",
    "timestamp",
])

# ── Relationships ────────────────────────────────────────────────────
# User -> TransferSession : initiates  (User right edge -> TransferSession left edge)
title_mid = uy + 19
d1x, d1y, d1w, d1h = rel((340, title_mid - 22), 110, 44, "initiates")
line([(ux + uw, title_mid), (d1x, title_mid)])
line([(d1x + d1w, title_mid), (tx, title_mid)], end_arrow=OPEN)
card(ux + uw + 8, title_mid - 18, "1")
card(d1x + d1w + 8, title_mid - 18, "1..*")

# User -> RoleHandshake : authorizes (routed beneath row 1, straight into RoleHandshake's bottom edge)
ax2 = ux + uw - 20          # x=260 — User bottom-right attach point
midy = ry + rh + 90         # y=322 — shared horizontal corridor
rhx = rx + rw - 85          # x=1155 — vertical riser into RoleHandshake
d2x, d2y, d2w, d2h = rel((rhx - 130, midy - 22), 130, 44, "authorizes")
line([(ax2, uy + uh), (ax2, midy), (d2x, midy)])
line([(d2x + d2w, midy), (rhx, midy), (rhx, ry + rh)], end_arrow=OPEN)
card(ax2 + 6, uy + uh + 4, "1")
card(rhx + 8, midy - 18, "1..*")

# User -> NeutralHandshake : proposes (corridor below row 1, drops straight into NeutralHandshake's top edge)
px = ux + uw / 2            # x=170 — User bottom-mid attach point
py = ny - 80                # y=380 — shared horizontal corridor
nmidx = nx + nw / 2         # x=610 — NeutralHandshake center
d3x, d3y, d3w, d3h = rel((nmidx - 55, py - 22), 110, 44, "proposes")
line([(px, uy + uh), (px, py), (d3x, py)])
line([(nmidx, d3y + d3h), (nmidx, ny)], end_arrow=OPEN)
card(px + 6, uy + uh + 4, "1")
card(nmidx + 8, d3y + d3h + 4, "0..*")

# User -> AuditLog : generates (corridor below row 1, drops straight into AuditLog's top edge)
gx = ux + 40                # x=80 — User bottom-left attach point
gy = ay - 80                # y=380 — shared horizontal corridor
amidx = ax + aw / 2         # x=190 — AuditLog center
d4x, d4y, d4w, d4h = rel((amidx - 55, gy - 22), 110, 44, "generates")
line([(gx, uy + uh), (gx, gy), (d4x, gy)])
line([(amidx, d4y + d4h), (amidx, ay)], end_arrow=OPEN)
card(gx + 6, uy + uh + 4, "1")
card(amidx + 8, d4y + d4h + 4, "0..*")

# ── Design notes callout ────────────────────────────────────────────
notes = (
    "Design notes (vs. original Fig. 4.21):\n"
    "- File and AESKey are not separate collections; Firestore embeds\n"
    "  fileName/fileSize/encryptedAESKey/iv directly on TransferSession\n"
    "  (denormalized doc model, not 3NF normalization).\n"
    "- RSAKeys is replaced by RoleHandshake (role_handshake collection) -\n"
    "  per-session RSA exchange, not a standalone key store.\n"
    "- NeutralHandshake is new: the friend/connection layer (neutral_handshakes)\n"
    "  is independent of session-layer RoleHandshake, matching firestore.rules.\n"
    "- AuditLog (users/{uid}/audit_logs) is an immutable, append-only\n"
    "  sub-collection: update is always denied in firestore.rules."
)
text(940, 460, notes, size=13, family=2, color="#343a40")

scene = {
    "type": "excalidraw",
    "version": 2,
    "source": "https://excalidraw.com",
    "elements": elements,
    "appState": {"viewBackgroundColor": "#ffffff", "gridSize": 20},
    "files": {},
}

with open("cryptransfer_erd.excalidraw", "w", encoding="utf-8") as f:
    json.dump(scene, f, indent=2)

print(f"wrote cryptransfer_erd.excalidraw with {len(elements)} elements")
