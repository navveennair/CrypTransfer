---
status: resolved
trigger: "app freezes when receiving connection request at home page itself"
created: 2026-06-14
updated: 2026-06-14
---

## Current Focus

hypothesis: RESOLVED. Root cause proven by runtime stack trace: CrypButton's internal Stack (all-positioned children) requires bounded width; the proposal banner placed two CrypButtons directly in a Row (unbounded width) → "A Stack requires bounded constraints" layout assertion → zero-size render box → per-frame "Cannot hit test a render box with no size" exception storm → frozen UI.
test: "Wrapped both banner CrypButtons in Expanded (bounded width). Rebuilt on emulator pair, re-fired the proposal banner."
expecting: "Banner renders, zero render exceptions, Home stays interactive."
next_action: "DONE — verified on emulator (banner built, 0 exceptions, app responsive). Instrumentation removed. flutter analyze clean."

instrumentation_applied:
  file: lib/presentation/home/home_screen.dart
  tag: "[FREEZE-DBG]"
  steps:
    - "S00/S01/S02 — initState + listener startup"
    - "N01-N05 — _startNotifListener callback + type filter"
    - "H01-H06 — _startHandshakeListener: snapshot fired, docChanges loop, _showProposalBanner call"
    - "P01-P05 — _showProposalBanner: remove prior, extract data, Overlay.insert"
    - "P10 — OverlayEntry.builder execution"
    - "PB01/PB02 — _ProposalBanner.build enter + tree build"
    - "AC00-AC03 — _ActiveConnectionsSection three StreamBuilders (rebuild-storm detector)"
  helper: "_fdbg(String) logs via debugPrint AND developer.log(name:'FREEZE-DBG')"
  flutter_analyze: clean

reasoning_checkpoint:
  hypothesis: "_ProposalBanner StatefulWidget is the OverlayEntry root → Overlay gives it tight(screenSize) constraints → Positioned inside build() is NOT a direct Stack/Theater child → Container receives full-screen tight constraints → paints full-screen opaque surface → absorbs all pointer events"
  confirming_evidence:
    - "Flutter overlay.dart line 1478: nonPositionedChildConstraints = BoxConstraints.tight(size) for non-positioned theater children"
    - "Line 1103-1105: isPositioned check is on the _OverlayEntryWidget's parent data, NOT on the Positioned inside the StatefulWidget's build tree"
    - "_ProposalBanner is a StatefulWidget → RenderProxyBox passes full-screen tight constraints through to its Positioned child → Positioned passes to Container"
    - "Container decoration: BoxDecoration(color: cs.surfaceContainerHigh) — this is OPAQUE, meaning full-screen paint with a solid color"
    - "_NotifBanner has the same structure but uses Material(color: Colors.transparent) which is visually transparent — that is why it does NOT visually freeze (still covers screen but appears transparent)"
    - "Freeze happens 100% of time — consistent with deterministic full-screen cover, not intermittent timing/race"
  falsification_test: "If the Positioned WERE correctly constraining the banner widget in the overlay theater, the Container would only paint the card-sized area (~100px tall) and touches below would reach the HomeScreen. The fact that everything freezes disproves this."
  fix_rationale: "The OverlayEntry builder must return a widget that the Overlay theater can recognize as positioned. Either: (1) Convert _ProposalBanner to a StatelessWidget that returns Positioned directly from the builder (NOT via StatefulWidget indirection), or (2) Make the OverlayEntry builder return Positioned(..., child: _ProposalBannerContent(...)) where _ProposalBannerContent is the StatefulWidget."
  blind_spots: "Have not verified that _NotifBanner also causes a full-screen overlay (transparent not opaque so won't freeze interaction but paints backdrop). Secondary issue to fix separately."

## Symptoms

- expected: Connection request shows as incoming banner, home screen remains interactive
- actual: UI locks completely — nothing tappable, must force-close
- errors: No error messages — silent freeze
- reproduction: User A sends connection request while User B is on Home screen
- started: Reported 2026-06-14; possibly persisting despite fixes

