# Phase 10: UI Polish Phase 2 + Stale-Key Security Fix — Context

**Gathered:** 2026-05-31
**Status:** Ready for planning

<domain>
## Phase Boundary

Two parallel workstreams:
1. **Security regression fix** — restore the stale-key AES invalidation guard in `SenderScreen._onHandshakeUpdate` that was verified in Phase 09 (commit `793e226`) but dropped in WIP commit `580616d`.
2. **UI polish finalization** — commit and verify the glassmorphic dialog styling already implemented in the working tree across 6 presentation screens, plus the completed admin dashboard visual identity quick task (260531-a1k).

New features, new Firestore schema, and new user-facing flows are out of scope.

</domain>

<decisions>
## Implementation Decisions

### Security Fix (D-01 – D-03)
- **D-01:** Restore the `previousPublicKey` capture immediately before the `setState` block in `_onHandshakeUpdate` (line ~207 in the reference commit `793e226`). Capture as `final previousPublicKey = _selectedReceiverPublicKeyJson;`.
- **D-02:** After `setState`, apply the D-06 mid-flight guard (`if (_encrypting || _encryptingKey) return;`) before the stale-key check.
- **D-03:** Stale-key check condition: `if (previousPublicKey != null && publicKey != previousPublicKey && _encryptedAESKey != null)` → call `_wipeSensitiveData()` + SnackBar `'Receiver key changed — re-encrypt required.'`. Do NOT call `_revertToWaiting()` — preserve `_receiverId`, `_receiverUsername`, `_selectedReceiverPublicKeyJson` (file + receiver preserved, only encrypted state wiped).

### UI Polish — Dialog Styling (D-04 – D-06)
- **D-04:** All `AlertDialog` instances that currently use the plain Material design get the glassmorphic treatment: `backgroundColor: Colors.transparent`, `elevation: 0`, `insetPadding: EdgeInsets.all(24)`, content wrapped in `GlassContainer(padding: EdgeInsets.all(24), borderRadius: 28)`.
- **D-05:** Confirm/destructive actions inside dialogs use `CrypButton` (not `FilledButton` or `TextButton` for the primary action). Cancel actions remain `TextButton`. Buttons laid out in a `Row` with `Expanded` children.
- **D-06:** Icons added to dialogs: context-appropriate icon (48px) above the title — e.g., `Icons.link_off_rounded` for disconnect, `Icons.warning_rounded` for abort/destructive, `Icons.arrow_back_rounded` for nav-back dialogs.

### Admin Dashboard Visual Identity (D-07)
- **D-07:** Commit the completed 260531-a1k changes as-is: AppBar title `'CrypTransferAdmin'`, `GlassContainer` in `_SecurityLogTile` and `_NodeTile`, `AdminDashboardScreen` dark theme wrapper + `GlassContainer` list items + Orbitron/Exo2 fonts.

### Affected Files (working tree, already modified)
- `lib/presentation/admin/admin_dashboard.dart` — AppBar title rename
- `lib/presentation/admin/admin_dashboard_screen.dart` — full visual rewrite
- `lib/presentation/admin/widgets/connection_node_map.dart` — `_NodeTile` GlassContainer
- `lib/presentation/admin/widgets/security_pulse_feed.dart` — `_SecurityLogTile` GlassContainer
- `lib/presentation/home/find_friends_screen.dart` — disconnect dialog glassmorphic
- `lib/presentation/home/home_screen.dart` — dialog styling
- `lib/presentation/receiver/decrypt_screen.dart` — abort dialog glassmorphic
- `lib/presentation/receiver/receiver_transfer_screen.dart` — dialog styling
- `lib/presentation/sender/sender_screen.dart` — go-back dialog glassmorphic + stale-key guard
- `lib/presentation/sender/transfer_progress_screen.dart` — dialog styling

### Housekeeping
- **D-08:** Commit `ROADMAP.md` working-tree changes: Phase 999.1 backlog deferral, Phase 08 completion status, Phase 10 definition.
- **D-09:** No new Firestore rules, no schema changes, no new collections needed.

