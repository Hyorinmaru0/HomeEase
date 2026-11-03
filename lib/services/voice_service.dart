import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../controllers/home_controller.dart';

class VoiceCommand {
  final String action;
  final String? deviceId;
  final bool? on;
  const VoiceCommand(this.action, {this.deviceId, this.on});
  static VoiceCommand? parse(String speech) {
    var text = speech
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    text = text
        .replaceAll(RegExp(r'\bplease\b'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (RegExp(r'^(check|show)( the)? home status$').hasMatch(text)) {
      return const VoiceCommand('status');
    }
    if (RegExp(r'^(run|start)( a| the)?( smart)? safety check$')
        .hasMatch(text)) {
      return const VoiceCommand('safety');
    }
    if (RegExp(r'^(turn|switch) off (everything|all devices|all appliances)$')
        .hasMatch(text)) {
      return const VoiceCommand('all');
    }
    if (RegExp(r'^(turn|switch) off( the)? all( the)? lights$')
        .hasMatch(text)) {
      return const VoiceCommand('lights');
    }
    const targets = {
      'living room light': 'living-light',
      'living room lights': 'living-light',
      'living room main light': 'living-light',
      'bedroom light': 'bedroom-light',
      'bedroom lights': 'bedroom-light',
      'bedroom main light': 'bedroom-light',
      'mini tv': 'mini-tv',
      'mini television': 'mini-tv',
      'mini fridge': 'mini-fridge',
      'fridge': 'mini-fridge',
      'mini refrigerator': 'mini-fridge',
      'refrigerator': 'mini-fridge',
      'living room ac': 'living-ac',
      'living room air conditioner': 'living-ac',
      'bedroom ac': 'bedroom-ac',
      'bedroom air conditioner': 'bedroom-ac',
      'wall lamp': 'bedroom-wall-lamp',
      'smart wall lamp': 'bedroom-wall-lamp',
      'bedroom wall lamp': 'bedroom-wall-lamp',
    };
    final prefix = RegExp(r'^(?:turn|switch) (on|off)(?: the)? (.+)$')
        .firstMatch(text);
    final suffix = RegExp(r'^(?:turn|switch)(?: the)? (.+) (on|off)$')
        .firstMatch(text);
    final target = prefix?[2] ?? suffix?[1];
    final direction = prefix?[1] ?? suffix?[2];
    if (!targets.containsKey(target)) return null;
    return VoiceCommand(
      'power',
      deviceId: targets[target],
      on: direction == 'on',
    );
  }
}

Future<String> executeVoice(
  VoiceCommand command,
  HomeController home,
  Future<void> Function() safety,
) async {
  if (!home.settings.voiceEnabled) {
    return 'Voice commands are disabled in Settings.';
  }
  if (command.action == 'safety') {
    await safety();
    return 'Safety check opened. See the verified result.';
  }
  if (!await home.freshSupportedState()) {
    return 'Failed: ESP32 offline, busy, or appliance unavailable.';
  }
  if (command.action == 'status') {
    return '${home.settings.demoMode ? "Demo: " : ""}${home.activeCount} of ${home.appliances.length} appliances ON. ${home.appliances.where((d) => d.isOn).map((d) => d.name).join(', ')}';
  }
  final ok = command.action == 'power'
      ? await home.setPower(command.deviceId!, command.on!, source: 'voice')
      : await home.turnOffSupported(
          lightsOnly: command.action == 'lights',
          source: 'voice',
        );
  return ok
      ? '${home.settings.demoMode ? "Demo: " : ""}Command executed and state verified.${command.action == 'all' ? ' Fridge excluded; use its individual command to turn it off.' : ''}'
      : 'Failed: appliance state could not be confirmed.';
}

abstract class SpeechInput {
  Future<bool> initialize(
    void Function(String) error,
    void Function(String) status,
  );
  Future<void> listen(void Function(String, bool) result);
  Future<void> cancel();
}

class DeviceSpeechInput implements SpeechInput {
  final SpeechToText _speech = SpeechToText();
  @override
  Future<bool> initialize(
    void Function(String) error,
    void Function(String) status,
  ) async {
    final available = await _speech.initialize(
      onError: (e) => error(e.errorMsg),
      onStatus: status,
      options: [SpeechToText.androidNoBluetooth],
    );
    _speech.errorListener = (e) => error(e.errorMsg);
    _speech.statusListener = status;
    return available;
  }

  @override
  Future<void> listen(void Function(String, bool) result) => _speech.listen(
    onResult: (r) => result(r.recognizedWords, r.finalResult),
    listenOptions: SpeechListenOptions(
      cancelOnError: true,
      partialResults: true,
      listenMode: ListenMode.confirmation,
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(seconds: 4),
    ),
  );
  @override
  Future<void> cancel() => _speech.cancel();
}

class VoiceSession extends ChangeNotifier {
  final SpeechInput input;
  final Future<String> Function(VoiceCommand) execute;
  bool listening = false, executing = false, _disposed = false;
  String recognized = '', message = 'Tap the microphone and speak one command.';
  int _session = 0;
  Timer? _timeout;
  VoiceSession(this.input, this.execute);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    if (listening || executing || _disposed) return;
    final session = ++_session;
    var submitted = false;
    listening = true;
    recognized = '';
    message = 'Preparing microphone…';
    _notify();
    try {
      final available = await input.initialize(
        (error) {
          if (session != _session) return;
          message = error.contains('permission') || error.contains('allowed')
              ? 'Microphone permission denied. Enable it in Android app settings.'
              : 'Speech recognition failed: $error. Try again.';
          listening = false;
          submitted = true;
          _timeout?.cancel();
          _notify();
        },
        (status) {
          if (session != _session || submitted) return;
          if (status == 'done' || status == 'notListening') {
            listening = false;
            message = 'No final command received. Tap the microphone to retry.';
            _notify();
          }
        },
      );
      if (session != _session || _disposed) {
        await input.cancel();
        return;
      }
      if (!available) {
        listening = false;
        message = 'Speech recognition unavailable or microphone permission denied. Check phone speech service and app permissions.';
        _notify();
        return;
      }
      if (submitted) return;
      message = 'Listening…';
      _notify();
      await input.listen((words, finalResult) async {
        if (session != _session || _disposed || submitted) return;
        recognized = words;
        _notify();
        if (!finalResult) return;
        submitted = true;
        listening = false;
        _timeout?.cancel();
        final command = VoiceCommand.parse(words);
        if (command == null) {
          message = words.trim().isEmpty
              ? 'No speech heard. Try again.'
              : 'Unsupported command. Try “Turn on Mini TV”.';
          _notify();
          return;
        }
        executing = true;
        message = 'Command recognized. Executing…';
        _notify();
        try {
          message = await execute(command);
        } catch (_) {
          message = 'Command failed. Check the connection and retry.';
        } finally {
          executing = false;
          _notify();
        }
      });
      if (!submitted && session == _session) {
        _timeout = Timer(const Duration(seconds: 18), () async {
          if (session != _session || submitted) return;
          await cancel();
          message = 'No final speech result received. Try again.';
          _notify();
        });
      }
    } catch (_) {
      listening = false;
      message = 'Speech recognition unavailable. Check microphone permissions and the phone speech service.';
      _notify();
    }
  }

  Future<void> cancel() async {
    ++_session;
    _timeout?.cancel();
    listening = false;
    message = 'Listening cancelled.';
    _notify();
    try {
      await input.cancel();
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}
