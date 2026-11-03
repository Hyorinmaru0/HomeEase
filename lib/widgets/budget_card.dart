import 'package:flutter/material.dart';

import '../controllers/home_controller.dart';
import '../services/budget_service.dart';
import '../services/supported_devices.dart';
import '../theme/app_theme.dart';
import 'common.dart';

class BudgetCard extends StatelessWidget {
  final HomeController controller;
  final VoidCallback configure;
  const BudgetCard({
    super.key,
    required this.controller,
    required this.configure,
  });
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final b = c.budgetSummary;
    final largest = b.deviceKwh.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading('Energy budget', action: 'Configure', onTap: configure),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${c.settings.budgetPeriod.toUpperCase()} • ${money(b.budget)} budget',
              ),
              Text('Estimated cost so far: ${money(b.cost)}'),
              Text(
                '${b.remaining < 0 ? "Over budget" : "Remaining budget"}: ${money(b.remaining.abs())}',
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: b.fraction.clamp(0, 1),
                color: b.threshold >= 80 ? AppColors.amber : AppColors.mint,
                semanticsLabel: 'Estimated budget used',
              ),
              const SizedBox(height: 8),
              Text(
                '${(b.fraction * 100).toStringAsFixed(1)}% used • ${b.kwh.toStringAsFixed(4)} estimated kWh',
              ),
              if (b.threshold > 0)
                Text(
                  b.threshold == 100
                      ? 'Estimated budget reached or exceeded.'
                      : 'Warning: estimated spending reached 80% of budget.',
                  style: const TextStyle(color: AppColors.amber),
                ),
              const Divider(),
              ...SupportedDevices.names.entries.map(
                (d) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '${d.value}: ${(b.deviceKwh[d.key] ?? 0).toStringAsFixed(4)} kWh • ${money((b.deviceKwh[d.key] ?? 0) * c.settings.electricityRate)} estimated',
                  ),
                ),
              ),
              const Divider(),
              ...['daily', 'weekly', 'monthly'].map((period) {
                final summary = BudgetService.calculate(
                  [...c.history, ...c.activeSessions],
                  c.now(),
                  period,
                  period == c.settings.budgetPeriod
                      ? c.settings.budget
                      : c.settings.budgetLimits[period] ?? 100,
                  c.settings.electricityRate,
                );
                return Text(
                  '$period: ${summary.kwh.toStringAsFixed(4)} kWh • ${money(summary.cost)} / ${money(summary.budget)} estimated budget',
                );
              }),
              const SizedBox(height: 10),
              Text(
                c.settings.demoMode ? 'Demo: simulated usage history.' : 'Incomplete monitoring: only observed intervals are included. Offline, suspended, and unobserved time is excluded; zero does not prove no usage.',
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
              Text(
                largest.isEmpty
                    ? 'Keep the app open and connected to record usage estimates.'
                    : 'Saving tip: review ${SupportedDevices.names[largest.first.key]} — the largest recorded energy contributor this period.',
                style: const TextStyle(fontSize: 12),
              ),
              const Text(
                'Weekly periods start Monday. Monthly periods use calendar months. Costs use your current rate; wattage changes apply to future observations.',
                style: TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
