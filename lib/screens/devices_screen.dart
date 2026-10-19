import 'package:flutter/material.dart';

import '../controllers/home_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/device_card.dart';

class DevicesScreen extends StatefulWidget {
  final HomeController controller;
  const DevicesScreen({super.key, required this.controller});
  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  String? _room;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final devices = c.appliances
        .where((d) => _room == null || d.roomId == _room)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          eyebrow: 'Control',
          title: 'Your devices',
          subtitle:
              '${c.appliances.length} devices · ${c.activeCount} switched on · ${c.connectionLabel}',
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('All rooms'),
                  selected: _room == null,
                  onSelected: (_) => setState(() => _room = null),
                ),
              ),
              ...c.rooms.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(r.name),
                    selected: _room == r.id,
                    onSelected: (_) => setState(() => _room = r.id),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (devices.isEmpty)
          const EmptyState(
            icon: Icons.devices_other,
            title: 'No devices here yet',
            message: 'Your devices will appear after connecting your ESP32.',
          ),
        AdaptiveGrid(
          minWidth: 340,
          children: devices
              .map(
                (d) => DeviceCard(controller: c, device: d, listLayout: true),
              )
              .toList(),
        ),
        const SizedBox(height: 22),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.layers_outlined, size: 18, color: AppColors.muted),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Tap a device to see its usage and set its load priority.',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
