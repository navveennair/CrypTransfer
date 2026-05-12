import 'package:flutter_test/flutter_test.dart';
import 'package:cryptransfer/presentation/sender/sender_screen.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('SENDER PREFILL TESTS', () {
    testWidgets(
      'TC-HAND-07: SenderScreen accepts preFilledPartnerUid without throwing',
      (tester) async {
        // SenderScreen with pre-fill should construct without error.
        // Full session flow requires Firebase — just verify widget instantiation.
        expect(
          () => const SenderScreen(
            preFilledPartnerUid: 'uid123',
            preFilledPartnerUsername: 'alice',
          ),
          returnsNormally,
        );
        // Verify preFilledPartnerUid field is accessible
        const screen = SenderScreen(
          preFilledPartnerUid: 'uid123',
          preFilledPartnerUsername: 'alice',
        );
        expect(screen.preFilledPartnerUid, equals('uid123'));
        expect(screen.preFilledPartnerUsername, equals('alice'));
      },
    );
  });
}
