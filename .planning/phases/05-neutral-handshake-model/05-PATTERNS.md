# Phase 5: Neutral Handshake Model - Pattern Map

**Mapped:** 2026-05-12
**Files analyzed:** 5 (1 new, 4 modified)
**Analogs found:** 5 / 5

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `lib/data/repositories/handshake_repository.dart` | repository | CRUD + streaming | `lib/data/repositories/key_repository.dart` | exact |
| `lib/presentation/home/home_screen.dart` | screen/component | event-driven + streaming | `lib/presentation/home/home_screen.dart` (self — restructure) | exact |
| `lib/presentation/sender/sender_screen.dart` | screen | request-response | `lib/presentation/receiver/receiver_screen.dart` (optional param pattern) | role-match |
| `lib/presentation/receiver/receiver_screen.dart` | screen | request-response | `lib/presentation/receiver/receiver_screen.dart` (self — add param) | exact |
| `firestore.rules` | config | — | `firestore.rules` (self — add block) | exact |

---

## Pattern Assignments

### `lib/data/repositories/handshake_repository.dart` (repository, CRUD + streaming)

**Analog:** `lib/data/repositories/key_repository.dart`

**Imports pattern** (`key_repository.dart` lines 1–7):
```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../models/user_model.dart';
```
For `HandshakeRepository`, drop `flutter_secure_storage` (no local key storage needed) and `user_model.dart` (not required). Add nothing new — all imports are already in the project.

**Constructor / dependency injection pattern** (`key_repository.dart` lines 11–28):
```dart
class KeyRepository {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  KeyRepository({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
  })  : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw AuthException('Not authenticated.');
    return uid;
  }
```
Copy verbatim for `HandshakeRepository`. No `FlutterSecureStorage` field needed.

**`FirebaseConstants` constant registration** (`lib/core/constants/firebase_constants.dart` line 13):
```dart
static const String handshakes = 'handshakes';
```
Add a parallel entry: `static const String neutralHandshakes = 'neutral_handshakes';` in the same abstract class. This is the only change to `firebase_constants.dart`.

**WriteBatch for atomic multi-doc writes** (`key_repository.dart` lines 469–500, `selectSenderHandshake()`):
```dart
final batch = _db.batch();

// Write 1 — mark selected sender on the receiver's user document.
batch.set(
  _db.collection(FirebaseConstants.users).doc(_uid),
  {'selectedSenderUid': senderUid},
  SetOptions(merge: true),
);

// Write 2 — publish receiver's public key to the sender.
if (existing.docs.isNotEmpty) {
  batch.update(existing.docs.first.reference, keyPayload);
} else {
  final newRef = _db.collection(FirebaseConstants.handshakes).doc();
  batch.set(newRef, {
    'receiverId': _uid,
    'senderId': senderUid,
    ...keyPayload,
  });
}

await batch.commit();
```
`acceptProposal()` in `HandshakeRepository` follows this same pattern: build batch, add update calls for the primary doc and optionally the mutual doc, then `await batch.commit()`.

**WriteBatch delete pattern** (`key_repository.dart` lines 166–176, `disconnectFriend()`):
```dart
Future<void> disconnectFriend(String friendId) async {
  try {
    final batch = _db.batch();
    batch.delete(_friendshipsOf(_uid).doc(friendId));
    batch.delete(_friendshipsOf(friendId).doc(_uid));
    await batch.commit();
  } on FirebaseException catch (e) {
    throw NetworkException('Failed to disconnect: ${e.message ?? e.code}');
  }
}
```
`cancelProposal(docId)` in `HandshakeRepository` is a single `_db.collection(FirebaseConstants.neutralHandshakes).doc(docId).delete()` wrapped in the same try/catch structure.

**Deterministic doc ID for idempotent upsert** (`key_repository.dart` lines 568–578, `publishRSAPublicKey()`):
```dart
final docId = '${_uid}_$targetUserId';
await _db.collection(FirebaseConstants.handshakes).doc(docId).set({
  ...payload,
}, SetOptions(merge: true));
```
`sendProposal()` uses the same scheme: `final docId = '${_uid}_$partnerUid';` then `.doc(docId).set({...}, SetOptions(merge: true))`. Idempotent re-proposals produce no duplicates.

