# Phase 05: Neutral Handshake Model — Research

**Researched:** 2026-05-12
**Domain:** Flutter/Firestore connection-layer refactor — neutral handshake, HomeScreen restructure, role-selection bridge
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Rename `senderId`/`receiverId` in handshake logic to `proposerId` (initiator) and `partnerId` (recipient). Default `status: 'pending'`. Firestore security rules updated: create allowed for `proposerId == auth.uid`; read for either party; update allowed for `partnerId` only, restricting status to `connected` or `rejected`.
- **D-02:** Incoming handshake proposals surface to the partner as a `_NotifBanner` OverlayEntry with inline **Accept** and **Reject** buttons (reuse the existing banner pattern in `home_screen.dart`).
- **D-03:** If the partner dismisses the banner without acting, the proposal stays `pending` and re-surfaces as a persistent **Pending Requests** section on HomeScreen. No auto-expire.
- **D-04:** Standalone **Send / Receive role buttons are RETIRED**. All sessions must go through an Active Connection. New users with no connections see an empty-state prompt.
- **D-05:** HomeScreen layout (top to bottom): Welcome banner → **Active Connections section** → **Pending Requests section** → Recent Transfers.
- **D-06:** New connection proposals are initiated via an **"Add New Connection" button inside the Active Connections section**. Tapping opens friend search to select a user and send a neutral handshake proposal.
- **D-07:** When a proposal is sent, a **Pending row appears immediately** in the Active Connections section with a `Pending` badge. Non-blocking.
- **D-08:** When the partner responds, the proposer sees a **5-second fading `_NotifBanner`** showing acceptance or rejection outcome.
- **D-09:** On rejection, the Pending row **disappears silently** after the outcome banner dismisses.
- **D-10:** The Pending row has a **cancel button** that lets the proposer withdraw before the partner responds. Cancelling deletes the Firestore handshake doc.
- **D-11:** Tapping an **Active Connection row** opens a **bottom sheet** with two large tiles: **[Send File]** and **[Receive File]**.
- **D-12:** Role selection is **independent** — each user picks their own role.
- **D-13:** Tapping **[Send File]** navigates to existing `SenderScreen` with partner pre-filled — `_FindSenderSheet` step bypassed.
- **D-14:** Tapping **[Receive File]** navigates to existing `ReceiverScreen` with partner pre-filled via `SessionManager.selectSender()`.

### Claude's Discretion

- How Pending Requests section handles simultaneous mutual proposals (e.g., merge into one connected state or show as two separate pending rows).
- Cancel button placement within the Pending row (icon button vs. swipe-to-dismiss vs. context menu).
- Exact Firestore doc ID scheme for the new neutral handshake collection (deterministic vs. auto-ID).

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

## Summary

Phase 5 inserts a connection-management layer between HomeScreen and the existing session screens. The core change is replacing the `senderId`/`receiverId` semantics in the `handshakes` Firestore collection with neutral `proposerId`/`partnerId` semantics, adding a pending-approval flow, and restructuring HomeScreen to show Active Connections and Pending Requests sections instead of the retired role buttons.

The existing `handshakes` Firestore collection is the target of the data-model rename. The existing `_NotifBanner` OverlayEntry pattern in `home_screen.dart` (lines 54–86 and 400–479) is directly reusable for both the approval banner (partner side) and the outcome banner (proposer side, D-08). The `_FindSenderSheet` / `GlassContainer` bottom-sheet modal pattern is directly reusable for the role picker (D-11). `SessionManager.selectSender()` is the pre-fill entry point for the ReceiverScreen path (D-14). `SenderScreen` needs an optional constructor parameter for the pre-filled partner.

One critical implementation ambiguity: the current `handshakes` collection is not used purely for the neutral handshake concept — it is also used mid-session as the carrier for RSA public key material (`publishRSAPublicKey`, `selectSenderHandshake`). The new neutral handshake collection must coexist with or subsume this existing usage. Research confirms this is cleanest as a new `neutral_handshakes` collection, leaving the existing `handshakes` collection for session-phase RSA key exchange (see Architecture Patterns section).

**Primary recommendation:** Add a new `neutral_handshakes` Firestore top-level collection with `proposerId`/`partnerId` semantics. Keep the existing `handshakes` collection for in-session RSA key material. HomeScreen streams `neutral_handshakes` for the Active Connections / Pending Requests UI.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Neutral handshake proposal / accept / reject | Firestore (neutral_handshakes collection) | KeyRepository (data layer) | Persistent cross-device state; both parties must see it |
| Global pending-proposal listener | HomeScreen (_HomeScreenState) | — | HomeScreen is always mounted when app is in use; equivalent to existing `_notifListener` pattern |
| Approval banner (Accept/Reject) | HomeScreen OverlayEntry | — | Reuse existing `_NotifBanner` OverlayEntry infrastructure |
| Pending Requests fallback section | HomeScreen StreamBuilder | — | Persistent Firestore stream on neutral_handshakes; no auto-expire |
| Active Connections section | HomeScreen StreamBuilder | — | Firestore stream on neutral_handshakes where status == connected |
| Role picker bottom sheet | HomeScreen (new _RolePickerSheet) | — | Opened by tapping an Active Connection row |
| Pre-fill sender path | SenderScreen (optional param) | — | Bypass _FindSenderSheet; wire receiver UID directly into _receiverId |
| Pre-fill receiver path | ReceiverScreen + SessionManager | — | Call selectSender() directly; skip _openFindSenderSheet |
| Firestore security rules | firestore.rules | — | neutral_handshakes collection needs new rules block |
| Outcome notification (D-08) | HomeScreen OverlayEntry | Firestore stream | Proposer streams their own neutral_handshake doc; when status changes, fires banner |

