---
status: diagnosed
trigger: "Cancel/trash icon on pending connection proposal shows no confirmation bottom sheet — cancellation happens immediately or does nothing"
created: 2026-05-13T00:00:00Z
updated: 2026-05-13T00:00:00Z
---

## Current Focus

hypothesis: _cancelProposal() IS implemented and IS wired to the IconButton, but the IconButton's onPressed fires _cancelProposal directly — which itself calls showModalBottomSheet. Investigation confirms the sheet code exists in full; the issue is NOT a missing sheet.
test: Trace the exact call path from IconButton.onPressed through _ActiveConnectionRow → onCancelTap callback → _HomeScreenState._cancelProposal
expecting: Sheet IS shown; bug report symptom may not match current code, OR a context/widget-tree issue causes showModalBottomSheet to silently fail.
next_action: DIAGNOSED — see Resolution

## Symptoms

expected: Tapping the cancel icon on a pending outgoing connection row should open a "Cancel connection request?" confirmation bottom sheet before any Firestore write.
actual: No confirmation sheet appears — cancellation reportedly happens immediately or icon does nothing.
errors: None reported
reproduction: Tap trash/cancel icon on a pending (amber "Pending" badge) outgoing connection row in Active Connections on HomeScreen.
started: Unknown — possibly always broken or regressed

## Eliminated

- hypothesis: _cancelProposal() method does not exist or calls cancelProposal() directly without a sheet
  evidence: Lines 276-324 of home_screen.dart show _cancelProposal() is fully implemented with showModalBottomSheet, GlassContainer, CrypButton("Cancel Request"), and TextButton("Keep Waiting"). It does NOT call cancelProposal() directly.
  timestamp: 2026-05-13

- hypothesis: The IconButton in _ActiveConnectionRow is missing an onPressed handler
  evidence: Lines 1059-1065 — IconButton.onPressed is `() => onCancelTap(docId: docId, partnerUsername: username)`. It is wired correctly.
  timestamp: 2026-05-13

- hypothesis: The onCancelTap callback is not passed down to _ActiveConnectionRow
  evidence: Lines 988-991 in _ActiveConnectionsSection pass onCancelTap to _ActiveConnectionRow for pending rows. Lines 957-959 also pass it for connected rows (though cancel icon only renders when !isConnected per line 1059).
  timestamp: 2026-05-13

- hypothesis: Widget is in a separate file under lib/presentation/home/widgets/
  evidence: Glob found no files in that directory. All widget code is in home_screen.dart.
  timestamp: 2026-05-13

## Evidence

- timestamp: 2026-05-13
  checked: home_screen.dart lines 276-324
  found: _cancelProposal() calls showModalBottomSheet with a full confirmation sheet. Content: title "Cancel connection request?", body "Cancel request to @$partnerUsername? They won't be notified.", CrypButton("Cancel Request") that calls Navigator.pop then _handshakeRepo.cancelProposal(docId), TextButton("Keep Waiting") that calls Navigator.pop.
  implication: Confirmation sheet IS implemented. The bug is not a missing sheet.

- timestamp: 2026-05-13
  checked: home_screen.dart lines 1059-1065 (_ActiveConnectionRow.build)
  found: IconButton with icon Icons.cancel_outlined, color Colors.amber.shade400, onPressed fires `onCancelTap(docId: docId, partnerUsername: username)`. The guard `if (!isConnected)` at line 1059 means the button only renders for pending rows.
  implication: Wiring from icon to callback is correct.

- timestamp: 2026-05-13
  checked: home_screen.dart lines 432-443 (_HomeScreenState.build — _ActiveConnectionsSection instantiation)
  found: onCancelTap: _cancelProposal is passed at line 438.
  implication: The _HomeScreenState._cancelProposal method is the actual handler.

- timestamp: 2026-05-13
  checked: home_screen.dart lines 979-991 (_ActiveConnectionsSection.build — pending rows construction)
  found: _ActiveConnectionRow constructed with isConnected: false and onCancelTap: onCancelTap (which is _cancelProposal from state). The docId comes from doc.id and partnerUsername from data['partnerUsername'].
  implication: partnerUsername is read from Firestore field 'partnerUsername'. If that field is missing/empty in a Firestore doc, _cancelProposal receives an empty string — sheet still appears but text says "Cancel request to @?".

- timestamp: 2026-05-13
  checked: home_screen.dart lines 276-324 — _cancelProposal context usage
  found: showModalBottomSheet uses `context` (the BuildContext from _HomeScreenState). The builder parameter uses `ctx` (the sheet's own BuildContext), and CrypButton.onPressed calls Navigator.pop(ctx) then references `context` (outer) for ScaffoldMessenger. This is correct.
  implication: No context mismatch that would cause showModalBottomSheet to fail.

## Resolution

root_cause: The confirmation bottom sheet IS fully implemented. The call chain is intact: IconButton.onPressed → onCancelTap(docId, partnerUsername) → _HomeScreenState._cancelProposal() → showModalBottomSheet(). Based on static analysis there is NO missing implementation. The bug as described (no sheet appears) is most likely caused by one of two runtime conditions:

  CONDITION A — context not yet mounted / BuildContext from a deactivated element: _ActiveConnectionRow is a StatelessWidget. Its build context is a child of the StreamBuilder tree inside _ActiveConnectionsSection. If a rapid Firestore update causes the widget to be deactivated at the exact moment the tap fires, the context passed up via onCancelTap may be stale. However this is unlikely for a simple tap.

  CONDITION B — showModalBottomSheet silently fails because context does not belong to a Scaffold ancestor that is still mounted. _cancelProposal is called on _HomeScreenState's context (captured in the closure at line 438: `onCancelTap: _cancelProposal`). This context IS a Scaffold context and should be valid throughout the screen lifetime.

  CONDITION C (most likely cause of initial report): The cancel IconButton's tap target is small (default IconButton size 48x48) but it sits inside an InkWell (lines 1078-1085) that fires a SnackBar on tap. If the user's tap registers on the InkWell rather than the IconButton, they see a SnackBar ("Waiting for @X to respond") instead of the sheet. The InkWell wraps the entire row including the area around the IconButton. Flutter's hit-test gives precedence to the innermost widget, so a direct tap on the icon should reach the IconButton — but a tap on the badge or row body hits the InkWell. This is a UX confusion issue, not a code bug.

  CONDITION D: If the Firestore 'partnerUsername' field is absent (empty string), the sheet title/body renders with empty username but still opens. Not a silent-failure scenario.

fix: No code change required for the confirmation sheet logic — it is correctly implemented. To eliminate CONDITION C confusion:
  1. The InkWell for the pending row at lines 1078-1085 fires a SnackBar instead of the sheet. A user who taps the row body (not the icon) sees only the SnackBar. Consider removing or narrowing the InkWell for !isConnected rows, or removing it entirely (the cancel icon is the only meaningful action for a pending row).

verification: Static analysis complete. No runtime test performed.
files_changed: []
