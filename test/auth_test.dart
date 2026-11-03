import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeease/controllers/auth_controller.dart';
import 'package:homeease/screens/auth_screen.dart';
import 'package:homeease/services/auth_service.dart';
import 'package:homeease/theme/app_theme.dart';

import 'auth_fakes.dart';

void main() {
  late FakeAuth repo;
  late AuthController auth;
  setUp(() {
    repo = FakeAuth();
    auth = AuthController(repo);
  });
  tearDown(() {
    auth.dispose();
    repo.dispose();
  });
  test('signup shows recovery code before opening the account', () async {
    await auth.signup('Alice', 'alice@example.test', 'password123');
    expect(repo.signups, 1);
    expect(auth.page, AuthPage.saveRecovery);
    expect(auth.authenticated, false);
    expect(auth.recoveryCode, isNotNull);
    auth.acknowledgeRecoveryCode();
    expect(auth.authenticated, true);
    expect(auth.recoveryCode, isNull);
  });
  test('failed signup has visible feedback and never grants access', () async {
    repo.failure = const LocalAuthException('Unable to save account.');
    await auth.signup('Alice', 'alice@example.test', 'password123');
    expect(auth.authenticated, false);
    expect(auth.message, 'Unable to save account.');
    expect(auth.busy, false);
  });
  test(
    'recovery is gated until code and new password, then returns to login',
    () async {
      await auth.recover('alice@example.test', 'code');
      expect(auth.page, AuthPage.reset);
      expect(auth.authenticated, false);
      await auth.reset('replacement123');
      expect(auth.page, AuthPage.saveRecovery);
      expect(auth.authenticated, false);
      auth.acknowledgeRecoveryCode();
      expect(auth.page, AuthPage.login);
      expect(auth.authenticated, false);
    },
  );
  test('restored local session grants access without internet', () {
    auth.dispose();
    repo.session = repo.account;
    auth = AuthController(repo);
    expect(auth.authenticated, true);
  });
  test('late session events cannot undo explicit logout', () async {
    await auth.login('alice@example.test', 'password123');
    await auth.logout();
    repo.session = repo.account;
    repo.emit();
    expect(auth.authenticated, false);
    expect(auth.session, isNull);
    await auth.login('alice@example.test', 'password123');
    expect(auth.authenticated, true);
  });
  test('logout failure is explicit and closes protected UI', () async {
    await auth.login('alice@example.test', 'password123');
    repo.failure = StateError('failed save');
    await auth.logout();
    expect(auth.authenticated, false);
    expect(auth.message, contains('saved login could not be removed'));
  });
  test('basic validators and error privacy', () {
    expect(validatePassword('short'), isNotNull);
    expect(validatePassword('simplepass'), isNull);
    expect(validateEmail('alice@example.test'), isNull);
    expect(validateEmail('alice@'), isNotNull);
    expect(
      friendlyAuthError(Exception('private details')),
      isNot(contains('private details')),
    );
  });
  for (final width in [320.0, 390.0]) {
    testWidgets('all auth forms fit width $width with larger text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      for (final page in AuthPage.values) {
        auth.page = page;
        auth.email = 'alice@example.test';
        if (page == AuthPage.saveRecovery) {
          auth.recoveryCode = 'ABCD-1234-ABCD-1234-ABCD-1234-ABCD-1234';
        }
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(),
            home: AuthScreen(key: ValueKey(page), auth: auth),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: page.name);
      }
    });
  }
  testWidgets('signup validates matching passwords before request', (
    tester,
  ) async {
    auth.page = AuthPage.signup;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: AuthScreen(auth: auth),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Full name'),
      'Alice',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email address'),
      'alice@example.test',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'GoodPassword123!',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm password'),
      'Mismatch123!',
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sign up'));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign up'));
    await tester.pumpAndSettle();
    expect(repo.signups, 0);
    expect(find.text('Passwords do not match.'), findsOneWidget);
  });

  for (final failed in [true, false]) {
    testWidgets(
      failed
          ? 'scrolled signup failure stays visible beside submit with keyboard insets'
          : 'successful signup opens the interface without a confirmation screen',
      (tester) async {
        tester.view.physicalSize = const Size(390, 650);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 220);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetViewInsets();
        });
        auth.page = AuthPage.signup;
        if (failed) {
          repo.failure = const LocalAuthException(
            'Could not save account. Please try again.',
          );
        }
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(),
            home: AnimatedBuilder(
              animation: auth,
              builder: (_, _) => auth.authenticated
                  ? const Scaffold(body: Text('Account interface'))
                  : AuthScreen(key: ValueKey(auth.page), auth: auth),
            ),
          ),
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Full name'),
          'Alice',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Email address'),
          'alice@example.test',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'),
          'GoodPassword123!',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirm password'),
          'GoodPassword123!',
        );
        final submit = find.widgetWithText(FilledButton, 'Sign up');
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(auth.busy, isFalse);
        if (failed) {
          expect(auth.authenticated, isFalse);
          expect(auth.page, AuthPage.signup);
          expect(
            find.textContaining('Could not save account').hitTestable(),
            findsOneWidget,
          );
          expect(submit.hitTestable(), findsOneWidget);
          expect(
            find.widgetWithText(TextFormField, 'Email address'),
            findsOneWidget,
          );
        } else {
          expect(auth.authenticated, isFalse);
          expect(find.text('Save your recovery code'), findsOneWidget);
          await tester.ensureVisible(find.byType(CheckboxListTile));
          await tester.tap(find.byType(CheckboxListTile));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Continue to HomeEase'));
          await tester.tap(find.text('Continue to HomeEase'));
          await tester.pumpAndSettle();
          expect(auth.authenticated, isTrue);
          expect(find.text('Account interface'), findsOneWidget);
          expect(find.text('Verify your email'), findsNothing);
          expect(repo.signups, 1);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
