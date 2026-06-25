import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Regression guard for the SplashScreen / KillSwitchOutbox wiring decision.
//
// KillSwitchOutbox.resumeIfPending() existed for a full commit with nothing
// calling it at all (dead code), and the class's own doc comment says it
// should be called "from main on every app launch" — which would have been
// wrong: FirebaseAuth.instance.currentUser is not reliably restored
// immediately after Firebase.initializeApp(), so a call from main() risks
// silently no-op'ing on cold start. SplashScreen already works around this
// exact problem (it awaits authStateChanges().first instead of reading
// .currentUser synchronously), which is why resumeIfPending() is wired
// there instead. Source-inspected (not a logic mirror) because the actual
// risk is a future refactor moving the call back to main() or dropping it
// silently — neither breaks compilation, so flutter analyze can't catch it.
void main() {
  group('SPLASH SCREEN — KillSwitchOutbox wiring', () {
    test(
      'main.dart does NOT call KillSwitchOutbox.resumeIfPending '
      '(would race FirebaseAuth restore)',
      () {
        final mainSrc = File('lib/main.dart').readAsStringSync();
        expect(mainSrc.contains('resumeIfPending'), false,
            reason: 'resumeIfPending() must not be called from main() — '
                'FirebaseAuth.instance.currentUser is not guaranteed to be '
                'restored yet at that point, unlike after '
                'authStateChanges().first in SplashScreen');

        // ignore: avoid_print
        print('✅ main.dart does not call resumeIfPending directly');
      },
    );

    test(
      'SplashScreen calls KillSwitchOutbox.resumeIfPending() after '
      'authStateChanges resolves and before/alongside wipeAllSessionKeys',
      () {
        final src = File('lib/presentation/auth/splash_screen.dart')
            .readAsStringSync();

        final authIdx = src.indexOf('authStateChanges.first');
        final resumeIdx = src.indexOf('await KillSwitchOutbox.resumeIfPending()');
        // Exact call text, not just 'wipeAllSessionKeys' — that substring
        // also appears in the explanatory comment directly above the call.
        final wipeIdx = src.indexOf('await KeyRepository().wipeAllSessionKeys');

        expect(authIdx, greaterThan(-1),
            reason: 'expected SplashScreen to still await authStateChanges()'
                '.first before resolving the current user');
        expect(resumeIdx, greaterThan(-1),
            reason: 'SplashScreen must call KillSwitchOutbox.resumeIfPending() '
                '— without this, an interrupted closeReceiverSession leaves '
                "the user doc's publicKey/isReadyToReceive/sessionActive "
                'fields stale indefinitely');
        expect(wipeIdx, greaterThan(-1),
            reason: 'expected the existing wipeAllSessionKeys() call to '
                'still be present');

        expect(resumeIdx, greaterThan(authIdx),
            reason: 'resumeIfPending() must run after the authenticated uid '
                'is known (post authStateChanges().first), not before');
        expect(resumeIdx, lessThan(wipeIdx),
            reason: 'resumeIfPending() should run before wipeAllSessionKeys '
                '— it resolves the narrower, targeted leftover (user doc '
                'fields, pending transfers) that the blanket wipe never '
                'touches, so ordering them the other way would not change '
                'correctness today but inverts the documented intent '
                '(targeted resume of a specific interrupted op, then '
                'defensive blanket wipe)');

        // ignore: avoid_print
        print('✅ SplashScreen wires resumeIfPending() in the correct position');
      },
    );
  });
}