## Eliminated

- hypothesis: "sendProposal() runTransaction retry loop"
  evidence: "sendProposal() uses get() + WriteBatch (no runTransaction). Confirmed in handshake_repository.dart lines 60-84."
  timestamp: 2026-06-14

- hypothesis: "Material(color:Colors.transparent) in _ProposalBanner absorbing all pointer events"
  evidence: "Material wrapper removed from _ProposalBanner OverlayEntry. OverlayEntry builder now returns _ProposalBanner directly → Positioned(left:16,right:16,top:top,child:Container(...)) with no full-screen hit blocker."
  timestamp: 2026-06-14

- hypothesis: "Positioned without bottom fills screen height in Overlay (hit-test region)"
  evidence: "In Flutter's RenderStack (and Overlay theater), a Positioned without bottom gives the child its intrinsic height. The hit-test region follows the painted bounds of the child (the card's content height), not the remaining screen height. Ruled out as the primary cause."
  timestamp: 2026-06-14

- hypothesis: "_NotifBanner Material(transparent) covering full screen for connection_request type"
  evidence: "_startNotifListener filters type == 'connection_request' before calling _showNotifBanner. _NotifBanner is never inserted for connection requests. This path cannot cause the freeze."
  timestamp: 2026-06-14

- hypothesis: "_startHandshakeListener called multiple times"
  evidence: "initState uses addPostFrameCallback which fires once per lifecycle. Single subscription via _pendingProposalSub. No double-subscribe path found."
  timestamp: 2026-06-14

- hypothesis: "_outgoingPendingStream or _activeAsPartnerStream fires for User B on incoming proposal"
  evidence: "streamOutgoingPending() filters proposerId==uid. streamActiveConnectionsAsPartner() filters status=='connected'. Incoming pending doc has proposerId==User A and status=='pending'. Neither stream fires for User B."
  timestamp: 2026-06-14

## Evidence

- timestamp: 2026-06-14
  checked: "home_screen.dart _showProposalBanner lines 257-283"
  found: "OverlayEntry builder returns _ProposalBanner(...) directly — no Material wrapper. _ProposalBanner is a StatefulWidget."
  implication: "Prior fix (removing Material wrapper) is in place. But a deeper structural issue remains."

- timestamp: 2026-06-14
  checked: "handshake_repository.dart sendProposal lines 40-111"
  found: "Uses snap = await docRef.get() then WriteBatch — no runTransaction"
  implication: "Prior fix is in place"

- timestamp: 2026-06-14
  checked: "_NotifBanner.build() lines 842-888"
  found: "Still wraps GestureDetector in Material(color: Colors.transparent). This IS the same blocked hit-testing bug BUT only fires for non-connection-request notification types. Connection requests are filtered before reaching _showNotifBanner."
  implication: "Potential separate bug for other notification types but should NOT cause connection-request freeze"

- timestamp: 2026-06-14
  checked: "_startNotifListener filter"
  found: "if (type == 'connection_request' || type == 'friend_request') return; — filters before _showNotifBanner"
  implication: "Connection request type correctly filtered; _NotifBanner with Material should not be triggered"

- timestamp: 2026-06-14
  checked: "_ProposalBanner.build() lines 929-1030"
  found: "Returns Positioned(top:top,left:16,right:16,child:Container(color:cs.surfaceContainerHigh,...)) — no bottom constraint, sized by Column(mainAxisSize:min)"
  implication: "Should NOT block full-screen IF Positioned were a direct theater child. But _ProposalBanner is a StatefulWidget root."

- timestamp: 2026-06-14
  checked: "Flutter overlay.dart source — _RenderTheater.layoutChild and performLayout"
  found: "Line 1478: nonPositionedChildConstraints = BoxConstraints.tight(size) — theater gives full-screen tight constraints to non-positioned children. Line 1103-1105: isPositioned check operates on the _OverlayEntryWidget's parent data, not on inner tree widgets."
  implication: "CRITICAL: _ProposalBanner as OverlayEntry root is non-positioned → gets full-screen tight constraints → passes to Positioned → passes to Container → Container fills full screen."

