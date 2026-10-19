import 'package:flutter/material.dart';

import '../controllers/home_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/device_card.dart';
import '../widgets/energy_card.dart';
import '../widgets/room_status_card.dart';

class DashboardScreen extends StatelessWidget {
  final HomeController controller;
  final ValueChanged<int> navigate;
  final VoidCallback openRooms;
  final VoidCallback openAlerts;
  final VoidCallback openHistory;
  const DashboardScreen({
    super.key,
    required this.controller,
    required this.navigate,
    required this.openRooms,
    required this.openAlerts,
    required this.openHistory,
  });

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Home overview',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'My home',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                ],
              ),
            ),
            StatusPill(
              c.settings.demoMode
                  ? 'Demo'
                  : c.connected
                  ? 'Connected'
                  : 'Offline',
              color: c.settings.demoMode || c.connected
                  ? AppColors.mint
                  : AppColors.amber,
            ),
          ],
        ),
        const SizedBox(height: 22),
        _HomeOverview(controller: c, onRooms: openRooms),
        SectionHeading(
          'Quick controls',
          action: 'All devices',
          onTap: () => navigate(1),
        ),
        if (c.appliances.isEmpty)
          const EmptyState(
            icon: Icons.devices_other_rounded,
            title: 'Connect your home',
            message: 'Add your ESP32 address in Settings to see your devices.',
          ),
        AdaptiveGrid(
          minWidth: 150,
          children: c.appliances
              .map((d) => DeviceCard(controller: c, device: d))
              .toList(),
        ),
        SectionHeading('Rooms', action: 'View all', onTap: openRooms),
        AdaptiveGrid(
          minWidth: 150,
          children: c.rooms
              .map(
                (r) => RoomStatusCard(
                  room: r,
                  status: c.roomStatus(r),
                  sensorReading: c.sensorReading(r),
                  activeDevices: c.appliances
                      .where((d) => d.roomId == r.id && d.isOn)
                      .length,
                  onTap: openRooms,
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 20),
        EnergyCard(controller: c, onTap: () => navigate(2)),
        SectionHeading('Recent activity', action: 'Alerts', onTap: openAlerts),
        Surface(
          onTap: openAlerts,
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(
                c.alerts.isEmpty
                    ? Icons.done_rounded
                    : Icons.notifications_none_rounded,
                color: c.alerts.isEmpty ? AppColors.mint : AppColors.amber,
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.alerts.isEmpty
                          ? 'You’re all caught up'
                          : c.alerts.first.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      c.alerts.isEmpty
                          ? 'No alerts to review.'
                          : c.alerts.first.message,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.muted,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: openHistory,
          icon: const Icon(Icons.history_rounded, size: 18),
          label: const Text('Usage history'),
        ),
      ],
    );
  }
}

class _HomeOverview extends StatelessWidget {
  final HomeController controller;
  final VoidCallback onRooms;
  const _HomeOverview({required this.controller, required this.onRooms});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final occupied = c.rooms.where((r) => r.sensorOnline && r.occupied).length;
    final occupancyKnown =
        c.settings.demoMode ||
        (c.connected && c.rooms.every((r) => r.sensorOnline));
    final load = (c.currentWatts / c.settings.highLoadWatts).clamp(0.0, 1.0);
    return Surface(
      color: AppColors.raised,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CURRENT POWER',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.1,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text.rich(
                      TextSpan(
                        text: c.currentWatts.toStringAsFixed(0),
                        style: const TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -1.5,
                          color: AppColors.mint,
                        ),
                        children: const [
                          TextSpan(
                            text: ' W',
                            style: TextStyle(
                              fontSize: 17,
                              letterSpacing: 0,
                              fontWeight: FontWeight.w400,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      c.settings.demoMode
                          ? 'Simulated home usage'
                          : c.connected
                          ? c.energyLabel
                          : 'Last known • ${c.energyLabel}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Semantics(
                label: '${(load * 100).round()} percent of load threshold',
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: load,
                          strokeWidth: 5,
                          strokeCap: StrokeCap.round,
                          backgroundColor: AppColors.border,
                          color: load >= 1 ? AppColors.amber : AppColors.mint,
                        ),
                      ),
                      const Icon(
                        Icons.bolt_rounded,
                        color: AppColors.mint,
                        size: 28,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _OverviewStat(
                  icon: Icons.power_outlined,
                  value: '${c.activeCount} / ${c.appliances.length}',
                  label: 'devices on',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'View room occupancy',
                  child: InkWell(
                    onTap: onRooms,
                    borderRadius: BorderRadius.circular(8),
                    child: _OverviewStat(
                      icon: Icons.meeting_room_outlined,
                      value:
                          '${occupancyKnown ? occupied : '—'} / ${c.rooms.length}',
                      label: 'rooms occupied',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewStat extends StatelessWidget {
  final IconData icon;
  final String value, label;
  const _OverviewStat({
    required this.icon,
    required this.value,
    required this.label,
  });
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Icon(icon, size: 18, color: AppColors.muted),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
        ),
      ),
    ],
  );
}
