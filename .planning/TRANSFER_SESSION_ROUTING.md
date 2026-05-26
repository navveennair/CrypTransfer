# Transfer Session Routing & Navigation Flow

## 1. Navigation Entry Point — HomeScreen RolePickerSheet

**Trigger:** User taps a connected partner's name in Active Connections list

**Location:** `lib/presentation/home/home_screen.dart:230-299`

**Action:** Shows a modal bottom sheet with role selection

```dart
showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _RolePickerSheet(
    partnerUid: partnerUid,
    partnerUsername: partnerUsername,
    keyRepository: _connService,
    onSendFile: () async { ... },      // ← "Send File" button
    onReceiveFile: () async { ... },   // ← "Receive File" button
  ),
);
```

---

## 2. Role Determination & Navigation Targets

### 2.1 SEND FILE Path

**Code Location:** `lib/presentation/home/home_screen.dart:247-271`

**Button Press Handler:**
```dart
onSendFile: () async {
  try {
    // Step 1: Assign transfer role (sets senderUid/receiverUid on handshake doc)
    final handshakeDocId = await _connService.assignTransferRole(
      partnerUid: partnerUid,
      isSender: true,  // ← SENDER role
    );
    if (!context.mounted) return;
    
    // Step 2: Close role picker sheet
    Navigator.pop(context);
    
    // Step 3: Push SenderScreen to navigation stack
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SenderScreen(
          preFilledPartnerUid: partnerUid,
          preFilledPartnerUsername: partnerUsername,
          handshakeDocId: handshakeDocId,  // ← Role assignment ID
        ),
      ),
    );
  } catch (e) {
    // Error handling...
  }
}
```

**Target Screen:** `SenderScreen` (lib/presentation/sender/sender_screen.dart:34)

---

### 2.2 RECEIVE FILE Path

**Code Location:** `lib/presentation/home/home_screen.dart:272-296`

**Button Press Handler:**
```dart
onReceiveFile: () async {
  try {
    // Step 1: Assign transfer role (sets senderUid/receiverUid on handshake doc)
    final handshakeDocId = await _connService.assignTransferRole(
      partnerUid: partnerUid,
      isSender: false,  // ← RECEIVER role
    );
    if (!context.mounted) return;
    
    // Step 2: Close role picker sheet
    Navigator.pop(context);
    
    // Step 3: Push ReceiverScreen to navigation stack
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReceiverScreen(
          preFilledSenderUid: partnerUid,
          preFilledSenderUsername: partnerUsername,
          handshakeDocId: handshakeDocId,  // ← Role assignment ID
        ),
      ),
    );
  } catch (e) {
    // Error handling...
  }
}
```

**Target Screen:** `ReceiverScreen` (lib/presentation/receiver/receiver_screen.dart:22)

---

## 3. Role Determination Logic

**Question:** How does the UI determine sender vs receiver?

**Answer:** **Not dynamically** — they are **completely separate view files**.

### 3.1 Separate Screen Classes

| Aspect | SenderScreen | ReceiverScreen |
|--------|--------------|----------------|
| **File** | `lib/presentation/sender/sender_screen.dart` | `lib/presentation/receiver/receiver_screen.dart` |
| **Class** | `SenderScreen extends StatefulWidget` | `ReceiverScreen extends StatefulWidget` |
| **Responsibility** | Upload encrypted file, track progress | Download & decrypt file |
| **Constructor Args** | `preFilledPartnerUid`, `preFilledPartnerUsername`, `handshakeDocId` | `preFilledSenderUid`, `preFilledSenderUsername`, `handshakeDocId` |

### 3.2 No Unified Stepper

**NOT a shared view like:** `TransferStepperScreen(role: 'sender')`

**Instead:** Two completely independent widgets with their own:
- State management
- UI layouts
- Service initialization
- Stream listeners

---

## 4. Services & Controllers Initialization

### 4.1 SenderScreen Initialization

**Location:** `lib/presentation/sender/sender_screen.dart:50-109`