- timestamp: 2026-06-14
  checked: "_ProposalBanner StatefulWidget render chain"
  found: "StatefulWidget → RenderProxyBox → passes constraints unchanged to child. Positioned as ParentDataWidget → passes constraints to Container. Container receives BoxConstraints.tight(screenSize). Container with decoration BoxDecoration(color: cs.surfaceContainerHigh) paints a full-screen opaque rectangle."
  implication: "ROOT CAUSE CONFIRMED: Entire screen covered by opaque Container → all input blocked → freeze."

- timestamp: 2026-06-14
  checked: "_NotifBanner same structural pattern"
  found: "_NotifBanner is also a StatefulWidget returned by OverlayEntry builder, with Positioned inside build(). Has same full-screen sizing issue. But Material(color: Colors.transparent) inside means the screen is overlaid with a transparent surface. Visually invisible but still participates in hit-testing as transparent layer."
  implication: "Secondary bug: _NotifBanner also covers full screen when shown. Non-connection-request notifications (rsa_key_received, file_received) would cause full-screen hit-test absorption via the transparent Material. Needs the same fix."

## DISPROOF — fix applied, freeze persists (2026-06-14, reopened)

The Stack-wrapper fix WAS applied to both `_showProposalBanner` and `_showNotifBanner`
(OverlayEntry builders now return `Stack(children: [_ProposalBanner(...)])`). `flutter analyze`
clean. User did a FULL RESTART (flutter run fresh — new Dart code confirmed loaded) and the
home screen STILL freezes instantly when the connection request arrives, before any touch.

This DISPROVES the overlay-hit-test-absorption hypothesis as the (whole) cause:
- A `Stack` as the OverlayEntry root definitively gives the inner `Positioned` correct
  Stack-relative layout. `Stack.hitTestSelf` is false, so empty regions do NOT absorb pointer
  events. If hit-test absorption were the cause, the Stack wrapper would have fixed it.
- Symptom refinement from user: freeze is "instant when request arrives, before touching
  anything." This points toward a main-thread block / synchronous hang triggered by the
  incoming Firestore snapshot — NOT a passive touch-blocking overlay (a touch-blocker would
  leave the screen animating/scrollable, just untappable).

This bug has now been diagnosed-and-"fixed" THREE times (runTransaction→WriteBatch;
Material-wrapper removal; StatefulWidget→Stack) and still reproduces. All three diagnoses were
speculative reasoning about Flutter/Firestore internals with NO runtime evidence. STOP guessing.
Next step MUST be runtime ground truth (logs/timestamps along the incoming-proposal path),
not another armchair fix.

- hypothesis: "Overlay full-screen opaque Container absorbs pointer events (StatefulWidget-as-root)"
  evidence: "Stack-wrapper fix applied to both banners, flutter analyze clean, full restart — still freezes instantly on arrival. Stack root makes inner Positioned hit-test correctly; empty areas pass touches through. Disproven as the cause."
  timestamp: 2026-06-14

## ROOT CAUSE FOUND — runtime evidence (2026-06-14)

RUNTIME LOG (receiver emulator, instrumented build) — captured at the instant a connection
request arrives:

```
[FREEZE-DBG] ... N01 notifStream fired (notif null? false)
[FREEZE-DBG] ... N02 notif type=connection_request
[FREEZE-DBG] ... N03 notif filtered out (type=connection_request)
Another exception was thrown: Cannot hit test a render box with no size.
Another exception was thrown: Cannot hit test a render box with no size.
Another exception was thrown: Cannot hit test a render box with no size.
... (repeats every frame — exception storm)
```

