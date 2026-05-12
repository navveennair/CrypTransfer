import 'package:flutter_test/flutter_test.dart';
import 'package:cryptransfer/presentation/sender/sender_screen.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('SENDER PREFILL TESTS', () {
    // HAND-07: SenderScreen with preFilledPartnerUid sets _receiverId without _FindSenderSheet
    test(
      'TC-HAND-07: SenderScreen accepts preFilledPartnerUid constructor param',
      () {
        // After Wave 2, SenderScreen will have preFilledPartnerUid param.
        // This test verifies the widget can be constructed with the param.
        fail('TC-HAND-07: not implemented yet — SenderScreen pre-fill not built');
      },
    );
  });
}
