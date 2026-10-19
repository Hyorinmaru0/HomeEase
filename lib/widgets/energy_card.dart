import 'package:flutter/material.dart';

import '../controllers/home_controller.dart';
import '../theme/app_theme.dart';
import 'common.dart';

class EnergyCard extends StatelessWidget {
  final HomeController controller;
  final VoidCallback onTap;
  const EnergyCard({super.key, required this.controller, required this.onTap});
  @override
  Widget build(BuildContext context) => Surface(
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Today’s energy',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
            IconButton(
              onPressed: onTap,
              tooltip: 'View energy',
              constraints: const BoxConstraints(minHeight: 36, minWidth: 36),
              padding: EdgeInsets.zero,
              icon: const Icon(
                Icons.arrow_outward_rounded,
                size: 18,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: controller.todayKwh.toStringAsFixed(3),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -.7,
                  ),
                  children: const [
                    TextSpan(
                      text: ' kWh',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money(
                      controller.todayKwh * controller.settings.electricityRate,
                    ),
                    style: const TextStyle(fontSize: 18, color: AppColors.mint),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'estimated cost',
                    style: TextStyle(fontSize: 10, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          controller.energyLabel,
          style: const TextStyle(fontSize: 11, color: AppColors.muted),
        ),
        const SizedBox(height: 20),
        EnergyBars(
          values: List.generate(
            7,
            (i) => controller.energyOn(
              controller.now().subtract(Duration(days: 6 - i)),
            ),
          ),
          date: controller.now(),
          compact: true,
        ),
      ],
    ),
  );
}

class EnergyBars extends StatelessWidget {
  final List<double> values;
  final DateTime date;
  final bool compact;
  const EnergyBars({
    super.key,
    required this.values,
    required this.date,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) {
    final max = values.fold<double>(.001, (a, b) => a > b ? a : b);
    return SizedBox(
      height: compact ? 65 : 164,
      child: Stack(
        children: [
          if (!compact)
            Positioned.fill(
              bottom: 24,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                  3,
                  (_) => const Divider(
                    height: 1,
                    color: AppColors.border,
                    thickness: .5,
                  ),
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(values.length, (i) {
              final d = date.subtract(Duration(days: values.length - 1 - i));
              final selected = i == values.length - 1;
              return Expanded(
                child: Semantics(
                  label:
                      '${dateLabel(d)}: ${values[i].toStringAsFixed(3)} kilowatt-hours',
                  child: Tooltip(
                    message:
                        '${dateLabel(d)}: ${values[i].toStringAsFixed(3)} kWh',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (!compact)
                            FittedBox(
                              child: Text(
                                values[i].toStringAsFixed(2),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: selected
                                      ? AppColors.mint
                                      : AppColors.muted,
                                ),
                              ),
                            ),
                          const SizedBox(height: 6),
                          Flexible(
                            child: Container(
                              width: compact ? double.infinity : 26,
                              height:
                                  (compact ? 36 : 112) * values[i] / max + 2,
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.mint
                                    : AppColors.green.withValues(alpha: .28),
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 9),
                          FittedBox(
                            child: Text(
                              compact
                                  ? [
                                      'M',
                                      'T',
                                      'W',
                                      'T',
                                      'F',
                                      'S',
                                      'S',
                                    ][d.weekday - 1]
                                  : [
                                      'Mon',
                                      'Tue',
                                      'Wed',
                                      'Thu',
                                      'Fri',
                                      'Sat',
                                      'Sun',
                                    ][d.weekday - 1],
                              style: TextStyle(
                                fontSize: 10,
                                color: selected
                                    ? AppColors.mint
                                    : AppColors.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
