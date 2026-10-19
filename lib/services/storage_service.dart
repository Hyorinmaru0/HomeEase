import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract class HomeStorage {
  Future<Map<String, dynamic>?> read(String key);
  Future<void> write(String key, Map<String, dynamic> value);
}

class StorageService implements HomeStorage {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  @override
  Future<Map<String, dynamic>?> read(String key) async {
    final raw = await _preferences.getString('homeease.v1.$key');
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  @override
  Future<void> write(String key, Map<String, dynamic> value) =>
      _preferences.setString('homeease.v1.$key', jsonEncode(value));
}
