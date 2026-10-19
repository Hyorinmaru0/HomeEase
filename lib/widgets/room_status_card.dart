import 'package:flutter/material.dart';

import '../models/room.dart';
import '../theme/app_theme.dart';
import 'common.dart';

class RoomStatusCard extends StatelessWidget {
  final Room room;
  final int activeDevices;
  final String status;
  final String sensorReading;
  final VoidCallback? onTap;
  const RoomStatusCard({
    super.key,
    required this.room,
    required this.activeDevices,
    required this.status,
    required this.sensorReading,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => Surface(
    onTap: onTap,
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              room.id == 'living' ? Icons.weekend_outlined : Icons.bed_outlined,
              color: AppColors.muted,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                room.name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          status,
          style: TextStyle(
            fontSize: 13,
            color: room.occupied ? AppColors.mint : AppColors.muted,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          sensorReading,
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
        const SizedBox(height: 3),
        Text(
          '$activeDevices device${activeDevices == 1 ? '' : 's'} on',
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
      ],
    ),
  );
}