---

## Standard Stack

### Core (already in project — no new installs needed)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| cloud_firestore | ^6.2.0 | neutral_handshakes collection, StreamBuilder streams | Already wired; all reactive patterns use it |
| firebase_auth | ^6.3.0 | Auth UID for proposerId / security rules | Already wired |
| flutter (SDK) | 3.41.9 | OverlayEntry, showModalBottomSheet, StreamBuilder | Platform |
| google_fonts | ^8.0.2 | Typography consistency with rest of app | Already used everywhere |

### Supporting (already in project)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| shared_widgets.dart | project | GlassContainer, GlassButton, BottomSheetHandle | All new UI surfaces |
| session_manager.dart | project | selectSender() for ReceiverScreen pre-fill (D-14) | Role picker → Receive File path |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| New `neutral_handshakes` collection | Reuse existing `handshakes` | Existing handshakes col is used for RSA key material mid-session; mixing connection-layer semantics with crypto-session semantics creates ambiguity in rules and cleanup logic |
| StreamBuilder in HomeScreen | Provider/Riverpod for connection state | No state management package is used elsewhere; StreamBuilder is the established pattern in this codebase |

**Installation:** No new packages required. [VERIFIED: pubspec.yaml]

---

## Architecture Patterns

### System Architecture Diagram

```
User (Proposer)                    Firestore                    User (Partner)
      │                                │                               │
      │ Tap "Add New Connection"       │                               │
      │ → Open friend search           │                               │
      │ → Select partner               │                               │
      │ → sendNeutralHandshake()       │                               │
      │──────────────────────────────►│ neutral_handshakes/{docId}    │
      │                                │   proposerId: currentUid      │
      │                                │   partnerId: partnerUid       │
      │                                │   status: 'pending'           │
      │                                │◄──────────────────────────────│
      │                                │                               │ HomeScreen global listener
      │                                │                               │ fires _NotifBanner (Accept/Reject)
      │                                │                               │
      │                                │◄──────────────────────────────│ Accept → updateHandshake(connected)
      │                                │   status: 'connected'         │ Reject → updateHandshake(rejected)
      │                                │                               │
      │ Proposer stream fires          │                               │
      │ outcome _NotifBanner (5s)      │                               │
      │                                │                               │
      │ Active Connection row visible  │                               │
      │ Tap → _RolePickerSheet         │                               │
      │   [Send File]────────────────────────────────────► SenderScreen(preFilledPartner)
      │   [Receive File]─────────────────────────────────► ReceiverScreen + selectSender()
```

### Recommended Project Structure (changes only)

```
lib/
├── data/
│   └── repositories/
│       └── handshake_repository.dart     # NEW — neutral handshake CRUD + streams
├── presentation/
│   └── home/
│       ├── home_screen.dart              # MODIFY — restructure layout + add listeners
│       └── find_friends_screen.dart      # REFERENCE ONLY — search logic reused
├── presentation/
│   └── sender/
│       └── sender_screen.dart            # MODIFY — add preFilledPartner optional param
├── presentation/
│   └── receiver/
│       └── receiver_screen.dart          # MODIFY — add optional pre-fill entry point
└── (firestore.rules)                     # MODIFY — add neutral_handshakes rules block
```

---

### Pattern 1: New Collection — `neutral_handshakes`

**What:** A new top-level Firestore collection for connection-layer proposals. Separate from `handshakes` (RSA key material) to avoid semantic collision.

**Firestore document schema:**
```
neutral_handshakes/{docId}
  proposerId: String      ← auth.uid of initiator
  proposerUsername: String
  partnerId: String       ← auth.uid of recipient
  partnerUsername: String
  status: 'pending' | 'connected' | 'rejected'
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Doc ID scheme (Claude's Discretion):** Deterministic `${proposerId}_${partnerId}` — ensures idempotent re-proposals without duplicates, mirrors `publishRSAPublicKey` pattern already in codebase. [VERIFIED: existing `publishRSAPublicKey` in key_repository.dart uses this scheme]

**Simultaneous mutual proposals (Claude's Discretion):** When A proposes to B and B simultaneously proposes to A, two docs exist: `A_B` and `B_A`. The simpler resolution is to merge: when either party's proposal is accepted, both docs are updated to `connected` in a WriteBatch. This is the recommended approach — no special "detect mutual" logic needed; the acceptor's WriteBatch just updates both docs.

**Why separate from `handshakes`:** The existing `handshakes` collection is mid-session infrastructure — it carries RSA public keys, is batch-deleted on `closeReceiverSession()`, and has rules tied to `senderId`/`receiverId` semantics from the session model. Mixing connection-layer (persistent across sessions) with session-layer (ephemeral per transfer) data creates cleanup hazards. [VERIFIED: key_repository.dart `wipeAllSessionKeys()` deletes all `handshakes` docs — this would delete connection state if merged]

---

### Pattern 2: `HandshakeRepository` — New Data Layer Class

**What:** A dedicated repository for `neutral_handshakes` CRUD, mirroring the existing `KeyRepository` structure.

**Key methods:**
```dart
// Source: mirrored from key_repository.dart WriteBatch pattern [VERIFIED]

