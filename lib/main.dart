import 'package:flutter/material.dart';

import 'controllers/home_controller.dart';
import 'screens/home_shell.dart';
import 'services/esp32_service.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HomeEaseApp());
}

class HomeEaseApp extends StatefulWidget {
  final HomeController? controller;
  const HomeEaseApp({super.key, this.controller});
  @override
  State<HomeEaseApp> createState() => _HomeEaseAppState();
}

class _HomeEaseAppState extends State<HomeEaseApp> {
  late final HomeController _controller;
  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        HomeController(storage: StorageService(), gateway: Esp32Service());
    if (!_controller.ready) _controller.initialize();
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'HomeEase',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => _controller.ready
          ? HomeShell(controller: _controller)
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    ),
  );
}
