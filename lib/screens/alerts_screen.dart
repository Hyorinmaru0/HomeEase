import 'package:flutter/material.dart';

import '../controllers/home_controller.dart';
import '../models/homeease_alert.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class AlertsScreen extends StatefulWidget {
  final HomeController controller;
  final VoidCallback openDevices;
  const AlertsScreen({
    super.key,
    required this.controller,
    required this.openDevices,
  });
  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  bool _unreadOnly = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final alerts = c.alerts.where((a) => !_unreadOnly || !a.read).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          eyebrow: 'Notifications',
          title: 'Your alerts',
          subtitle: '${c.unreadCount} unread · stay in the know',
        ),
        Row(
          children: [
            FilterChip(
              label: const Text('Unread only'),
              selected: _unreadOnly,
              onSelected: (v) => setState(() => _unreadOnly = v),
            ),
            const Spacer(),
            TextButton(
              onPressed: c.unreadCount == 0 ? null : c.markAlertsRead,
              child: const Text(
                'Mark all read',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (alerts.isEmpty)
          const EmptyState(
            icon: Icons.done_all_rounded,
            title: 'All caught up',
            message: 'We’ll keep an eye on occupancy, long runtimes, and high loads.',
          ),
        ...alerts.map(
          (a) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconTile(
                        switch (a.kind) {
                          AlertKind.smartExit => Icons.door_front_door_outlined,
                          AlertKind.highLoad => Icons.bolt_rounded,
                          AlertKind.abnormalUsage => Icons.schedule_rounded,
                          AlertKind.connection => Icons.wifi_off_rounded,
                        },
                        color: a.kind == AlertKind.smartExit
                            ? AppColors.amber
                            : AppColors.lavender,
                        size: 38,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          switch (a.kind) {
                            AlertKind.smartExit => 'Smart Exit',
                            AlertKind.highLoad => 'High load',
                            AlertKind.abnormalUsage => 'Unusual runtime',
                            AlertKind.connection => 'Connection',
                          },
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                      if (!a.read) const StatusPill('New'),
                    ],
                  ),
                  const SizedBox(height: 17),
                  Text(
                    a.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    a.message,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 13),
                  Text(
                    '${dateLabel(a.createdAt)} · ${clockLabel(a.createdAt)}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (a.kind != AlertKind.connection)
                        TextButton(
                          onPressed: widget.openDevices,
                          child: const Text('Review devices'),
                        ),
                      if (!a.read)
                        TextButton(
                          onPressed: () => c.markAlertRead(a.id),
                          child: const Text('Mark read'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
