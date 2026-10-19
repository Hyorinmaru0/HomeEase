import 'package:flutter/material.dart';

import '../controllers/home_controller.dart';
import '../models/schedule.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class SchedulesScreen extends StatelessWidget {
  final HomeController controller;
  const SchedulesScreen({super.key, required this.controller});
  Future<void> _edit(BuildContext context, [DeviceSchedule? schedule]) async {
    final result = await showModalBottomSheet<DeviceSchedule>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          ScheduleEditor(controller: controller, existing: schedule),
    );
    if (result == null) return;
    final ok = await controller.saveSchedule(result);
    if (context.mounted) {
      showMessage(
        context,
        ok ? 'Schedule saved.' : controller.error ?? 'Could not save schedule.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const PageHeading(
        eyebrow: 'Automation',
        title: 'Routines',
        subtitle: 'Set a time. Let your home take care of it.',
      ),
      Surface(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: AppColors.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.settings.demoMode
                        ? 'Demo routines run while the app is open.'
                        : controller.espClockSynced == false
                        ? 'ESP32 clock is waiting for time sync. Saved routines will run once its clock is ready.'
                        : 'Schedules sync to your ESP32 and run there while the app is closed.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      SectionHeading(
        'Schedules',
        action: '${controller.schedules.where((s) => s.enabled).length} active',
      ),
      if (controller.schedules.isEmpty)
        const EmptyState(
          icon: Icons.event_repeat_rounded,
          title: 'Your first routine awaits',
          message: 'Schedule a light for the morning or switch off a fan at bedtime.',
        ),
      ...controller.schedules.map(
        (s) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconTile(
                      s.turnOn
                          ? Icons.wb_sunny_outlined
                          : Icons.nightlight_outlined,
                      color: s.turnOn ? AppColors.amber : AppColors.lavender,
                      size: 42,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            controller.device(s.applianceId)?.name ??
                                s.applianceId,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: s.enabled,
                      onChanged: controller.canControl
                          ? (v) async {
                              if (!await controller.saveSchedule(
                                    s.withEnabled(v),
                                  ) &&
                                  context.mounted) {
                                showMessage(
                                  context,
                                  controller.error ??
                                      'Could not update schedule.',
                                );
                              }
                            }
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      TimeOfDay(
                        hour: s.minuteOfDay ~/ 60,
                        minute: s.minuteOfDay % 60,
                      ).format(context),
                      style: const TextStyle(fontSize: 24, letterSpacing: -.6),
                    ),
                    StatusPill(
                      s.turnOn ? 'Turn on' : 'Turn off',
                      color: s.turnOn ? AppColors.mint : AppColors.lavender,
                      dot: false,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.days.length == 7
                            ? 'Every day'
                            : s.days
                                  .map(
                                    (d) => [
                                      'Mon',
                                      'Tue',
                                      'Wed',
                                      'Thu',
                                      'Fri',
                                      'Sat',
                                      'Sun',
                                    ][d - 1],
                                  )
                                  .join(' · '),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit ${s.name}',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: controller.canControl
                          ? () => _edit(context, s)
                          : null,
                    ),
                    IconButton(
                      tooltip: 'Delete ${s.name}',
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      onPressed: controller.canControl
                          ? () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Delete schedule?'),
                                  content: Text('Remove “${s.name}”?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                final ok = await controller.deleteSchedule(
                                  s.id,
                                );
                                if (!ok && context.mounted) {
                                  showMessage(
                                    context,
                                    controller.error ??
                                        'Could not delete schedule.',
                                  );
                                }
                              }
                            }
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: controller.canControl && controller.appliances.isNotEmpty
              ? () => _edit(context)
              : null,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Create schedule'),
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'Times use the phone’s local time. Set the same timezone on your ESP32 when connecting your hardware.',
        style: TextStyle(color: AppColors.muted, fontSize: 11),
      ),
    ],
  );
}

class ScheduleEditor extends StatefulWidget {
  final HomeController controller;
  final DeviceSchedule? existing;
  const ScheduleEditor({super.key, required this.controller, this.existing});
  @override
  State<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<ScheduleEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late String _device;
  late TimeOfDay _time;
  late bool _on;
  late Set<int> _days;
  String? _dayError;
  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    _name = TextEditingController(text: s?.name ?? '');
    _device = s?.applianceId ?? widget.controller.appliances.first.id;
    _time = TimeOfDay(
      hour: (s?.minuteOfDay ?? 420) ~/ 60,
      minute: (s?.minuteOfDay ?? 420) % 60,
    );
    _on = s?.turnOn ?? true;
    _days = (s?.days ?? [1, 2, 3, 4, 5, 6, 7]).toSet();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.existing == null ? 'Create a routine' : 'Edit routine',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _name,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: 'Schedule name',
                hintText: 'e.g. A brighter morning',
              ),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Give your schedule a name.'
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _device,
              decoration: const InputDecoration(labelText: 'Appliance'),
              items: widget.controller.appliances
                  .map(
                    (d) => DropdownMenuItem(value: d.id, child: Text(d.name)),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _device = v!),
            ),
            const SizedBox(height: 20),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.power_settings_new),
                  label: Text('Turn on'),
                ),
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.power_off_outlined),
                  label: Text('Turn off'),
                ),
              ],
              selected: {_on},
              onSelectionChanged: (v) => setState(() => _on = v.first),
            ),
            const SizedBox(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const IconTile(Icons.schedule_rounded),
              title: const Text('Time'),
              trailing: TextButton(
                onPressed: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: _time,
                  );
                  if (time != null && mounted) setState(() => _time = time);
                },
                child: Text(
                  _time.format(context),
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Repeat on', style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 8,
              children: List.generate(
                7,
                (i) => FilterChip(
                  label: Text(
                    ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][i],
                  ),
                  selected: _days.contains(i + 1),
                  onSelected: (v) => setState(() {
                    v ? _days.add(i + 1) : _days.remove(i + 1);
                    _dayError = null;
                  }),
                ),
              ),
            ),
            if (_dayError != null)
              Text(
                _dayError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  if (!_form.currentState!.validate()) return;
                  if (_days.isEmpty) {
                    setState(() => _dayError = 'Select at least one day.');
                    return;
                  }
                  final minutes = _time.hour * 60 + _time.minute;
                  final conflict = widget.controller.schedules.any(
                    (s) =>
                        s.id != widget.existing?.id &&
                        s.applianceId == _device &&
                        s.minuteOfDay == minutes &&
                        s.days.any(_days.contains),
                  );
                  if (conflict) {
                    setState(
                      () => _dayError =
                          'This appliance already has a schedule at that time.',
                    );
                    return;
                  }
                  Navigator.pop(
                    context,
                    DeviceSchedule(
                      id:
                          widget.existing?.id ??
                          'schedule-${DateTime.now().microsecondsSinceEpoch}',
                      applianceId: _device,
                      name: _name.text.trim(),
                      minuteOfDay: minutes,
                      turnOn: _on,
                      days: _days.toList()..sort(),
                      enabled: widget.existing?.enabled ?? true,
                    ),
                  );
                },
                child: const Text('Save schedule'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