```dart
class _SenderScreenState extends State<SenderScreen>
    with SecurityLifecycleMixin<SenderScreen> {  // ← Mixin for buffer wipe
  
  // Services initialized in State (not passed as params)
  final _connService = KeyRepository();           // ← RSA key mgmt
  final _transferRepo = TransferRepository();     // ← File transfer CRUD
  
  // State fields
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _handshakeSub;
  String? _selectedReceiverPublicKeyJson;
  PlatformFile? _file;
  Uint8List? _encryptedBytes;
  Uint8List? _aesKey;
  Uint8List? _iv;
  
  // Progress tracking
  final _progressCtrl = StreamController<double>.broadcast();
  StreamSubscription<double>? _progressSub;
  
  // Receiver readiness gate (Phase 6)
  bool _receiverReady = false;
  Timer? _readinessTimer;
  
  @override
  void initState() {
    super.initState();
    _handshakeDocId = widget.handshakeDocId;
    _startHandshakeListener();  // ← Listen for receiver's RSA public key
    
    if (widget.preFilledPartnerUid != null) {
      // Pre-filled from role picker — skip sender selection sheet
      setState(() {
        _receiverId = widget.preFilledPartnerUid;
        _receiverUsername = widget.preFilledPartnerUsername ?? 'Partner';
      });
    }
    
    _progressSub = _progressCtrl.stream.listen((p) {
      if (mounted) setState(() => _encryptionProgress = p);
    });
  }
}
```

**Controllers/Services:**
- ✅ `KeyRepository` — RSA key operations
- ✅ `TransferRepository` — Firestore transfer CRUD
- ✅ `SecurityLifecycleMixin<SenderScreen>` — Buffer zero-wipe on dispose
- ✅ `StreamController<double>` — Progress broadcast stream

---

### 4.2 ReceiverScreen Initialization

**Location:** `lib/presentation/receiver/receiver_screen.dart:38-109`

```dart
class _ReceiverScreenState extends State<ReceiverScreen>
    with SecurityLifecycleMixin<ReceiverScreen>, WidgetsBindingObserver {
  
  // Services initialized in State
  final _authService = AuthRepository();          // ← Auth & key vault
  final _connService = KeyRepository();           // ← Connection mgmt
  final _transferRepo = TransferRepository();     // ← Transfer CRUD
  final _sessionManager = SessionManager();       // ← Kill-switch orchestrator
  
  // Mailbox state
  bool _isReadyToReceive = false;
  bool _isTogglingReady = false;
  
  // Sender selection state
  List<UserModel> _connectedFriends = [];
  StreamSubscription<List<UserModel>>? _friendsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _incomingHandshakeSub;
  
  // Transfer state
  String? _incomingTransferId;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _transferStream;
  
  UserModel? _pendingPrefilledSender;  // ← Deferred until mailbox open
  
  @override
  void initState() {
    super.initState();
    _handshakeDocId = widget.handshakeDocId;
    
    WidgetsBinding.instance.addObserver(this);  // ← Lifecycle observer
    _sessionManager.stateNotifier.addListener(_onSessionStateChanged);  // ← Kill-switch listener
    
    _checkKeyStatus().then((_) {
      if (mounted && widget.preFilledSenderUid != null) {
        // Defer sender selection until mailbox is open (D-14)
        setState(() {
          _pendingPrefilledSender = UserModel(
            uid: widget.preFilledSenderUid!,
            username: widget.preFilledSenderUsername ?? '',
            email: '',
            phone: '',
          );
        });
      }
    });
    
    _subscribeToFriends();
    _loadReadyToReceiveState();
  }
  
  @override
  void dispose() {
    _friendsSub?.cancel();
    _incomingHandshakeSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _sessionManager.stateNotifier.removeListener(_onSessionStateChanged);
    EncryptionService.unbindSession();
    _sessionManager.dispose();
    super.dispose();
  }
}
```

**Controllers/Services:**
- ✅ `AuthRepository` — User profile & key vault
- ✅ `KeyRepository` — Handshake & connection mgmt
- ✅ `TransferRepository` — Transfer metadata CRUD
- ✅ `SessionManager` — Session state machine + kill-switch
- ✅ `WidgetsBindingObserver` — App lifecycle (background/foreground)
- ✅ `SecurityLifecycleMixin<ReceiverScreen>` — Buffer zero-wipe on dispose

---

## 5. Sub-Screen Navigation (Transfer Phase)

### 5.1 Sender: Upload Phase

**Trigger:** User selects file and clicks "Encrypt & Send"

**Code:** `lib/presentation/sender/sender_screen.dart:427-444`

```dart
Navigator.push(
  context,
  PageRouteBuilder(
    pageBuilder: (_, anim, _) => TransferProgressScreen(
      transferId: transferId,
      encryptedBytes: encryptedBytesCopy,
      fileName: file.name,
      fileSize: file.size,
      receiverUsername: receiverUsername,
      receiverId: receiverId,
      senderId: senderId,
      encryptedAESKeyB64: encryptedAESKeyB64,
      ivB64: ivB64,
    ),
    transitionsBuilder: (_, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
  ),
);
```

**Target Screen:** `TransferProgressScreen` (lib/presentation/sender/transfer_progress_screen.dart:16)

**Services Initialized:**
- `TransferRepository` — Upload tracking
- `SecurityLifecycleMixin` — Buffer wipe on abort
- Non-repudiation listener — Tracks `receiverStatus` changes

