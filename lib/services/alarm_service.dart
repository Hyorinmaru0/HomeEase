import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

abstract class AlarmOutput {
  Future<void> start({bool vibrate = false});
  Future<void> stop();
  Future<void> dispose();
}

class AlarmService implements AlarmOutput {
  AudioPlayer? _player;
  Future<void> _queue = Future.value();
  bool _disposed = false;
  @override
  Future<void> start({bool vibrate = false}) =>
      _queue = _queue.catchError((_) {}).then((_) async {
        if (_disposed) return;
        _player ??= AudioPlayer();
        await _player!.setAudioContext(
          AudioContextConfig(respectSilence: true, stayAwake: false).build(),
        );
        await _player!.setReleaseMode(ReleaseMode.loop);
        await _player!.play(AssetSource('audio/safety_alarm.wav'), volume: .65);
        if (vibrate) await HapticFeedback.heavyImpact();
      });
  @override
  Future<void> stop() => _queue = _queue.catchError((_) {}).then((_) async {
    await _player?.stop();
  });
  @override
  Future<void> dispose() async {
    _disposed = true;
    try {
      await stop();
      await _player?.dispose();
    } catch (_) {}
  }
}
