import 'package:flutter/material.dart';

import '../controllers/home_controller.dart';
import '../models/appliance.dart';
import '../theme/app_theme.dart';
import 'common.dart';

class DeviceCard extends StatelessWidget {
  final HomeController controller;
  final Appliance device;
  final bool listLayout;
  const DeviceCard({
    super.key,
    required this.controller,
    required this.device,
    this.listLayout = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = device.kind == 'fan' ? AppColors.lavender : AppColors.amber;
    final status = !device.online
        ? 'Unavailable'
        : device.isOn
        ? '${device.watts.toStringAsFixed(0)} W · On'
        : 'Off';
    final toggle = Semantics(
      label: '${device.name} power',
      child: SizedBox(
        width: 52,
        height: 48,
        child: FittedBox(
          child: Switch(
            value: device.isOn,
            onChanged: controller.canControl && device.online
                ? (on) async {
                    if (!await controller.setPower(device.id, on) &&
                        context.mounted) {
                      showMessage(
                        context,
                        controller.error ?? 'Device is unavailable.',
                      );
                    }
                  }
                : null,
          ),
        ),
      ),
    );
    final details = IconButton(
      tooltip: '${device.name} details',
      onPressed: () => showDeviceDetails(context, controller, device.id),
      icon: const Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: AppColors.muted,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      visualDensity: VisualDensity.compact,
    );
    final name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          device.name,
          style: const TextStyle(
            fontSize: 14,
            height: 1.35,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          controller.roomName(device.roomId),
          style: const TextStyle(fontSize: 11, color: AppColors.muted),
        ),
        if (!controller.settings.demoMode && device.hardwareNote != null)
          Text(
            device.hardwareNote!,
            style: const TextStyle(fontSize: 11, color: AppColors.amber),
          ),
      ],
    );
    return Surface(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
      onTap: () => showDeviceDetails(context, controller, device.id),
      color: device.isOn ? AppColors.raised : AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (listLayout)
            Row(
              children: [
                IconTile(
                  applianceIcon(device.kind),
                  color: device.isOn ? color : AppColors.muted,
                  size: 38,
                ),
                const SizedBox(width: 12),
                Expanded(child: name),
                const SizedBox(width: 4),
                toggle,
              ],
            )
          else ...[
            Row(
              children: [
                IconTile(
                  applianceIcon(device.kind),
                  color: device.isOn ? color : AppColors.muted,
                  size: 34,
                ),
                const Spacer(),
                toggle,
              ],
            ),
            const SizedBox(height: 10),
            name,
          ],
          if (listLayout)
            const Padding(
              padding: EdgeInsets.only(top: 12, right: 4),
              child: Divider(height: 1),
            ),
          const SizedBox(height: 5),
          Row(
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: !device.online
                      ? AppColors.amber
                      : device.isOn
                      ? AppColors.mint
                      : AppColors.muted,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 11,
                    color: device.isOn ? AppColors.mint : AppColors.muted,
                  ),
                ),
              ),
              if (listLayout)
                Flexible(
                  fit: FlexFit.tight,
                  child: Text(
                    '${device.priority.name[0].toUpperCase()}${device.priority.name.substring(1)} priority',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              details,
            ],
          ),
        ],
      ),
    );
  }
}

void showDeviceDetails(
  BuildContext context,
  HomeController controller,
  String id,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (context) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final d = controller.device(id);
        if (d == null) {
          return const Padding(
            padding: EdgeInsets.all(30),
            child: Text('Device is no longer available.'),
          );
        }
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconTile(
                  applianceIcon(d.kind),
                  color: d.kind == 'fan' ? AppColors.lavender : AppColors.amber,
                  size: 64,
                ),
                const SizedBox(height: 20),
                Text(d.name, style: Theme.of(context).textTheme.headlineMedium),
                Text(
                  '${controller.roomName(d.roomId)} · ${d.online ? 'Online' : 'Unavailable'}',
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 24),
                if (!controller.settings.demoMode && d.hardwareNote != null)
                  Text(
                    d.hardwareNote!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.amber,
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Power'),
                  subtitle: Text(
                    !d.online
                        ? 'Not connected'
                        : d.kind == 'tv'
                        ? (d.isOn ? 'HomeEase TV • TV ON' : 'Display blank')
                        : (d.isOn ? 'Device is running' : 'Device is off'),
                  ),
                  value: d.isOn,
                  onChanged: controller.canControl && d.online
                      ? (v) async {
                          if (!await controller.setPower(id, v) &&
                              context.mounted) {
                            showMessage(
                              context,
                              controller.error ?? 'Could not change device.',
                            );
                          }
                        }
                      : null,
                ),
                const Divider(),
                Text(
                  '${controller.connectionLabel} • ${controller.energyLabel}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                _DetailLine('Current power', '${d.watts.toStringAsFixed(0)} W'),
                _DetailLine(
                  'Rated power',
                  '${d.ratedWatts.toStringAsFixed(0)} W',
                ),
                _DetailLine(
                  'Current runtime',
                  d.onSince == null
                      ? '—'
                      : durationLabel(controller.now().difference(d.onSince!)),
                ),
                _DetailLine(
                  'Energy this session',
                  '${(d.isOn ? d.totalKwh - d.sessionStartKwh : 0).toStringAsFixed(4)} kWh',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<LoadPriority>(
                  initialValue: d.priority,
                  decoration: const InputDecoration(labelText: 'Load priority'),
                  items: LoadPriority.values
                      .map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: Text(
                            '${p.name[0].toUpperCase()}${p.name.substring(1)} priority',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: controller.canControl
                      ? (p) async {
                          if (p != null &&
                              !await controller.setPriority(id, p) &&
                              context.mounted) {
                            showMessage(
                              context,
                              controller.error ?? 'Could not save priority.',
                            );
                          }
                        }
                      : null,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Priorities help you choose what to switch off when the load is high. Devices are never switched off automatically by this setting.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _DetailLine extends StatelessWidget {
  final String label;
  final String value;
  const _DetailLine(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: AppColors.muted)),
        ),
        Text(value),
      ],
    ),
  );
}
