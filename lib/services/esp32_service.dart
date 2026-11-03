import 'dart:async';
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
  final Duration requestTimeout, readRetryDelay;
  bool _closed = false;
  Esp32Service({
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 6),
    this.readRetryDelay = const Duration(milliseconds: 250),
  }) : _client = client ?? http.Client();
  static bool validAddress(String address) {
    final uri = Uri.tryParse(address.trim());
    return uri != null &&
        ['http', 'https'].contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty;
  }

  Future<http.Response> _request(
    String base,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (!validAddress(base)) {
      throw const Esp32AddressException();
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
            .timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Esp32HttpException(
        response.statusCode,
        body == null ? 'GET' : 'PUT',
      );
    }
    return response;
  }

  @override
  Future<Map<String, dynamic>> fetchState(String baseUrl) async {
    for (var attempt = 0; ; attempt++) {
      try {
        final response = await _request(baseUrl, 'state');
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is! Map<String, dynamic>) {
            throw const Esp32StateException();
          }
          return decoded;
        } on FormatException {
          throw const Esp32StateException();
        }
      } catch (error) {
        if (_closed ||
            attempt > 0 ||
            (error is! http.ClientException && error is! TimeoutException)) {
          rethrow;
        }
        await Future<void>.delayed(readRetryDelay);
        if (_closed) rethrow;
      }
    }
  }

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
  void close() {
    _closed = true;
    _client.close();
  }
}

class LocalNetworkPermissionException implements Exception {
  const LocalNetworkPermissionException();
}

class Esp32AddressException implements Exception {
  const Esp32AddressException();
}

class Esp32HttpException implements Exception {
  final int statusCode;
  final String method;
  const Esp32HttpException(this.statusCode, this.method);
}

class Esp32StateException implements Exception {
  const Esp32StateException();
}

String esp32FailureMessage(Object error) {
  if (error is LocalNetworkPermissionException) {
    return 'Allow local-network access in Android app settings, then reconnect.';
  }
  if (error is Esp32AddressException) {
    return 'Enter the ESP32 base address in Settings, including http://.';
  }
  if (error is Esp32HttpException) {
    if (error.method == 'PUT') {
      if (error.statusCode == 503) {
        return 'ESP32 reported a command failure (HTTP 503). Check device availability and the board storage status in Settings.';
      }
      return 'ESP32 rejected the command (HTTP ${error.statusCode}). Check that the board is running compatible HomeEase firmware.';
    }
    return 'ESP32 state request failed (HTTP ${error.statusCode}). Check the board firmware, then reconnect.';
  }
  if (error is Esp32StateException ||
      error is FormatException ||
      error is TypeError ||
      error is ArgumentError ||
      error is NoSuchMethodError) {
    return 'ESP32 returned invalid device data. Check that the board is running compatible HomeEase firmware.';
  }
  if (error is TimeoutException) {
    return 'ESP32 timed out. Check its address and Wi-Fi, then reconnect.';
  }
  if (error is http.ClientException) {
    return 'Could not reach ESP32. Check its address and Wi-Fi, then reconnect.';
  }
  if (error is PlatformException || error is MissingPluginException) {
    return 'Android local-network access could not be checked. Restart HomeEase and reconnect.';
  }
  return 'Could not confirm ESP32 state. Check the address and Wi-Fi, then reconnect.';
}
