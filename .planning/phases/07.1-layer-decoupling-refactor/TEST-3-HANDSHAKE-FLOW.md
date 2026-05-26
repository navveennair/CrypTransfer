# Test 3: Automated Handshake Flow (Fully Automated)

## Expected Automated Flow

### Receiver Side
1. Open HomeScreen
2. Tap connection → role picker
3. Tap "Receive File" → navigates to ReceiverScreen
   - Step 0: Mailbox toggle OFF → shows "Open Mailbox" prompt
4. Toggle mailbox ON
   - Calls `setReadyToReceive(true)` → global user flag set
   - Firestore: `users/{uid}.isReadyToReceive = true`
5. **Wait** - receiver should see "Waiting for sender..." OR active connections list
6. When sender has the receiver selected → **automatic** sender selection from friends list

### Sender Side  
1. Open HomeScreen
2. Tap connection → role picker
3. Tap "Send File" → navigates to SenderScreen **automatically with receiver pre-filled**
   - `preFilledPartnerUid` = partner's UID
   - `preFilledPartnerUsername` = partner's name
4. Step 0: "Waiting for Secure Connection…" 
   - **Stream listener is ACTIVE** (listening to `handshakes WHERE senderId == currentUser`)
   - **No manual clicking required here** 
5. When receiver selects sender → `selectSenderHandshake()` publishes RSA key
   - **Handshake doc updates with:**
     - `publicKey` = receiver's RSA public key
     - `status` = 'handshake_complete'
     - `receiverReady` = true (auto if mailbox open)
6. Sender's stream fires → `_onHandshakeUpdate()` processes doc
   - Sets `_receiverId = receiverUid` ✓
   - Sets `_receiverUsername = receiverUsername` ✓
   - Sets `_receiverReady = true` ✓
   - **Steps 1-4 automatically unlock** (no longer grayed out)
7. **No manual clicking** - sender proceeds to Step 1 (Select File)

---

## Test Execution

### Start Emulator 1 (Receiver)
```
adb devices
# Note the emulator (e.g., emulator-5554)
flutter run -d emulator-5554
```

1. Log in as **User B** (receiver)
2. Home → Find Friends → Find **User A**
3. Tap connection → **"Receive File"**
4. **Wait for ReceiverScreen to load** (Step 0 should show mailbox toggle)
5. **Toggle mailbox ON** ← THIS IS THE KEY TRIGGER
6. **Stay on this screen** — watch for when sender subscribes

### Start Emulator 2 (Sender)
```
flutter run -d emulator-5555  # or different emulator port
```

1. Log in as **User A** (sender)
2. Home → Find Friends → Find **User B**
3. Tap connection → **"Send File"** 
4. **SenderScreen should open with:**
   - ✅ Receiver pre-filled (shows "Waiting for Secure Connection…")
   - ✅ **No sheet or manual selection prompt**
   - ✅ Stream listener active
5. **Sender waits here** — **NO manual clicking needed**

### Complete the Handshake
1. **On Receiver side:** If not already visible, look for sender in "Active Connections" list
2. **On Receiver side:** Tap sender name to select them
   - This calls `selectSenderHandshake()` → publishes RSA key
   - Firestore: `handshakes/{docId}.publicKey = receiver's RSA public key`
   - Firestore: `handshakes/{docId}.status = 'handshake_complete'`
   - Firestore: `handshakes/{docId}.receiverReady = true`
3. **On Sender side:** 
   - ✅ Stream fires within <2 seconds
   - ✅ "Waiting for Secure Connection" disappears
   - ✅ "Secure Channel Established / Key received from @User B" appears
   - ✅ Steps 1-4 fade in and become clickable
4. **Sender proceeds to Step 1** (Select File)
   - No blocks, no manual prompts
   - Just picks a file and continues

---

## Failure Signs (STOP & Debug)

- ❌ SenderScreen shows manual "Find Receiver" sheet (should NOT appear)
- ❌ Receiver pre-fill isn't set (username/UID blank)
- ❌ Step 0 shows "Waiting for Connection" forever (> 5 seconds)
- ❌ Sender can't click Step 1 even after receiver selection
- ❌ Stream doesn't fire after receiver selects sender
- ❌ Handshake doc doesn't get publicKey written
- ❌ Role conflict errors appear

## Success Signs

- ✅ Sender screen opens with receiver name pre-filled
- ✅ "Waiting for Secure Connection" pulsing animation
- ✅ When receiver selects → immediate status change (< 2 sec)
- ✅ Steps 1-4 become enabled
- ✅ Both users can proceed through full transfer

---

## Commits Applied
- `133e2cb` - Fix handshake architecture, simplify queries, add setReceiverReady call
- `ab3469a` - Add explicit handshake_complete status check
