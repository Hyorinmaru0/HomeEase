class Room {
  final String id;
  final String name;
  bool occupied;
  final String? sensor;
  final bool sensorOnline;
  final double? distanceCm;
  final bool? motion;
  Room({
    required this.id,
    required this.name,
    this.occupied = false,
    this.sensor,
    this.sensorOnline = true,
    this.distanceCm,
    this.motion,
  });
  factory Room.fromJson(Map<String, dynamic> j) => Room(
    id: j['id'] as String,
    name: j['name'] as String,
    occupied: j['occupied'] as bool,
    sensor: j['sensor'] as String?,
    sensorOnline: j['sensorOnline'] as bool? ?? true,
    distanceCm: (j['distanceCm'] as num?)?.toDouble(),
    motion: j['motion'] as bool?,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'occupied': occupied,
    'sensor': sensor,
    'sensorOnline': sensorOnline,
    'distanceCm': distanceCm,
    'motion': motion,
  };
}
