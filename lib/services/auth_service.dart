import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class AccountSession {
  final String userId, email, fullName;
  const AccountSession({
    required this.userId,
    required this.email,
    required this.fullName,
  });
}

class AccountEvent {
  final AccountSession? session;
  final bool recovery;
  const AccountEvent(this.session, {this.recovery = false});
}

class LocalAuthException implements Exception {
  final String message;
  const LocalAuthException(this.message);
}

abstract class AuthRepository {
  AccountSession? get session;
  bool get recovering;
  Stream<AccountEvent> get events;
  String? takeRecoveryCode();
  Future<void> signUp(String name, String email, String password);
  Future<void> login(String email, String password);
  Future<void> verifyRecovery(String email, String code);
  Future<void> resetPassword(String password);
  Future<void> changePassword(String currentPassword, String newPassword);
  Future<void> logout();
  void dispose();
}

abstract class CredentialStore {
  Future<String?> read();
  Future<void> write(String value);
}

class SecureCredentialStore implements CredentialStore {
  final FlutterSecureStorage storage;
  const SecureCredentialStore({this.storage = const FlutterSecureStorage()});
  static const key = 'homeease.local.accounts.v1';
  @override
  Future<String?> read() => storage.read(key: key);
  @override
  Future<void> write(String value) => storage.write(key: key, value: value);
}

String deriveLocalSecret(Map<String, dynamic> request) {
  final hmac = Hmac(sha256, utf8.encode(request['secret'] as String));
  final salt = base64Decode(request['salt'] as String);
  var block = Uint8List.fromList(hmac.convert([...salt, 0, 0, 0, 1]).bytes);
  final result = Uint8List.fromList(block);
  for (var i = 1; i < (request['iterations'] as int); i++) {
    block = Uint8List.fromList(hmac.convert(block).bytes);
    for (var j = 0; j < result.length; j++) {
      result[j] ^= block[j];
    }
  }
  return base64Encode(result);
}

class LocalAuthRepository implements AuthRepository {
  final CredentialStore store;
  final int iterations;
  final DateTime Function() now;
  final _events = StreamController<AccountEvent>.broadcast(sync: true);
  Map<String, dynamic> _data = {'version': 1, 'accounts': <String, dynamic>{}};
  String? _recoveryId, _newRecoveryCode;
  bool _busy = false, _disposed = false;
  LocalAuthRepository({
    this.store = const SecureCredentialStore(),
    this.iterations = 600000,
    DateTime Function()? clock,
  }) : now = clock ?? DateTime.now;

  Map<String, dynamic> get _accounts =>
      _data['accounts'] as Map<String, dynamic>;
  Future<void> initialize() async {
    final raw = await store.read();
    if (raw == null) return;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    if (decoded['version'] != 1 || decoded['accounts'] is! Map) {
      throw const LocalAuthException(
        'Saved accounts could not be opened. Restart the app and try again.',
      );
    }
    _data = decoded;
  }

  @override
  AccountSession? get session {
    final id = _data['session'];
    if (id == null) return null;
    for (final value in _accounts.values) {
      final a = value as Map<String, dynamic>;
      if (a['id'] == id) {
        return AccountSession(
          userId: id as String,
          email: a['email'] as String,
          fullName: a['name'] as String,
        );
      }
    }
    return null;
  }

  @override
  bool get recovering => _recoveryId != null;
  @override
  Stream<AccountEvent> get events => _events.stream;
  @override
  String? takeRecoveryCode() {
    final code = _newRecoveryCode;
    _newRecoveryCode = null;
    return code;
  }

  void _emit() {
    if (!_disposed) _events.add(AccountEvent(session, recovery: recovering));
  }

  String _salt() =>
      base64Encode(List.generate(16, (_) => Random.secure().nextInt(256)));
  String _generateCode() {
    final bytes = List.generate(16, (_) => Random.secure().nextInt(256));
    final hex = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    return List.generate(8, (i) => hex.substring(i * 4, i * 4 + 4)).join('-');
  }

  static String normalizeCode(String value) =>
      value.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  Future<Map<String, dynamic>> _hash(String secret) async {
    final salt = _salt();
    final hash = await compute(deriveLocalSecret, {
      'secret': secret,
      'salt': salt,
      'iterations': iterations,
    });
    return {'salt': salt, 'hash': hash, 'iterations': iterations};
  }

