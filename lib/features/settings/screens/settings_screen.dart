// lib/features/settings/screens/settings_screen.dart
//
// Language override (system/EN/DE) and a compact SRI statistics summary.

import 'dart:async';

import 'package:comet_beat/core/audio/transcription/engine_config.dart';
import 'package:comet_beat/core/audio/tts/tts_engine.dart';
import 'package:comet_beat/core/build_info.dart';
import 'package:comet_beat/core/note_naming.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/debug_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/core/services/transcription_config_service.dart';
import 'package:comet_beat/core/services/tts_service.dart';
import 'package:comet_beat/features/games/composition/tab_arranger.dart'
    show TabArranger;
import 'package:comet_beat/features/games/note_reading/note_colors.dart';
import 'package:comet_beat/features/games/note_reading/note_names.dart';
import 'package:comet_beat/features/library/attribution_screen.dart';
import 'package:comet_beat/features/settings/screens/about_screen.dart';
import 'package:comet_beat/features/settings/screens/downloads_screen.dart';
import 'package:comet_beat/features/settings/screens/voice_models_screen.dart';
import 'package:comet_beat/features/settings/screens/voice_picker_sheet.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart' show ScoreFont;
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsService>();
    final sri = context.watch<SriService>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.languageLabel,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Card(
            child: RadioGroup<String>(
              groupValue: settings.locale?.languageCode ?? '',
              onChanged: (code) => settings.setLocale(
                (code == null || code.isEmpty) ? null : Locale(code),
              ),
              child: Column(
                children: [
                  RadioListTile<String>(
                    title: Text(l10n.systemDefault),
                    value: '',
                  ),
                  const RadioListTile<String>(
                    title: Text('English'),
                    value: 'en',
                  ),
                  const RadioListTile<String>(
                    title: Text('Deutsch'),
                    value: 'de',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.instrumentLabel,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.music_note),
              title: Text(voiceLabel(l10n, settings.voiceId)),
              subtitle: Text(l10n.voicePickerTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final picked = await showVoicePicker(
                  context,
                  currentId: settings.voiceId,
                );
                if (picked == null) return;
                await settings.setVoiceId(
                  picked.id,
                  resolvedVoice: picked.resolved,
                );
                if (!context.mounted) return;
                // Preview through the newly-selected global voice.
                final audio = context.read<AudioService>()
                  ..instrument = settings.instrument
                  ..voice = settings.voice;
                unawaited(audio.playMidiNote(67));
              },
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.noteNamingLabel,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Card(
            child: RadioGroup<NoteNaming>(
              groupValue: settings.noteNaming,
              onChanged: (naming) =>
                  settings.setNoteNaming(naming ?? NoteNaming.auto),
              child: Column(
                children: [
                  RadioListTile<NoteNaming>(
                    title: Text(l10n.noteNamingAuto),
                    value: NoteNaming.auto,
                  ),
                  RadioListTile<NoteNaming>(
                    title: Text(l10n.noteNamingGerman),
                    value: NoteNaming.germanH,
                  ),
                  RadioListTile<NoteNaming>(
                    title: Text(l10n.noteNamingEnglish),
                    value: NoteNaming.english,
                  ),
                  RadioListTile<NoteNaming>(
                    title: Text(l10n.noteNamingSolfege),
                    value: NoteNaming.solfege,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: SwitchListTile(
              secondary: Icon(
                settings.soundOn
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
              ),
              title: Text(l10n.soundOnLabel),
              subtitle: Text(l10n.soundOnSubtitle),
              value: settings.soundOn,
              onChanged: (v) {
                settings.setSoundOn(v);
                if (!v) context.read<AudioService>().stop();
              },
            ),
          ),
          Card(
            child: SwitchListTile(
              secondary: Icon(
                settings.narrationOn
                    ? Icons.record_voice_over_rounded
                    : Icons.voice_over_off_rounded,
              ),
              title: Text(l10n.narrationOnLabel),
              subtitle: Text(l10n.narrationOnSubtitle),
              value: settings.narrationOn,
              onChanged: (v) {
                settings.setNarrationOn(v);
                if (!v) {
                  try {
                    context.read<TtsService>().stop();
                  } on ProviderNotFoundException {
                    /* no TtsService in this tree (some tests) */
                  }
                }
              },
            ),
          ),
          const _HdVoiceTile(),
          const _VoiceEngineTile(),
          const _NarrationVoiceTile(),
          const _VoiceModelsTile(),
          const _TranscriptionEngineSection(),
          const SizedBox(height: 20),
          Card(
            child: SwitchListTile(
              title: Text(l10n.showTimerLabel),
              value: settings.showTimer,
              onChanged: settings.setShowTimer,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.notationFontLabel,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.notationFontSubtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final font in ScoreFont.values)
                        ChoiceChip(
                          label: Text(_scoreFontName(l10n, font)),
                          selected: settings.scoreFont == font,
                          onSelected: (_) => settings.setScoreFont(font),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(l10n.colorScaffoldLabel),
                  subtitle: Text(l10n.colorScaffoldSubtitle),
                  value: settings.colorScaffold,
                  onChanged: settings.setColorScaffold,
                ),
                if (settings.colorScaffold)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (final step in Step.values)
                          Column(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: pitchClassColor(step),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                noteNameFor(context, step),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                const Divider(height: 0),
                SwitchListTile(
                  title: Text(l10n.showNoteNamesLabel),
                  subtitle: Text(l10n.showNoteNamesSubtitle),
                  value: settings.showNoteNames,
                  onChanged: settings.setShowNoteNames,
                ),
                const Divider(height: 0),
                SwitchListTile(
                  title: Text(l10n.smartTabFingeringLabel),
                  subtitle: Text(l10n.smartTabFingeringSubtitle),
                  value: settings.smartTabFingering,
                  onChanged: (v) {
                    settings.setSmartTabFingering(v);
                    // Off → drop the loaded model now so it takes effect at once.
                    if (!v) TabArranger.shared = null;
                  },
                ),
                const Divider(height: 0),
                SwitchListTile(
                  title: Text(l10n.authenticSlidesLabel),
                  subtitle: Text(l10n.authenticSlidesSubtitle),
                  value: settings.authenticSlides,
                  // Takes effect on the NEXT import: the choice is baked into
                  // each song's ReplayProfile when the module is read, so a
                  // song already loaded keeps the rules it was opened with.
                  onChanged: settings.setAuthenticSlides,
                ),
              ],
            ),
          ),
          if (context.watch<DebugService>().menuEnabled) ...[
            const SizedBox(height: 20),
            Text(
              l10n.debugSectionTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Card(
              child: SwitchListTile(
                secondary: const Icon(Icons.lock_open),
                title: Text(l10n.debugUnlockLabel),
                value: context.watch<DebugService>().unlockAll,
                onChanged: (v) => context.read<DebugService>().setUnlockAll(v),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(l10n.statsTitle, style: Theme.of(context).textTheme.titleMedium),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.dataset),
                  title: Text(l10n.statsTracked),
                  trailing: Text('${sri.totalTrackedItems}'),
                ),
                ListTile(
                  leading: const Icon(Icons.school),
                  title: Text(l10n.statsLearning),
                  trailing: Text('${sri.learningItemCount}'),
                ),
                ListTile(
                  leading: const Icon(Icons.star, color: Colors.amber),
                  title: Text(l10n.boxMastered),
                  trailing: Text('${sri.masteredItemCount}'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(l10n.aboutTitle, style: Theme.of(context).textTheme.titleMedium),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l10n.appTitle),
              subtitle: Text(l10n.aboutSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
            ),
          ),
          // Attribution for CC-BY (Tier B) content — imported songs + samples
          // credit their sources here, so credit is reachable app-wide, not only
          // from the library browser.
          Card(
            child: ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: Text(l10n.librarySourcesCredits),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => AttributionScreen()),
              ),
            ),
          ),
          // Downloads manager — see cached models/SoundFonts/samples, their size,
          // and free space by removing them.
          Card(
            child: ListTile(
              leading: const Icon(Icons.download_done_outlined),
              title: Text(l10n.downloadsTitle),
              subtitle: Text(l10n.downloadsSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DownloadsScreen()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final info = snapshot.data;
              return Text(
                info == null
                    ? ''
                    : 'CometBeat ${BuildInfo.versionLabel('${info.version}+${info.buildNumber}')}',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              );
            },
          ),
        ],
      ),
    );
  }
}

String _scoreFontName(AppLocalizations l10n, ScoreFont font) => switch (font) {
      ScoreFont.bravura => l10n.scoreFontBravura,
      ScoreFont.petaluma => l10n.scoreFontPetaluma,
      ScoreFont.leland => l10n.scoreFontLeland,
      ScoreFont.leipzig => l10n.scoreFontLeipzig,
    };

/// Which engine synthesizes narration — the user-facing slice of the TtsEngine
/// framework. Auto (default) lets TtsService pick the best usable path per
/// platform; the override lets a user force the Natural (HD) or the device
/// voice. Shown only where a neural voice EXISTS on this build — with only the
/// device voice there's no choice to make, so we don't add a noise tile.
class _VoiceEngineTile extends StatelessWidget {
  const _VoiceEngineTile();

  // Only the user-meaningful engines; the internal ones (onnx-FFI, pure-Dart,
  // wasm, pre-baked) stay behind Auto.
  static const _choices = [
    TtsEngine.auto,
    TtsEngine.crispasrFfi,
    TtsEngine.platform,
  ];

  @override
  Widget build(BuildContext context) {
    TtsService tts;
    try {
      tts = context.watch<TtsService>();
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    if (!tts.hasNeural) return const SizedBox.shrink(); // no real choice
    final l10n = AppLocalizations.of(context)!;
    String label(TtsEngine e) => switch (e) {
          TtsEngine.crispasrFfi => l10n.ttsEngineNatural,
          TtsEngine.platform => l10n.ttsEnginePlatform,
          _ => l10n.ttsEngineAuto,
        };
    final current = _choices.contains(tts.preferredEngine)
        ? tts.preferredEngine
        : TtsEngine.auto;
    return ListTile(
      leading: const Icon(Icons.record_voice_over_outlined),
      title: Text(l10n.ttsEngineTitle),
      trailing: DropdownButton<TtsEngine>(
        value: current,
        underline: const SizedBox.shrink(),
        onChanged: (e) {
          if (e != null) tts.preferredEngine = e;
        },
        items: [
          for (final e in _choices)
            DropdownMenuItem(value: e, child: Text(label(e))),
        ],
      ),
    );
  }
}

/// Picks which on-device OS voice narrates — Apple/Android/browser voices via
/// `flutter_tts.getVoices`. Lets a user choose a better/enhanced installed voice
/// with NO download. Shown only when the OS offers ≥2 voices for the current
/// language (with 0–1 there's nothing to pick, so no noise tile).
class _NarrationVoiceTile extends StatefulWidget {
  const _NarrationVoiceTile();

  @override
  State<_NarrationVoiceTile> createState() => _NarrationVoiceTileState();
}

class _NarrationVoiceTileState extends State<_NarrationVoiceTile> {
  List<TtsVoiceOption> _voices = const [];
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) _load();
  }

  Future<void> _load() async {
    _loaded = true;
    TtsService? tts;
    try {
      tts = context.read<TtsService>();
    } on ProviderNotFoundException {
      return;
    }
    final lang = TtsService.voiceTag(Localizations.localeOf(context));
    final voices = await tts.narrationVoices(lang);
    if (mounted) setState(() => _voices = voices);
  }

  @override
  Widget build(BuildContext context) {
    if (_voices.length < 2) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final tts = context.watch<TtsService>();
    final lang = TtsService.voiceTag(Localizations.localeOf(context));
    final current = tts.chosenNarrationVoice(lang);
    // Guard: the persisted choice may not be in the OS's current list.
    final value = _voices.contains(current) ? current : null;
    return ListTile(
      leading: const Icon(Icons.settings_voice_outlined),
      title: Text(l10n.ttsVoicePickerTitle),
      subtitle: Text(l10n.ttsVoicePickerSubtitle),
      trailing: DropdownButton<TtsVoiceOption?>(
        value: value,
        underline: const SizedBox.shrink(),
        onChanged: (v) => tts.chooseNarrationVoice(lang, v),
        items: [
          DropdownMenuItem<TtsVoiceOption?>(
            child: Text(l10n.ttsVoicePickerDefault),
          ),
          for (final v in _voices)
            DropdownMenuItem<TtsVoiceOption?>(
              value: v,
              child: Text(_voiceLabel(v)),
            ),
        ],
      ),
    );
  }

  /// A compact label: the voice name, plus its region if it adds info.
  String _voiceLabel(TtsVoiceOption v) {
    final region = v.locale.split(RegExp('[-_]')).skip(1).join('-');
    return region.isEmpty ? v.name : '${v.name} ($region)';
  }
}

/// The optional HD (neural, CrispASR/Kokoro) narration voice. Shown only where
/// the native lib is present (so it's invisible until libcrispasr is bundled for
/// the platform). Offers a one-tap opt-in download of the ~135 MB model; once
/// cached, narration automatically upgrades to the natural voice.
enum _HdState { checking, hidden, notDownloaded, downloading, ready, failed }

/// Opens the [VoiceModelsScreen] — the download/remove manager for the vetted
/// CC0 HD voices (the unified TtsModelManager cache; native files + web IDB).
class _VoiceModelsTile extends StatelessWidget {
  const _VoiceModelsTile();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.download_for_offline_outlined),
          title: Text(l10n.voiceModelsTitle),
          subtitle: Text(l10n.voiceModelsSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const VoiceModelsScreen()),
          ),
        ),
      ),
    );
  }
}

