import 'package:flutter/material.dart';

import '../controllers/home_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class RoomsScreen extends StatelessWidget {
  final HomeController controller;
  const RoomsScreen({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PageHeading(
        eyebrow: 'Occupancy',
        title: 'Room occupancy',
        subtitle: controller.settings.demoMode
            ? 'Tap a switch to simulate an occupancy sensor.'
            : controller.connected
            ? 'Occupancy readings from your ESP32 sensors.'
            : 'Last known sensor readings. Reconnect to update.',
      ),
      ...controller.rooms.map(
        (r) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconTile(
                      r.id == 'living'
                          ? Icons.weekend_outlined
                          : Icons.bed_outlined,
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Text(
                        r.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Flexible(
                      flex: 2,
                      child: StatusPill(
                        controller.roomStatus(r),
                        color: r.occupied ? AppColors.mint : AppColors.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  controller.sensorReading(r),
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                ...controller.appliances
                    .where((d) => d.roomId == r.id)
                    .map(
                      (d) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                d.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                            Text(
                              !d.online
                                  ? 'Unavailable'
                                  : d.isOn
                                  ? '${d.watts.toStringAsFixed(0)} W · On'
                                  : 'Off',
                              style: TextStyle(
                                fontSize: 12,
                                color: d.isOn
                                    ? AppColors.mint
                                    : AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                if (controller.settings.demoMode) ...[
                  const Divider(height: 30),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Simulate occupancy',
                      style: TextStyle(fontSize: 13),
                    ),
                    value: r.occupied,
                    onChanged: (v) => controller.setOccupancy(r.id, v),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      if (controller.rooms.isEmpty)
        const EmptyState(
          icon: Icons.sensor_door_outlined,
          title: 'No room readings',
          message: 'Connect your ESP32 to see room occupancy.',
        ),
      const SizedBox(height: 8),
      const Text(
        'Smart Exit creates an alert when a room is vacant while an appliance is still on.',
        style: TextStyle(color: AppColors.muted, fontSize: 12),
      ),
    ],
  );
}