### Claude's Discretion
- Exact ordering of commits (atomic vs batched)
- Whether to run `flutter test` in Wave 1 or only in Wave 2 final gate
- Minor wording tweaks inside dialog text (keep intent, not verbatim)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Security Fix Reference
- Reference stale-key guard: `git show 793e226:lib/presentation/sender/sender_screen.dart` lines 207–227 — the exact D-05/D-06 block to restore
- Phase 09 verification: `.planning/phases/09-navigation-safety-session-integrity-hardening/09-VERIFICATION.md` — confirms D-05, D-06, D-07 were verified at lines 207-230 (now absent)

### UI Design System
- `design-system/cryptransfer/MASTER.md` — global color, spacing, and effects rules
- `design-system/cryptransfer/QUICK-FIX-GUIDE.md` — Phase 2 secondary fixes list; dialog styling is item 3 (StepCard visual hierarchy) and surrounding dialog improvements
- `lib/presentation/widgets/shared_widgets.dart` — `GlassContainer` and `CrypButton` widget definitions

### Quick Task Completed
- `.planning/quick/260531-a1k-admin-dashboard-ui-consistency/260531-a1k-PLAN.md` — task spec for admin dashboard changes
- `.planning/quick/260531-a1k-admin-dashboard-ui-consistency/260531-a1k-SUMMARY.md` — confirmed complete, 4/4 tasks done

### Prior Phase Context
- `.planning/phases/09-navigation-safety-session-integrity-hardening/09-03-PLAN.md` — original D-05/D-06 implementation spec
- `.planning/phases/09-navigation-safety-session-integrity-hardening/09-VERIFICATION.md` — verified stale-key guard was implemented (now regressed)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `GlassContainer` (`lib/presentation/widgets/shared_widgets.dart`) — glassmorphic container; used pattern: `GlassContainer(padding: EdgeInsets.all(24), borderRadius: 28, child: Column(...))`
- `CrypButton` (`lib/presentation/widgets/shared_widgets.dart`) — 3D button; used in confirm actions: `CrypButton(label: Text('...'), color: cs.error, onPressed: () => ...)`
- `_wipeSensitiveData()` (`lib/presentation/sender/sender_screen.dart`) — clears `_aesKey`, `_iv`, `_encryptedBytes`, `_encryptedAESKey`; does NOT clear receiver identity fields

### Established Patterns
- Glassmorphic dialog pattern already applied in `find_friends_screen.dart` and `sender_screen.dart` working tree — copy that exact structure for remaining screens
- All dialogs use `barrierDismissible: false` for destructive operations, `true` for informational

### Integration Points
- `_onHandshakeUpdate` in `lib/presentation/sender/sender_screen.dart` lines 134–248 — insert stale-key guard in the non-empty branch after `setState`
- `flutter analyze` must pass with no issues after all changes (baseline: 0 issues, 113/114 tests passing)

</code_context>

<specifics>
## Specific Ideas

- Dialog icon size: 48px, placed above title — establishes visual hierarchy in the glassmorphic container
- "Secure Inbox" label rename in `sender_screen.dart` (line ~746: `'File Transfer'` → `'Secure Inbox'`) is already in the working tree; keep it
- The stale-key guard must NOT use `_revertToWaiting()` — that would clear receiver selection; only `_wipeSensitiveData()` is correct (preserves who the receiver is, just clears encrypted state)

</specifics>

<deferred>
## Deferred Ideas

- Typography extraction to theme (Phase 2 item 1 from QUICK-FIX-GUIDE.md) — out of scope; separate quick task
- Glass opacity standardization (Phase 2 item 2) — out of scope
- Session state color migration (Phase 2 item 4) — out of scope
- Face ID re-enable (`biometric_helper.dart`) — noted in PROJECT.md pre-viva items; separate task

</deferred>

---

*Phase: 10-ui-polish-phase-2-stale-key-security-fix*
*Context gathered: 2026-05-31*
