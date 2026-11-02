// narration_voice_picker.dart — ONE voice picker for narration, opened from
// Settings (scope: global) and right where an explanation is read — the
// lesson/tutorial sheet (scope: lesson, a persisted override on top of
// Settings). Lists Automatic, the device voice and the small neural voices of
// the current language with size + licence, downloads a voice in place
// (progress, and the concrete error if it fails), and previews any usable
// voice. Everything goes through TtsService, so the state (download progress,
// installed set, choice) is shared with every other open picker.

import 'package:comet_beat/core/audio/tts/neural_voice_catalog.dart';
import 'package:comet_beat/core/services/tts_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Opens the picker for the current UI language.
Future<void> showNarrationVoicePicker(
  BuildContext context, {
  NarrationScope scope = NarrationScope.global,
}) {
  final tts = context.read<TtsService>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ChangeNotifierProvider<TtsService>.value(
      value: tts,
      child: NarrationVoicePicker(scope: scope),
    ),
  );
}

/// Human label for a stored voice choice.
String narrationVoiceLabel(AppLocalizations l10n, String choice) {
  if (choice == kNarrationVoiceDevice) return l10n.ttsVoiceDevice;
  final v = neuralVoiceById(choice);
  return v?.name ?? l10n.ttsVoiceAuto;
}

/// `31 MB`, `10 MB`, `135 MB`.
String formatVoiceBytes(int bytes) =>
    '${(bytes / (1024 * 1024)).round().clamp(1, 1 << 20)} MB';

class NarrationVoicePicker extends StatefulWidget {
  const NarrationVoicePicker({super.key, this.scope = NarrationScope.global});

  final NarrationScope scope;

  @override
  State<NarrationVoicePicker> createState() => _NarrationVoicePickerState();
}

class _NarrationVoicePickerState extends State<NarrationVoicePicker> {
  String? _unavailable;
  bool _probed = false;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    final tts = context.read<TtsService>();
    final reason = await tts.neuralUnavailableReason();
    await tts.refreshInstalled();
    if (mounted) {
      setState(() {
        _unavailable = reason;
        _probed = true;
      });
    }
  }

  String get _lang => TtsService.voiceTag(Localizations.localeOf(context));

  Future<void> _choose(String? choice) =>
      context.read<TtsService>().setVoiceChoice(
            _lang,
            choice,
            scope: widget.scope,
          );

  Future<void> _download(NeuralVoice v) async {
    final tts = context.read<TtsService>();
    final ok = await tts.downloadVoice(v);
    // Choosing a voice that wasn't downloaded yet: select it once it is.
    if (ok && mounted) await _choose(v.id);
  }

  void _preview(String choice) {
    final l10n = AppLocalizations.of(context)!;
    context.read<TtsService>().preview(
          choice,
          l10n.ttsVoicePreviewText,
          locale: Localizations.localeOf(context),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tts = context.watch<TtsService>();
    final lang = _lang;
    final base = lang.split('-').first;
    final lesson = widget.scope == NarrationScope.lesson;
    final override = tts.lessonVoiceOverride(lang);
    final current = lesson ? override : tts.globalVoiceChoice(lang);
    final neuralOk = _probed && _unavailable == null && tts.hasNeural;

    Widget radio(String? value) => Icon(
          current == value
              ? Icons.radio_button_checked
              : Icons.radio_button_unchecked,
          color: current == value ? theme.colorScheme.primary : null,
        );

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: ListView(
          key: const ValueKey('narration-voice-picker'),
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                lesson ? l10n.ttsVoiceLessonTitle : l10n.ttsVoiceTitle,
                style: theme.textTheme.titleLarge,
              ),
            ),
            if (lesson)
              ListTile(
                key: const ValueKey('voice-follow-settings'),
                leading: radio(null),
                title: Text(l10n.ttsVoiceFollowSettings),
                subtitle: Text(
                  l10n.ttsVoiceFollowSettingsSubtitle(
                    narrationVoiceLabel(l10n, tts.globalVoiceChoice(lang)),
                  ),
                ),
                onTap: () => _choose(null),
              ),
            ListTile(
              key: const ValueKey('voice-auto'),
              leading: radio(kNarrationVoiceAuto),
              title: Text(l10n.ttsVoiceAuto),
              subtitle: Text(l10n.ttsVoiceAutoSubtitle),
              onTap: () => _choose(kNarrationVoiceAuto),
            ),
            ListTile(
              key: const ValueKey('voice-device'),
              leading: radio(kNarrationVoiceDevice),
              title: Text(l10n.ttsVoiceDevice),
              subtitle: Text(l10n.ttsVoiceDeviceSubtitle),
              trailing: IconButton(
                tooltip: l10n.ttsVoicePreview,
                icon: const Icon(Icons.play_circle_outline),
                onPressed: () => _preview(kNarrationVoiceDevice),
              ),
              onTap: () => _choose(kNarrationVoiceDevice),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                l10n.ttsVoiceNaturalHeader,
                style: theme.textTheme.titleSmall,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
              child: Text(
                l10n.ttsVoiceSyntheticNote,
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (_probed && !neuralOk)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  l10n.ttsVoiceUnavailable(
                    _unavailable ?? 'no neural voice engine in this build',
                  ),
                  key: const ValueKey('voice-unavailable'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            for (final v in neuralVoicesFor(base))
              _voiceTile(context, l10n, tts, v, radio(v.id), neuralOk),
          ],
        ),
      ),
    );
  }

  Widget _voiceTile(
    BuildContext context,
    AppLocalizations l10n,
    TtsService tts,
    NeuralVoice v,
    Widget radio,
    bool neuralOk,
  ) {
    final theme = Theme.of(context);
    final installed = tts.isInstalledCached(v.id);
    final progress = tts.downloadProgress(v.id);
    final error = tts.downloadError(v.id);
    final langName = v.lang == 'de' ? l10n.ttsVoiceLangDe : l10n.ttsVoiceLangEn;
    final meta = [
      if (v.region != null) '$langName (${v.region})' else langName,
      formatVoiceBytes(v.totalBytes) +
          (v.isLarge ? ' · ${l10n.ttsVoiceLarge}' : ''),
      v.license,
      if (installed) l10n.voiceModelsDownloaded,
    ].join(' · ');

    final Widget trailing;
    if (progress != null) {
      trailing = SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          value: progress > 0 ? progress : null,
          strokeWidth: 2.6,
        ),
      );
    } else if (installed) {
      trailing = IconButton(
        tooltip: l10n.ttsVoicePreview,
        icon: const Icon(Icons.play_circle_outline),
        onPressed: neuralOk ? () => _preview(v.id) : null,
      );
    } else {
      trailing = IconButton(
        key: ValueKey('voice-download-${v.id}'),
        tooltip: l10n.voiceModelsDownload,
        icon: const Icon(Icons.download_rounded),
        onPressed: neuralOk ? () => _download(v) : null,
      );
    }

    return ListTile(
      key: ValueKey('voice-${v.id}'),
      enabled: neuralOk,
      leading: radio,
      title: Text(v.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(meta),
          if (progress != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(
                value: progress > 0 ? progress : null,
              ),
            ),
          if (error != null)
            Text(
              l10n.ttsVoiceDownloadFailed(error),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
        ],
      ),
      trailing: trailing,
      onTap: !neuralOk || progress != null
          ? null
          : () => installed ? _choose(v.id) : _download(v),
    );
  }
}
