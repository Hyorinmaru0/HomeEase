import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeease/controllers/auth_controller.dart';
import 'package:homeease/main.dart';
import 'package:homeease/screens/home_shell.dart';
import 'package:homeease/services/storage_service.dart';
import 'package:homeease/services/auth_service.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'auth_fakes.dart';
import 'storage_isolation_test.dart' show MemoryPreferences;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'create account saves recovery code then opens HomeShell with account storage',
    (tester) async {
      final prefs = MemoryPreferences();
      SharedPreferencesAsyncPlatform.instance = prefs;
      final repository = FakeAuth()
        ..account = AccountSession(
          userId: 'new-signup',
          email: 'alice@example.test',
          fullName: 'Alice',
        );
      final auth = AuthController(repository);
      await tester.pumpWidget(HomeEaseApp(auth: auth));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Verify email'), findsNothing);
      await tester.ensureVisible(find.text('Create new account'));
      await tester.tap(find.text('Create new account'));
      await tester.pumpAndSettle();
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
        'StrongPassword1!',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm password'),
        'StrongPassword1!',
      );
      final submit = find.widgetWithText(FilledButton, 'Sign up');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.byType(HomeShell), findsNothing);
      expect(find.text('Save your recovery code'), findsOneWidget);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Continue to HomeEase'));
      await tester.tap(find.text('Continue to HomeEase'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.text('Verify your email'), findsNothing);
      expect(auth.authenticated, true);
      expect(auth.guest, false);
      expect(repository.signups, 1);
      expect(
        prefs.data.keys.any(
          (k) => k.startsWith('homeease.user.v2.new-signup.'),
        ),
        true,
      );
      await tester.pumpWidget(const SizedBox());
      await StorageService(namespace: 'homeease.user.v2.new-signup')
          .read('settings');
      repository.dispose();
    },
  );
  testWidgets('logout removes protected routes and preserves local user data', (
    tester,
  ) async {
    final prefs = MemoryPreferences();
    SharedPreferencesAsyncPlatform.instance = prefs;
    final repository = FakeAuth()..session = FakeAuth().account;
    final auth = AuthController(repository);
    await tester.pumpWidget(HomeEaseApp(auth: auth));
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    expect(
      prefs.data.keys.any((k) => k.startsWith('homeease.user.v2.alice.')),
      true,
    );
    final context = tester.element(find.byType(HomeShell));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Protected detail')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Protected detail'), findsOneWidget);
    await auth.logout();
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsNothing);
    expect(find.text('Protected detail'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(
      prefs.data.keys.where((k) => k.startsWith('homeease.user.v2.alice.')),
      isNotEmpty,
    );
    await auth.login('alice@example.test', 'correct');
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    repository.dispose();
  });
  testWidgets('guest demo has a separate local workspace', (tester) async {
    final prefs = MemoryPreferences();
    SharedPreferencesAsyncPlatform.instance = prefs;
    final auth = AuthController(null)..enterDemo();
    await tester.pumpWidget(HomeEaseApp(auth: auth));
    await tester.pumpAndSettle();
    expect(find.text('LOCAL DEMO ? Simulated devices only'), findsOneWidget);
    expect(
      prefs.data.keys.where((k) => k.startsWith('homeease.user.')),
      isEmpty,
    );
    auth.exitDemo();
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