**Firestore stream pattern** (`key_repository.dart` lines 594–599, `streamHandshakesForSender()`):
```dart
Stream<QuerySnapshot<Map<String, dynamic>>> streamHandshakesForSender() =>
    _db
        .collection(FirebaseConstants.handshakes)
        .where('senderId', isEqualTo: _uid)
        .where('status', isEqualTo: 'handshake_complete')
        .snapshots();
```
All four `HandshakeRepository` stream methods copy this pattern, substituting the collection name and field filters:
- `streamIncomingPending()` — `where('partnerId', isEqualTo: _uid).where('status', isEqualTo: 'pending')`
- `streamActiveConnections()` — `where('proposerId', isEqualTo: _uid)` OR `where('partnerId', isEqualTo: _uid)` combined client-side, or two separate streams merged
- `streamOutgoingPending()` — `where('proposerId', isEqualTo: _uid).where('status', isEqualTo: 'pending')`
- `streamProposalOutcome(docId)` — `_db.collection(...).doc(docId).snapshots()`

**Error handling pattern** (`key_repository.dart` lines 116–119, `sendConnectionRequest()`):
```dart
} on FirebaseException catch (e) {
  throw NetworkException(
      'Connection request failed: ${e.message ?? e.code}');
}
```
Every public method in `HandshakeRepository` wraps its Firestore calls in this identical try/catch. The `NetworkException` type is already defined in `lib/core/errors/app_exceptions.dart`.

---

### `lib/presentation/home/home_screen.dart` (screen, event-driven + streaming)

**Analog:** `lib/presentation/home/home_screen.dart` (self — restructure + additions)

**Existing subscription field pattern** (`home_screen.dart` lines 23–26):
```dart
class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription<Map<String, dynamic>?>? _notifSub;
  OverlayEntry? _bannerEntry;
  String? _lastBannerDocId;
```
Add parallel fields alongside these:
```dart
  StreamSubscription<QuerySnapshot>? _pendingProposalSub;
  String? _lastSeenProposalId;    // deduplication — mirrors _lastBannerDocId
```

**`addPostFrameCallback` listener startup** (`home_screen.dart` line 31):
```dart
WidgetsBinding.instance.addPostFrameCallback((_) => _startNotifListener());
```
Add the handshake listener startup in the same callback:
```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  _startNotifListener();
  _startHandshakeListener();
});
```
This is mandatory — `Overlay.of(context)` requires the widget to be in the tree. Never call it before `addPostFrameCallback`.

**`dispose()` cancel pattern** (`home_screen.dart` lines 35–39):
```dart
@override
void dispose() {
  _notifSub?.cancel();
  _bannerEntry?.remove();
  super.dispose();
}
```
Add `_pendingProposalSub?.cancel();` in the same block.

**`_startNotifListener()` — the listener pattern to mirror** (`home_screen.dart` lines 41–52):
```dart
void _startNotifListener() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  _notifSub =
      NotificationService.latestUnreadStream(uid).listen((notif) {
    if (!mounted || notif == null) return;
    final docId = notif['docId'] as String;
    if (docId == _lastBannerDocId) return;   // deduplication
    _lastBannerDocId = docId;
    _showNotifBanner(notif);
  });
}
```
`_startHandshakeListener()` mirrors this structure, using `docChanges` with `DocumentChangeType.added` and deduplicating by `_lastSeenProposalId`.

**`_showNotifBanner()` — OverlayEntry insertion pattern** (`home_screen.dart` lines 54–86):
```dart
void _showNotifBanner(Map<String, dynamic> notif) {
  _bannerEntry?.remove();
  // ...
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _NotifBanner(
      message: message,
      onDismiss: () {
        entry.remove();
        if (_bannerEntry == entry) _bannerEntry = null;
        // ... mark read
      },
      onTap: () {
        entry.remove();
        if (_bannerEntry == entry) _bannerEntry = null;
        // ... navigate
      },
    ),
  );
  _bannerEntry = entry;
  Overlay.of(context).insert(entry);
}
```
`_showProposalBanner(DocumentSnapshot doc)` copies this structure but passes `onAccept` and `onReject` callbacks instead of `onTap`. The `_ProposalBanner` widget is a new variant of `_NotifBanner` (see below).

