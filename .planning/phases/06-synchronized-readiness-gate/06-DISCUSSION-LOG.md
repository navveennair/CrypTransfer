# Phase 6: Synchronized Readiness Gate - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-15
**Phase:** 06-synchronized-readiness-gate
**Areas discussed:** Readiness signal location, Sender waiting UI, Receiver trigger moment, Safety timer UX

---

## Readiness signal location

| Option | Description | Selected |
|--------|-------------|----------|
| Create Transfers doc early | Sender creates lightweight Transfers doc at SenderScreen entry; receiver updates it | |
| Use the handshake doc | Add `receiverReady` field to existing RSA handshake doc in `handshakes/`; sender already streams this | ✓ |
| Use the receiver's user doc | Watch `users/{receiverUid}.isReadyToReceive`; fires at Step 2 not Step 3 | |

**User's choice:** Use the handshake doc
**Notes:** Avoids creating a new doc before the file is even picked; sender already has the handshake stream open via `streamHandshakesForSender()`.

---

## Sender waiting UI

| Option | Description | Selected |
|--------|-------------|----------|
| Full-screen pulsing replacement | Steps 1–4 hidden; Step 0 expands with pulsing widget + countdown | ✓ |
| Dimmed step cards below a banner | Steps visible at opacity 0.4; banner above | |
| Step 0 badge changes, rest normal | Step 0 shows amber badge; steps 1–4 unchanged but disabled | |

**User's choice:** Full-screen pulsing replacement
**Notes:** Steps hidden until receiver ready; snackbar + AnimatedOpacity fade-in on unlock.

---

## Receiver trigger moment

| Option | Description | Selected |
|--------|-------------|----------|
| After handshake WriteBatch succeeds | Write `receiverReady: true` after `selectSenderHandshake()` resolves in `_onSenderSelected()` | ✓ |
| When receiver opens mailbox (Step 2) | Write in `_onToggleReady(true)` after `setupReceiverSession` — fires before handshake | |

**User's choice:** After handshake WriteBatch succeeds
**Notes:** Atomic confirmation required; receiver not truly ready until sender is specifically authorized via WriteBatch.

---

## Safety timer UX

| Option | Description | Selected |
|--------|-------------|----------|
| Silent timer, snackbar on eject | No visible countdown; red snackbar + HomeScreen on expiry | |
| Visible countdown in waiting widget | Countdown shown "MM:SS remaining" in pulsing widget; updates every second | ✓ |
| Warning dialog at 10 seconds | Modal dialog at T-10 with Stay/Leave; more complex | |

**User's choice:** Visible countdown in waiting widget
**Notes:** 1-minute duration (spec'd in ROADMAP); timer cancelled if receiverReady fires before expiry.

---

## Claude's Discretion

- Countdown display format (MM:SS vs "N seconds remaining")
- Whether `senderReady` field is added to handshake doc (symmetric but not functionally required)
- Dart Timer implementation details
- Animation curve for steps fading in

## Deferred Ideas

None — discussion stayed within phase scope.
