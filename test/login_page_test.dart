import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_planner/auth/auth_service.dart';
import 'package:ultra_planner/auth/login_page.dart';

Widget _wrap(AuthService service) {
  return MaterialApp(home: LoginPage(authService: service));
}

/// The ocean background animates continuously, so `pumpAndSettle` would never
/// return. Pump a fixed slice of time instead.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  late MockFirebaseAuth auth;
  late AuthService service;

  setUp(() {
    // The mock does not derive a user from the submitted credentials, so give
    // it one whose email the sign-in assertion can check against.
    auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'user-a', email: 'kid@example.com'),
    );
    service = AuthService(auth: auth);
  });

  testWidgets('opens in login mode', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(service));

    expect(find.text('Log in'), findsWidgets);
    expect(find.text('Confirm password'), findsNothing);
    expect(find.text('Forgot password?'), findsOneWidget);
  });

  testWidgets('switching to sign up reveals name and confirm fields', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_wrap(service));

    await tester.tap(find.widgetWithText(TextButton, 'Sign up'));
    await _settle(tester);

    expect(find.text('Confirm password'), findsOneWidget);
    expect(find.text('Name (optional)'), findsOneWidget);
    // Password reset only makes sense when logging in.
    expect(find.text('Forgot password?'), findsNothing);
  });

  testWidgets('empty submit shows validation errors and does not sign in', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_wrap(service));

    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await _settle(tester);

    expect(find.text('Email is required.'), findsOneWidget);
    expect(find.text('Password is required.'), findsOneWidget);
    expect(auth.currentUser, isNull);
  });

  testWidgets('malformed email is rejected before hitting Firebase', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_wrap(service));

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'not-an-email',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'sekrit123',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await _settle(tester);

    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(auth.currentUser, isNull);
  });

  testWidgets('sign up rejects a short password', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(service));
    await tester.tap(find.widgetWithText(TextButton, 'Sign up'));
    await _settle(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'kid@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'abc',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await _settle(tester);

    expect(find.text('Use at least 6 characters.'), findsOneWidget);
  });

  testWidgets('sign up rejects mismatched confirmation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_wrap(service));
    await tester.tap(find.widgetWithText(TextButton, 'Sign up'));
    await _settle(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'kid@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'sekrit123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm password'),
      'sekrit124',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await _settle(tester);

    expect(find.text('Passwords do not match.'), findsOneWidget);
  });

  testWidgets('valid credentials sign the user in', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_wrap(service));

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'kid@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'sekrit123',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await _settle(tester);

    expect(auth.currentUser, isNotNull);
    expect(auth.currentUser!.email, 'kid@example.com');
  });

  testWidgets('password reset needs an email first', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_wrap(service));

    await tester.tap(find.text('Forgot password?'));
    await _settle(tester);

    expect(find.text('Enter your email first, then tap reset.'), findsOneWidget);
  });
}
