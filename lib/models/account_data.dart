import '../services/supported_devices.dart';

class UserProfile {
  final String userId, fullName;
  const UserProfile(this.userId, this.fullName);
  factory UserProfile.fromJson(Map<String, dynamic> j) =>
      UserProfile(j['user_id'], j['full_name']);
  Map<String, dynamic> toJson() => {'user_id': userId, 'full_name': fullName};
}

class DevicePreference {
  final String deviceId, displayName, room;
  final Map<String, dynamic> preferences;
  const DevicePreference({
    required this.deviceId,
    required this.displayName,
    required this.room,
    this.preferences = const {},
  });
  factory DevicePreference.fromJson(Map<String, dynamic> j) => DevicePreference(
    deviceId: SupportedDevices.canonical(j['device_id']),
    displayName:
        j['device_id'] == 'bedroom-lamp' &&
            [
              'Table Lamp',
              'Bedroom Lamp',
              'Bedroom Table Lamp',
            ].contains(j['display_name'])
        ? 'Smart Wall Lamp'
        : j['display_name'],
    room: j['room'],
    preferences: Map<String, dynamic>.from(j['preferences'] ?? {}),
  );
  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'display_name': displayName,
    'room': room,
    'preferences': preferences,
  };
}

class DeviceActivity {
  final String id, deviceId, action, source;
  final DateTime eventTime;
  final bool success;
  const DeviceActivity({
    required this.id,
    required this.deviceId,
    required this.action,
    required this.source,
    required this.eventTime,
    required this.success,
  });
  factory DeviceActivity.fromJson(Map<String, dynamic> j) => DeviceActivity(
    id: j['id'],
    deviceId: SupportedDevices.canonical(j['device_id']),
    action: j['action'],
    source: j['source'],
    eventTime: DateTime.parse(j['event_time']).toLocal(),
    success: j['success'],
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'device_id': deviceId,
    'action': action,
    'source': source,
    'event_time': eventTime.toUtc().toIso8601String(),
    'success': success,
  };
}
