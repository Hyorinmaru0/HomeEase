import 'package:flutter/material.dart';

import '../controllers/home_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'alerts_screen.dart';
import 'dashboard_screen.dart';
import 'devices_screen.dart';
import 'energy_screen.dart';
import 'history_screen.dart';
import 'rooms_screen.dart';
import 'schedules_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  final HomeController controller;
  const HomeShell({super.key, required this.controller});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _scroll = ScrollController();
  static const _labels = ['Home', 'Devices', 'Energy', 'Routines', 'Settings'];
  static const _icons = [
    Icons.grid_view_rounded,
    Icons.tune_rounded,
    Icons.bolt_rounded,
    Icons.event_repeat_rounded,
    Icons.settings_outlined,
  ];
  void _navigate(int index) {
    setState(() => _index = index);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _open(String title, Widget Function() child) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) => Scaffold(
              appBar: AppBar(
                title: Text(title, style: const TextStyle(fontSize: 16)),
              ),
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(22),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 850),
                      child: child(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
  void _history() => _open(
    'Usage history',
    () => HistoryScreen(controller: widget.controller),
  );
  void _rooms() =>
      _open('Rooms', () => RoomsScreen(controller: widget.controller));
  void _alerts() => _open(
    'Alerts',
    () => AlertsScreen(
      controller: widget.controller,
      openDevices: () {
        Navigator.of(context).pop();
        _navigate(1);
      },
    ),
  );
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final page = switch (_index) {
      0 => DashboardScreen(
        controller: c,
        navigate: _navigate,
        openRooms: _rooms,
        openAlerts: _alerts,
        openHistory: _history,
      ),
      1 => DevicesScreen(controller: c),
      2 => EnergyScreen(
        controller: c,
        openHistory: _history,
        openSettings: () => _navigate(4),
      ),
      3 => SchedulesScreen(controller: c),
      _ => SettingsScreen(controller: c),
    };
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.raised,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.cottage_outlined,
                color: AppColors.mint,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            const Flexible(
              child: Text(
                'homeease',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -.6,
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (wide) StatusPill(c.connectionLabel),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Alerts',
            onPressed: _alerts,
            icon: Badge(
              isLabelVisible: c.unreadCount > 0,
              smallSize: 6,
              backgroundColor: AppColors.mint,
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: IconButton(
              tooltip: 'Open settings',
              onPressed: () => _navigate(4),
              icon: const Icon(Icons.settings_outlined),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (wide)
              NavigationRail(
                labelType: MediaQuery.sizeOf(context).width > 1150
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.all,
                extended: MediaQuery.sizeOf(context).width > 1150,
                backgroundColor: AppColors.background,
                selectedIndex: _index,
                onDestinationSelected: _navigate,
                indicatorColor: AppColors.raised,
                selectedIconTheme: const IconThemeData(color: AppColors.mint),
                destinations: List.generate(
                  5,
                  (i) => NavigationRailDestination(
                    icon: Icon(_icons[i]),
                    label: Text(_labels[i]),
                  ),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: c.settings.demoMode ? c.tick : c.refresh,
                child: SingleChildScrollView(
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    wide ? 36 : 20,
                    12,
                    wide ? 36 : 20,
                    30,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (c.error != null || c.storageError != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: Surface(
                                color: const Color(0xFF3B3024),
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.info_outline_rounded,
                                      color: AppColors.amber,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        c.storageError ?? c.error!,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.amber,
                                        ),
                                      ),
                                    ),
                                    if (!c.settings.demoMode)
                                      IconButton(
                                        tooltip: 'Reconnect',
                                        onPressed: c.busy ? null : c.refresh,
                                        icon: const Icon(Icons.refresh_rounded),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          KeyedSubtree(key: ValueKey(_index), child: page),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.border, width: .5),
                ),
              ),
              child: NavigationBar(
                height: 68,
                selectedIndex: _index,
                onDestinationSelected: _navigate,
                destinations: List.generate(
                  5,
                  (i) => NavigationDestination(
                    icon: Icon(_icons[i], size: 22),
                    label: _labels[i],
                  ),
                ),
              ),
            ),
    );
  }
}