---

### 5.2 Receiver: Download Phase

**Trigger:** Receiver receives incoming transfer notification (stream fires)

**Code:** `lib/presentation/receiver/receiver_screen.dart:173-182`

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => ReceiverTransferScreen(
      transferId: id,
      fileName: name,
      sessionManager: _sessionManager,  // ← Kill-switch propagation
    ),
  ),
);
```

**Target Screen:** `ReceiverTransferScreen` (lib/presentation/receiver/receiver_transfer_screen.dart:18)

**Services Initialized:**
- `TransferRepository` — Download & metadata
- `AuthRepository` — Sender username lookup
- `SessionManager` — Kill-switch listener (passed from parent)
- `SecurityLifecycleMixin` — Buffer wipe on dispose
- Transfer status watcher — Monitors sender abort signals

---

## 6. Navigation Stack Summary

```
HomeScreen (Active Connections list)
    ↓ [User taps partner name]
_RolePickerSheet (modal bottom sheet)
    ├─ onSendFile()
    │   ├─ assignTransferRole(isSender: true)
    │   └─ Navigator.push() → SenderScreen
    │       ├─ [User selects file & encrypts]
    │       └─ Navigator.push() → TransferProgressScreen
    │           ├─ [Upload + non-repudiation listener]
    │           └─ [On success: navigate to SenderSessionEndedScreen]
    │
    └─ onReceiveFile()
        ├─ assignTransferRole(isSender: false)
        └─ Navigator.push() → ReceiverScreen
            ├─ [User opens mailbox (toggle ready)]
            ├─ [Incoming transfer stream fires]
            └─ Navigator.push() → ReceiverTransferScreen
                ├─ [Download & decrypt]
                └─ [On success: navigate to DecryptScreen → EndSessionScreen]
```

---

## 7. Role Assignment Architecture

**Question:** Is there any shared infrastructure for role determination?

**Answer:** **Yes, centralized in KeyRepository:**

```dart
// lib/data/repositories/key_repository.dart:657-698

Future<String> assignTransferRole({
  required String partnerUid,
  required bool isSender,  // ← Role decision point
}) async {
  final currentUid = _uid;
  final senderUid = isSender ? currentUid : partnerUid;
  final receiverUid = isSender ? partnerUid : currentUid;
  
  // Deterministic doc ID for consistency
  final sortedUids = [currentUid, partnerUid]..sort();
  final docId = '${sortedUids[0]}_${sortedUids[1]}';
  
  // Write roles to session-layer handshake collection
  await _db.collection(FirebaseConstants.handshakes).doc(docId).set({
    'receiverId': receiverUid,
    'senderId': senderUid,
    'status': 'handshake_pending',
    'senderUid': senderUid,
    'receiverUid': receiverUid,
    'rolesAssignedAt': FieldValue.serverTimestamp(),
    'createdAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
  
  return docId;  // ← Passed to SenderScreen/ReceiverScreen
}
```

**The `isSender` boolean parameter is the only role determination point.**

---

## 8. Key Implementation Details

### Separate vs. Unified Approach

```
ACTUAL DESIGN (Separate Screens):
├─ SenderScreen (lib/presentation/sender/)
│  ├─ Build stepper UI (file select → encrypt → upload)
│  ├─ Manage local encryption state
│  └─ Handle upload + stream listener lifecycle
│
└─ ReceiverScreen (lib/presentation/receiver/)
   ├─ Build stepper UI (key setup → mailbox → sender selection → receive)
   ├─ Manage session + kill-switch
   └─ Handle incoming transfer detection

NOT LIKE THIS (Unified):
└─ TransferScreen(role: 'sender' | 'receiver')
   ├─ if (role == 'sender') { ... }
   └─ else { ... }
```

### Why Separate?

1. **Asymmetric Responsibilities** — Sender uploads; Receiver downloads
2. **Different Lifecycles** — Sender is ephemeral; Receiver is persistent (mailbox open)
3. **Kill-Switch Complexity** — Receiver owns session termination; Sender reacts reactively
4. **Stream Dependencies** — Different Firestore listeners (sender: handshake stream; receiver: transfer stream + kill-switch stream)

---

## 9. Firestore Collections Involved

| Collection | Role | Written By | Triggering Event |
|------------|------|-----------|-----------------|
| `handshakes` | Session-layer role assignment | `KeyRepository.assignTransferRole()` | User picks "Send"/"Receive" |
| `transfers` | Active transfer metadata | `TransferRepository` after encryption | File upload starts |
| `users/{uid}/audit_logs` | Non-repudiation log | `TransferRepository` | Transfer completes |

---