class _HdVoiceTile extends StatefulWidget {
  const _HdVoiceTile();

  @override
  State<_HdVoiceTile> createState() => _HdVoiceTileState();
}

class _HdVoiceTileState extends State<_HdVoiceTile> {
  _HdState _state = _HdState.checking;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    // Optional: no-op (hidden) if TtsService isn't in the tree (e.g. some tests).
    TtsService? tts;
    try {
      tts = context.read<TtsService>();
    } on ProviderNotFoundException {
      tts = null;
    }
    if (tts == null || !tts.hasNeural || !await tts.neuralSupported()) {
      if (mounted) setState(() => _state = _HdState.hidden);
      return;
    }
    final ready = await tts.neuralReady();
    if (mounted) {
      setState(() => _state = ready ? _HdState.ready : _HdState.notDownloaded);
    }
  }

  Future<void> _download() async {
    final tts = context.read<TtsService>();
    final locale = Localizations.localeOf(context);
    setState(() => _state = _HdState.downloading);
    final ok = await tts.downloadNeuralVoice(locale);
    if (mounted) {
      setState(() => _state = ok ? _HdState.ready : _HdState.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _HdState.checking || _state == _HdState.hidden) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final Widget trailing = switch (_state) {
      _HdState.ready =>
        Icon(Icons.check_circle, color: theme.colorScheme.primary),
      _HdState.downloading => const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      _ => FilledButton.tonal(
          onPressed: _download,
          child: Text(l10n.ttsHdVoiceDownload),
        ),
    };

    final String subtitle = switch (_state) {
      _HdState.ready => l10n.ttsHdVoiceReady,
      _HdState.downloading => l10n.ttsHdVoiceDownloading,
      _HdState.failed => l10n.ttsHdVoiceFailed,
      _ => l10n.ttsHdVoiceSubtitle,
    };

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.graphic_eq_rounded),
          title: Text(l10n.ttsHdVoiceTitle),
          subtitle: Text(subtitle),
          trailing: trailing,
        ),
      ),
    );
  }
}

