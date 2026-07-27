// voice_models_screen.dart — the user-facing manager for downloadable HD neural
// voices, driven by TtsModelManager (the unified download+cache layer). Lists
// the vetted CC0 Piper voices, shows which are cached + total size, and lets the
// user pre-download or remove each. Works on native (files under the models dir
// that synthesis reads) and web (IndexedDB) alike — the manager hides the split.

import 'package:comet_beat/core/audio/tts/tts_asset_catalog.dart';
import 'package:comet_beat/core/audio/tts/tts_model_manager.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class VoiceModelsScreen extends StatefulWidget {
  const VoiceModelsScreen({super.key, TtsModelManager? manager})
      : _manager = manager;

  final TtsModelManager? _manager;

  @override
  State<VoiceModelsScreen> createState() => _VoiceModelsScreenState();
}

class _VoiceModelsScreenState extends State<VoiceModelsScreen> {
  late final TtsModelManager _mgr = widget._manager ?? TtsModelManager();
  final _busy = <String>{}; // group ids currently downloading
  Map<String, bool> _cached = {}; // group id → all-assets-cached
  int _totalBytes = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final report = await _mgr.report();
    final total = await _mgr.cachedBytes();
    final byGroup = <String, bool>{};
    for (final g in ttsVoiceGroups()) {
      byGroup[g.id] =
          report.where((s) => s.asset.group == g.id).every((s) => s.cached);
    }
    if (mounted) {
      setState(() {
        _cached = byGroup;
        _totalBytes = total;
      });
    }
  }

  Future<void> _download(TtsVoiceGroup g) async {
    setState(() => _busy.add(g.id));
    await _mgr.ensureGroup(g.id);
    if (mounted) setState(() => _busy.remove(g.id));
    await _refresh();
  }

  Future<void> _remove(TtsVoiceGroup g) async {
    await _mgr.removeGroup(g.id);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final groups = ttsVoiceGroups();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.voiceModelsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.voiceModelsSubtitle,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '${l10n.voiceModelsCachedLabel}: ${_fmtBytes(_totalBytes)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          for (final g in groups) _voiceCard(context, l10n, g),
        ],
      ),
    );
  }

  Widget _voiceCard(
    BuildContext context,
    AppLocalizations l10n,
    TtsVoiceGroup g,
  ) {
    final theme = Theme.of(context);
    final downloading = _busy.contains(g.id);
    final cached = _cached[g.id] ?? false;
    final size = g.approxBytes;

    final Widget trailing;
    if (downloading) {
      trailing = const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.4),
      );
    } else if (cached) {
      trailing = TextButton.icon(
        onPressed: () => _remove(g),
        icon: const Icon(Icons.delete_outline),
        label: Text(l10n.voiceModelsRemove),
      );
    } else {
      trailing = FilledButton.tonal(
        onPressed: () => _download(g),
        child: Text(
          size == null
              ? l10n.voiceModelsDownload
              : '${l10n.voiceModelsDownload} (~${_fmtBytes(size)})',
        ),
      );
    }

    return Card(
      child: ListTile(
        leading: Icon(
          cached ? Icons.check_circle : Icons.graphic_eq_rounded,
          color: cached ? theme.colorScheme.primary : null,
        ),
        title: Text(g.label),
        subtitle: Text(
          '${cached ? l10n.voiceModelsDownloaded : l10n.voiceModelsNotDownloaded}'
          ' · ${g.license}',
        ),
        trailing: trailing,
      ),
    );
  }
}

String _fmtBytes(int bytes) {
  if (bytes <= 0) return '0 MB';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).round()} MB';
}
