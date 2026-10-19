import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/schedule.dart';

abstract class Esp32Gateway {
  Future<Map<String, dynamic>> fetchState(String baseUrl);
  Future<void> setPower(String baseUrl, String id, bool on);
  Future<void> setPriority(String baseUrl, String id, String priority);
  Future<void> saveSchedules(String baseUrl, List<DeviceSchedule> schedules);
  void close();
}

class Esp32Service implements Esp32Gateway {
  final http.Client _client;
  Esp32Service({http.Client? client}) : _client = client ?? http.Client();
  static bool validAddress(String address) {
    final uri = Uri.tryParse(address.trim());
    return uri != null &&
        ['http', 'https'].contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty;
  }

  Future<Map<String, dynamic>> _request(
    String base,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (!validAddress(base)) {
      throw const FormatException(
        'Enter a valid http:// or https:// ESP32 address.',
      );
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final granted = await const MethodChannel('homeease/network')
          .invokeMethod<bool>('ensureLocalNetwork');
      if (granted != true) throw const LocalNetworkPermissionException();
    }
    final uri = Uri.parse(
      '${base.trim().replaceAll(RegExp(r'/+$'), '')}/api/$path',
    );
    final response =
        await (body == null
                ? _client.get(uri)
                : _client.put(
                    uri,
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(body),
                  ))
            .timeout(const Duration(seconds: 6));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('ESP32 returned HTTP ${response.statusCode}.');
    }
    return response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> fetchState(String baseUrl) =>
      _request(baseUrl, 'state');
  @override
  Future<void> setPower(String baseUrl, String id, bool on) async {
    await _request(
      baseUrl,
      'devices/${Uri.encodeComponent(id)}/power',
      body: {'isOn': on},
    );
  }

  @override
  Future<void> setPriority(String baseUrl, String id, String priority) async {
    await _request(
      baseUrl,
      'devices/${Uri.encodeComponent(id)}/priority',
      body: {'priority': priority},
    );
  }

  @override
  Future<void> saveSchedules(
    String baseUrl,
    List<DeviceSchedule> schedules,
  ) async {
    await _request(
      baseUrl,
      'schedules',
      body: {'schedules': schedules.map((s) => s.toJson()).toList()},
    );
  }

  @override
  void close() => _client.close();
}

class LocalNetworkPermissionException implements Exception {
  const LocalNetworkPermissionException();
}
