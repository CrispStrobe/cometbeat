// lib/shared/widgets/sound_toggle.dart
//
// The master sound on/off control, wired to [SettingsService.soundOn] (which
// gates all synthesized playback via AudioService — the microphone is
// unaffected). Drop it into any AppBar `actions:` or toolbar; it appears
// app-wide as screens adopt the shared game app bar.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SoundToggle extends StatelessWidget {
  const SoundToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final l10n = AppLocalizations.of(context)!;
    final on = settings.soundOn;
    return IconButton(
      icon: Icon(on ? Icons.volume_up_rounded : Icons.volume_off_rounded),
      tooltip: on ? l10n.muteTooltip : l10n.unmuteTooltip,
      onPressed: () {
        settings.setSoundOn(!on);
        // Silence whatever is ringing right now when muting.
        if (on) context.read<AudioService>().stop();
      },
    );
  }
}
