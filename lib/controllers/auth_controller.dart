import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';

enum AuthPage { login, signup, forgot, reset, saveRecovery }

class AuthController extends ChangeNotifier {
  final AuthRepository? repository;
  AccountSession? session;
  AuthPage page = AuthPage.login;
  String email = '', message = '';
  String? recoveryCode;
  bool busy = false, guest = false, recovering = false;
  bool _disposed = false, _suppressSession = false, _signedOutByUser = false;
  int workspaceGeneration = 0;
  StreamSubscription<AccountEvent>? _subscription;
  AuthController(this.repository) {
    session = repository?.session;
    _subscription = repository?.events.listen(
      (event) {
        if (_suppressSession || _signedOutByUser || _disposed) return;
        session = event.session;
        recovering = event.recovery;
        _notify();
      },
      onError: (Object error) {
        message = friendlyAuthError(error);
        _notify();
      },
    );
  }
  bool get configured => repository != null;
  bool get authenticated =>
      !_suppressSession &&
      !recovering &&
      recoveryCode == null &&
      session != null;
  String get workspaceKey =>
      guest ? 'guest' : '${session?.userId}:$workspaceGeneration';
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void navigate(AuthPage next) {
    if (busy) return;
    page = next;
    message = '';
    _notify();
  }

  void enterDemo() {
    if (busy) return;
    guest = true;
    message = '';
    _notify();
  }

  void exitDemo() {
    guest = false;
    page = AuthPage.login;
    _notify();
  }

  Future<bool> perform(Future<void> Function(AuthRepository) action) async {
    if (busy || _disposed) return false;
    if (repository == null) {
      message =
          'Local account storage is unavailable. Restart the app to try again.';
      _notify();
      return false;
    }
    busy = true;
    message = '';
    _notify();
    try {
      await action(repository!);
      return true;
    } catch (error) {
      message = friendlyAuthError(error);
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> signup(String name, String address, String password) async {
    if (busy) return;
    _signedOutByUser = false;
    _suppressSession = true;
    email = address.trim();
    if (await perform((r) => r.signUp(name.trim(), email, password))) {
      session = repository!.session;
      recoveryCode = repository!.takeRecoveryCode();
      guest = recovering = false;
      if (session == null || recoveryCode == null) {
        session = null;
        recoveryCode = null;
        message =
            'Account creation could not be completed. Please try signing in.';
      } else {
        page = AuthPage.saveRecovery;
      }
    }
    _suppressSession = false;
    _notify();
  }

  void acknowledgeRecoveryCode() {
    recoveryCode = null;
    page = AuthPage.login;
    if (session == null) {
      message = 'Password updated. Sign in with your new password.';
    }
    _notify();
  }

  Future<void> login(String address, String password) async {
    if (busy) return;
    _signedOutByUser = false;
    email = address.trim();
    if (await perform((r) => r.login(email, password))) {
      session = repository!.session;
      recovering = guest = false;
      recoveryCode = null;
    }
    _notify();
  }

  Future<void> recover(String address, String code) async {
    if (busy) return;
    _signedOutByUser = false;
    _suppressSession = true;
    email = address.trim();
    if (await perform((r) => r.verifyRecovery(email, code))) {
      session = null;
      recovering = true;
      guest = false;
      page = AuthPage.reset;
    }
    _suppressSession = false;
    _notify();
  }

  Future<void> reset(String password) async {
    if (busy) return;
    _suppressSession = true;
    if (await perform((r) => r.resetPassword(password))) {
      session = null;
      recovering = false;
      recoveryCode = repository!.takeRecoveryCode();
      page = recoveryCode == null ? AuthPage.login : AuthPage.saveRecovery;
      message = 'Password updated. Save your replacement recovery code.';
    }
    _suppressSession = false;
    _notify();
  }

  Future<void> logout() async {
    if (busy) return;
    _signedOutByUser = true;
    _suppressSession = true;
    session = null;
    guest = recovering = false;
    recoveryCode = null;
    workspaceGeneration++;
    page = AuthPage.login;
    _notify();
    final ok = await perform((r) => r.logout());
    _suppressSession = false;
    if (!ok) message = 'The saved login could not be removed. Try again before closing the app.';
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}
