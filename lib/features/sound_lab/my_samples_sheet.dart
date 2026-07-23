// The shared "My Samples" browser over [SampleClipStore].
//
// The library is filled from several places — the Voice Lab saves a shaped
// voice, the Sample Extractor adds samples lifted out of modules and packs —
// so browsing it belongs in one reusable sheet rather than re-implemented per
// screen. Preview and delete work everywhere; whether tapping a row PICKS the
// clip is up to the host (the Voice Lab loads it, the Extractor just manages).

import 'dart:typed_data';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/sound_lab/my_instruments_sheet.dart';
import 'package:comet_beat/features/sound_lab/sample_clip_store.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart';
import 'package:comet_beat/shared/music_io/audio_import.dart';
import 'package:comet_beat/shared/widgets/waveform_thumbnail.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Shows the sample library. Now a thin ADAPTER over the one unified Sound
/// Library sheet (restricted to the Samples rubric): the two libraries are one,
/// so a "pick a sample" host opens the same dialog and gets the chosen sample
/// back as a [SampleClip]. Resolves to the picked clip, or null (cancelled, or
/// [pickable] false). [store] is ignored — the unified store is shared backing.
Future<SampleClip?> showMySamplesSheet(
  BuildContext context, {
  SampleClipStore? store,
  bool pickable = true,
  Future<void> Function(SampleClip clip)? onCatalogSampleInsert,
}) async {
  final picked = await showMyInstrumentsSheet(
    context,
    pickable: pickable,
    restrictToCategory: 'Samples',
    onCatalogSampleInsert: onCatalogSampleInsert,
  );
  return picked == null ? null : sampleClipFromSaved(picked);
}

/// Test seam — drive the sheet without tapping through the UI.
abstract class MySamplesTester {
  List<SampleClip> get clips;
  Future<void> deleteAt(int index);
  List<SampleClip> get attributionRequired;

  /// Decode [bytes] (WAV/MP3) and add it to the library under a name derived
  /// from [filename]. Returns false if the bytes aren't readable audio.
  Future<bool> importAudio(Uint8List bytes, String filename);
}

@visibleForTesting
class MySamplesSheet extends StatefulWidget {
  const MySamplesSheet({
    required this.store,
    this.pickable = true,
    super.key,
  });

  final SampleClipStore store;
  final bool pickable;

  @override
  State<MySamplesSheet> createState() => _MySamplesSheetState();
}

class _MySamplesSheetState extends State<MySamplesSheet>
    implements MySamplesTester {
  List<SampleClip> _clips = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.store.load().then((list) {
      if (mounted) {
        setState(() {
          _clips = list;
          _loading = false;
        });
      }
    });
  }

  @override
  List<SampleClip> get clips => _clips;

  @override
  Future<void> deleteAt(int index) async {
    final list = await widget.store.delete(_clips[index].name);
    if (mounted) setState(() => _clips = list);
  }

  @override
  Future<bool> importAudio(Uint8List bytes, String filename) async {
    final imported = importAudioMono(bytes);
    if (imported == null || imported.pcm.isEmpty) return false;
    final name = _uniqueName(_baseName(filename));
    final list = await widget.store.save(
      SampleClip(
        name: name,
        sampleRate: imported.sampleRate,
        pcm: imported.pcm,
        source: 'Imported',
      ),
    );
    if (mounted) setState(() => _clips = list);
    return true;
  }

  /// Filename → a clean sample name (basename, no extension, safe characters).
  String _baseName(String filename) {
    var s = filename;
    final slash = s.lastIndexOf(RegExp(r'[/\\]'));
    if (slash >= 0) s = s.substring(slash + 1);
    final dot = s.lastIndexOf('.');
    if (dot > 0) s = s.substring(0, dot);
    s = s.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim();
    return s.isEmpty ? 'sample' : s;
  }

  /// Disambiguate against existing clips so an import never overwrites one.
  String _uniqueName(String base) {
    final taken = _clips.map((c) => c.name).toSet();
    if (!taken.contains(base)) return base;
    for (var i = 2;; i++) {
      final candidate = '$base $i';
      if (!taken.contains(candidate)) return candidate;
    }
  }

  Future<void> _pickAndImport() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Audio (WAV, MP3)',
            extensions: kAudioImportExtensions,
          ),
        ],
      );
      if (file == null) return;
      final ok = await importAudio(await file.readAsBytes(), file.name);
      if (!ok) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.mySamplesImportFailed)),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.mySamplesImportFailed)),
      );
    }
  }

  @override
  List<SampleClip> get attributionRequired => _needAttribution;

  void _preview(SampleClip clip) {
    if (clip.pcm.isEmpty) return;
    context.read<AudioService>().playWavBytes(
          pcmFloatToWav(clip.pcm, sampleRate: clip.sampleRate),
        );
  }

  /// Clips whose licence obliges crediting the author.
  List<SampleClip> get _needAttribution =>
      _clips.where((c) => c.needsAttribution).toList();

  Future<void> _showCredits() async {
    final l10n = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.mySamplesCredits),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in _needAttribution) ...[
                Text(c.name, style: Theme.of(ctx).textTheme.titleSmall),
                Text(
                  [
                    if (c.source != null) c.source!,
                    if (c.license != null) c.license!,
                    if (c.sourceUrl != null) c.sourceUrl!,
                  ].join(' · '),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.mySamplesClose),
          ),
        ],
      ),
    );
  }

  String _duration(SampleClip clip) {
    if (clip.sampleRate <= 0) return '';
    return '${(clip.pcm.length / clip.sampleRate).toStringAsFixed(2)}s';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.bookmarks_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    l10n.mySamplesTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.file_upload_outlined, size: 18),
                    label: Text(l10n.mySamplesImport),
                    onPressed: _pickAndImport,
                  ),
                  if (_needAttribution.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.copyright, size: 18),
                      label: Text(l10n.mySamplesCredits),
                      onPressed: _showCredits,
                    ),
                  if (_clips.isNotEmpty)
                    Text(
                      '${_clips.length}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            Expanded(
              child: _clips.isEmpty && !_loading
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l10n.mySamplesEmpty,
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: _clips.length,
                      itemBuilder: (ctx, i) {
                        final clip = _clips[i];
                        final detail = [
                          if (clip.source != null) clip.source!,
                          if (clip.license != null) clip.license!,
                          _duration(clip),
                        ].where((s) => s.isNotEmpty).join(' · ');
                        return ListTile(
                          leading: WaveformThumbnail(clip.pcm),
                          title: Text(clip.name),
                          subtitle: detail.isEmpty ? null : Text(detail),
                          onTap: widget.pickable
                              ? () => Navigator.of(context).pop(clip)
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.play_arrow),
                                tooltip: l10n.mySamplesPreview,
                                onPressed: () => _preview(clip),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: l10n.mySamplesDelete,
                                onPressed: () => deleteAt(i),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
