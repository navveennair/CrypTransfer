# Phase 5: Neutral Handshake Model — Separate Connection from Role Assignment - Context

**Gathered:** 2026-05-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Refactor the CrypTransfer connection architecture so that "establishing a connection" (the neutral handshake) is decoupled from "defining sender/receiver roles" (which happens at session start). Introduces `proposerId`/`partnerId` semantics, a pending-approval flow with global listener and approval banner, and defers role selection (Send/Receive) to the moment a user taps an active connection.

The existing Zero Remanence session flow (SenderScreen → TransferProgressScreen; ReceiverScreen → ReceiverTransferScreen) is UNCHANGED. Phase 5 adds the connection-management layer on top; it does not alter the in-session crypto or cleanup logic.

</domain>

<decisions>
## Implementation Decisions

### Neutral Handshake Data Model
- **D-01:** Rename `senderId`/`receiverId` in handshake logic to `proposerId` (initiator) and `partnerId` (recipient). Default `status: 'pending'`. Firestore security rules updated: create allowed for `proposerId == auth.uid`; read for either party; update allowed for `partnerId` only (restricting `status` to `connected` or `rejected`).

### Approval Dialog Format — Partner Side
- **D-02:** Incoming handshake proposals surface to the partner as a `_NotifBanner` OverlayEntry with inline **Accept** and **Reject** buttons (reuse the existing banner pattern in `home_screen.dart`).
- **D-03:** If the partner dismisses the banner without acting, the proposal stays `pending` and re-surfaces as a persistent **Pending Requests** section on HomeScreen. No auto-expire.

### HomeScreen Restructuring
- **D-04:** Standalone **Send / Receive role buttons are RETIRED**. All sessions must go through an Active Connection. New users with no connections see an empty-state prompt: "No connections yet" + "Add New Connection" button.
- **D-05:** HomeScreen layout (top to bottom): Welcome banner → **Active Connections section** → **Pending Requests section** → Recent Transfers (the role buttons area is replaced by Active Connections + Pending Requests).
- **D-06:** New connection proposals are initiated via an **"Add New Connection" button inside the Active Connections section**. Tapping it opens the friend search to select a user and send a neutral handshake proposal.

### Proposer Feedback UX
- **D-07:** When a proposal is sent, a **Pending row appears immediately** in the Active Connections section with a `Pending` badge. The proposer continues using the app normally — no blocking waiting screen.
- **D-08:** When the partner responds, the proposer sees a **5-second fading `_NotifBanner`** showing "Connection accepted by @username" or "Connection rejected by @username".
- **D-09:** On rejection, the Pending row **disappears silently** after the outcome banner dismisses. No red flash or linger.
- **D-10:** The Pending row has a **cancel button** that lets the proposer withdraw before the partner responds. Cancelling deletes the Firestore handshake doc.

### Role Selection at Session Start
- **D-11:** Tapping an **Active Connection row** opens a **bottom sheet** with two large tiles: **[Send File]** and **[Receive File]**. The bottom sheet follows the existing `_FindSenderSheet` modal pattern.
- **D-12:** Role selection is **independent** — each user picks their own role. No cross-device coordination at this step. The two users decide independently which role they want.
- **D-13:** Tapping **[Send File]** navigates to the existing `SenderScreen` with the partner **pre-filled** — the `_FindSenderSheet` discovery step is bypassed. The user lands directly at the handshake/waiting state with that partner wired in.
- **D-14:** Tapping **[Receive File]** navigates to the existing `ReceiverScreen` with the partner **pre-filled** via `SessionManager.selectSender()` — the manual partner-selection step is bypassed. The user lands at the mailbox-open state with that partner already set.

### Claude's Discretion
- How Pending Requests section handles the case where both parties send simultaneous proposals to each other (e.g., merge into one connected state or show as two separate pending rows).
- Cancel button placement within the Pending row (icon button vs. swipe-to-dismiss vs. context menu).
- Exact Firestore doc ID scheme for the new neutral handshake collection (deterministic vs. auto-ID).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### HomeScreen and notification banner
- `lib/presentation/home/home_screen.dart` — HomeScreen layout, `_NotifBanner` OverlayEntry pattern (lines 54–86), existing notification listener; this is the primary file to restructure for Active Connections + Pending Requests sections
- `lib/presentation/home/find_friends_screen.dart` — friend search UI; reused/adapted as the "Add New Connection" flow for sending proposals

