import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeease/models/app_settings.dart';
import 'package:homeease/services/storage_service.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

final class MemoryPreferences extends SharedPreferencesAsyncPlatform {
  final Map<String, Object> data = {};
  Completer<void>? pendingWrite;
  @override
  Future<void> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) async {
    if (pendingWrite != null) await pendingWrite!.future;
    data[key] = value;
  }

  @override
  Future<String?> getString(
    String key,
    SharedPreferencesOptions options,
  ) async => data[key] as String?;
  @override
  Future<Set<String>> getKeys(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async => data.keys
      .where((k) => parameters.filter.allowList?.contains(k) ?? true)
      .toSet();
  @override
  Future<void> clear(
    ClearPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async {
    data.removeWhere(
      (k, _) => parameters.filter.allowList?.contains(k) ?? true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MemoryPreferences prefs;
  setUp(() {
    prefs = MemoryPreferences();
    SharedPreferencesAsyncPlatform.instance = prefs;
  });
  test('local logout drains accepted writes, keeps history and blocks stale writes', () async {
    final store = StorageService(namespace: 'test.local-retain');
    prefs.pendingWrite = Completer<void>();
    final write = store.write('live', {
      'history': ['saved'],
    });
    await Future<void>.delayed(Duration.zero);
    final close = store.close();
    final replacement = StorageService(namespace: 'test.local-retain');
    final read = replacement.read('live');
    await store.write('live', {
      'history': ['stale'],
    });
    prefs.pendingWrite!.complete();
    await write;
    await close;
    expect((await read)!['history'], ['saved']);
    await replacement.write('live', {
      'history': ['new'],
    });
    expect((await replacement.read('live'))!['history'], ['new']);
  });
  test('user namespaces isolate data and clearing one leaves other and demo intact', () async {
    final alice = StorageService(namespace: 'test.alice');
    final bob = StorageService(namespace: 'test.bob');
    final demo = StorageService(namespace: 'test.demo');
    await alice.write('settings', {'name': 'Alice'});
    await bob.write('settings', {'name': 'Bob'});
    await demo.write('settings', {'name': 'Demo'});
    expect((await alice.read('settings'))!['name'], 'Alice');
    expect((await bob.read('settings'))!['name'], 'Bob');
    await alice.closeAndClear();
    expect(prefs.data.keys.where((k) => k.startsWith('test.alice.')), isEmpty);
    expect((await bob.read('settings'))!['name'], 'Bob');
    expect((await demo.read('settings'))!['name'], 'Demo');
    await alice.write('live', {'late': true});
    expect(prefs.data.keys.where((k) => k.startsWith('test.alice.')), isEmpty);
  });
  test('logout waits for pending writes and subsequent same-user reads wait for cleanup', () async {
    final store = StorageService(namespace: 'test.race');
    prefs.pendingWrite = Completer<void>();
    final write = store.write('live', {'old': true});
    await Future<void>.delayed(Duration.zero);
    final clear = store.closeAndClear();
    final replacement = StorageService(namespace: 'test.race');
    final read = replacement.read('live');
    prefs.pendingWrite!.complete();
    await write;
    await clear;
    expect(await read, isNull);
    await replacement.write('live', {'new': true});
    expect((await replacement.read('live'))!['new'], true);
  });
  test(
    'legacy migration copies demo only and never assigns unowned live history',
    () async {
      final old = StorageService();
      await old.write('settings', AppSettings(demoMode: false).toJson());
      await old.write('demo', {'marker': 'simulation'});
      await old.write('live', {'marker': 'unowned-private-history'});
      final demo = StorageService(namespace: 'test.migration');
      await demo.migrateGuestDemo();
      expect((await demo.read('settings'))!['demoMode'], true);
      expect((await demo.read('demo'))!['marker'], 'simulation');
      expect(await demo.read('live'), isNull);
      expect((await old.read('live'))!['marker'], 'unowned-private-history');
      expect(
        await StorageService(namespace: 'test.newuser').read('live'),
        isNull,
      );
      await demo.write('demo', {'marker': 'edited'});
      await demo.migrateGuestDemo();
      expect((await demo.read('demo'))!['marker'], 'edited');
    },
  );

  test('new accounts retain only the installation ESP32 address', () async {
    await StorageService().write(
      'settings',
      AppSettings(
        name: 'Old owner',
        esp32Url: 'http://192.168.4.1',
        electricityRate: 99,
        budget: 900,
      ).toJson(),
    );
    final user = StorageService(namespace: 'homeease.user.v2.connection-test');
    await user.prepareUser();
    final settings = (await user.read('settings'))!;
    expect(settings['esp32Url'], 'http://192.168.4.1');
    expect(settings['electricityRate'], 11.50);
    expect(settings['name'], isNot('Old owner'));
    await user.closeAndClear();
    expect(
      (await StorageService(namespace: 'homeease.installation.v2')
          .read('connection'))!['esp32Url'],
      'http://192.168.4.1',
    );
  });
}
