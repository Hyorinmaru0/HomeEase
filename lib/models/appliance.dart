enum LoadPriority { high, medium, low }

class Appliance {
  final String id;
  final String name;
  final String roomId;
  final String kind;
  final double ratedWatts;
  final String? hardwareNote;
  bool isOn;
  bool online;
  double watts;
  double totalKwh;
  LoadPriority priority;
  DateTime? onSince;
  double sessionStartKwh;

  Appliance({
    required this.id,
    required this.name,
    required this.roomId,
    required this.kind,
    required this.ratedWatts,
    this.hardwareNote,
    this.isOn = false,
    this.online = true,
    this.watts = 0,
    this.totalKwh = 0,
    this.priority = LoadPriority.medium,
    this.onSince,
    this.sessionStartKwh = 0,
  });

  factory Appliance.fromJson(Map<String, dynamic> j) => Appliance(
    id: j['id'] as String,
    name: j['name'] as String,
    roomId: j['roomId'] as String,
    kind: j['kind'] as String,
    ratedWatts: (j['ratedWatts'] as num).toDouble(),
    hardwareNote: j['hardwareNote'] as String?,
    isOn: j['isOn'] as bool,
    online: j['online'] as bool,
    watts: (j['watts'] as num).toDouble(),
    totalKwh: (j['totalKwh'] as num).toDouble(),
    priority: LoadPriority.values.byName(j['priority'] as String),
    onSince: DateTime.tryParse(j['onSince'] as String? ?? ''),
    sessionStartKwh: (j['sessionStartKwh'] as num? ?? j['totalKwh'] as num)
        .toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'roomId': roomId,
    'kind': kind,
    'ratedWatts': ratedWatts,
    'hardwareNote': hardwareNote,
    'isOn': isOn,
    'online': online,
    'watts': watts,
    'totalKwh': totalKwh,
    'priority': priority.name,
    'onSince': onSince?.toIso8601String(),
    'sessionStartKwh': sessionStartKwh,
  };
}