root_cause: |
  The freeze is NOT touch-absorption by an opaque overlay. It is a per-frame EXCEPTION STORM:
  "Cannot hit test a render box with no size." thrown repeatedly the instant the proposal
  banner OverlayEntry is inserted. A render box in the banner's overlay subtree has ZERO size,
  and Flutter throws on every attempt to hit-test it — flooding the engine and freezing the UI.

  The trigger is the OverlayEntry builder structure. The current code (my prior "fix") wraps the
  banner in `Stack(children: [_ProposalBanner(...)])`, and `_ProposalBanner.build()` itself
  returns a `Positioned(top, left, right, child: Container(...))`. A `Stack` whose ONLY child is
  a `Positioned` (no non-positioned child to give the Stack an intrinsic size), laid out under
  the Overlay theater, collapses such that the relevant render box has no resolvable size →
  hit-test throws → storm.

  This same zero-size condition — not opaque-fill — was almost certainly the TRUE cause behind
  all prior "freeze" reports. Every earlier fix reshuffled the Positioned/Material/Stack nesting
  without ever giving the overlay child a real, theater-recognised size, so the storm persisted.

fix: |
  Use the documented Flutter overlay-banner pattern: the OverlayEntry builder returns
  `Positioned(...)` as its DIRECT root (the Overlay's _Theater is Stack-like and natively
  understands Positioned), and the Positioned's child is a normally-sized banner widget that
  does NOT itself return a Positioned.

  Concretely, for BOTH _showProposalBanner and _showNotifBanner:
    builder: (ctx) => Positioned(
      top: MediaQuery.of(ctx).padding.top + kToolbarHeight + 8,
      left: 16, right: 16,
      child: _ProposalBanner(...),   // or _NotifBanner(...)
    )
  And change _ProposalBannerState.build() / _NotifBannerState.build() to return their inner
  content (Container / Material-wrapped content) directly, WITHOUT the outer Positioned.

  This removes the Stack-with-only-positioned-child, makes Positioned a direct theater child,
  and gives the banner a real intrinsic height → no zero-size render box → no hit-test storm.

verification: "SUPERSEDED — see FINAL ROOT CAUSE below. The overlay-structure fixes did NOT resolve it; full stack trace revealed the true cause."
files_changed:
  - lib/presentation/home/home_screen.dart

## FINAL ROOT CAUSE — stack-trace proven (2026-06-14)

The "zero-size overlay" theory above was still a symptom, not the cause. Returning `Positioned`
directly from the OverlayEntry builder ALSO froze. A `flutter run` console on the receiver
(5556) finally captured the FIRST full framework exception (it goes to the VM console, not
logcat — which is why every filtered logcat capture showed 0 hits):

```
══╡ EXCEPTION CAUGHT BY RENDERING LIBRARY ╞══
The following assertion was thrown during performLayout():
A Stack requires bounded constraints from its parent. ... Failed assertion: line 666: 'size.isFinite'
The relevant error-causing widget was:
  Stack  Stack:file:///.../lib/presentation/widgets/shared_widgets.dart:535:18
... RenderStack.layoutPositionedChild ← _RenderTheater.performLayout ...
RenderObject being processed: RenderStack ... creator: Stack ← SizedBox ← Transform ← Container
  ← AnimatedContainer ← ... ← GestureDetector ← CrypButton ← Row ← Column ← ...
  constraints: BoxConstraints(0.0<=w<=Infinity, h=48.0)   ← UNBOUNDED WIDTH
  size: MISSING
```

root_cause_final: |
  CrypButton (lib/presentation/widgets/shared_widgets.dart:535) builds its 3D effect from a
  `Stack` whose children are ALL positioned (Positioned + AnimatedPositioned, left:0/right:0).
  Such a Stack has no intrinsic width and REQUIRES a bounded width from its parent.

  The proposal banner placed two CrypButtons directly inside a `Row` (mainAxisAlignment.end)
  with no Expanded/Flexible and no explicit width. A Row gives non-flex children UNBOUNDED width
  (BoxConstraints 0..Infinity). CrypButton's internal Stack therefore failed its
  `size.isFinite` assertion during performLayout → the render box never got a size → every
  subsequent frame's hit-test threw "Cannot hit test a render box with no size." → per-frame
  exception storm → engine flooded → UI frozen the instant the banner was inserted.

  This is why all three earlier overlay fixes (runTransaction→WriteBatch; remove Material wrapper;
  StatefulWidget→Stack→Positioned-direct) failed: the crash was never in the overlay/positioning —
  it was inside CrypButton when handed unbounded width.

