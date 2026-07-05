---
status: resolved
trigger: "Home screen freezes (full app hang) when another user sends a connection proposal to the current user"
created: 2026-06-13T00:00:00Z
updated: 2026-07-05T00:00:00Z
---

## Current Focus

hypothesis: _ProposalBanner is inserted into the Overlay stack as an opaque hit-test blocker, intercepting all pointer events from the user. Because it has no auto-dismiss timer and its close button is visually positioned but rendered at full-overlay-entry Z-order, all taps on the underlying home screen (including navigation buttons, drawer, etc.) are swallowed by the banner's Material/GestureDetector layer — causing the UI to appear frozen.
test: Code inspection — trace what the OverlayEntry renders and whether it absorbs pointer events for the full screen
expecting: Confirmed — OverlayEntry builder wraps content in a Material widget which is by default opaque to hit-testing, blocking all touches to widgets below
next_action: DONE — root cause confirmed via code trace

## Symptoms

expected: User receives incoming proposal notification but can still navigate the home screen normally
actual: Home screen completely freezes — cannot navigate anywhere; must force-close
errors: No crash, no error message — purely a UI hang / input-blocked state
reproduction: Have another user send a connection proposal while you are on the home screen
started: Current

## Eliminated

- hypothesis: Firestore security rule hang (like prior dialogs-freeze-on-proposal-accept bug)
  evidence: streamIncomingPending() is a plain .snapshots() query read — no write/transaction involved. Read rule is simple isAuthenticated() + field check. Cannot hang.
  timestamp: 2026-06-13

- hypothesis: runTransaction() retry loop
  evidence: _startHandshakeListener only calls _showProposalBanner on DocumentChangeType.added. No transaction is invoked in the stream callback path.
  timestamp: 2026-06-13

- hypothesis: showDialog() blocking navigation
  evidence: No showDialog() is called from _startHandshakeListener. The proposal display uses OverlayEntry, not a dialog.
  timestamp: 2026-06-13

## Evidence

- timestamp: 2026-06-13
  checked: home_screen.dart _showProposalBanner() lines 250-284
  found: Creates an OverlayEntry whose builder returns _ProposalBanner wrapped in a Positioned widget inside a Material(color: Colors.transparent) widget
  implication: Material widget with color:transparent is still opaque to hit-testing by default (absorbs pointer events)

- timestamp: 2026-06-13
  checked: _ProposalBanner widget (lines 895-1034)
  found: The banner has NO auto-dismiss timer (initState comment explicitly says "No auto-dismiss"). It renders action buttons (Accept/Decline) and a close icon but the entire banner is a Container sitting inside an OverlayEntry — which covers the full overlay surface.
  implication: The OverlayEntry is inserted on top of the navigator stack. The Positioned widget places the banner at a specific position but the OverlayEntry itself fills the entire overlay — any touch OUTSIDE the visible banner card but within the overlay area still hits the OverlayEntry's hit-test region.

- timestamp: 2026-06-13
  checked: Flutter OverlayEntry + Material hit-testing behavior
  found: An OverlayEntry covers the full overlay. Its builder widget tree participates in hit-testing. Material(color: Colors.transparent) still has HitTestBehavior.opaque by default, meaning it absorbs ALL pointer events in its bounds — which is the full screen. Only areas explicitly painted (the Positioned card) are "visible" but the Material fills the entire overlay slot.
  implication: Every tap, swipe, or navigation gesture on the home screen is intercepted by the transparent-but-opaque-to-hits Material layer. The user cannot tap any nav item, drawer, button, or FAB. App appears frozen.

- timestamp: 2026-06-13
  checked: _ProposalBannerState (lines 912-1034) — dispose(), initState()
  found: No timer to auto-remove. The banner stays forever until the user explicitly taps Accept, Decline, or the X close icon. Since those are the only hit-testable elements in the banner card area, the user IS able to interact with those — but nothing outside the banner card responds.
  implication: If the user is not aware of the X close button (or misses it), the entire UI is bricked until force-close.

- timestamp: 2026-06-13
  checked: _showProposalBanner entry insertion: Overlay.of(context).insert(entry) at line 283
  found: The entry is inserted into the navigator's overlay — this is above ALL route-level widgets including the AppBar, Scaffold body, and bottom nav.
  implication: Confirmed full-screen input blocking.

## Resolution

root_cause: _ProposalBanner is inserted as an OverlayEntry wrapping a Material(color:Colors.transparent) widget that fills the full overlay slot. Material is opaque to hit-testing regardless of its paint color. The banner has no auto-dismiss. Result: ALL touches outside the small banner card (taps on home body, drawer, AppBar) are absorbed by the transparent Material, making the app appear completely frozen.

fix: Superseded by a later home_screen.dart rewrite rather than patched in place. The original _ProposalBanner/_startHandshakeListener mechanism no longer exists — incoming connection/friend requests were relocated entirely to FindFriendsScreen's inline "Incoming Requests" list (plain Material list rows, no OverlayEntry). HomeScreen now only has two OverlayEntry banners (_showNotifBanner for rsa_key_received/file_received, _showOutcomeBanner for the proposer's own outgoing-request outcome), both confined via a Positioned root + scoped Material and both auto-dismiss after 5s — neither can block full-screen hit-testing and neither fires on an incoming request.

verification: "Traced 2026-07-05: grepped home_screen.dart for _ProposalBanner/_startHandshakeListener/streamIncomingPending — zero matches. Confirmed find_friends_screen.dart renders incoming requests as inline list rows (line 478 'Incoming Requests' section) with no OverlayEntry. No code path remains that can reproduce the original full-screen Material hit-test block."
files_changed: [lib/presentation/home/home_screen.dart, lib/presentation/home/find_friends_screen.dart]
