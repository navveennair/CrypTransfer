# Phase 10: UI Polish Phase 2 + Stale-Key Security Fix — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-31
**Phase:** 10-ui-polish-phase-2-stale-key-security-fix
**Areas discussed:** Phase scope definition

---

## Phase Scope

| Option | Description | Selected |
|--------|-------------|----------|
| UI Polish + Security Fix | Commit glassmorphic dialog work + restore stale-key guard | ✓ |
| Security Fix Only | Just restore stale-key guard, defer UI | |
| UI Polish Only | Commit UI work, defer stale-key fix to quick task | |

**User's choice:** UI Polish + Security Fix  
**Notes:** Both workstreams are in-flight (UI work already in working tree, security guard is a known regression from Phase 09). Combining them keeps Phase 10 clean and production-ready.

---

## Context Discovery

**Security regression (identified by integration agent during /gsd-next):**
- WIP commit `580616d` dropped the `previousPublicKey` + stale-key check from `_onHandshakeUpdate`
- Phase 09 VERIFICATION.md verified this at lines 207-230 (commit `793e226`) — no longer in working tree
- Impact: sender can encrypt AES key to a stale receiver public key without notification

**UI work in working tree (from session before this one):**
- 6 presentation screens have glassmorphic dialog rewrites (transparent AlertDialog + GlassContainer + CrypButton)
- Admin dashboard quick task 260531-a1k complete but uncommitted (4 tasks done)
- ROADMAP.md Phase 999.1 backlog + Phase 08 completion status: unstaged changes

## Claude's Discretion

- Exact commit strategy (atomic vs batched waves)
- Whether to run flutter test in each wave or only final gate
- Minor dialog text wording (preserve intent)
