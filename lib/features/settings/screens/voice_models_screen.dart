// voice_models_screen.dart — manager for the downloadable natural (neural)
// narration voices of BOTH languages: size, licence, download (with progress
// and the concrete error on failure) and remove. State lives in TtsService
// (shared with the narration voice picker); files live in CrispASR's cache
// dir, inside the app container on sandboxed macOS.

import 'package:comet_beat/core/audio/tts/neural_voice_catalog.dart';
import 'package:comet_beat/core/services/tts_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/tts/narration_voice_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class VoiceModelsScreen extends StatefulWidget {
  const VoiceModelsScreen({super.key});

  @override
  State<VoiceModelsScreen> createState() => _VoiceModelsScreenState();
}

class _VoiceModelsScreenState extends State<VoiceModelsScreen> {
  String? _unavailable;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    final tts = context.read<TtsService>();
    final reason = await tts.neuralUnavailableReason();
    await tts.refreshInstalled();
    if (mounted) setState(() => _unavailable = reason);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tts = context.watch<TtsService>();
    // Unique files (the Kokoro backbone is shared) of the installed voices.
    final installedFiles = <String, int>{
      for (final v in kNeuralVoices)
        if (tts.isInstalledCached(v.id))
          for (final f in v.files) f.filename: f.bytes,
    };
    final installedBytes = installedFiles.values.fold<int>(0, (s, b) => s + b);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.voiceModelsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.voiceModelsSubtitle, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            '${l10n.voiceModelsCachedLabel}: '
            '${installedBytes == 0 ? '0 MB' : formatVoiceBytes(installedBytes)}',
            style: theme.textTheme.bodySmall,
          ),
          Text(l10n.ttsVoiceSyntheticNote, style: theme.textTheme.bodySmall),
          if (_unavailable != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.ttsVoiceUnavailable(_unavailable!),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          for (final lang in const ['de', 'en']) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
              child: Text(
                lang == 'de' ? l10n.ttsVoiceLangDe : l10n.ttsVoiceLangEn,
                style: theme.textTheme.titleSmall,
              ),
            ),
            for (final v in neuralVoicesFor(lang)) _card(context, l10n, tts, v),
          ],
        ],
      ),
    );
  }

  Widget _card(
    BuildContext context,
    AppLocalizations l10n,
    TtsService tts,
    NeuralVoice v,
  ) {
    final theme = Theme.of(context);
    final cached = tts.isInstalledCached(v.id);
    final progress = tts.downloadProgress(v.id);
    final error = tts.downloadError(v.id);
    final usable = _unavailable == null && tts.hasNeural;

    final Widget trailing;
    if (progress != null) {
      trailing = SizedBox(
        width: 26,
        height: 26,
        child: CircularProgressIndicator(
          value: progress > 0 ? progress : null,
          strokeWidth: 2.4,
        ),
      );
    } else if (cached) {
      trailing = TextButton.icon(
        onPressed: () => tts.removeVoice(v),
        icon: const Icon(Icons.delete_outline),
        label: Text(l10n.voiceModelsRemove),
      );
    } else {
      trailing = FilledButton.tonal(
        onPressed: usable ? () => tts.downloadVoice(v) : null,
        child: Text(
          '${l10n.voiceModelsDownload} (${formatVoiceBytes(v.totalBytes)})',
        ),
      );
    }

    return Card(
      child: ListTile(
        leading: Icon(
          cached ? Icons.check_circle : Icons.graphic_eq_rounded,
          color: cached ? theme.colorScheme.primary : null,
        ),
        title: Text(v.name + (v.region == null ? '' : ' (${v.region})')),
        subtitle: Text(
          [
            cached ? l10n.voiceModelsDownloaded : l10n.voiceModelsNotDownloaded,
            v.license,
            if (v.isLarge) l10n.ttsVoiceLarge,
            if (error != null) l10n.ttsVoiceDownloadFailed(error),
          ].join(' · '),
          style:
              error == null ? null : TextStyle(color: theme.colorScheme.error),
        ),
        trailing: trailing,
      ),
    );
  }
}