**`_NotifBanner` widget — the OverlayEntry content** (`home_screen.dart` lines 400–479):
```dart
class _NotifBanner extends StatefulWidget {
  final String message;
  final VoidCallback onDismiss;
  final VoidCallback onTap;

  const _NotifBanner({
    required this.message,
    required this.onDismiss,
    required this.onTap,
  });

  @override
  State<_NotifBanner> createState() => _NotifBannerState();
}

class _NotifBannerState extends State<_NotifBanner> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 5), () {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
  // ... build: Positioned > Material > GestureDetector > GlassContainer > Row
```
`_ProposalBanner` replaces `onTap: VoidCallback` with `onAccept: VoidCallback` and `onReject: VoidCallback`. The `Timer` auto-dismiss (5 seconds) and `Positioned` layout are copied verbatim. The `GestureDetector` wrapping is removed; instead, the action row inside the `GlassContainer` contains two `TextButton` widgets for Accept and Reject.

**`StreamBuilder` in `build()` — existing pattern** (`home_screen.dart` lines 204–327):
```dart
StreamBuilder<QuerySnapshot>(
  stream: FirebaseFirestore.instance
      .collection(FirebaseConstants.users)
      .doc(FirebaseAuth.instance.currentUser?.uid ?? '')
      .collection(FirebaseConstants.auditLogs)
      .orderBy('loggedAt', descending: true)
      .limit(10)
      .snapshots(),
  builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Padding(
        padding: EdgeInsets.all(20.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final docs = snapshot.data?.docs ?? [];
    if (docs.isEmpty) {
      return GlassContainer(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_outlined, size: 40, color: cs.onSurfaceVariant),
              const SizedBox(height: 12),
              Text('No transfers yet',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // ...
    );
  },
),
```
The Active Connections and Pending Requests `StreamBuilder` widgets follow this identical skeleton: `stream` from `HandshakeRepository`, loading spinner via `ConnectionState.waiting`, empty-state via `GlassContainer` with centered icon + text, populated state via `ListView.separated` with `shrinkWrap: true` and `NeverScrollableScrollPhysics`.

**`showModalBottomSheet` pattern used in this file for role picker:**
Borrow directly from `receiver_screen.dart` lines 276–289 (see that section below). The HomeScreen `_openRolePicker()` method uses the same call signature.

**Role buttons to retire** (`home_screen.dart` lines 159–179):
```dart
// ── Role buttons ──────────────────────────────────
GlassButton(
  icon: const Text('📤', style: TextStyle(fontSize: 18)),
  label: const Text('I am a Sender'),
  color: Colors.green.shade400,
  onPressed: () => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const SenderScreen()),
  ),
),
const SizedBox(height: 12),
GlassButton(
  icon: const Text('📥', style: TextStyle(fontSize: 18)),
  label: const Text('I am a Receiver'),
  color: cs.primary,
  onPressed: () => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const ReceiverScreen()),
  ),
),
const SizedBox(height: 32),
```
These lines are **deleted**. The `const SizedBox(height: 32)` spacer following them is also removed. The section label `'Actions'` (lines 149–157) is replaced by the `'Active Connections'` section header.

---

### `lib/presentation/sender/sender_screen.dart` (screen, request-response — add optional param)

**Analog:** `lib/presentation/receiver/receiver_screen.dart` (optional constructor parameter pattern)

**Current constructor** (`sender_screen.dart` lines 34–35):
```dart
class SenderScreen extends StatefulWidget {
  const SenderScreen({super.key});
```

**Target constructor — copy `ReceiverScreen`'s future pattern**:
```dart
class SenderScreen extends StatefulWidget {
  final String? preFilledPartnerUid;
  final String? preFilledPartnerUsername;

  const SenderScreen({
    super.key,
    this.preFilledPartnerUid,
    this.preFilledPartnerUsername,
  });
```

