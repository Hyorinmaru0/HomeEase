class UsageRecord {
  final String id;
  final String applianceId;
  final String applianceName;
  final DateTime onTime;
  final DateTime offTime;
  final double energyKwh;
  final double rate;
  const UsageRecord({
    required this.id,
    required this.applianceId,
    required this.applianceName,
    required this.onTime,
    required this.offTime,
    required this.energyKwh,
    required this.rate,
  });
  Duration get runtime => offTime.difference(onTime);
  double get cost => energyKwh * rate;
  // Spread a session across dates proportionally, including overnight sessions.
  double energyOn(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final a = onTime.isAfter(start) ? onTime : start;
    final b = offTime.isBefore(end) ? offTime : end;
    if (!b.isAfter(a) || runtime.inMilliseconds <= 0) return 0;
    return energyKwh * b.difference(a).inMilliseconds / runtime.inMilliseconds;
  }

  factory UsageRecord.fromJson(Map<String, dynamic> j) => UsageRecord(
    id: j['id'],
    applianceId: j['applianceId'],
    applianceName: j['applianceName'],
    onTime: DateTime.parse(j['onTime']).toLocal(),
    offTime: DateTime.parse(j['offTime']).toLocal(),
    energyKwh: (j['energyKwh'] as num).toDouble(),
    rate: (j['rate'] as num).toDouble(),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'applianceId': applianceId,
    'applianceName': applianceName,
    'onTime': onTime.toIso8601String(),
    'offTime': offTime.toIso8601String(),
    'energyKwh': energyKwh,
    'rate': rate,
  };
}
