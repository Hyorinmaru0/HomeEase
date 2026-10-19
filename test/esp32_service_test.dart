import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:homeease/services/esp32_service.dart';

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.linux);
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test('all four appliance IDs use the same Wi-Fi power API', () async {
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
    for (final id in ['living-light', 'bedroom-light', 'fan', 'mini-tv']) {
      await service.setPower(' http://192.168.1.100/ ', id, true);
      expect(calls.last, '/api/devices/$id/power');
    }
    expect(calls.length, 4);
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
}