### Sender-side integration point
- `lib/presentation/sender/sender_screen.dart` — `_FindSenderSheet` (partner discovery to be bypassed when entering from Active Connection), `_WaitingForConnectionWidget`, `_ConnectedBadge`, `streamHandshakesForSender()` usage; SenderScreen entry must accept a pre-filled partner
- `lib/data/repositories/key_repository.dart` — `selectSenderHandshake()` (atomic WriteBatch for handshake), `streamHandshakesForSender()` (basis for proposer's pending stream), `publishRSAPublicKey()` — handshake data model lives here

### Receiver-side integration point
- `lib/presentation/receiver/receiver_screen.dart` — `_onSenderSelected()` and `SessionManager.selectSender()` — pre-fill flow when entering from Active Connection bypasses `_FindSenderSheet` and calls `selectSender()` directly

### Firestore rules
- `firestore.rules` — handshake collection security rules must be updated for `proposerId`/`partnerId` semantics; update/create restrictions are part of D-01

### Prior phase context
- `.planning/phases/04-zero-remanence-reactive-session-termination-receiver-as-mast/04-CONTEXT.md` — in-session cleanup flow that Phase 5 feeds into; the role picker (D-13/D-14) is the on-ramp to the Phase 4 session lifecycle

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `_NotifBanner` OverlayEntry (`home_screen.dart:54–86`) — reuse for both partner approval banner (D-02) and proposer outcome banner (D-08)
- `_FindSenderSheet` (`sender_screen.dart`) — bottom sheet modal pattern; new role-selection bottom sheet follows the same structure
- `selectSenderHandshake()` (`key_repository.dart`) — atomic WriteBatch pattern for handshake doc + user doc; adapt for neutral `proposerId`/`partnerId` semantics
- `streamHandshakesForSender()` (`key_repository.dart`) — Firestore stream for handshake status changes; basis for the pending/connected reactive stream
- `SessionManager.selectSender(uid, username)` (`session_manager.dart`) — pre-fill mechanism for ReceiverScreen; called directly from role picker (D-14)
- `_WaitingForConnectionWidget` pulsing animation (`sender_screen.dart`) — reuse or adapt for the Pending row animation in Active Connections

### Established Patterns
- `WriteBatch` for atomic multi-doc Firestore ops — use for accept/reject state transitions and cancel
- `StreamBuilder` on Firestore snapshots — the pending/connected state in Active Connections section is a live stream, not a one-time fetch
- `pushReplacement` for navigation into session screens (established in Phases 3/4)
- `_NotifBanner` auto-dismiss timer — existing 5-second auto-dismiss behaviour; reuse as-is for D-08

### Integration Points
- HomeScreen `_notifListener` Firestore stream — extend to also listen for `partnerId == currentUser.uid && status == pending` handshake docs to trigger the approval banner (D-02)
- SenderScreen constructor — add optional `preFilledPartner` param (uid + username) so Active Connection role picker can bypass `_FindSenderSheet`
- ReceiverScreen — add optional entry point that calls `_onSenderSelected(partner)` directly, skipping the manual find-sender UX

</code_context>

<specifics>
## Specific Ideas

- Role buttons on HomeScreen are **fully retired** — this is a deliberate simplification. All sessions require a prior neutral connection. No ad-hoc sessions.
- The bottom sheet role picker (D-11) bridges directly to the **existing** SenderScreen / ReceiverScreen — no new session-flow screens. Phase 5 is purely a connection-layer change.
- Partner pre-fill (D-13/D-14) is the key integration: the Active Connection carries the partner UID and username, so neither party needs to re-discover each other inside the session screens.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 05-neutral-handshake-model*
*Context gathered: 2026-05-12*