/// Backend + model-quality picker for the transcription pipeline. The quality
/// preset drives model size/quant; the advanced expander lets a user pin a
/// backend per step (falls back to on-device when a neural backend isn't
/// present). Dart-only steps (rhythm/drums/notation) aren't shown — they never
/// go neural.
class _TranscriptionEngineSection extends StatelessWidget {
  const _TranscriptionEngineSection();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // No-op when the config service isn't in scope (e.g. a widget test that
    // pumps SettingsScreen without it) — mirrors the HD-voice tile.
    final TranscriptionConfigService svc;
    try {
      svc = context.watch<TranscriptionConfigService>();
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    final cfg = svc.config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(
          l10n.transcriptionEngineTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.transcriptionEngineIntro,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.transcriptionQualityLabel,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final q in ModelQuality.values)
                      ChoiceChip(
                        label: Text(_qualityName(l10n, q)),
                        selected: cfg.quality == q,
                        onSelected: (_) => svc.setQuality(q),
                      ),
                  ],
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    l10n.transcriptionAdvancedLabel,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  children: [
                    // Each list is the set of backends actually wired for that
                    // step. FFI runtimes (onnxFfi/crispasr) are filtered out on
                    // web by [_stepPicker]; picking one that isn't present at
                    // runtime degrades gracefully to on-device (see
                    // TranscriptionEngineConfig.resolve).
                    _stepPicker(
                      context,
                      svc,
                      l10n.transcriptionStepF0,
                      TranscriptionStep.f0,
                      const [
                        Backend.auto,
                        Backend.pureDart,
                        Backend.onnx,
                        Backend.onnxFfi,
                        Backend.crispasr,
                      ],
                    ),
                    _stepPicker(
                      context,
                      svc,
                      l10n.transcriptionStepPoly,
                      TranscriptionStep.polyphonic,
                      const [
                        Backend.auto,
                        Backend.onnx,
                        Backend.onnxFfi,
                        Backend.crispasr,
                      ],
                    ),
                    _stepPicker(
                      context,
                      svc,
                      l10n.transcriptionStepSep,
                      TranscriptionStep.separation,
                      // No native-ORT separator; UMX (onnx) + ggml htdemucs.
                      const [Backend.auto, Backend.onnx, Backend.crispasr],
                    ),
                    _stepPicker(
                      context,
                      svc,
                      l10n.transcriptionStepChords,
                      TranscriptionStep.chords,
                      // No ggml chord model; chroma (pureDart) + BTC onnx/ffi.
                      const [
                        Backend.auto,
                        Backend.pureDart,
                        Backend.onnx,
                        Backend.onnxFfi,
                      ],
                    ),
                    _stepPicker(
                      context,
                      svc,
                      l10n.transcriptionStepTab,
                      TranscriptionStep.tab,
                      // TabCNN: pure-Dart onnx or native ggml. No pureDart
                      // heuristic (audio→tab needs a model) and no native-ORT.
                      const [Backend.auto, Backend.onnx, Backend.crispasr],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.transcriptionF0ViterbiLabel),
                      subtitle: Text(l10n.transcriptionF0ViterbiSubtitle),
                      value: cfg.f0Viterbi,
                      onChanged: svc.setF0Viterbi,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _stepPicker(
    BuildContext context,
    TranscriptionConfigService svc,
    String label,
    TranscriptionStep step,
    List<Backend> offered,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final cur = svc.config.backendFor(step);
    // The FFI runtimes can't run on web — don't offer them there.
    final shown =
        kIsWeb ? offered.where((b) => !backendNeedsFfi(b)).toList() : offered;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Wrap(
            spacing: 8,
            children: [
              for (final b in shown)
                ChoiceChip(
                  label: Text(_backendName(l10n, b)),
                  selected: cur == b,
                  onSelected: (_) => svc.setBackend(step, b),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String _qualityName(AppLocalizations l10n, ModelQuality q) => switch (q) {
      ModelQuality.fast => l10n.transcriptionQualityFast,
      ModelQuality.balanced => l10n.transcriptionQualityBalanced,
      ModelQuality.accurate => l10n.transcriptionQualityAccurate,
    };

String _backendName(AppLocalizations l10n, Backend b) => switch (b) {
      Backend.auto => l10n.transcriptionBackendAuto,
      Backend.pureDart => l10n.transcriptionBackendDart,
      Backend.onnx => l10n.transcriptionBackendOnnx,
      Backend.onnxFfi => l10n.transcriptionBackendOnnxFfi,
      Backend.crispasr => l10n.transcriptionBackendCrispasr,
    };