**Current `initState`** (`sender_screen.dart` lines 72–78):
```dart
@override
void initState() {
  super.initState();
  _startHandshakeListener();
  _progressSub = _progressCtrl.stream.listen((p) {
    if (mounted) setState(() => _encryptionProgress = p);
  });
}
```
After the pre-fill change, add a conditional block after `_startHandshakeListener()`:
```dart
if (widget.preFilledPartnerUid != null) {
  // Pre-fill: receiver UID is already known from the Active Connection.
  // The handshake stream is still started so the RSA key arrives reactively
  // when the partner opens ReceiverScreen.
  setState(() {
    _receiverId = widget.preFilledPartnerUid;
    _receiverUsername = widget.preFilledPartnerUsername ?? 'Partner';
  });
}
```
Note: `_selectedReceiverPublicKeyJson` remains null until `_onHandshakeUpdate` fires — this is correct. The sender waits at Step 3 until the receiver publishes their key via the stream.

**`_onHandshakeUpdate` pre-fill filter** (`sender_screen.dart` lines 93–126):
```dart
void _onHandshakeUpdate(QuerySnapshot<Map<String, dynamic>> snap) {
  if (!mounted) return;
  if (snap.docs.isEmpty) {
    // ...revert to waiting
  } else {
    final doc = snap.docs.first.data();
    final receiverId = doc['receiverId'] as String? ?? '';
    // ...
    if (publicKey != null && publicKey.isNotEmpty && receiverId.isNotEmpty) {
      setState(() {
        _receiverId = receiverId;
        _receiverUsername = receiverUsername;
        _selectedReceiverPublicKeyJson = publicKey;
      });
    }
  }
}
```
When `preFilledPartnerUid` is set, add a guard: only accept the handshake doc if `receiverId == widget.preFilledPartnerUid`. This prevents a different receiver's key from overwriting the pre-filled partner. The condition becomes:
```dart
if (publicKey != null &&
    publicKey.isNotEmpty &&
    receiverId.isNotEmpty &&
    (widget.preFilledPartnerUid == null || receiverId == widget.preFilledPartnerUid)) {
```

**`_WaitingForConnectionWidget` pulsing animation** (`sender_screen.dart` lines 586–661):
```dart
class _WaitingForConnectionWidget extends StatefulWidget {
  const _WaitingForConnectionWidget();
  // ...
}

class _WaitingForConnectionWidgetState
    extends State<_WaitingForConnectionWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _fade = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }
  // build: Center > Column > ScaleTransition > FadeTransition > Container > Icon
```
Copy this animation pattern for the Pending row amber pulse widget in HomeScreen's Active Connections section.

---

### `lib/presentation/receiver/receiver_screen.dart` (screen, request-response — add optional param)

**Analog:** `lib/presentation/receiver/receiver_screen.dart` (self — add optional constructor param)

**Current constructor** (`receiver_screen.dart` lines 21–22):
```dart
class ReceiverScreen extends StatefulWidget {
  const ReceiverScreen({super.key});
```

**Target constructor:**
```dart
class ReceiverScreen extends StatefulWidget {
  final String? preFilledSenderUid;
  final String? preFilledSenderUsername;

  const ReceiverScreen({
    super.key,
    this.preFilledSenderUid,
    this.preFilledSenderUsername,
  });
```

**Current `initState`** (`receiver_screen.dart` lines 61–68):
```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this);
  _sessionManager.stateNotifier.addListener(_onSessionStateChanged);
  _checkKeyStatus();
  _subscribeToFriends();
  _loadReadyToReceiveState();
}
```
Add the pre-fill path after `_checkKeyStatus()`:
```dart
_checkKeyStatus().then((_) {
  if (mounted && widget.preFilledSenderUid != null) {
    _onSenderSelected(UserModel(
      uid: widget.preFilledSenderUid!,
      username: widget.preFilledSenderUsername ?? '',
      email: '',
      phone: '',
      publicKey: '',
      isAdmin: false,
    ));
  }
});
```
This ensures `_step1Done` is true before `_onSenderSelected()` is called. The `UserModel` constructor must match `lib/data/models/user_model.dart` — check exact field list before writing.

