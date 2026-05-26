# Firebase Rules — Architectural Analysis & Alignment

## Current Database Architecture

**Transfer ↔ Handshake Relationship:**
- **No explicit reference:** Transfer doc does NOT store `handshakeDocId`
- **Relationship:** Implicit via `senderId` + `receiverId` pair
- **Query pattern:** During cleanup, code queries for handshake using `getActiveHandshakeDocId(senderId, receiverId)`

**Atomic Guarantee:**
- `selectSenderHandshake()` uses Firestore `WriteBatch`:
  1. Write `users/{receiver}.selectedSenderUid = sender`
  2. Write `handshakes/{autoId}` with RSA key
  - Both succeed together or both fail — **no partial writes**

**Session Lifecycle:**
1. Receiver calls `selectSenderHandshake()` → WriteBatch (both docs)
2. Sender queries `streamHandshakesForSender()` → discovers handshake doc
3. Sender calls `uploadAndCreate()` → creates transfer doc
4. Rule validates `users/{receiver}.selectedSenderUid == sender`
5. Cleanup queries for handshake by `senderId + receiverId`, then deletes both

---

## Rule-Code Contradictions Found

### **Contradiction 1: Handshakes Create Rule** ⚠️ [CRITICAL]

**Current Rule (line 129-131):**
```firestore
allow create: if isAuthenticated() &&
               (request.resource.data.receiverId == request.auth.uid ||
                request.resource.data.senderId == request.auth.uid);
```

**What it allows:** Both receiver AND sender can create handshake docs

**What the code does:** ONLY receiver creates via `selectSenderHandshake()`
- Sender NEVER calls any handshake create method
- `assignTransferRole()` deprecated (no-op in Phase 07.1 migration)

**Risk:** Sender could create a fake handshake doc directly, bypassing receiver authorization

**Alignment Issue:** Rule is overly permissive compared to actual code behavior

---

### **Contradiction 2: Transfers Create Rule** ✅ [SAFE]

**Current Rule (line 98-106):**
```firestore
allow create: if isAuthenticated() &&
               request.resource.data.senderId == request.auth.uid &&
               (
                 get(...users/{receiverId}...).data['selectedSenderUid'] == request.auth.uid
                 || exists(...neutral_handshakes...)
               );
```

**What it validates:** `selectedSenderUid == sender`

**Why it's safe:** 
- `selectSenderHandshake()` WriteBatch atomically writes BOTH:
  - `users/{receiver}.selectedSenderUid = sender`
  - `handshakes/{autoId}`
- If WriteBatch succeeds, both exist; if it fails, neither exists
- Rule validates the user doc field (sufficient proof of authorization)

**Architecture alignment:** Rule doesn't store `handshakeDocId` in transfer doc, which aligns with current implicit-reference design

**Decision:** KEEP AS-IS — no change needed

---

## Recommended Fix (Minimal, Aligned with Architecture)

### **Fix Contradiction 1 Only**

**Change handshakes create rule to receiver-only:**

```firestore
// BEFORE (overly permissive)
allow create: if isAuthenticated() &&
               (request.resource.data.receiverId == request.auth.uid ||
                request.resource.data.senderId == request.auth.uid);

// AFTER (aligned with code)
allow create: if isAuthenticated() &&
               request.resource.data.receiverId == request.auth.uid;
```

**Why this works:**
- Only receiver calls `selectSenderHandshake()`
- Receiver always sets `receiverId == currentUser`
- Sender cannot create handshake docs (intentional)
- Maintains the implicit `senderId + receiverId` relationship pattern

**Impact:**
- ✅ Closes security gap (sender cannot create fake handshake)
- ✅ Aligns rule with actual code behavior
- ✅ No database schema changes required
- ✅ No changes to application code needed
- ✅ No changes to query patterns or cleanup logic

---

## Why NOT Fix Contradiction 2

**Option A: Add `handshakeDocId` to transfer doc**
- Pros: Explicit reference validation in rule
- Cons: Requires architectural refactor:
  - Modify `TransferModel` schema
  - Update `uploadAndCreate()` to store handshakeDocId
  - Update cleanup to use stored ID instead of query
  - Change Firestore rule to validate reference
  - **Breaking change to transfer document structure**

**Option B: Keep implicit reference (current)**
- Pros: Leverages WriteBatch atomicity (no partial writes)
- Pros: Query pattern is standard for lookup in cleanup
- Pros: Rule validation via `selectedSenderUid` field is sufficient
- Cons: Rule doesn't explicitly validate handshake doc exists
- **Accepted risk**: WriteBatch atomicity prevents the edge case

**Decision:** Keep Option B (current architecture)

---

## Summary

| Contradiction | Severity | Fix | Impact |
|---------------|----------|-----|--------|
| Handshakes create rule | HIGH | Change to receiver-only | Rule now aligns with code; closes security gap |
| Transfers create rule | LOW | No fix needed | WriteBatch atomicity + rule validation sufficient |

**Total changes:** 1 rule line (4 words removed)
**Schema changes:** None
**Code changes:** None
**Architectural impact:** Improved security, no behavior change
