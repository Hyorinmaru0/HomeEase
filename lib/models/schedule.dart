class DeviceSchedule {
  final String id;
  final String applianceId;
  final String name;
  final int minuteOfDay;
  final bool turnOn;
  final List<int> days;
  final bool enabled;
  const DeviceSchedule({
    required this.id,
    required this.applianceId,
    required this.name,
    required this.minuteOfDay,
    required this.turnOn,
    required this.days,
    this.enabled = true,
  });
  DeviceSchedule withEnabled(bool value) => DeviceSchedule(
    id: id,
    applianceId: applianceId,
    name: name,
    minuteOfDay: minuteOfDay,
    turnOn: turnOn,
    days: days,
    enabled: value,
  );
  factory DeviceSchedule.fromJson(Map<String, dynamic> j) {
    final minute = j['minuteOfDay'] as int;
    final days = List<int>.from(j['days']);
    if (minute < 0 ||
        minute >= 1440 ||
        days.isEmpty ||
        days.any((d) => d < 1 || d > 7)) {
      throw const FormatException('Invalid schedule');
    }
    return DeviceSchedule(
      id: j['id'],
      applianceId: j['applianceId'],
      name: j['name'],
      minuteOfDay: minute,
      turnOn: j['turnOn'],
      days: days,
      enabled: j['enabled'],
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'applianceId': applianceId,
    'name': name,
    'minuteOfDay': minuteOfDay,
    'turnOn': turnOn,
    'days': days,
    'enabled': enabled,
  };
}
