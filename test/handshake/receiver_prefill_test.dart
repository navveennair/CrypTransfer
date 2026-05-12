import 'package:flutter_test/flutter_test.dart';
import 'package:cryptransfer/presentation/receiver/receiver_screen.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('RECEIVER PREFILL TESTS', () {
    test(
      'TC-HAND-08: ReceiverScreen accepts preFilledSenderUid constructor param',
      () {
        const screen = ReceiverScreen(
          preFilledSenderUid: 'uid456',
          preFilledSenderUsername: 'bob',
        );
        expect(screen.preFilledSenderUid, equals('uid456'));
        expect(screen.preFilledSenderUsername, equals('bob'));
      },
    );
  });
}
