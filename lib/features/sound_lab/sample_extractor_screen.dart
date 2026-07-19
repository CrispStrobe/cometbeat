// The Sample Extractor — open one or many tracker modules (.mod/.xm/.s3m/.it)
// and lift out their individual instrument samples: preview each, export it as
// a WAV, or add it to your "My Samples" library. Reuses the public
// `extractModuleSamples` + the shared audio-export helper + the clip store.

import 'dart:typed_data';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/sound_lab/sample_clip_store.dart';
import 'package:comet_beat/features/sound_lab/sample_extractor.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const _kModuleGroup = XTypeGroup(
  label: 'Modules & sample packs',
  extensions: [
    // Tracker modules…
    'mod', 'xm', 's3m', 'it',
    // …and sample-pack archives (7z via our own pure-Dart reader).
    'zip', '7z', 'tar', 'gz', 'tgz', 'bz2', 'xz',
  ],
);

/// Test seam.
abstract class SampleExtractorTester {
  List<ExtractedSample> get samples;
  List<String> get failedFiles;
  void debugLoad(Uint8List bytes, String name);
  Future<void> addToLibrary(int index);
  int get librarySize;
}

class SampleExtractorScreen extends StatefulWidget {
  const SampleExtractorScreen({super.key});

  @override
  State<SampleExtractorScreen> createState() => _SampleExtractorScreenState();
}

class _SampleExtractorScreenState extends State<SampleExtractorScreen>
    implements SampleExtractorTester {
  final _store = SampleClipStore();
  final List<ExtractedSample> _samples = [];
  final List<String> _failed = [];
  int _librarySize = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _store.load().then((list) {
      if (mounted) setState(() => _librarySize = list.length);
    });
  }

  // ── Tester seam ────────────────────────────────────────────────────────────
  @override
  List<ExtractedSample> get samples => _samples;
  @override
  List<String> get failedFiles => _failed;
  @override
  int get librarySize => _librarySize;

  @override
  void debugLoad(Uint8List bytes, String name) => _ingest(bytes, name);

  @override
  Future<void> addToLibrary(int index) async {
    final list = await _store.save(_samples[index].toClip());
    if (mounted) setState(() => _librarySize = list.length);
  }

  // ── Ingest ─────────────────────────────────────────────────────────────────
  void _ingest(Uint8List bytes, String name) {
    try {
      // Sniff the container: a sample-pack archive, else a tracker module.
      final extracted = looksLikeArchive(bytes)
          ? extractArchiveSamples(bytes, sourceFile: name)
          : extractModuleSamples(bytes, sourceFile: name);
      setState(() => _samples.addAll(extracted));
    } catch (_) {
      setState(() => _failed.add(name));
    }
  }

  Future<void> _pickFiles() async {
    final files = await openFiles(acceptedTypeGroups: const [_kModuleGroup]);
    if (files.isEmpty) return;
    setState(() {
      _samples.clear();
      _failed.clear();
      _busy = true;
    });
    for (final f in files) {
      _ingest(await f.readAsBytes(), _baseName(f.name));
    }
    if (mounted) setState(() => _busy = false);
  }

  static String _baseName(String path) {
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    final file = slash >= 0 ? path.substring(slash + 1) : path;
    final dot = file.lastIndexOf('.');
    return dot > 0 ? file.substring(0, dot) : file;
  }

  // ── Per-sample actions ───────────────────────────────────────────────────
  void _preview(ExtractedSample s) => context.read<AudioService>().playWavBytes(
        pcmFloatToWav(s.pcm, sampleRate: s.sampleRate),
      );

  Future<void> _exportOne(ExtractedSample s) => showAudioExportSheet(
        context,
        pcm: s.pcm,
        baseName: safeSampleFileName(s.displayName),
        sampleRate: s.sampleRate,
      );

  /// Writes every extracted sample as a WAV into a chosen folder.
  Future<void> _exportAllToFolder() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final dir = await getDirectoryPath();
    if (dir == null || !mounted) return;
    setState(() => _busy = true);
    final names = uniqueWavNames([for (final s in _samples) s.displayName]);
    var written = 0;
    try {
      for (var i = 0; i < _samples.length; i++) {
        final s = _samples[i];
        final wav = pcmFloatToWav(s.pcm, sampleRate: s.sampleRate);
        await XFile.fromData(wav, name: names[i]).saveTo('$dir/${names[i]}');
        written++;
      }
    } catch (_) {
      // fall through — report however many made it
    }
    if (!mounted) return;
    setState(() => _busy = false);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(l10n.sampleExtractSavedFolder(written, dir))),
      );
  }

  Future<void> _addOne(int index) async {
    final l10n = AppLocalizations.of(context)!;
    await addToLibrary(index);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.sampleExtractAdded(_samples[index].displayName)),
        ),
      );
  }

  Future<void> _addAll() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    var list = <SampleClip>[];
    for (final s in _samples) {
      list = await _store.save(s.toClip());
    }
    if (!mounted) return;
    setState(() {
      _librarySize = list.length;
      _busy = false;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(l10n.sampleExtractAddedAll(_samples.length))),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.sampleExtractTitle),
        actions: [
          if (_samples.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.drive_folder_upload),
              tooltip: l10n.sampleExtractExportFolder,
              onPressed: _busy ? null : _exportAllToFolder,
            ),
            IconButton(
              icon: const Icon(Icons.library_add),
              tooltip: l10n.sampleExtractAddAll,
              onPressed: _busy ? null : _addAll,
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: Text(l10n.sampleExtractOpen),
                  onPressed: _busy ? null : _pickFiles,
                ),
                const SizedBox(width: 12),
                if (_samples.isNotEmpty)
                  Text(
                    l10n.sampleExtractCount(_samples.length),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const Spacer(),
                Text(
                  l10n.sampleExtractLibrary(_librarySize),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (_failed.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                l10n.sampleExtractFailed(_failed.join(', ')),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: _samples.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l10n.sampleExtractHint,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _samples.length,
                    itemBuilder: (ctx, i) {
                      final s = _samples[i];
                      return ListTile(
                        leading: const Icon(Icons.graphic_eq),
                        title: Text(s.displayName),
                        subtitle: Text(
                          l10n.sampleExtractMeta(
                            s.sourceFile,
                            (s.pcm.length / s.sampleRate).toStringAsFixed(2),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.play_arrow),
                              tooltip: l10n.sampleExtractPreview,
                              onPressed: () => _preview(s),
                            ),
                            IconButton(
                              icon: const Icon(Icons.ios_share),
                              tooltip: l10n.sampleExtractExport,
                              onPressed: () => _exportOne(s),
                            ),
                            IconButton(
                              icon: const Icon(Icons.bookmark_add_outlined),
                              tooltip: l10n.sampleExtractAdd,
                              onPressed: () => _addOne(i),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