  Future<bool> _matches(String secret, Map<String, dynamic> saved) async {
    final result = await compute(deriveLocalSecret, {
      'secret': secret,
      'salt': saved['salt'],
      'iterations': saved['iterations'],
    });
    final expected = saved['hash'] as String;
    var difference = result.length ^ expected.length;
    for (var i = 0; i < min(result.length, expected.length); i++) {
      difference |= result.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return difference == 0;
  }

  Future<void> _commit(Map<String, dynamic> next) async {
    await store.write(jsonEncode(next));
    _data = next;
  }

  Map<String, dynamic> _copy() =>
      jsonDecode(jsonEncode(_data)) as Map<String, dynamic>;
  Future<void> _exclusive(Future<void> Function() action) async {
    if (_busy) {
      throw const LocalAuthException(
        'Please wait for the current request to finish.',
      );
    }
    _busy = true;
    try {
      await action();
    } finally {
      _busy = false;
    }
  }

  void _password(String password) {
    final error = validatePassword(password);
    if (error != null) throw LocalAuthException(error);
  }

  Map<String, dynamic>? _find(String email) =>
      _accounts[email.trim().toLowerCase()] as Map<String, dynamic>?;
  Future<void> _checkSecret(String email, String secret, String field) async {
    final account = _find(email);
    const incorrect = LocalAuthException(
      'The email, password, or recovery code is incorrect.',
    );
    if (account == null) throw incorrect;
    final until = DateTime.tryParse(account['lockedUntil'] as String? ?? '');
    if (until != null && now().isBefore(until)) {
      throw const LocalAuthException(
        'Too many attempts. Wait 30 seconds and try again.',
      );
    }
    if (!await _matches(secret, Map<String, dynamic>.from(account[field]))) {
      final next = _copy();
      final a =
          next['accounts'][email.trim().toLowerCase()] as Map<String, dynamic>;
      final failures = (a['failures'] as int? ?? 0) + 1;
      a['failures'] = failures >= 5 ? 0 : failures;
      if (failures >= 5) {
        a['lockedUntil'] = now()
            .add(const Duration(seconds: 30))
            .toIso8601String();
      }
      await _commit(next);
      throw incorrect;
    }
  }

  @override
  Future<void> signUp(String name, String email, String password) =>
      _exclusive(() async {
        final address = email.trim().toLowerCase();
        if (validateEmail(address) != null) {
          throw const LocalAuthException('Enter a valid email address.');
        }
        if (name.trim().isEmpty || name.trim().length > 80) {
          throw const LocalAuthException('Enter a name of 1–80 characters.');
        }
        _password(password);
        if (_find(address) != null) {
          throw const LocalAuthException(
            'An account with this email already exists on this phone. Sign in or use your recovery code.',
          );
        }
        final code = _generateCode();
        final id = const Uuid().v4();
        final account = {
          'id': id,
          'name': name.trim(),
          'email': address,
          'password': await _hash(password),
          'recovery': await _hash(normalizeCode(code)),
          'failures': 0,
        };
        final next = _copy();
        next['accounts'][address] = account;
        next['session'] = id;
        await _commit(next);
        _recoveryId = null;
        _newRecoveryCode = code;
        _emit();
      });
  @override
  Future<void> login(String email, String password) => _exclusive(() async {
    await _checkSecret(email, password, 'password');
    final next = _copy();
    final a = next['accounts'][email.trim().toLowerCase()];
    a['failures'] = 0;
    a.remove('lockedUntil');
    next['session'] = a['id'];
    await _commit(next);
    _recoveryId = null;
    _newRecoveryCode = null;
    _emit();
  });
  @override
  Future<void> verifyRecovery(String email, String code) =>
      _exclusive(() async {
        _recoveryId = null;
        await _checkSecret(email, normalizeCode(code), 'recovery');
        final next = _copy()..remove('session');
        await _commit(next);
        _recoveryId = _find(email)!['id'] as String;
        _emit();
      });
  @override
  Future<void> resetPassword(String password) => _exclusive(() async {
    _password(password);
    if (_recoveryId == null) {
      throw const LocalAuthException('Verify your recovery code first.');
    }
    final next = _copy()..remove('session');
    final a = (next['accounts'] as Map).values
        .cast<Map<String, dynamic>>()
        .firstWhere((a) => a['id'] == _recoveryId);
    final code = _generateCode();
    a['password'] = await _hash(password);
    a['recovery'] = await _hash(normalizeCode(code));
    a['failures'] = 0;
    a.remove('lockedUntil');
    await _commit(next);
    _newRecoveryCode = code;
    _recoveryId = null;
    _emit();
  });
  @override
  Future<void> changePassword(String currentPassword, String newPassword) =>
      _exclusive(() async {
        _password(newPassword);
        final current = session;
        if (current == null) throw const LocalAuthException('Sign in first.');
        await _checkSecret(current.email, currentPassword, 'password');
        final next = _copy();
        next['accounts'][current.email]['password'] = await _hash(newPassword);
        await _commit(next);
      });
  @override
  Future<void> logout() => _exclusive(() async {
    await _commit(_copy()..remove('session'));
    _recoveryId = null;
    _newRecoveryCode = null;
    _emit();
  });
  @override
  void dispose() {
    _disposed = true;
    _events.close();
  }
}

String friendlyAuthError(Object error) => error is LocalAuthException
    ? error.message
    : 'Could not save or open your local account. Please try again.';
String? validateEmail(String? value) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value?.trim() ?? '')
    ? null
    : 'Enter a valid email address.';
String? validatePassword(String? value) =>
    (value?.length ?? 0) >= 8 &&
        (value?.length ?? 0) <= 128 &&
        value!.trim().isNotEmpty
    ? null
    : 'Use 8–128 characters for your password.';
