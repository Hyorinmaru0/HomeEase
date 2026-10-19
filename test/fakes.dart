import 'dart:convert';

import 'package:homeease/services/storage_service.dart';
import 'package:homeease/services/esp32_service.dart';
import 'package:homeease/models/schedule.dart';

class MemoryStorage implements HomeStorage {
  final Map<String, String> data = {};
  bool failWrites = false;
  @override
  Future<Map<String, dynamic>?> read(String key) async =>
      data[key] == null ? null : jsonDecode(data[key]!) as Map<String, dynamic>;
  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    if (failWrites) throw Exception('disk full');
    data[key] = jsonEncode(value);
  }
}

class FakeGateway implements Esp32Gateway {
  Map<String, dynamic> state = {
    'devices': <dynamic>[],
    'rooms': <dynamic>[],
    'history': <dynamic>[],
    'schedules': <dynamic>[],
  };
  bool fail = false;
  int powerCalls = 0;
  @override
  Future<Map<String, dynamic>> fetchState(String baseUrl) async {
    if (fail) throw Exception('offline');
    return jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
  }

  @override
  Future<void> setPower(String baseUrl, String id, bool on) async {
    powerCalls++;
    if (fail) throw Exception('offline');
    final d = (state['devices'] as List).firstWhere((d) => d['id'] == id);
    d['isOn'] = on;
    d['watts'] = on ? d['ratedWatts'] : 0;
  }

  @override
  Future<void> setPriority(String baseUrl, String id, String priority) async {
    if (fail) throw Exception('offline');
    (state['devices'] as List).firstWhere((d) => d['id'] == id)['priority'] =
        priority;
  }

  @override
  Future<void> saveSchedules(
    String baseUrl,
    List<DeviceSchedule> schedules,
  ) async {
    if (fail) throw Exception('offline');
    state['schedules'] = schedules.map((s) => s.toJson()).toList();
  }

  @override
  void close() {}
}
