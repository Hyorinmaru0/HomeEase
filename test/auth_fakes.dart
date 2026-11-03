import 'dart:async';

import 'package:homeease/services/auth_service.dart';

class FakeAuth implements AuthRepository {
  @override
  AccountSession? session;
  @override
  bool recovering = false;
  final changes = StreamController<AccountEvent>.broadcast(sync: true);
  Object? failure;
  int signups = 0;
  String? code;
  AccountSession account = const AccountSession(
    userId: 'alice',
    email: 'alice@example.test',
    fullName: 'Alice',
  );
  void check() {
    if (failure != null) throw failure!;
  }

  void emit() => changes.add(AccountEvent(session, recovery: recovering));
  @override
  Stream<AccountEvent> get events => changes.stream;
  @override
  String? takeRecoveryCode() {
    final value = code;
    code = null;
    return value;
  }

  @override
  Future<void> signUp(String name, String email, String password) async {
    check();
    signups++;
    session = account;
    recovering = false;
    code = 'ABCD-1234-ABCD-1234-ABCD-1234-ABCD-1234';
    emit();
  }

  @override
  Future<void> login(String email, String password) async {
    check();
    session = account;
    recovering = false;
    emit();
  }

  @override
  Future<void> verifyRecovery(String email, String token) async {
    check();
    session = null;
    recovering = true;
    emit();
  }

  @override
  Future<void> resetPassword(String password) async {
    check();
    recovering = false;
    session = null;
    code = 'DCBA-4321-DCBA-4321-DCBA-4321-DCBA-4321';
    emit();
  }

  @override
  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    check();
  }

  @override
  Future<void> logout() async {
    check();
    session = null;
    recovering = false;
    emit();
  }

  @override
  void dispose() {
    changes.close();
  }
}

class MemoryCredentials implements CredentialStore {
  String? value;
  bool failWrites = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    if (failWrites) throw StateError('storage unavailable');
    this.value = value;
  }
}
