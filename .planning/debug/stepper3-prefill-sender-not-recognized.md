---
status: investigating
trigger: "ReceiverScreen stepper 3 does not recognise pre-connected partner from neutral handshake flow"
created: 2026-05-13T00:00:00Z
updated: 2026-05-13T00:00:00Z
---

## Current Focus

hypothesis: "_onSenderSelected is called before _step2Done is true — _isReadyToReceive is still false when _checkKeyStatus() completes, so selectSenderHandshake throws KeyNotFoundException and _handshakeDone stays false; stepper 3 falls through to the 'Find & Select Sender' button branch"
test: "Trace _checkKeyStatus() + _loadReadyToReceiveState() completion order relative to the preFilledSenderUid callback"
expecting: "The prefill callback fires while _isReadyToReceive=false and the mailbox toggle is still OFF, meaning EncryptionService.setupReceiverSession has NOT been called yet and no public key exists in Firestore — selectSenderHandshake will find no publicKey and throw KeyNotFoundException"
next_action: "Document root cause and fix direction"

## Symptoms

expected: "When navigating to ReceiverScreen with preFilledSenderUid set, stepper 3 should show the pre-connected partner badge and auto-complete the RSA handshake without the user touching 'Find & Select Sender'"
actual: "Stepper 3 shows the 'Find & Select Sender' button as if no partner was pre-selected; RSA handshake never starts"
errors: "No visible crash — selectSenderHandshake likely throws KeyNotFoundException silently (caught by the catch block in _onSenderSelected, which calls _showError — but error may be swallowed if session not yet open)"
reproduction: "Navigate to ReceiverScreen via HomeScreen Role Picker 'Receive File' option with a connected partner"
started: "After neutral handshake refactor"

## Eliminated

- hypothesis: "Navigation args are not passed at all — preFilledSenderUid is null when ReceiverScreen is constructed"
  evidence: "home_screen.dart lines 263-268: ReceiverScreen(preFilledSenderUid: partnerUid, preFilledSenderUsername: partnerUsername) — args ARE passed correctly"
  timestamp: 2026-05-13

- hypothesis: "initState does not read the widget.preFilledSenderUid"
  evidence: "receiver_screen.dart lines 73-84: initState reads preFilledSenderUid and calls _onSenderSelected after _checkKeyStatus() completes — the read IS attempted"
  timestamp: 2026-05-13

## Evidence

- timestamp: 2026-05-13
  checked: "home_screen.dart _openRolePicker (lines 236-273)"
  found: "ReceiverScreen is constructed with preFilledSenderUid: partnerUid and preFilledSenderUsername: partnerUsername — both are passed correctly"
  implication: "Navigation layer is not the bug — args arrive at ReceiverScreen"

- timestamp: 2026-05-13
  checked: "receiver_screen.dart initState (lines 68-87)"
  found: "initState chains: _checkKeyStatus().then((_) { if (widget.preFilledSenderUid != null) _onSenderSelected(...) }). _subscribeToFriends() and _loadReadyToReceiveState() are called AFTER the then-chain is set up but they are independent async calls — they do NOT block the then-callback."
  implication: "The then-callback fires as soon as _checkKeyStatus resolves. At that point _isReadyToReceive is still its initial value of false unless _loadReadyToReceiveState happened to complete faster (race condition, but typically false on first load)."

- timestamp: 2026-05-13
  checked: "_onSenderSelected (lines 311-338)"
  found: "_onSenderSelected calls selectSenderHandshake which calls selectSenderHandshake in KeyRepository (line 445). That method immediately reads the receiver's publicKey from Firestore users doc. CRITICALLY: the public key is only published to Firestore when _onToggleReady(true) calls EncryptionService.setupReceiverSession(uid) — which has NOT been called yet because _isReadyToReceive is false."
  implication: "selectSenderHandshake will find publicKey=null and throw KeyNotFoundException. The catch in _onSenderSelected sets _handshaking=false but does NOT set _handshakeDone=true. _sessionManager.selectSender() IS called first (line 312) so activeSenderUid gets set."

- timestamp: 2026-05-13
  checked: "_step3Done getter (line 64-65) and _step3Content (lines 485-552)"
  found: "_step3Done = activeSenderUid != null && _handshakeDone. After the failed _onSenderSelected, activeSenderUid IS set but _handshakeDone=false, so _step3Done=false. In _step3Content, since activeSenderUid IS non-null, the UI correctly renders the partner badge — but _handshaking=false and _handshakeDone=false means the body shows SizedBox.shrink() — no transfer stream, no 'Waiting for file transfer' widget. The stepper card title shows done=false."
  implication: "This contradicts the reported symptom of 'Find & Select Sender' button showing. The UI SHOULD show the partner badge with an empty body. The 'Find & Select Sender' button only renders when activeSenderUid is null."

