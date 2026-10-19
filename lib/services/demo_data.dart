import '../models/appliance.dart';
import '../models/room.dart';
import '../models/schedule.dart';
import '../models/usage_record.dart';

abstract final class DemoData {
  static Appliance miniTv() => Appliance(
    id: 'mini-tv',
    name: 'Mini TV (LCD 16×2)',
    roomId: 'living',
    kind: 'tv',
    ratedWatts: 1,
    priority: LoadPriority.low,
  );
  static List<Room> rooms() => [
    Room(id: 'living', name: 'Living room', occupied: true),
    Room(id: 'bedroom', name: 'Bedroom'),
  ];
  static List<Appliance> appliances(DateTime now) => [
    Appliance(
      id: 'living-light',
      name: 'Living Room Light',
      roomId: 'living',
      kind: 'light',
      ratedWatts: 12,
      isOn: true,
      watts: 12,
      priority: LoadPriority.high,
      onSince: now.subtract(const Duration(minutes: 42)),
      totalKwh: .0084,
    ),
    Appliance(
      id: 'bedroom-light',
      name: 'Bedroom Light',
      roomId: 'bedroom',
      kind: 'light',
      ratedWatts: 9,
      priority: LoadPriority.medium,
    ),
    Appliance(
      id: 'fan',
      name: 'Fan',
      roomId: 'bedroom',
      kind: 'fan',
      ratedWatts: 45,
      isOn: true,
      watts: 45,
      priority: LoadPriority.low,
      onSince: now.subtract(const Duration(minutes: 85)),
      totalKwh: .06375,
    ),
    miniTv(),
  ];
  static List<DeviceSchedule> schedules() => [
    const DeviceSchedule(
      id: 'morning',
      applianceId: 'living-light',
      name: 'A brighter morning',
      minuteOfDay: 6 * 60 + 30,
      turnOn: true,
      days: [1, 2, 3, 4, 5],
    ),
    const DeviceSchedule(
      id: 'bedtime',
      applianceId: 'fan',
      name: 'Time to wind down',
      minuteOfDay: 23 * 60,
      turnOn: false,
      days: [1, 2, 3, 4, 5, 6, 7],
    ),
  ];
  static List<UsageRecord> history(DateTime now) {
    final records = <UsageRecord>[];
    for (var day = 0; day < 7; day++) {
      final date = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: day));
      for (final device in appliances(now)) {
        final start = date.add(const Duration(hours: 1));
        final end = date.add(
          Duration(hours: device.kind == 'fan' ? 7 + day % 3 : 4 + day % 2),
        );
        // Every seeded session ends in the past, even just after midnight.
        if (end.isAfter(now.subtract(const Duration(hours: 2)))) continue;
        records.add(
          UsageRecord(
            id: 'demo-$day-${device.id}',
            applianceId: device.id,
            applianceName: device.name,
            onTime: start,
            offTime: end,
            energyKwh:
                device.ratedWatts * end.difference(start).inMinutes / 60000,
            rate: 11.5,
          ),
        );
      }
    }
    return records..sort((a, b) => b.offTime.compareTo(a.offTime));
  }
}