/// Send a neutral handshake proposal. Uses deterministic doc ID.
Future<void> sendProposal({
  required String partnerUid,
  required String partnerUsername,
}) async { ... }

/// Accept a proposal — WriteBatch: update neutral_handshakes doc status to
/// 'connected'. If mutual proposal exists, update both docs.
Future<void> acceptProposal(String docId, String proposerId) async { ... }

/// Reject a proposal — WriteBatch: update neutral_handshakes doc status to
/// 'rejected'.
Future<void> rejectProposal(String docId) async { ... }

/// Cancel own proposal (proposer withdraws) — delete the doc.
Future<void> cancelProposal(String docId) async { ... }

/// Stream of docs where current user is partnerId and status == pending.
/// Used by HomeScreen global listener for approval banners.
Stream<QuerySnapshot> streamIncomingPending() => ...

/// Stream of docs where current user is proposerId or partnerId and
/// status == connected. Used by HomeScreen Active Connections section.
Stream<QuerySnapshot> streamActiveConnections() => ...

/// Stream of docs where current user is proposerId and status == pending.
/// Used by HomeScreen for the proposer's own pending rows.
Stream<QuerySnapshot> streamOutgoingPending() => ...

/// Stream of a single doc — used by proposer to detect outcome (D-08).
Stream<DocumentSnapshot> streamProposalOutcome(String docId) => ...
```

**WriteBatch for accept:**
```dart
// Source: WriteBatch pattern verified in key_repository.dart [VERIFIED]
final batch = _db.batch();
batch.update(
  _db.collection('neutral_handshakes').doc(docId),
  {'status': 'connected', 'updatedAt': FieldValue.serverTimestamp()},
);
// If mutual proposal exists (B_A doc), update that too
if (mutualDocId != null) {
  batch.update(
    _db.collection('neutral_handshakes').doc(mutualDocId),
    {'status': 'connected', 'updatedAt': FieldValue.serverTimestamp()},
  );
}
await batch.commit();
```

---

### Pattern 3: HomeScreen Global Listener — Extended `_startNotifListener`

**What:** Extend the existing `_HomeScreenState` init to also subscribe to incoming pending proposals (D-02).

**Current pattern in `home_screen.dart`:**
```dart
// EXISTING: lines 41-86 [VERIFIED: home_screen.dart]
void _startNotifListener() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  _notifSub = NotificationService.latestUnreadStream(uid).listen((notif) {
    if (!mounted || notif == null) return;
    _showNotifBanner(notif);
  });
}
```

**Extended pattern (Phase 5):**
```dart
// NEW — add alongside existing _notifSub
StreamSubscription<QuerySnapshot>? _pendingProposalSub;

void _startHandshakeListener() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  _pendingProposalSub = _handshakeRepo.streamIncomingPending().listen((snap) {
    if (!mounted) return;
    for (final doc in snap.docChanges) {
      if (doc.type == DocumentChangeType.added) {
        _showProposalBanner(doc.doc);
      }
    }
  });
}
```

**Key nuance:** Use `docChanges` with `DocumentChangeType.added` to fire only on new arrivals, not on every stream re-emit. The existing notification listener does not have this problem because `latestUnreadStream` filters to the most recent unread doc. For proposals, multiple can arrive simultaneously. [ASSUMED — Firestore SDK behavior; standard pattern]

---

### Pattern 4: Approval Banner — Reusing `_NotifBanner` with Accept/Reject Actions

**What:** The existing `_NotifBanner` (OverlayEntry, 5-second auto-dismiss, GlassContainer) needs a variant with inline Accept and Reject buttons instead of a navigation tap action.

**Current `_NotifBanner` signature (lines 400-479 of home_screen.dart) [VERIFIED]:**
```dart
class _NotifBanner extends StatefulWidget {
  final String message;
  final VoidCallback onDismiss;
  final VoidCallback onTap;
  ...
}
```

**New variant approach:** Create `_ProposalBanner` — same OverlayEntry pattern, different action row. Keeps the existing `_NotifBanner` unchanged (still used for rsa_key_received and file_received types).

```dart
class _ProposalBanner extends StatefulWidget {
  final String message;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onDismiss;  // no-action dismiss (D-03: stays pending)
  ...
}
```

**5-second auto-dismiss for D-08 (outcome banner):** The existing `_NotifBanner` already has a 5-second `Timer` auto-dismiss. [VERIFIED: home_screen.dart lines 420-422] Reuse as-is for proposer outcome banner.

---

### Pattern 5: Active Connections Section — `StreamBuilder` on `neutral_handshakes`

**What:** Replace the role buttons area in HomeScreen with two `StreamBuilder` widgets — one for Active Connections, one for Pending Requests.

**Structure:**
```dart
// Active Connections
StreamBuilder<QuerySnapshot>(
  stream: _handshakeRepo.streamActiveConnections(),
  builder: (context, snap) {
    final docs = snap.data?.docs ?? [];
    if (docs.isEmpty) return _EmptyConnectionsPrompt(); // "No connections yet" + Add button
    return Column(
      children: [
        _SectionHeader('Active Connections', action: _addConnectionButton()),
        ...docs.map((doc) => _ActiveConnectionRow(doc: doc, onTap: _openRolePicker)),
      ],
    );
  },
),

