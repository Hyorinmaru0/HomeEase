import 'dart:async';

import 'package:flutter/material.dart';

import 'controllers/home_controller.dart';
import 'screens/home_shell.dart';
import 'services/esp32_service.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';
import 'controllers/auth_controller.dart';
import 'controllers/account_data_controller.dart';
import 'services/auth_service.dart';
import 'screens/auth_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = LocalAuthRepository();
  AuthController auth;
  try {
    await repository.initialize();
    auth = AuthController(repository);
  } catch (error) {
    repository.dispose();
    auth = AuthController(null)..message = friendlyAuthError(error);
  }
  runApp(HomeEaseApp(auth: auth));
}

class HomeEaseApp extends StatefulWidget {
  final HomeController? controller;
  final AuthController? auth;
  const HomeEaseApp({super.key, this.controller, this.auth});
  @override
  State<HomeEaseApp> createState() => _HomeEaseAppState();
}

class _HomeEaseAppState extends State<HomeEaseApp> {
  late final AuthController _auth;
  @override
  void initState() {
    super.initState();
    _auth = widget.auth ?? AuthController(null);
    if (widget.controller != null && !widget.controller!.ready) {
      widget.controller!.initialize();
    }
  }

  @override
  void dispose() {
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller case final home?) {
      return MaterialApp(
        title: 'HomeEase',
        theme: buildTheme(),
        home: AnimatedBuilder(
          animation: home,
          builder: (_, _) => home.ready
              ? HomeShell(controller: home)
              : const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                ),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _auth,
      builder: (_, _) {
        final allowed = _auth.authenticated || _auth.guest;
        final identity = allowed ? _auth.workspaceKey : 'signed-out';
        return MaterialApp(
          key: ValueKey(identity),
          title: 'HomeEase',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: allowed
              ? _AccountWorkspace(key: ValueKey(identity), auth: _auth)
              : AuthScreen(key: ValueKey(_auth.page), auth: _auth),
        );
      },
    );
  }
}

class _AccountWorkspace extends StatefulWidget {
  final AuthController auth;
  const _AccountWorkspace({super.key, required this.auth});
  @override
  State<_AccountWorkspace> createState() => _AccountWorkspaceState();
}

class _AccountWorkspaceState extends State<_AccountWorkspace> {
  late final StorageService storage;
  late final HomeController home;
  AccountDataController? account;
  late final bool guest;
  bool initialized = false;
  String? startupError;
  @override
  void initState() {
    super.initState();
    guest = widget.auth.guest;
    final session = widget.auth.session;
    storage = StorageService(
      namespace: guest
          ? 'homeease.demo.v2'
          : 'homeease.user.v2.${session!.userId}',
    );
    if (!guest) {
      account = AccountDataController(
        userId: session!.userId,
        storage: storage,
        initialName: session.fullName,
      );
    }
    home = HomeController(
      storage: storage,
      gateway: Esp32Service(),
      events: account,
      localDemoOnly: guest,
    );
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      if (guest) await storage.migrateGuestDemo();
      if (!guest) await storage.prepareUser();
      if (!mounted) return;
      await home.initialize();
      if (!mounted) return;
      if (account != null) await account!.initialize(home);
      if (mounted) setState(() => initialized = true);
    } catch (_) {
      if (mounted) {
        setState(
          () => startupError =
              'Saved data could not be opened. Sign out and try again.',
        );
      }
    }
  }

  @override
  void dispose() {
    account?.dispose();
    home.dispose();
    if (!guest) unawaited(storage.close().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([home, ?account]),
    builder: (_, _) {
      if (startupError != null) {
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(startupError!),
                TextButton(
                  onPressed: guest ? widget.auth.exitDemo : widget.auth.logout,
                  child: const Text('Return to login'),
                ),
              ],
            ),
          ),
        );
      }
      if (!home.ready || !initialized) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return HomeShell(controller: home, auth: widget.auth, account: account);
    },
  );
}