- timestamp: 2026-05-13
  checked: "_onToggleReady guard in _step2Content (line 477)"
  found: "The Toggle switch has onChanged: _step1Done && !_isTogglingReady ? _onToggleReady : null. The pre-fill fires before the user has toggled on, so step 2 is locked (no receive mode). The user STILL needs to toggle before any key can be published."
  implication: "Root cause is an ordering problem: pre-fill fires before the mailbox is open (step 2 not done). The RSA public key does not exist in Firestore until the user opens the mailbox via the toggle."

- timestamp: 2026-05-13
  checked: "Revised symptom analysis — when exactly does 'Find & Select Sender' appear?"
  found: "If _checkKeyStatus throws or if _hasPrivateKey/_hasPublicKey are false at the time initState runs the prefill, then _step1Done=false and the guard `if (mounted && widget.preFilledSenderUid != null)` still fires _onSenderSelected regardless of _step1Done/_step2Done. But _onSenderSelected sets activeSenderUid via selectSender() at line 312 BEFORE the async selectSenderHandshake call. So the partner badge WILL appear but the handshake fails silently. The actual rendered UI should show the badge with an empty/shrunk body — NOT the 'Find Sender' button."
  implication: "The reported symptom 'shows Find & Select Sender' could mean: (a) the error IS thrown and selectSender() is somehow not persisting, OR (b) the error is thrown early enough that setState hasn't run and a rebuild resets activeSenderUid — but clearSender() is never called in the error path so (b) is unlikely. More likely the user is seeing the badge but noting the handshake didn't complete. OR: _checkKeyStatus ITSELF is failing/returning early, meaning the .then() block never runs."

## Resolution

root_cause: |
  Two-part root cause:
  
  PRIMARY (ordering): _onSenderSelected is called immediately when _checkKeyStatus()
  completes, which happens BEFORE the user has opened the mailbox (toggled step 2 on).
  selectSenderHandshake (KeyRepository line 445) reads the receiver's publicKey from
  Firestore. This key is only written to Firestore inside EncryptionService.setupReceiverSession(),
  which is only called from _onToggleReady(true). Since the toggle is off on entry,
  selectSenderHandshake finds publicKey=null → throws KeyNotFoundException → _handshakeDone
  stays false.
  
  SECONDARY (UX gap): The pre-fill path was designed assuming the receiver was already
  in "ready" state before navigating, but the neutral handshake flow navigates to
  ReceiverScreen fresh, requiring the user to complete steps 1 and 2 first. The
  preFilledSenderUid is consumed too early (at _checkKeyStatus completion) rather
  than deferred until step 2 is complete.
  
  The activeSenderUid IS set (line 312 runs before the async throw), so the partner
  badge renders in step 3 — but _handshakeDone=false means no transfer stream is
  built and the stepper shows incomplete state.

fix: |
  Defer the _onSenderSelected call for preFilledSenderUid until AFTER _isReadyToReceive
  becomes true (i.e., after the user completes step 2 toggle). Two approaches:
  
  Option A (preferred): Store the preFilledSenderUid in instance state and trigger
  _onSenderSelected reactively inside _onToggleReady(true), after setupReceiverSession
  completes successfully. Specifically: after setState sets _isReadyToReceive=true
  (line 209), check if _pendingPrefilledSender != null and call _onSenderSelected then.
  
  Option B: Auto-advance — if preFilledSenderUid is set, also auto-trigger the mailbox
  toggle (call _onToggleReady(true) automatically in initState after checking keys exist),
  then call _onSenderSelected in the toggle's completion path. This is more aggressive
  but gives a fully zero-click experience.
  
  The _checkKeyStatus().then() block should only call _onSenderSelected if _isReadyToReceive
  is already true (which would be the case if the user had previously opened the mailbox
  in a prior session — the Firestore state is loaded by _loadReadyToReceiveState). This
  is a secondary race condition: _loadReadyToReceiveState is also async and fires in
  parallel, so even checking _isReadyToReceive in the .then() block is unreliable.
  The correct fix is to hold the prefill UID and apply it after the toggle confirms.

verification: ""
files_changed: []
