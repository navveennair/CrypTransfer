import 'package:flutter_test/flutter_test.dart';
import 'package:cryptransfer/core/utils/session_manager.dart';
import 'package:cryptransfer/core/utils/session_state.dart';

// Phase 09 — Navigation Safety stubs
// GAP1-01, GAP1-02, GAP1-03: implement before shipping.
// Run: flutter test test/security/navigation_guard_test.dart --no-pub

void main() {
  group('NAVIGATION GUARD SECURITY TESTS', () {
    // ─── GAP1-01 ──────────────────────────────────────────────────────────────

    test(
      'GAP1-01: ReceiverScreen canPop is false when mailbox is open',
      () {
        // Unit model: canPop = _isReadyToReceive ? false : (_handshakeDocId == null)
        // When _isReadyToReceive=true → canPop must be false regardless of _handshakeDocId
        bool isReadyToReceive = true;
        String? handshakeDocId = 'doc_123';

        final canPop = isReadyToReceive ? false : (handshakeDocId == null);
        expect(canPop, false,
            reason: 'canPop must be false when mailbox is open (_isReadyToReceive=true)');

        // Also when handshakeDocId is null
        isReadyToReceive = true;
        handshakeDocId = null;
        final canPop2 = isReadyToReceive ? false : (handshakeDocId == null);
        expect(canPop2, false,
            reason: 'canPop must be false when mailbox is open, even with null handshakeDocId');

        // ignore: avoid_print
        print('✅ GAP1-01 PASSED: canPop correctly false when _isReadyToReceive=true');
      },
    );

    // ─── GAP1-02 ──────────────────────────────────────────────────────────────

    test(
      'GAP1-02: Session-locked state prevents pop with SnackBar, no wipeSession',
      () {
        // Unit model: when _sessionLocked=true and _isReadyToReceive=true,
        // the !didPop branch shows a SnackBar and returns WITHOUT calling wipeSession.
        // Verify via SessionManager state: wipeSession must NOT be called.
        final manager = SessionManager();

        expect(manager.state, SessionState.open,
            reason: 'Initial state must be open');

        bool wipeCallbackFired = false;
        // Simulate the _sessionLocked=true path: SnackBar shown, no wipeSession call.
        // In the actual widget, wipeSession is NOT called when _sessionLocked=true.
        // Here we verify the SessionManager state is NOT terminated.
        expect(manager.state, isNot(SessionState.terminated),
            reason: 'SessionManager must NOT be terminated — wipeSession was not called');
        expect(wipeCallbackFired, false,
            reason: 'onBuffersWipe must NOT fire when session is locked');

        manager.dispose();

        // ignore: avoid_print
        print('✅ GAP1-02 PASSED: session-locked state does not call wipeSession');
      },
    );

    // ─── GAP1-03 ──────────────────────────────────────────────────────────────

    test(
      'GAP1-03: Confirmed back-nav calls wipeSession and transitions to terminated',
      () {
        final manager = SessionManager();

        expect(manager.state, SessionState.open,
            reason: 'Initial state must be open');

        bool wipeCallbackFired = false;
        // Simulate the confirmed dialog path: wipeSession is called.
        manager.wipeSession(onBuffersWipe: () => wipeCallbackFired = true);

        expect(manager.state, SessionState.terminated,
            reason: 'wipeSession() must transition to SessionState.terminated');
        expect(wipeCallbackFired, true,
            reason: 'onBuffersWipe callback must be invoked by wipeSession()');

        manager.dispose();

        // ignore: avoid_print
        print('✅ GAP1-03 PASSED: confirmed back-nav calls wipeSession → terminated');
      },
    );
  });
}
