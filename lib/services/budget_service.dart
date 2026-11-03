import '../models/usage_record.dart';

class BudgetSummary {
  final DateTime start, end;
  final double budget, rate;
  final Map<String, double> deviceKwh;
  BudgetSummary(this.start, this.end, this.budget, this.rate, this.deviceKwh);
  double get kwh => deviceKwh.values.fold(0, (a, b) => a + b);
  double get cost => kwh * rate;
  double get remaining => budget - cost;
  double get fraction => budget > 0 ? cost / budget : 0;
  int get threshold => fraction >= 1
      ? 100
      : fraction >= .8
      ? 80
      : 0;
}

abstract final class BudgetService {
  static Map<String, double> energyBetween(
    Iterable<UsageRecord> records,
    DateTime start,
    DateTime end,
  ) {
    final byId = <String, UsageRecord>{};
    for (final r in records) {
      final key = '${r.applianceId}:${r.id}';
      if (byId[key] == null || r.offTime.isAfter(byId[key]!.offTime)) {
        byId[key] = r;
      }
    }
    final sorted = byId.values.toList()
      ..sort((a, b) {
        final order = a.onTime.compareTo(b.onTime);
        return order != 0 ? order : a.id.compareTo(b.id);
      });
    final coveredUntil = <String, DateTime>{};
    final result = <String, double>{};
    for (final r in sorted) {
      if (r.runtime.inMilliseconds <= 0 ||
          !r.energyKwh.isFinite ||
          r.energyKwh < 0) {
        continue;
      }
      var a = r.onTime.isAfter(start) ? r.onTime : start;
      final covered = coveredUntil[r.applianceId];
      if (covered != null && covered.isAfter(a)) a = covered;
      final b = r.offTime.isBefore(end) ? r.offTime : end;
      if (!b.isAfter(a)) continue;
      final energy =
          r.energyKwh *
          b.difference(a).inMilliseconds /
          r.runtime.inMilliseconds;
      result.update(r.applianceId, (v) => v + energy, ifAbsent: () => energy);
      coveredUntil[r.applianceId] = b;
    }
    return result;
  }

  static BudgetSummary calculate(
    Iterable<UsageRecord> records,
    DateTime now,
    String period,
    double budget,
    double rate,
  ) {
    final day = DateTime(now.year, now.month, now.day);
    final start = switch (period) {
      'daily' => day,
      'weekly' => day.subtract(Duration(days: day.weekday - 1)),
      _ => DateTime(now.year, now.month),
    };
    final end = switch (period) {
      'daily' => DateTime(start.year, start.month, start.day + 1),
      'weekly' => DateTime(start.year, start.month, start.day + 7),
      _ => DateTime(start.year, start.month + 1),
    };
    final byDevice = energyBetween(
      records,
      start,
      now.isBefore(end) ? now : end,
    );
    return BudgetSummary(start, end, budget, rate, byDevice);
  }
}
