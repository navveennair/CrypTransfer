import 'package:flutter_test/flutter_test.dart';
import 'package:cryptransfer/core/errors/app_exceptions.dart';

void main() {
  group('ROLE ASSIGNMENT TESTS — Race Condition Detection', () {
    test(
      'TC-ROLE-01: RoleConflictException can be instantiated and thrown',
      () {
        const exception = RoleConflictException(
          'Role conflict detected. One user must be sender, another must be receiver.',
        );
        expect(exception is RoleConflictException, true);
        expect(exception is AppException, true);
      },
    );

    test(
      'TC-ROLE-02: RoleConflictException toString returns message',
      () {
        const message =
            'One user must be sender, another must be receiver. Partner has already selected a different sender.';
        const exception = RoleConflictException(message);
        expect(exception.toString(), equals(message));
      },
    );

    test(
      'TC-ROLE-03: RoleConflictException message contains guidance for both users',
      () {
        const exception = RoleConflictException(
          'Role conflict detected. Both users cannot be receivers. '
          'One user must be sender, another must be receiver.',
        );
        expect(exception.toString(), contains('One user must be sender'));
        expect(exception.toString(), contains('must be receiver'));
      },
    );

    test(
      'TC-ROLE-04: RoleConflictException is catchable and distinguishable from other exceptions',
      () {
        const roleConflict = RoleConflictException('Both users tried to be receiver');
        const authError = AuthException('Auth failed');

        expect(roleConflict is RoleConflictException, true);
        expect(roleConflict is AuthException, false);
        expect(authError is AuthException, true);
        expect(authError is RoleConflictException, false);
      },
    );

    test(
      'TC-ROLE-05: RoleConflictException dialog message is user-friendly',
      () {
        const exception = RoleConflictException(
          'You are already in receiver mode with another user. '
          'One user must be sender, another must be receiver.',
        );
        final msg = exception.toString();
        expect(msg.toLowerCase(), contains('receiver'));
        expect(msg.toLowerCase(), contains('sender'));
      },
    );

    test(
      'TC-ROLE-06: Multiple RoleConflictException instances can be created with different messages',
      () {
        const exc1 = RoleConflictException('Both try to be sender');
        const exc2 = RoleConflictException('Both try to be receiver');
        const exc3 = RoleConflictException('Partner already selected different sender');

        expect(exc1.toString(), isNotEmpty);
        expect(exc2.toString(), isNotEmpty);
        expect(exc3.toString(), isNotEmpty);
        expect(exc1.toString(), isNot(exc2.toString()));
      },
    );
  });
}