**`_onSenderSelected()` — the method called by pre-fill** (`receiver_screen.dart` lines 292–319):
```dart
Future<void> _onSenderSelected(UserModel sender) async {
  _sessionManager.selectSender(sender.uid, sender.username);
  final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  _transferStream = FirebaseFirestore.instance
      .collection(FirebaseConstants.transfers)
      .where('receiverId', isEqualTo: myUid)
      .where('senderId', isEqualTo: sender.uid)
      .where('status', isEqualTo: 'pending')
      .snapshots();
  setState(() => _handshaking = true);
  try {
    await _connService.selectSenderHandshake(
      senderUid: sender.uid,
      senderUsername: sender.username,
    );
    if (mounted) {
      setState(() {
        _handshakeDone = true;
        _handshaking = false;
      });
    }
  } catch (e) {
    if (mounted) {
      setState(() => _handshaking = false);
      _showError(e.toString());
    }
  }
}
```
This method is called unchanged by the pre-fill path. No modification needed here.

**`showModalBottomSheet` for `_showCloseSessionDialog`** (`receiver_screen.dart` lines 225–273):
```dart
final result = await showModalBottomSheet<bool>(
  context: context,
  backgroundColor: Colors.transparent,
  builder: (ctx) => GlassContainer(
    borderRadius: 24,
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BottomSheetHandle(),
        // ...
      ],
    ),
  ),
);
return result ?? false;
```

**`showModalBottomSheet` for `_openFindSenderSheet`** (`receiver_screen.dart` lines 276–289):
```dart
showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => GlassContainer(
    borderRadius: 24,
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      children: [
        const BottomSheetHandle(),
        // content
      ],
    ),
  ),
);
```
The HomeScreen `_openRolePicker()` copies this call signature exactly. `isScrollControlled: true` and `useSafeArea: true` are both required for large modal sheets. `backgroundColor: Colors.transparent` is required so `GlassContainer`'s own decoration shows.

**`_FindSenderSheet` build structure** (`receiver_screen.dart` lines 816–909):
```dart
@override
Widget build(BuildContext context) {
  return GlassContainer(
    borderRadius: 24,
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      children: [
        const BottomSheetHandle(),
        // search field
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [ /* rows */ ],
          ),
        ),
      ],
    ),
  );
}
```
`_RolePickerSheet` follows this layout structure but replaces the search + list with two large `GlassButton` tiles for Send File / Receive File. The `GlassContainer` + `BottomSheetHandle` header is identical.

---

### `firestore.rules` (config — add rules block)

**Analog:** `firestore.rules` (self — add `neutral_handshakes` block after existing `handshakes` block)

**Existing `handshakes` block to insert after** (`firestore.rules` lines 162–184):
```javascript
match /handshakes/{handshakeId} {
  allow read:   if isAuthenticated() &&
                   (resource.data.senderId == request.auth.uid ||
                    resource.data.receiverId == request.auth.uid ||
                    isAdmin());

  allow create: if isAuthenticated() &&
                   request.resource.data.receiverId == request.auth.uid;

  allow update: if isAuthenticated() &&
                   (resource.data.receiverId == request.auth.uid ||
                    resource.data.senderId == request.auth.uid);

  allow delete: if isAuthenticated() &&
                   (resource.data.senderId == request.auth.uid || isAdmin());
}
```

