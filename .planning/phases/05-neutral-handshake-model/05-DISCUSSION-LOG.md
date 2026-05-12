# Phase 5: Neutral Handshake Model — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-12
**Phase:** 05-neutral-handshake-model
**Mode:** discuss (resumed from checkpoint — 2 areas from prior session, 2 areas in current session)
**Areas discussed:** Approval dialog format, HomeScreen restructuring, Proposer feedback UX, Role selection at session start

---

## Approval dialog format

| Option | Description | Selected |
|--------|-------------|----------|
| Banner with inline buttons | Reuse _NotifBanner OverlayEntry with Accept/Reject buttons | ✓ |
| Bottom sheet | Modal bottom sheet with accept/reject actions | |
| Full-screen modal dialog | Interrupts UX completely | |

**User's choice:** Banner with inline buttons
**Notes:** Reuse existing `_NotifBanner` OverlayEntry pattern from home_screen.dart

---

| Option | Description | Selected |
|--------|-------------|----------|
| Proposal stays pending — re-surfaces on HomeScreen | Persistent Pending Requests section | ✓ |
| Proposal stays pending — banner re-appears on next open | Re-triggers banner | |
| Auto-expire after timeout | Proposal deleted if not acted on | |

**User's choice:** Proposal stays pending — persistent Pending Requests section on HomeScreen

---

## HomeScreen restructuring

| Option | Description | Selected |
|--------|-------------|----------|
| Remove role buttons | No more standalone Send/Receive | |
| Keep them as secondary option | Buttons stay but deprioritised | |
| Replace with single Connect button | One button → role picker | |

**User's choice (revised later):** Role buttons fully retired — all sessions go through Active Connections (updated from initial "keep as-is" to "retire" during Role selection discussion)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Above role buttons | Between welcome banner and role buttons | ✓ |
| Between role buttons and Recent Transfers | Below role buttons | |

**User's choice:** Active Connections + Pending Requests above role buttons (role buttons now retired)

---

| Option | Description | Selected |
|--------|-------------|----------|
| New Connection button inside Active Connections section | Opens friend search | ✓ |
| Keep in SenderScreen as-is | No HomeScreen entry point | |

**User's choice:** Add New Connection button inside Active Connections section

---

## Proposer feedback UX

| Option | Description | Selected |
|--------|-------------|----------|
| Pending badge on the connection row | Row appears immediately with Pending badge | ✓ |
| Toast/snackbar confirmation only | Brief snackbar, row doesn't appear until accepted | |
| Full waiting screen | Blocks the proposer | |

**User's choice:** Pending badge on connection row — proposer continues using app normally

---

| Option | Description | Selected |
|--------|-------------|----------|
| Fading overlay banner — accepted/rejected | 5-second auto-dismiss _NotifBanner | ✓ |
| Snackbar only | Simple SnackBar at bottom | |
| Push notification + in-app banner | Device notification + banner | |

**User's choice:** Fading overlay banner (reuse _NotifBanner, 5-second auto-dismiss)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Row disappears silently after the banner | Clean removal after outcome banner | ✓ |
| Row turns red with Rejected label briefly, then removes | Explicit visual rejection feedback on row | |

**User's choice:** Row disappears silently after the outcome banner

---

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — cancel button on the Pending row | Proposer can withdraw before partner responds | ✓ |
| No — only the partner can act on it | Proposal immutable once sent | |

**User's choice:** Cancel button on Pending row; cancellation deletes Firestore handshake doc

---

## Role selection at session start

| Option | Description | Selected |
|--------|-------------|----------|
| Bottom sheet with two big buttons | [Send File] / [Receive File] tiles; bridges to existing screens | ✓ |
| Inline action buttons on the row | Row expands in place | |
| Dialog with two options | AlertDialog style | |

**User's choice:** Bottom sheet — bridges to existing SenderScreen / ReceiverScreen once role is selected

---

| Option | Description | Selected |
|--------|-------------|----------|
| Independent — each user picks their own role | No cross-device coordination | ✓ |
| Coordinated — one user triggers, other sees prompt | Explicit consent from both sides | |

**User's choice:** Independent role selection

---

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — partner pre-filled, skip discovery | SenderScreen opens with partner already set | ✓ |
| No — SenderScreen opens normally | User still goes through _FindSenderSheet | |

**User's choice:** Partner pre-filled in SenderScreen (bypass _FindSenderSheet)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — partner pre-filled, skip _FindSenderSheet | ReceiverScreen opens with sender pre-selected | ✓ |
| No — ReceiverScreen opens normally | User manually selects sender | |

**User's choice:** Partner pre-filled in ReceiverScreen (bypass manual partner selection)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Keep HomeScreen role buttons (ad-hoc sessions) | Already decided from earlier area | |
| Retire them — all sessions through Active Connections | ✓ |
| Demote to overflow menu | | |

**User's choice:** Retire role buttons — all sessions must go through a connection. Empty state shows "No connections yet" + "Add New Connection" button.

---

## Claude's Discretion

- Simultaneous mutual proposals (both users propose to each other at same time)
- Cancel button placement within Pending row
- Firestore doc ID scheme for neutral handshake collection

## Deferred Ideas

None raised during discussion.
