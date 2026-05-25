# Session Handoff — Phase 07.1 UAT & Role Assignment

**Date:** 2026-05-26  
**Status:** Mid-implementation — bottleneck fixed, role assignment ready to implement

---

## ✅ What's Done

### 1. Fixed Sender Step 3 Bottleneck
- **Problem:** Sender's Step 3 button was blocked by `IgnorePointer(ignoring: !_receiverReady)`
- **Root Cause:** `receiverReady` was only set when receiver manually called `setReceiverReady()` after selecting a sender
- **Solution:** Automatic `receiverReady: true` when handshake is created IF receiver's mailbox is open
- **Implementation:**
  - `receiver_screen.dart`: calls `setReadyToReceive(true/false)` on mailbox toggle
  - `key_repository.selectSenderHandshake()`: checks receiver's `isReadyToReceive`, sets `handshake.receiverReady` accordingly
  - `key_repository.publishRSAPublicKey()`: same automatic logic
  - Removed manual `_writeReceiverReady()` from receiver selection flow
  - Sender's listener restored to check per-handshake `receiverReady` field

**Commits:**
- `405d7e4` — fix(07.1): receiver readiness now global (reverted)
- `0005e7c` — fix(07.1): per-handshake readiness — auto-signal when mailbox is open ✅
- `825b645` — test(07.1): ready to resume Test 3 with per-handshake fix

### 2. Architecture Decision
- **Rejected:** Global `isReadyToReceive` gate for all senders
- **Implemented:** Per-handshake `receiverReady` coupled to specific sender/receiver pair (cleaner)

### 3. UAT Status
- Test 1: ✅ PASS (Cold Start)
- Test 2: ✅ PASS (Transfer Flow - biometric disabled)
- Test 3: ⏳ PENDING (Decrypt & Save Flow - ready to re-test after fix)
- Test 4: ✅ PASS (Admin Dashboard)
- Test 5: ⏳ BLOCKED (depends on Test 3)
- Test 6: ✅ PASS (Onboarding)

---

## 🔄 What's Next: Role Assignment Architecture

### Requirement
When user clicks partner in HomeScreen → popup shows "Send File" / "Receive File"  
User chooses role → **Update handshake doc with `senderUid` and `receiverUid`**  
Other user's UI locks to opposite role  
If back button → show warning → clear roles → return to HomePage

### Current HomeScreen Structure
- File: `lib/presentation/home/home_screen.dart` lines 1355-1429
- Two buttons: `onSendFile` (line 1357) and `onReceiveFile` (line 1395)
- Both are callbacks passed to a dialog/sheet widget

### Implementation Steps (In Order)

1. **Add method to KeyRepository** (`key_repository.dart`)
   ```dart
   Future<void> setTransferRoles({
     required String handshakeDocId,
     required String senderUid,
     required String receiverUid,
   }) async {
     // Update handshake doc: senderUid, receiverUid
   }
   ```

2. **Update HomeScreen callbacks** (lines 244-256)
   ```dart
   onSendFile: () {
     // Call: setTransferRoles(docId, currentUser, partner)
     // Then: Navigator.push(SenderScreen(...))
   }
   onReceiveFile: () {
     // Call: setTransferRoles(docId, partner, currentUser)
     // Then: Navigator.push(ReceiverScreen(...))
   }
   ```

3. **Add validation in SenderScreen**
   - Fetch handshake doc
   - Verify: `senderUid == currentUser.uid` AND `receiverUid == partner.uid`
   - If mismatch: show error, pop back

4. **Add validation in ReceiverScreen**
   - Fetch handshake doc
   - Verify: `receiverUid == currentUser.uid` AND `senderUid == partner.uid`
   - If mismatch: show error, pop back

5. **Add back button warning**
   - PopScope or WillPopScope on both screens
   - Dialog: "Going back will clear role assignment. Connection remains. Continue?"
   - On confirm: clear `senderUid`/`receiverUid` → navigate to HomePage

### Key Files to Modify
- `lib/data/repositories/key_repository.dart` — add `setTransferRoles()`
- `lib/presentation/home/home_screen.dart` — update callbacks (lines 244-256)
- `lib/presentation/sender/sender_screen.dart` — add role validation
- `lib/presentation/receiver/receiver_screen.dart` — add role validation

### Current Handshake Doc Structure
```
{
  receiverId: <connection initiator>,
  senderId: <connection target>,
  publicKey: <RSA key>,
  status: 'handshake_complete',
  receiverReady: <true if mailbox open>,
  
  // TO ADD:
  senderUid: <who will send the file>,
  receiverUid: <who will receive the file>
}
```

### Role Assignment Logic
- User A clicks "Send File" → `senderUid: A, receiverUid: B`
- User B sees partner chose sender role → UI shows only "Receive File" (locked)
- If User B also wants to send → must go back, break connection, create new one

---

## Quick Reference

**Last commit:** `825b645`  
**Current branch:** main  
**Test file:** `.planning/phases/07.1-layer-decoupling-refactor/07.1-UAT.md`  
**Debug docs:** `.planning/debug/` (check sender-stepper3-button-unresponsive.md)  

**To resume:**
1. Review this handoff
2. Implement KeyRepository.setTransferRoles()
3. Update HomeScreen callbacks
4. Test with manual UAT (Test 3-6)
5. Commit atomic changes
6. Resume /gsd:verify-work 07.1 when ready