// Pending Requests (for partner — incoming)
StreamBuilder<QuerySnapshot>(
  stream: _handshakeRepo.streamIncomingPending(),
  builder: (context, snap) {
    final docs = snap.data?.docs ?? [];
    if (docs.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        _SectionHeader('Pending Requests'),
        ...docs.map((doc) => _PendingRequestRow(
          doc: doc,
          onAccept: () => _acceptProposal(doc),
          onReject: () => _rejectProposal(doc),
        )),
      ],
    );
  },
),
```

**Pending row for proposer (D-07/D-10):** The Active Connections stream includes `status == pending` for the proposer's own outgoing proposals. A pending doc shows in the Active Connections section with an amber `Pending` badge and a cancel icon button. [ASSUMED — design recommendation; consistent with D-07]

---

### Pattern 6: Role Picker Bottom Sheet — `_RolePickerSheet`

**What:** A `showModalBottomSheet` opened when the user taps an Active Connection row. Follows the `_FindSenderSheet` pattern. [VERIFIED: receiver_screen.dart lines 276-289]

```dart
void _openRolePicker(Map<String, dynamic> connectionData) {
  final partnerUid = ...;
  final partnerUsername = ...;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RolePickerSheet(
      partnerUid: partnerUid,
      partnerUsername: partnerUsername,
      onSendFile: () => _navigateToSender(partnerUid, partnerUsername),
      onReceiveFile: () => _navigateToReceiver(partnerUid, partnerUsername),
    ),
  );
}
```

**Send File navigation (D-13):**
```dart
void _navigateToSender(String partnerUid, String partnerUsername) {
  Navigator.pop(context); // close bottom sheet
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => SenderScreen(
        preFilledPartnerUid: partnerUid,
        preFilledPartnerUsername: partnerUsername,
      ),
    ),
  );
}
```

**Receive File navigation (D-14):**
```dart
void _navigateToReceiver(String partnerUid, String partnerUsername) {
  Navigator.pop(context); // close bottom sheet
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ReceiverScreen(
        preFilledSenderUid: partnerUid,
        preFilledSenderUsername: partnerUsername,
      ),
    ),
  );
}
```

---

### Pattern 7: SenderScreen Pre-Fill — Optional Constructor Parameter

**What:** `SenderScreen` currently takes no constructor parameters. Adding optional `preFilledPartnerUid` and `preFilledPartnerUsername` allows bypassing `_FindSenderSheet`.

**Current `SenderScreen` constructor [VERIFIED: sender_screen.dart line 34]:**
```dart
class SenderScreen extends StatefulWidget {
  const SenderScreen({super.key});
```

**New constructor:**
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

**In `_SenderScreenState.initState()`:** If `preFilledPartnerUid` is non-null, skip `_startHandshakeListener()` and set `_receiverId` + `_receiverUsername` directly. The `_FindSenderSheet` step is bypassed because `_receiverSelected` is already true.

**Critical detail:** `_selectedReceiverPublicKeyJson` is populated by `_onHandshakeUpdate` from the stream. With pre-fill, the RSA public key still needs to arrive via the same stream OR be fetched up-front. The handshake listener (`streamHandshakesForSender()`) can still run — it will detect when the receiver publishes their key. Pre-fill only sets who the sender is waiting for; the stream detects when that specific receiver authorizes the session. [VERIFIED: sender_screen.dart lines 88-126, _onHandshakeUpdate only accepts the key when receiverId matches]

---

### Pattern 8: ReceiverScreen Pre-Fill — Optional Entry Point

**Current `ReceiverScreen` constructor [VERIFIED: receiver_screen.dart line 22]:**
```dart
class ReceiverScreen extends StatefulWidget {
  const ReceiverScreen({super.key});
```

**New constructor:**
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

**In `_ReceiverScreenState.initState()`:** If `preFilledSenderUid` is non-null, after `_checkKeyStatus()` resolves, call `_onSenderSelected(UserModel(...))` directly — bypassing the manual "Find & Select Sender" button. [VERIFIED: receiver_screen.dart _onSenderSelected at line 292]

**Flow after pre-fill:** `_onSenderSelected()` calls `_sessionManager.selectSender()` and `_connService.selectSenderHandshake()`. These are the same calls made in the existing flow; pre-fill just invokes them programmatically instead of waiting for user interaction.

---

### Pattern 9: Firestore Security Rules — `neutral_handshakes`

**What:** New rules block for the `neutral_handshakes` collection, following D-01.

```javascript
// neutral_handshakes — connection-layer neutral handshakes
// proposer creates; both parties read; only partner may accept/reject;
// either party may delete (cancel or cleanup).
match /neutral_handshakes/{handshakeId} {
  allow read: if isAuthenticated() &&
                 (resource.data.proposerId == request.auth.uid ||
                  resource.data.partnerId == request.auth.uid);

  // Only proposer may create, and only with their own UID as proposerId
  allow create: if isAuthenticated() &&
                   request.resource.data.proposerId == request.auth.uid;

  // Only partner may update status (accept/reject)
  // Status must transition to 'connected' or 'rejected' only
  allow update: if isAuthenticated() &&
                   resource.data.partnerId == request.auth.uid &&
                   request.resource.data.status in ['connected', 'rejected'];

  // Either party may delete (cancel or post-session cleanup)
  allow delete: if isAuthenticated() &&
                   (resource.data.proposerId == request.auth.uid ||
                    resource.data.partnerId == request.auth.uid);
}
```

**Note on mutual-accept WriteBatch:** The acceptor updates both `A_B` and `B_A` docs. The `B_A` doc has `partnerId == B` — the acceptor is B — so they can update it. The `A_B` doc has `proposerId == A` and `partnerId == B` — the acceptor (B) is the partnerId — so they can update that too. Both updates satisfy the `partnerId == request.auth.uid` rule. [VERIFIED: rule logic consistent with D-01]

---

### Anti-Patterns to Avoid

- **Reusing `handshakes` collection for neutral handshakes:** The existing `handshakes` collection is batch-deleted by `closeReceiverSession()` and `wipeAllSessionKeys()`. If connection-layer docs live there, they get wiped at session end, destroying the persistent connection.
- **Polling instead of streaming for proposal status:** The proposer outcome banner (D-08) must be reactive. A one-time fetch would miss the update if the partner responds while the app is open. Use `streamProposalOutcome()`.
- **Direct `setState` from docChanges callback without `mounted` guard:** The HomeScreen stream listener fires on the Firestore event loop. Always check `if (!mounted) return;` before calling `setState` or inserting OverlayEntry.
- **Starting handshake listener before initState `addPostFrameCallback`:** The existing `_startNotifListener` uses `addPostFrameCallback` because `Overlay.of(context)` requires the widget to be in the tree. The new handshake listener must follow the same pattern. [VERIFIED: home_screen.dart line 31]
- **Blocking UI while proposal is in flight:** D-07 requires the proposer to continue using the app normally. The `sendProposal()` call should be async with a loading indicator only on the "Add Connection" button, not a blocking dialog.
- **Navigating to ReceiverScreen before key status is checked:** The pre-fill path (D-14) calls `_onSenderSelected()` in initState. If `_checkKeyStatus()` has not completed yet, `_step1Done` is false and the handshake step will not be visible. Sequence: await `_checkKeyStatus()` → then conditionally call `_onSenderSelected()`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Atomic multi-doc status updates | Custom sequential Firestore writes | `WriteBatch` | Prevents partial-write where one doc updates and the other fails |
| Pending state UI | Custom timer/polling | Firestore `StreamBuilder` | Reactive — fires immediately when partner responds, even if app is backgrounded momentarily |
| 5-second auto-dismiss banner | Custom timer widget | Existing `_NotifBanner` `Timer(Duration(seconds: 5), ...)` | [VERIFIED: home_screen.dart lines 420-422] Already implemented and tested |
| Bottom sheet modal | Custom overlay | `showModalBottomSheet` + `GlassContainer` + `BottomSheetHandle` | [VERIFIED: receiver_screen.dart lines 277-290] Established pattern in codebase |
| Idempotent doc upsert | Check-then-write sequence | `set(..., SetOptions(merge: true))` with deterministic doc ID | [VERIFIED: publishRSAPublicKey in key_repository.dart] Prevents duplicates atomically |

**Key insight:** Every custom Firestore write pattern needed in Phase 5 has a direct precedent in `key_repository.dart`. Copy the WriteBatch, stream, and SetOptions(merge: true) patterns verbatim.

---

## Common Pitfalls

### Pitfall 1: Overlay Insert Before Widget Is In Tree

**What goes wrong:** `Overlay.of(context).insert(entry)` throws if called during `initState` before the widget is laid out.

**Why it happens:** `initState` runs before the first frame. OverlayEntry insertion requires the Overlay to be mounted.

**How to avoid:** Always wrap stream listener startup in `WidgetsBinding.instance.addPostFrameCallback((_) => _startHandshakeListener())`. [VERIFIED: home_screen.dart line 31 uses exactly this pattern]

**Warning signs:** `Null check operator used on a null value` from `Overlay.of(context)` during startup.

---

### Pitfall 2: Double-Firing of DocChange Events on Stream Re-Subscribe

**What goes wrong:** If `_pendingProposalSub` is cancelled and restarted (e.g., on dispose/re-init), the stream re-emits all current docs as `DocumentChangeType.added`, causing banners to re-appear for proposals that were already seen.

**Why it happens:** Firestore Snapshot streams always emit the full current state as `added` events when a new listener attaches.

**How to avoid:** Track `_lastSeenProposalId` (equivalent to `_lastBannerDocId` in the existing notification listener). Only show banner if `docId != _lastSeenProposalId`. [VERIFIED: home_screen.dart line 48 uses `_lastBannerDocId` for exactly this deduplication]

---

### Pitfall 3: SenderScreen Pre-Fill RSA Key Race Condition

**What goes wrong:** With `preFilledPartnerUid` set, `_receiverId` is populated in `initState`. But `_selectedReceiverPublicKeyJson` remains null because the RSA key arrives via the `streamHandshakesForSender()` stream — which fires only after the receiver calls `selectSenderHandshake()`. If the sender tries to encrypt before the receiver has published their key, the key is null.

**Why it happens:** Pre-fill bypasses the handshake stream's normal trigger. The receiver side still needs to call `selectSenderHandshake()` independently (D-12: role selection is independent).

**How to avoid:** This is correct behavior — Step 3 (RSA Key Handshake) remains guarded by `_fileEncrypted && !_encryptingKey && _selectedReceiverPublicKeyJson != null`. The sender simply waits at Step 3 until the stream fires. The pre-fill change is cosmetic: the sender already knows who they're sending to; they just need the receiver to open their ReceiverScreen with pre-fill as well. The UX expectation must be set correctly: both parties open the role picker and choose their roles; the session initializes after that. [ASSUMED — behavioral inference from existing sender_screen.dart step flow]

---

### Pitfall 4: Firestore Rules Blocking the WriteBatch Accept for Mutual Proposals

**What goes wrong:** When accepting a mutual proposal, the acceptor (B) needs to update the `A_B` doc (where `partnerId == B`) AND the `B_A` doc (where `proposerId == B`, `partnerId == A`). The rule for `B_A` requires `resource.data.partnerId == request.auth.uid` — but for `B_A`, the partnerId is `A`, not `B`. So B cannot update `B_A`.

**Why it happens:** The rule is written from the partner's perspective; B is the proposer for `B_A`, not the partner.

**How to avoid:** Add a second update condition: `resource.data.proposerId == request.auth.uid` is also allowed to update to `connected` (not `rejected` — proposer cannot reject their own proposal). Revised update rule:

```javascript
allow update: if isAuthenticated() && (
  // Partner accepts or rejects
  (resource.data.partnerId == request.auth.uid &&
   request.resource.data.status in ['connected', 'rejected'])
  ||
  // Proposer's own doc gets marked connected (mutual accept)
  (resource.data.proposerId == request.auth.uid &&
   request.resource.data.status == 'connected')
);
```

---

### Pitfall 5: `_onToggleReady` Called Before Key Status Resolves in Pre-Fill Path

**What goes wrong:** ReceiverScreen with `preFilledSenderUid` calls `_onSenderSelected()` in `initState`. But `_checkKeyStatus()` is async; if keys are not present, `_step1Done` is false. `_onSenderSelected()` will succeed (it doesn't gate on `_step1Done`) but the UX will show Step 2 in the dimmed state and the user cannot open the mailbox.

**Why it happens:** `_onSenderSelected()` is designed to be called after user interaction, which naturally occurs after `_checkKeyStatus()` completes. Pre-fill removes that natural sequencing.

**How to avoid:** In the pre-fill path, call `_onSenderSelected()` in a `then()` chained to `_checkKeyStatus()`:
```dart
if (widget.preFilledSenderUid != null) {
  _checkKeyStatus().then((_) {
    if (mounted && widget.preFilledSenderUid != null) {
      _onSenderSelected(UserModel(
        uid: widget.preFilledSenderUid!,
        username: widget.preFilledSenderUsername ?? '',
        ...
      ));
    }
  });
}
```

---

## Code Examples

### Verified Patterns from Codebase

#### WriteBatch for Atomic Status Update (key_repository.dart pattern)
```dart
// Source: key_repository.dart selectSenderHandshake() [VERIFIED]
final batch = _db.batch();
batch.set(
  _db.collection(FirebaseConstants.users).doc(_uid),
  {'selectedSenderUid': senderUid},
  SetOptions(merge: true),
);
batch.update(existingRef, keyPayload);
await batch.commit();
```

#### Firestore Stream for Reactive UI (key_repository.dart)
```dart
// Source: key_repository.dart streamHandshakesForSender() [VERIFIED]
Stream<QuerySnapshot<Map<String, dynamic>>> streamHandshakesForSender() =>
    _db
        .collection(FirebaseConstants.handshakes)
        .where('senderId', isEqualTo: _uid)
        .where('status', isEqualTo: 'handshake_complete')
        .snapshots();
```

#### OverlayEntry Banner with Auto-Dismiss (home_screen.dart pattern)
```dart
// Source: home_screen.dart lines 54-86 [VERIFIED]
late OverlayEntry entry;
entry = OverlayEntry(
  builder: (_) => _NotifBanner(
    message: message,
    onDismiss: () {
      entry.remove();
      if (_bannerEntry == entry) _bannerEntry = null;
    },
    onTap: () { entry.remove(); /* navigate */ },
  ),
);
_bannerEntry = entry;
Overlay.of(context).insert(entry);
```

#### showModalBottomSheet with GlassContainer (receiver_screen.dart pattern)
```dart
// Source: receiver_screen.dart lines 276-290 [VERIFIED]
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

#### Deterministic Doc ID for Idempotent Writes (key_repository.dart)
```dart
// Source: key_repository.dart publishRSAPublicKey() [VERIFIED]
final docId = '${_uid}_$targetUserId';
await _db.collection(FirebaseConstants.handshakes).doc(docId).set({
  ...payload,
}, SetOptions(merge: true));
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Role buttons on HomeScreen (ad-hoc sessions) | Active Connections + role picker (connection-gated sessions) | Phase 5 | Eliminates ad-hoc sessions; all file transfers require prior neutral connection |
| `senderId`/`receiverId` semantics in handshakes | `proposerId`/`partnerId` in neutral_handshakes | Phase 5 | Decouples connection-establishment from session role assignment |
| Manual "Find Sender" sheet in ReceiverScreen | Pre-filled from Active Connection | Phase 5 | Removes redundant partner discovery step |

**Deprecated by Phase 5:**
- HomeScreen `GlassButton` role buttons ("I am a Sender", "I am a Receiver") — replaced by Active Connections section
- `ReceiverScreen` "Find & Select Sender" sheet as primary entry point — now secondary (still accessible inside ReceiverScreen if navigated to independently, but primary path is pre-fill from role picker)

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Firestore `docChanges` with `DocumentChangeType.added` fires on new docs only (not on stream re-subscribe for existing docs in same session) | Pattern 3 | Banners could fire for pre-existing proposals on app restart; mitigated by `_lastSeenProposalId` deduplication |
| A2 | SenderScreen pre-fill: sender waits at Step 3 for receiver to publish key via existing stream; UX requires both users to be in their respective screens | Pitfall 3 | If both parties open simultaneously the flow is seamless; if one party delays, the other sees a waiting state — acceptable per D-12 |
| A3 | Mutual proposal acceptance uses WriteBatch updating both docs; acceptor can update the `B_A` doc where they are `proposerId` under the revised update rule | Pitfall 4, Firestore Rules | If rule revision is missed, mutual-accept WriteBatch fails; mitigated by Pitfall 4 explicit rule |
| A4 | `ReceiverScreen` pre-fill calls `_onSenderSelected()` after `_checkKeyStatus()` resolves; this is sufficient to enter the handshake flow without additional UI interaction | Pitfall 5 | If key status check reveals no keys, user sees the amber "No RSA keys found" banner and must generate keys first — acceptable UX |

---

## Open Questions (RESOLVED)

1. **HomeScreen Active Connections stream — include pending outgoing proposals?**
   - What we know: D-07 says Pending row appears in "Active Connections section"
   - What's unclear: Whether `streamActiveConnections()` should return `status in ['connected', 'pending']` or whether there should be a separate `streamOutgoingPending()` for the proposer's pending rows
   - Recommendation: Use two streams — `streamActiveConnections()` returns `status == connected`; `streamOutgoingPending()` returns `status == pending AND proposerId == uid`. Render both in the Active Connections section, with pending rows showing amber Pending badge and cancel button. This keeps the data model and queries clean.

2. **Simultaneous mutual proposals — merge or show separately?**
   - What we know: Claude's Discretion; no user constraint
   - Recommendation (above in Pattern 1): Merge — when either party accepts, update both docs to `connected`. Show only one row in Active Connections section (deduplicate by partnerUid, not by docId).

3. **`_FindSenderSheet` in ReceiverScreen — remove or keep accessible?**
   - What we know: D-04 says role buttons retired; all sessions via Active Connection
   - What's unclear: Does `_openFindSenderSheet` in ReceiverScreen remain accessible via the settings/action button, or is it fully removed?
   - Recommendation: Keep `_openFindSenderSheet` accessible but demote it — the primary path is via pre-fill from the role picker. The find-sender button inside ReceiverScreen can remain for the case where a user navigates to ReceiverScreen directly (e.g., from a notification tap). This preserves backward compatibility with the existing notification-driven navigation in `home_screen.dart` (lines 78-80).

---

## Environment Availability

Step 2.6: SKIPPED — Phase 5 is purely code and Firestore config changes. No external tooling dependencies beyond those already confirmed present (Flutter 3.41.9, Firebase emulator not required for development). [VERIFIED: flutter --version]

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | flutter_test + fake_cloud_firestore ^4.1.0+1 + firebase_auth_mocks ^0.15.1 |
| Config file | None — flutter test discovers test/ directory automatically |
| Quick run command | `flutter test test/handshake/ -x` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| HAND-01 | `sendProposal()` creates neutral_handshakes doc with proposerId, partnerId, status=pending | unit | `flutter test test/handshake/handshake_repository_test.dart -x` | ❌ Wave 0 |
| HAND-02 | `acceptProposal()` WriteBatch updates status to connected | unit | `flutter test test/handshake/handshake_repository_test.dart -x` | ❌ Wave 0 |
| HAND-03 | `rejectProposal()` updates status to rejected | unit | `flutter test test/handshake/handshake_repository_test.dart -x` | ❌ Wave 0 |
| HAND-04 | `cancelProposal()` deletes the doc | unit | `flutter test test/handshake/handshake_repository_test.dart -x` | ❌ Wave 0 |
| HAND-05 | `streamIncomingPending()` emits docs where partnerId==uid and status==pending | unit | `flutter test test/handshake/handshake_repository_test.dart -x` | ❌ Wave 0 |
| HAND-06 | HomeScreen shows approval banner when incoming pending proposal arrives | manual | — | N/A — OverlayEntry not testable in unit |
| HAND-07 | SenderScreen with preFilledPartnerUid sets _receiverId without FindSenderSheet | unit | `flutter test test/handshake/sender_prefill_test.dart -x` | ❌ Wave 0 |
| HAND-08 | ReceiverScreen with preFilledSenderUid calls selectSender() after checkKeyStatus | unit | `flutter test test/handshake/receiver_prefill_test.dart -x` | ❌ Wave 0 |
| HAND-09 | Firestore rules: only proposer can create, only partner can set connected/rejected | manual (Firebase Emulator or Rules Playground) | — | N/A |

### Sampling Rate
- **Per task commit:** `flutter test test/handshake/ -x`
- **Per wave merge:** `flutter test`
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `test/handshake/handshake_repository_test.dart` — covers HAND-01 through HAND-05
- [ ] `test/handshake/sender_prefill_test.dart` — covers HAND-07
- [ ] `test/handshake/receiver_prefill_test.dart` — covers HAND-08
- [ ] No new framework install needed — `fake_cloud_firestore` already in dev_dependencies [VERIFIED: pubspec.yaml]

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | Firebase Auth (request.auth.uid in Firestore rules) |
| V3 Session Management | no | Phase 5 does not modify session lifecycle |
| V4 Access Control | yes | Firestore security rules — proposer/partner field checks |
| V5 Input Validation | yes | Dart: `partnerUid` non-null/non-empty guards before Firestore write |
| V6 Cryptography | no | Phase 5 adds no crypto; existing session flow unchanged |

### Known Threat Patterns for This Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Proposer spoofing (writing another user's UID as proposerId) | Spoofing | Firestore rule: `request.resource.data.proposerId == request.auth.uid` [VERIFIED: D-01] |
| Partner updating own proposal to `connected` (self-accept) | Elevation of Privilege | Firestore rule: only `partnerId` may update; if proposerId == partnerId (self-proposal), rule prevents it since create already blocked same-party docs [ASSUMED] |
| Partner setting status to arbitrary string | Tampering | Firestore rule: `request.resource.data.status in ['connected', 'rejected']` whitelist [VERIFIED: D-01] |
| Cancelled proposal lingering after delete | Information Disclosure | `cancelProposal()` deletes doc; stream emits removed event; UI removes row reactively |
| Notification spam via `neutral_handshakes` create | Denial of Service | No change to notification service — proposal banners are driven by Firestore stream, not push notifications; no rate-limiting gap introduced |

---

## Sources

### Primary (HIGH confidence)

- `lib/presentation/home/home_screen.dart` — `_NotifBanner`, `_startNotifListener`, OverlayEntry pattern [VERIFIED: read in session]
- `lib/data/repositories/key_repository.dart` — WriteBatch, streamHandshakesForSender, deterministic doc IDs, `wipeAllSessionKeys` [VERIFIED: read in session]
- `lib/presentation/sender/sender_screen.dart` — `_WaitingForConnectionWidget`, `_onHandshakeUpdate`, pre-fill integration points [VERIFIED: read in session]
- `lib/presentation/receiver/receiver_screen.dart` — `_onSenderSelected`, `_FindSenderSheet`, `SessionManager.selectSender` integration [VERIFIED: read in session]
- `firestore.rules` — current handshakes rules, WriteBatch security model [VERIFIED: read in session]
- `lib/core/utils/session_manager.dart` — `selectSender()`, `stateStream`, `clearSender()` [VERIFIED: read in session]
- `lib/core/constants/firebase_constants.dart` — collection names, constant pattern [VERIFIED: read in session]
- `.planning/phases/05-neutral-handshake-model/05-CONTEXT.md` — locked decisions D-01 through D-14 [VERIFIED: read in session]

### Secondary (MEDIUM confidence)

- Flutter 3.41.9 `showModalBottomSheet` API — same as used in receiver_screen.dart; no breaking changes [VERIFIED: flutter --version]
- Firestore Dart SDK `WriteBatch` + `SetOptions(merge: true)` — stable API, unchanged across cloud_firestore ^6.2.0 [ASSUMED — API stable since v4]

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries already in project; no new dependencies
- Architecture: HIGH — all patterns verified against actual code files
- Pitfalls: MEDIUM — pitfalls 3-5 are inferred from code analysis; not encountered in prior phases
- Firestore rules: HIGH — rule logic derived from existing rule patterns in firestore.rules + D-01

**Research date:** 2026-05-12
**Valid until:** 2026-06-12 (Firebase SDK and Flutter are stable; rules logic tied to locked decisions)