**New block to add immediately after** (derived from D-01, Pitfall 4 fix from RESEARCH.md):
```javascript
// ─── neutral_handshakes ──────────────────────────────────────────────────────
// Connection-layer neutral handshakes. Separate from session-layer `handshakes`.
// proposer creates; both parties read; only partner may accept/reject;
// proposer may also mark their own doc connected (mutual-accept WriteBatch);
// either party may delete (cancel or post-session cleanup).
match /neutral_handshakes/{handshakeId} {
  allow read: if isAuthenticated() &&
                 (resource.data.proposerId == request.auth.uid ||
                  resource.data.partnerId == request.auth.uid);

  allow create: if isAuthenticated() &&
                   request.resource.data.proposerId == request.auth.uid;

  allow update: if isAuthenticated() && (
    // Partner accepts or rejects their incoming proposal
    (resource.data.partnerId == request.auth.uid &&
     request.resource.data.status in ['connected', 'rejected'])
    ||
    // Proposer's own outgoing doc gets marked connected (mutual-accept WriteBatch)
    (resource.data.proposerId == request.auth.uid &&
     request.resource.data.status == 'connected')
  );

  allow delete: if isAuthenticated() &&
                   (resource.data.proposerId == request.auth.uid ||
                    resource.data.partnerId == request.auth.uid);
}
```
The dual `allow update` condition (both partner-update and proposer-update to `connected`) is required by Pitfall 4 in RESEARCH.md — without the second clause, the mutual-accept WriteBatch fails on the `B_A` doc.

**`isAuthenticated()` helper already defined** (`firestore.rules` lines 12–14):
```javascript
function isAuthenticated() {
  return request.auth != null;
}
```
All `neutral_handshakes` rules reference this existing function — no new helpers needed.

---

## Shared Patterns

### `GlassContainer` / `GlassButton` / `BottomSheetHandle` — UI Components
**Source:** `lib/presentation/widgets/shared_widgets.dart`
**Apply to:** All new UI surfaces in HomeScreen (section cards, pending rows, role picker sheet), `_RolePickerSheet`
```dart
// Pattern: every card/surface uses GlassContainer; every CTA uses GlassButton
GlassContainer(
  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  color: cs.primary.withValues(alpha: 0.1),
  borderColor: cs.primary.withValues(alpha: 0.2),
  child: /* row content */,
)
```

### Error display in screens
**Source:** `lib/presentation/receiver/receiver_screen.dart` lines 363–370
**Apply to:** `home_screen.dart` (proposal accept/reject errors), `sender_screen.dart`, `receiver_screen.dart`
```dart
void _showError(String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg.replaceFirst('Exception: ', '')),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
}
```

### `mounted` guard before `setState` in async callbacks
**Source:** `receiver_screen.dart` lines 83–86 (friend stream listener), `home_screen.dart` lines 46–47 (notif listener)
**Apply to:** All Firestore stream listeners in `HandshakeRepository` callbacks and HomeScreen `_startHandshakeListener()`
```dart
if (!mounted) return;
```

### `UserAvatar` widget usage
**Source:** `receiver_screen.dart` lines 845, 892 — existing rows use `UserAvatar(username: u.username)`
**Apply to:** Active Connection rows, Pending Request rows in HomeScreen

### `GoogleFonts.poppins` for section headers
**Source:** `home_screen.dart` lines 149–157
**Apply to:** `'Active Connections'` and `'Pending Requests'` section headers
```dart
Text(
  'Active Connections',
  style: GoogleFonts.poppins(
    fontWeight: FontWeight.w600,
    fontSize: 14,
    color: cs.onSurfaceVariant,
  ),
),
```

### `SecurityBadge` for status display
**Source:** `home_screen.dart` line 320 — `SecurityBadge(label: isSender ? 'Sent' : 'Received')`
**Apply to:** Active Connection rows can use `SecurityBadge(label: 'Active')` and pending rows `SecurityBadge(label: 'Pending')` (amber variant to be styled via the `color` parameter if available, otherwise a custom `Container` styled to match the amber badge in the existing app).

---

## No Analog Found

All files have close analogs in the codebase. No files require falling back to RESEARCH.md patterns exclusively.

---

## Metadata

**Analog search scope:**
- `lib/data/repositories/` — all repository files
- `lib/presentation/home/` — HomeScreen and FindFriendsScreen
- `lib/presentation/sender/` — SenderScreen
- `lib/presentation/receiver/` — ReceiverScreen
- `lib/core/constants/` — FirebaseConstants
- `firestore.rules` — root-level security rules

**Files scanned:** 6 analog files read in full
**Pattern extraction date:** 2026-05-12
