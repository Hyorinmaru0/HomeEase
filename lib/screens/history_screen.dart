import 'package:flutter/material.dart';

import '../controllers/home_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class HistoryScreen extends StatefulWidget {
  final HomeController controller;
  const HistoryScreen({super.key, required this.controller});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String? _device;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final records = c.history
        .where((r) => _device == null || r.applianceId == _device)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          eyebrow: 'Activity',
          title: 'Usage history',
          subtitle: 'Every completed session, in one place. ${c.energyLabel}.',
        ),
        DropdownButtonFormField<String>(
          initialValue: _device ?? 'all',
          decoration: const InputDecoration(labelText: 'Appliance'),
          items: [
            const DropdownMenuItem(value: 'all', child: Text('All appliances')),
            ...c.appliances.map(
              (d) => DropdownMenuItem(value: d.id, child: Text(d.name)),
            ),
          ],
          onChanged: (v) => setState(() => _device = v == 'all' ? null : v),
        ),
        const SizedBox(height: 20),
        if (records.isEmpty)
          const EmptyState(
            icon: Icons.history_rounded,
            title: 'A fresh start',
            message:
                'Switch an appliance on, then off to record its first session.',
          ),
        ...records
            .take(100)
            .map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              r.applianceName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            money(r.cost),
                            style: const TextStyle(color: AppColors.mint),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${dateLabel(r.onTime)} · ${clockLabel(r.onTime)} → ${dateLabel(r.offTime)} · ${clockLabel(r.offTime)}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          StatusPill(
                            durationLabel(r.runtime),
                            color: AppColors.muted,
                            dot: false,
                          ),
                          StatusPill(
                            '${r.energyKwh.toStringAsFixed(4)} kWh',
                            color: AppColors.green,
                            dot: false,
                          ),
                          StatusPill(
                            '${money(r.rate)}/kWh',
                            color: AppColors.muted,
                            dot: false,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        if (records.length > 100)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Showing the most recent 100 sessions for this filter.',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
