// Phase 11 — AdminGuard widget tests
// Covers: D-01 (route wrapper), D-02 (isAdmin stream), D-03 (non-admin redirect)
// Status: Wave 0 stubs — implementation in Plan 05

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdminGuard', () {
    testWidgets('blocks non-admin user and redirects to home', (tester) async {
      // TODO(Phase11-D01-D03): pump AdminGuard with mocked non-admin stream
      // expect: SnackBar 'Access denied' shown, Navigator.pushReplacementNamed('/') called
    }, skip: true); // AdminGuard not implemented yet — Plan 05

    testWidgets('allows admin user and renders child', (tester) async {
      // TODO(Phase11-D02): pump AdminGuard with mocked isAdmin==true stream
      // expect: child widget rendered (AdminDashboard or placeholder Text)
    }, skip: true); // AdminGuard not implemented yet — Plan 05

    testWidgets('shows full-screen loading indicator while stream is pending', (tester) async {
      // TODO(Phase11-D02): pump AdminGuard with never-emitting stream
      // expect: CircularProgressIndicator visible, child NOT visible
    }, skip: true); // AdminGuard not implemented yet — Plan 05
  });
}
