# UAT: Proposal Accept/Reject Flow — Dialogs Freeze Fix

**Test Date:** 2026-05-26  
**Fix:** Commit 92e7ebc — Remove SetOptions(merge: true) from acceptProposal()  
**Deployment:** Firestore rules deployed (friendships bidirectional write rule live)

## Test Setup

**Emulator A (User A):** emulator-5554  
**Emulator B (User B):** emulator-5556  

Test accounts to be created during UAT.

## Test Scenarios

### Scenario 1: Send Proposal from User A to User B

**Steps:**
1. User A: Login/Register
2. User A: Go to Find Friends
3. User A: Search for User B
4. User A: Tap "Send" to create connection proposal
5. Verify: No UI freeze during send

**Expected Result:** 
- ✓ Proposal appears in User B's "Pending Requests"
- ✓ User A sees "Pending" status
- ✓ No error messages

---

### Scenario 2: Accept Proposal (User B)

**Steps:**
1. User B: Check "Pending Requests" section
2. User B: Find proposal from User A
3. User B: Tap "Accept" button
4. **CRITICAL:** Observe for UI freeze

**Expected Result:**
- ✓ UI remains responsive (no freeze)
- ✓ Operation completes in < 2 seconds
- ✓ No error messages in logs
- ✓ Both users see "Connected" status
- ✓ Dialog/confirmation appears (if implemented)

**What would indicate the fix failed:**
- ✗ UI becomes unresponsive after tapping Accept
- ✗ Accept button spinning indefinitely (>5 seconds)
- ✗ PERMISSION_DENIED error in logs
- ✗ Friendships document not created in Firestore

---

### Scenario 3: Reject Proposal (Optional)

**Steps:**
1. User A sends another proposal
2. User B: Tap "Reject" button
3. Observe for freeze/errors

**Expected Result:**
- ✓ UI stays responsive
- ✓ Proposal disappears from pending list
- ✓ Status updates to "Rejected"

---

### Scenario 4: Bidirectional Status Verification

**Steps:**
1. After successful accept, check Firestore:
   - `users/{userA_uid}/friendships/{userB_uid}` → status: "accepted"
   - `users/{userB_uid}/friendships/{userA_uid}` → status: "accepted"

**Expected Result:**
- ✓ Both documents exist with status="accepted"
- ✓ No partial writes (both or neither)

---

## Observations & Findings

### Console Logs to Monitor

Watch for:
- ✗ `PERMISSION_DENIED` errors
- ✗ Timeouts or hanging operations
- ✗ Exceptions in `acceptProposal()`
- ✓ Successful Firestore writes
- ✓ Sub-100ms frame times (no jank)

### UI Responsiveness Checks

- Can you tap other buttons while operation is in progress?
- Does the button show loading state?
- Does the state clear after 2 seconds?
- Any flicker or visual glitches?

---

## Results

(To be filled during UAT)

### Scenario 1: Send Proposal
- Status: ________
- Duration: ________
- Issues: ________

### Scenario 2: Accept Proposal (CRITICAL)
- Status: ________
- Duration: ________
- UI Freeze: YES / NO
- Errors: ________

### Scenario 3: Reject Proposal
- Status: ________
- Duration: ________
- Issues: ________

### Scenario 4: Firestore Verification
- User A doc: ________
- User B doc: ________
- Both created: YES / NO

---

## Final Verdict

**Fix Verified:** YES / NO  
**Ready for Release:** YES / NO  
**Blockers:** ________
