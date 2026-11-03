import 'package:flutter/material.dart';

import '../controllers/home_controller.dart';
import '../controllers/safety_controller.dart';
import '../services/alarm_service.dart';
import '../services/voice_service.dart';
import '../theme/app_theme.dart';
import 'common.dart';

class SmartControls extends StatefulWidget {
  final HomeController controller;
  final AlarmOutput? alarm;
  const SmartControls({super.key, required this.controller, this.alarm});
  @override
  State<SmartControls> createState() => _SmartControlsState();
}

class _SmartControlsState extends State<SmartControls>
    with WidgetsBindingObserver {
  late final SafetyController safety;
  late final VoiceSession voice;
  bool _showActive = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    safety = SafetyController(
      widget.controller,
      widget.alarm ?? AlarmService(),
    );
    voice = VoiceSession(
      DeviceSpeechInput(),
      (command) => executeVoice(command, widget.controller, safety.check),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      voice.cancel();
      safety.suspend();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    voice.dispose();
    safety.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([voice, safety]),
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading('Smart controls'),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      safety.checking ||
                          widget.controller.busy ||
                          voice.executing ||
                          voice.listening
                      ? null
                      : safety.check,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(
                    safety.checking ? 'Checking…' : 'Smart Safety Check',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (widget.controller.settings.demoMode)
                const StatusPill('Demo • Simulated checks'),
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      safety.warning
                          ? Icons.warning_amber_rounded
                          : Icons.fact_check_outlined,
                      color: safety.warning ? AppColors.amber : AppColors.mint,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        safety.message,
                        style: TextStyle(
                          color: safety.warning
                              ? AppColors.amber
                              : AppColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (safety.warning || safety.activeNames.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: safety.dismiss,
                      child: const Text('Dismiss Alarm'),
                    ),
                    FilledButton.tonal(
                      onPressed: safety.checking
                          ? null
                          : () => safety.check(turnOff: true),
                      child: const Text('Turn Off All (except fridge)'),
                    ),
                    TextButton(
                      onPressed: () =>
                          setState(() => _showActive = !_showActive),
                      child: const Text('View Active Devices'),
                    ),
                  ],
                ),
              TextButton(
                onPressed: safety.checking ? null : safety.check,
                child: const Text('Recheck'),
              ),
              if (_showActive)
                ...safety.activeNames.map((name) => Text('• $name — ON')),
              const Text(
                'Safety shutdown excludes the fridge. Use its device switch to turn it off explicitly.',
                style: TextStyle(fontSize: 11, color: AppColors.muted),
              ),
              if (widget.controller.settings.voiceEnabled) ...[
                const Divider(),
                OutlinedButton.icon(
                  onPressed: voice.executing || safety.checking
                      ? null
                      : voice.listening
                      ? voice.cancel
                      : voice.start,
                  icon: Icon(voice.listening ? Icons.stop : Icons.mic_none),
                  label: Text(
                    voice.listening ? 'Cancel listening' : 'Voice command',
                  ),
                ),
                if (voice.recognized.isNotEmpty)
                  Text('Heard: “${voice.recognized}”'),
                Text(
                  voice.message,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
              const Text(
                'Manual check while the app is active. No door or departure detection. Speech may need internet or installed language packs.',
                style: TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
