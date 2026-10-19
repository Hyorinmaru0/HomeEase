import 'package:flutter/material.dart';

import '../controllers/home_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/energy_card.dart';

class EnergyScreen extends StatefulWidget {
  final HomeController controller;
  final VoidCallback openHistory;
  final VoidCallback openSettings;
  const EnergyScreen({
    super.key,
    required this.controller,
    required this.openHistory,
    required this.openSettings,
  });
  @override
  State<EnergyScreen> createState() => _EnergyScreenState();
}

class _EnergyScreenState extends State<EnergyScreen> {
  int _days = 7;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final total = c.energyForDays(_days);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          eyebrow: 'Insights',
          title: 'Energy',
          subtitle: '${c.energyLabel}. Your consumption and estimated cost.',
        ),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 1, label: Text('Today')),
            ButtonSegment(value: 7, label: Text('7 days')),
            ButtonSegment(value: 30, label: Text('30 days')),
          ],
          selected: {_days},
          onSelectionChanged: (v) => setState(() => _days = v.first),
        ),
        const SizedBox(height: 20),
        Surface(
          color: AppColors.raised,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _days == 1 ? 'Today so far' : 'Last $_days days',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  StatusPill(
                    c.settings.demoMode
                        ? 'Simulated'
                        : c.connected
                        ? 'Synced'
                        : 'Last known',
                    color: AppColors.green,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _EnergyMetric(
                      label: 'Energy used',
                      value: total.toStringAsFixed(3),
                      unit: 'kWh',
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _EnergyMetric(
                      label: 'Estimated cost',
                      value: money(total * c.settings.electricityRate),
                      color: AppColors.mint,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.calculate_outlined,
                    color: AppColors.muted,
                    size: 16,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '${money(c.settings.electricityRate)} per kWh',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.openSettings,
                    child: const Text(
                      'Edit rate',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Energy-only estimate; excludes taxes and fixed charges.',
          style: TextStyle(fontSize: 11, color: AppColors.muted),
        ),
        const SectionHeading('Daily usage', action: 'Last 7 days'),
        Surface(
          child: EnergyBars(
            values: List.generate(
              7,
              (i) => c.energyOn(c.now().subtract(Duration(days: 6 - i))),
            ),
            date: c.now(),
          ),
        ),
        SectionHeading(
          c.energySource == 'measured' && !c.settings.demoMode
              ? 'Live power'
              : 'Estimated power',
          action: '${c.currentWatts.toStringAsFixed(0)} W total',
        ),
        Surface(
          child: Column(
            children: [
              if (c.appliances.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Connect your ESP32 to see live readings.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                ),
              ...c.appliances.map(
                (d) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            applianceIcon(d.kind),
                            size: 18,
                            color: AppColors.muted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              d.name,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Text(
                            '${d.isOn ? d.watts.toStringAsFixed(0) : '0'} W',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          minHeight: 3,
                          value: c.currentWatts == 0
                              ? 0
                              : (d.isOn ? d.watts / c.currentWatts : 0),
                          backgroundColor: AppColors.border,
                          color: d.kind == 'fan'
                              ? AppColors.lavender
                              : AppColors.mint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: widget.openHistory,
            icon: const Icon(Icons.history_rounded, size: 18),
            label: const Text('Usage history'),
          ),
        ),
      ],
    );
  }
}

class _EnergyMetric extends StatelessWidget {
  final String label, value;
  final String? unit;
  final Color color;
  const _EnergyMetric({
    required this.label,
    required this.value,
    this.unit,
    this.color = AppColors.text,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 29,
              letterSpacing: -.8,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        unit ?? 'PHP',
        style: const TextStyle(color: AppColors.muted, fontSize: 11),
      ),
    ],
  );
}
