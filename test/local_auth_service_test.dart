import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeease/services/auth_service.dart';

import 'auth_fakes.dart';

void main() {
  late MemoryCredentials store;
  late LocalAuthRepository repo;
  late DateTime time;
  setUp(() async {
    store = MemoryCredentials();
    time = DateTime(2026, 10, 31);
    repo = LocalAuthRepository(store: store, iterations: 2, clock: () => time);
    await repo.initialize();
  });
  tearDown(() => repo.dispose());
  Future<String> signup() async {
    await repo.signUp('Alice', 'Alice@example.test', 'password123');
    return repo.takeRecoveryCode()!;
  }

  test('PBKDF2 SHA256 matches an independently known test vector', () {
    final hash = deriveLocalSecret({
      'secret': 'password',
      'salt': base64Encode(utf8.encode('salt')),
      'iterations': 2,
    });
    final hex = base64Decode(hash)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    expect(
      hex,
      'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
    );
  });

  test('production-strength hashing creates a usable account', () async {
    final production = LocalAuthRepository(store: MemoryCredentials());
    final elapsed = Stopwatch()..start();
    await production.initialize();
    await production.signUp('Alice', 'alice@example.test', 'password123');
    expect(production.session, isNotNull);
    expect(production.takeRecoveryCode(), isNotNull);
    await production.logout();
    await production.login('alice@example.test', 'password123');
    expect(production.session, isNotNull);
    elapsed.stop();
    // Timing has no assertion: devices differ. This also exercises compute()
    // with the actual production work factor rather than only short vectors.
    // ignore: avoid_print
    print('Production signup + login: ${elapsed.elapsedMilliseconds} ms');
    production.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
  test('signup stores salted hashes, not password or recovery code', () async {
    final code = await signup();
    expect(repo.session!.email, 'alice@example.test');
    expect(repo.takeRecoveryCode(), isNull);
    expect(store.value, isNot(contains('password123')));
    expect(store.value, isNot(contains(code)));
    expect(
      store.value,
      isNot(contains(LocalAuthRepository.normalizeCode(code))),
    );
    final account = jsonDecode(store.value!)['accounts']['alice@example.test'];
    expect(account['password']['salt'], isNot(account['recovery']['salt']));
    expect(LocalAuthRepository().iterations, 600000);
  });
  test('session restores after restart, logout retains accounts and stable user ID', () async {
    await signup();
    final id = repo.session!.userId;
    final restored = LocalAuthRepository(store: store, iterations: 2);
    await restored.initialize();
    expect(restored.session!.userId, id);
    await restored.logout();
    final signedOut = LocalAuthRepository(store: store, iterations: 2);
    await signedOut.initialize();
    expect(signedOut.session, isNull);
    await signedOut.login(' ALICE@example.test ', 'password123');
    expect(signedOut.session!.userId, id);
    restored.dispose();
    signedOut.dispose();
  });
  test(
    'duplicate email, wrong password and unknown account never sign in',
    () async {
      await signup();
      await repo.logout();
      await expectLater(
        repo.signUp('Other', 'ALICE@example.test', 'password123'),
        throwsA(isA<LocalAuthException>()),
      );
      await expectLater(
        repo.login('alice@example.test', 'wrong'),
        throwsA(isA<LocalAuthException>()),
      );
      await expectLater(
        repo.login('missing@example.test', 'password123'),
        throwsA(isA<LocalAuthException>()),
      );
      expect(repo.session, isNull);
    },
  );
  test(
    'different accounts get distinct IDs even with identical passwords',
    () async {
      await signup();
      final alice = repo.session!.userId;
      await repo.logout();
      await repo.signUp('Bob', 'bob@example.test', 'password123');
      expect(repo.session!.userId, isNot(alice));
      final accounts = jsonDecode(store.value!)['accounts'];
      expect(
        accounts['alice@example.test']['password']['hash'],
        isNot(accounts['bob@example.test']['password']['hash']),
      );
    },
  );
  test('recovery needs correct code, gates controls, rotates code, and preserves identity', () async {
    final code = await signup();
    final id = repo.session!.userId;
    await repo.logout();
    await expectLater(
      repo.resetPassword('replacement123'),
      throwsA(isA<LocalAuthException>()),
    );
    await expectLater(
      repo.verifyRecovery('alice@example.test', 'wrong'),
      throwsA(isA<LocalAuthException>()),
    );
    await repo.verifyRecovery(
      'alice@example.test',
      code.toLowerCase().replaceAll('-', ' '),
    );
    expect(repo.recovering, true);
    expect(repo.session, isNull);
    await repo.resetPassword('replacement123');
    final replacement = repo.takeRecoveryCode()!;
    expect(replacement, isNot(code));
    expect(repo.session, isNull);
    await expectLater(
      repo.verifyRecovery('alice@example.test', code),
      throwsA(isA<LocalAuthException>()),
    );
    await expectLater(
      repo.login('alice@example.test', 'password123'),
      throwsA(isA<LocalAuthException>()),
    );
    await repo.login('alice@example.test', 'replacement123');
    expect(repo.session!.userId, id);
    await repo.logout();
    await repo.verifyRecovery('alice@example.test', replacement);
    expect(repo.recovering, true);
  });
  test('recovery authorization does not survive app restart', () async {
    final code = await signup();
    await repo.logout();
    await repo.verifyRecovery('alice@example.test', code);
    final restored = LocalAuthRepository(store: store, iterations: 2);
    await restored.initialize();
    expect(restored.session, isNull);
    await expectLater(
      restored.resetPassword('replacement123'),
      throwsA(isA<LocalAuthException>()),
    );
    restored.dispose();
  });
  test(
    'password changes require the current password and retain recovery code',
    () async {
      final code = await signup();
      await expectLater(
        repo.changePassword('wrong', 'replacement123'),
        throwsA(isA<LocalAuthException>()),
      );
      await repo.changePassword('password123', 'replacement123');
      await repo.logout();
      await expectLater(
        repo.login('alice@example.test', 'password123'),
        throwsA(isA<LocalAuthException>()),
      );
      await repo.login('alice@example.test', 'replacement123');
      await repo.logout();
      await repo.verifyRecovery('alice@example.test', code);
      expect(repo.recovering, true);
    },
  );
  test(
    'repeated failures are throttled across restart until cooldown expires',
    () async {
      await signup();
      await repo.logout();
      for (var i = 0; i < 5; i++) {
        await expectLater(
          repo.login('alice@example.test', 'wrong'),
          throwsA(isA<LocalAuthException>()),
        );
      }
      final restored = LocalAuthRepository(
        store: store,
        iterations: 2,
        clock: () => time,
      );
      await restored.initialize();
      await expectLater(
        restored.login('alice@example.test', 'password123'),
        throwsA(
          isA<LocalAuthException>().having(
            (e) => e.message,
            'message',
            contains('30 seconds'),
          ),
        ),
      );
      time = time.add(const Duration(seconds: 31));
      await restored.login('alice@example.test', 'password123');
      expect(restored.session, isNotNull);
      restored.dispose();
    },
  );
  test('failed storage writes do not manufacture a signup session', () async {
    store.failWrites = true;
    await expectLater(signup(), throwsStateError);
    expect(repo.session, isNull);
    expect(repo.takeRecoveryCode(), isNull);
    store.failWrites = false;
    await signup();
    expect(repo.session, isNotNull);
  });
  test('corrupt saved data fails initialization without silently replacing accounts', () async {
    store.value = '{bad json';
    await expectLater(repo.initialize(), throwsFormatException);
    expect(store.value, '{bad json');
  });
}
