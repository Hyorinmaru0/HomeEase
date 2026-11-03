import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

abstract class HomeStorage {
  Future<Map<String, dynamic>?> read(String key);
  Future<void> write(String key, Map<String, dynamic> value);
}

class StorageService implements HomeStorage {
  static final Map<String, Future<void>> _clearing = {};
  final String namespace;
  bool _closed = false;
  bool _retainAcceptedWrites = false;
  Future<void> _writes = Future.value();
  StorageService({this.namespace = 'homeease.v1'});
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  @override
  Future<Map<String, dynamic>?> read(String key) async {
    await _clearing[namespace];
    if (_closed) return null;
    final raw = await _preferences.getString('$namespace.$key');
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  @override
  Future<void> write(String key, Map<String, dynamic> value) {
    if (_closed) return Future.value();
    final encoded = jsonEncode(value);
    final clearing = _clearing[namespace];
    final work = _writes.then((_) async {
      await clearing;
      if (!_closed || _retainAcceptedWrites) {
        await _preferences.setString('$namespace.$key', encoded);
        if (namespace.startsWith('homeease.user.v2.') && key == 'settings') {
          await _preferences.setString(
            'homeease.installation.v2.connection',
            jsonEncode({'esp32Url': value['esp32Url']}),
          );
        }
      }
    });
    _writes = work.catchError((Object _) {});
    return work;
  }

  Future<void> closeAndClear() {
    _closed = true;
    final result = _clear();
    _clearing[namespace] = result;
    return result;
  }

  Future<void> close() {
    _retainAcceptedWrites = true;
    _closed = true;
    final result = _writes;
    _clearing[namespace] = result;
    unawaited(
      result.whenComplete(() {
        if (identical(_clearing[namespace], result)) {
          _clearing.remove(namespace);
        }
      }),
    );
    return result;
  }

  Future<void> _clear() async {
    await _writes;
    final keys = await _preferences.getKeys();
    for (final key in keys.where((k) => k.startsWith('$namespace.'))) {
      await _preferences.remove(key);
    }
  }

  Future<void> migrateGuestDemo() async {
    if (await read('migration') != null) return;
    final legacy = StorageService();
    final settings = await legacy.read('settings');
    final demo = await legacy.read('demo');
    if (settings != null) {
      await write('settings', {...settings, 'demoMode': true});
    }
    if (demo != null) await write('demo', demo);
    await write('migration', {'version': 1});
  }

  Future<void> prepareUser() async {
    if (await read('settings') != null) return;
    final installation = await StorageService(
      namespace: 'homeease.installation.v2',
    ).read('connection');
    final legacy = await StorageService().read('settings');
    final address =
        installation?['esp32Url'] as String? ?? legacy?['esp32Url'] as String?;
    await write(
      'settings',
      AppSettings(esp32Url: address ?? 'http://192.168.1.100').toJson(),
    );
  }
}
