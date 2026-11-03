import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:homeease/services/esp32_service.dart';
import 'package:homeease/services/supported_devices.dart';

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.linux);
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test('all seven appliance IDs use the same Wi-Fi power API', () async {
    final calls = <String>[];
    final service = Esp32Service(
      client: MockClient((request) async {
        calls.add(request.url.path);
        expect(request.method, 'PUT');
        expect(request.headers['content-type'], 'application/json');
        expect(jsonDecode(request.body), {'isOn': true});
        return http.Response('{}', 200);
      }),
    );
    for (final id in SupportedDevices.names.keys) {
      await service.setPower(' http://192.168.1.100/ ', id, true);
      expect(calls.last, '/api/devices/$id/power');
    }
    expect(calls.length, 7);
    service.close();
  });
  test(
    'uses an encoded device path and explicit idempotent power value',
    () async {
      final service = Esp32Service(
        client: MockClient((request) async {
          expect(request.method, 'PUT');
          expect(
            request.url.toString(),
            'http://192.168.1.100/api/devices/living%20light/power',
          );
          expect(jsonDecode(request.body), {'isOn': true});
          return http.Response('', 204);
        }),
      );
      await service.setPower('http://192.168.1.100/', 'living light', true);
      service.close();
    },
  );
  test(
    'surfaces non-success responses instead of accepting a command',
    () async {
      final service = Esp32Service(
        client: MockClient((_) async => http.Response('unavailable', 503)),
      );
      await expectLater(
        service.setPower('http://192.168.1.100', 'fan', false),
        throwsException,
      );
      service.close();
    },
  );
  test('validates connection addresses', () {
    expect(Esp32Service.validAddress('http://192.168.1.100:8080'), isTrue);
    expect(Esp32Service.validAddress('https://home.local'), isTrue);
    for (final address in [
      '192.168.1.100',
      'ftp://host',
      'http://',
      'http://user:pass@host',
      'http://host?x=1',
    ]) {
      expect(Esp32Service.validAddress(address), isFalse);
    }
  });

  test('successful command acknowledgments do not require JSON', () async {
    for (final body in ['OK', 'Power updated', '{}', '']) {
      final service = Esp32Service(
        client: MockClient((_) async => http.Response(body, 200)),
      );
      await service.setPower('http://board.local', 'living-light', true);
      service.close();
    }
  });

  test('state reads still require a JSON object', () async {
    for (final body in ['OK', '', '[]', '{broken']) {
      final service = Esp32Service(
        client: MockClient((_) async => http.Response(body, 200)),
      );
      await expectLater(
        service.fetchState('http://board.local'),
        throwsA(isA<Esp32StateException>()),
      );
      service.close();
    }
  });

  test('state read retries an unanswered read once', () async {
    var calls = 0;
    final service = Esp32Service(
      readRetryDelay: Duration.zero,
      client: MockClient((_) async {
        calls++;
        if (calls == 1) throw http.ClientException('connection closed');
        return http.Response('{"devices":[]}', 200);
      }),
    );
    expect(
      (await service.fetchState('http://board.local'))['devices'],
      isEmpty,
    );
    expect(calls, 2);
    service.close();
  });

  test(
    'timeouts are bounded to two reads and physical writes are not replayed',
    () async {
      var reads = 0, writes = 0;
      final service = Esp32Service(
        readRetryDelay: Duration.zero,
        client: MockClient((request) async {
          if (request.method == 'GET') {
            reads++;
          } else {
            writes++;
          }
          throw TimeoutException('test timeout');
        }),
      );
      await expectLater(
        service.fetchState('http://board.local'),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(
        service.setPower('http://board.local', 'living-light', true),
        throwsA(isA<TimeoutException>()),
      );
      expect(reads, 2);
      expect(writes, 1);
      service.close();
    },
  );

  test(
    'explicit board HTTP errors are not retried or mislabeled as Wi-Fi',
    () async {
      var calls = 0;
      final service = Esp32Service(
        client: MockClient((_) async {
          calls++;
          return http.Response('private board diagnostics', 503);
        }),
      );
      await expectLater(
        service.fetchState('http://board.local'),
        throwsA(isA<Esp32HttpException>()),
      );
      expect(calls, 1);
      final message = esp32FailureMessage(const Esp32HttpException(503, 'PUT'));
      expect(message, contains('HTTP 503'));
      expect(message, contains('storage'));
      expect(message, isNot(contains('private board diagnostics')));
      service.close();
    },
  );
}