fix_final: |
  Wrapped both CrypButtons in the proposal banner's button Row in `Expanded`, giving each a
  bounded (finite) width. (lib/presentation/home/home_screen.dart, _ProposalBannerState.build)
  Also reverted the banner OverlayEntry builders to the clean documented pattern (builder returns
  Positioned directly; banner build() returns its content) — correct regardless, and removed the
  Stack-with-only-positioned-child noise.

  NOTE / latent risk surfaced: CrypButton is fragile by contract — it crashes in ANY unbounded-
  width parent (a bare Row). Audit found the other 14 usages are in Columns / full-width contexts
  (bounded), so the banner was the only live instance. A future hardening could make CrypButton's
  internal Stack self-size (add an invisible non-positioned sizer child) so it never requires
  bounded width; deferred to avoid app-wide blast radius on the shared button.

verification_final: "Rebuilt fixed app on emulator 5556 (receiver). Proposal banner fired on launch (H04→PB01→PB02 in the still-instrumented build), ZERO 'Cannot hit test' / 'requires bounded' / 'size.isFinite' lines, app process alive and responsive. Instrumentation then removed; `flutter analyze` (whole project): No issues found."

## Evidence (instrumentation cycle)

- timestamp: 2026-06-14
  checked: "handshake_repository.dart sendProposal — what lands on User B when a request is sent"
  found: "sendProposal writes TWO docs that reach User B near-simultaneously: (1) a neutral_handshakes pending doc → fires streamIncomingPending → _showProposalBanner; (2) a notifications inbox doc → fires latestUnreadStream (filtered: connection_request → no banner) AND unreadCountStream → rebuilds _NotifBellButton."
  implication: "Two snapshots arrive at once. Either the proposal-banner overlay insert/build, or a rebuild cascade, blocks the main thread. Instrumentation will disambiguate."

- timestamp: 2026-06-14
  checked: "notification_service.dart latestUnreadStream / unreadCountStream / allStream"
  found: "Plain .snapshots().map() with a simple in-memory sort. No loops, no synchronous heavy work. unreadCountStream is just s.size."
  implication: "Notification streams are not the blocker. Ruled out as a heavy-compute hang source."

- timestamp: 2026-06-14
  checked: "main.dart app root + grep for global .snapshots().listen / WidgetsBindingObserver"
  found: "No app-level notification/handshake listener. admin_guard.dart listener is gated to the /admin-dashboard route only. The incoming-proposal reaction is entirely inside _HomeScreenState."
  implication: "No hidden global observer fires on the new doc. Freeze originates in HomeScreen's own reaction path."

- timestamp: 2026-06-14
  checked: "shared_widgets.dart — GlassContainer uses BackdropFilter(ImageFilter.blur)"
  found: "_ProposalBanner does NOT use GlassContainer (plain Container + BoxDecoration). Its buttons are CrypButton. So no BackdropFilter in the proposal banner itself. (Note: _NotifBanner DOES use GlassContainer, but it is not shown for connection_request.)"
  implication: "A blur/raster hang in the proposal banner is unlikely. Kept as a low-probability candidate for the banner-paint phase (if last log line is PB02 with no further progress)."

## Resolution

root_cause: ""  # REOPENED — instrumentation applied, awaiting runtime logs
fix: ""
verification: ""
files_changed:
  - lib/presentation/home/home_screen.dart  # [FREEZE-DBG] instrumentation added (temporary)
