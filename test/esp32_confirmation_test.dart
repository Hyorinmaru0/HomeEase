import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:homeease/controllers/home_controller.dart';
import 'package:homeease/models/app_settings.dart';
import 'package:homeease/services/esp32_service.dart';

import 'fakes.dart';

void main() {
  late HomeController home;
  late Map<String, dynamic> board;
  late List<String> requests;
  late int writeStatus, failedReads;
  late bool malformedRead;
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    writeStatus = 200;
    failedReads = 0;
    malformedRead = false;
    requests = [];
    final service = Esp32Service(
      readRetryDelay: Duration.zero,
      client: MockClient((request) async {
        requests.add(request.method);
        if (request.method == 'PUT') {
          final id = request.url.path.split('/')[3];
          final device = (board['devices'] as List).firstWhere(
            (d) => d['id'] == id,
          );
          final on = jsonDecode(request.body)['isOn'] as bool;
          device['isOn'] = on;
          device['watts'] = on ? device['ratedWatts'] : 0;
          board['storageHealthy'] = writeStatus != 503;
          return http.Response('OK', writeStatus);
        }
        if (failedReads > 0) {
          failedReads--;
          throw http.ClientException('read connection interrupted');
        }
        return http.Response(
          malformedRead ? 'not JSON' : jsonEncode(board),
          200,
        );
      }),
    );
    home = HomeController(storage: MemoryStorage(), gateway: service);
    await home.initialize(startTimer: false);
    board = {
      'devices': home.appliances.map((d) => d.toJson()).toList(),
      'rooms': home.rooms.map((r) => r.toJson()).toList(),
      'history': [],
      'schedules': [],
      'storageHealthy': true,
    };
    await home.updateSettings(AppSettings(demoMode: false));
    requests.clear();
  });
  tearDown(() {
    home.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  test('text acknowledgment plus fresh state confirms ON and OFF', () async {
    expect(await home.setPower('bedroom-light', true), true);
    expect(home.device('bedroom-light')!.isOn, true);
    expect(await home.setPower('bedroom-light', false), true);
    expect(home.device('bedroom-light')!.isOn, false);
    expect(home.connected, true);
    expect(home.error, isNull);
    expect(requests, ['PUT', 'GET', 'PUT', 'GET']);
  });
  test(
    'transient confirmation read retries without sending the command again',
    () async {
      failedReads = 1;
      expect(await home.setPower('bedroom-light', true), true);
      expect(requests, ['PUT', 'GET', 'GET']);
      expect(home.error, isNull);
    },
  );
  test(
    'bad confirmation never reports success or hides the last confirmed state',
    () async {
      malformedRead = true;
      expect(await home.setPower('bedroom-light', true), false);
      expect(
        board['devices'].firstWhere((d) => d['id'] == 'bedroom-light')['isOn'],
        true,
      );
      expect(home.device('bedroom-light')!.isOn, false);
      expect(home.connected, false);
      expect(home.error, contains('Command sent'));
      expect(home.error, contains('invalid device data'));
      malformedRead = false;
      await home.refresh();
      expect(home.connected, true);
      expect(home.device('bedroom-light')!.isOn, true);
    },
  );
  test(
    'board-side save failure refreshes actual output state and stays explicit',
    () async {
      writeStatus = 503;
      expect(await home.setPower('bedroom-light', true), false);
      expect(home.device('bedroom-light')!.isOn, true);
      expect(home.connected, true);
      expect(home.espStorageHealthy, false);
      expect(home.error, contains('HTTP 503'));
      expect(requests, ['PUT', 'GET']);
    },
  );
}
