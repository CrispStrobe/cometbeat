// "Browse catalog" — a capable browser over OUR curated, rights-verified catalog
// (music-db → published on Hugging Face, read via CometbeatCatalogSource). Every
// kind in one modal, with:
//   • search (name / attribution)
//   • filters — by kind (SoundFonts / Instruments / Samples / Modules) and by
//     licence bucket (CC0·PD / CC-BY / MIT)
//   • paths to the editors — each item routes to the right consumer:
//       SoundFont → the preset picker (audition) → live keyboard
//       Sample (WAV) → installed into your library (PCM, no path_provider) → play
//       Module     → opened in the Tracker
//       SFZ instrument → its source page (full sample-set install is a follow-up)
//
// Licence + attribution are shown per item and repeated in the detail sheet, so
// nothing is used without its credit visible.

import 'dart:async';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerInstrument;
import 'package:comet_beat/core/audio/tracker_song.dart' show TrackerSong;
import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:comet_beat/features/games/composition/advanced_tracker_screen.dart';
import 'package:comet_beat/features/library/content_source.dart';
import 'package:comet_beat/features/library/instrument_installer.dart';
import 'package:comet_beat/features/library/soundfont_sheet.dart';
import 'package:comet_beat/features/library/source_registry.dart';
import 'package:comet_beat/features/library/sources/cometbeat_catalog_source.dart';
import 'package:comet_beat/features/sound_lab/instrument_library_store.dart';
import 'package:comet_beat/features/sound_lab/instrument_play_screen.dart';
import 'package:comet_beat/features/sound_lab/sample_clip_store.dart';
import 'package:comet_beat/features/sound_lab/soundfont_persist.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/music_io/audio_import.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// The kind filter (matches LibraryItem.collection = the catalog `kind`).
enum _Kind { all, soundfont, instrument, sample, module }

/// A coarse licence bucket for filtering (the raw string stays visible).
enum _Lic { all, cc0, ccby, mit }

_Lic _licBucket(String raw) {
  final l = raw.toLowerCase();
  if (l.contains('cc0') || l.contains('public domain')) return _Lic.cc0;
  if (l.contains('mit')) return _Lic.mit;
  if (l.contains('cc') && l.contains('by')) return _Lic.ccby;
  return _Lic.all; // unbucketed → only shows under "all"
}

/// Opens the capable catalog browser. [source] and [store] are injectable for
/// tests; [store] receives installed samples (defaults to a fresh store).
/// [initialKind] pre-selects a kind chip (e.g. 'sample' when opened from the
/// Samples rubric) — one of soundfont/instrument/sample/module, else all.
Future<bool?> showCatalogBrowseSheet(
  BuildContext context, {
  ContentSource? source,
  InstrumentLibraryStore? store,
  String? initialKind,
  Future<void> Function(SampleClip clip)? onInsertSample,
  bool preferSampleInsert = false,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => CatalogBrowseSheet(
      source: source ?? CometbeatCatalogSource.all(defaultHttpGet),
      store: store ?? InstrumentLibraryStore(),
      initialKind: initialKind,
      onInsertSample: onInsertSample,
      preferSampleInsert: preferSampleInsert,
    ),
  );
}

@visibleForTesting
class CatalogBrowseSheet extends StatefulWidget {
  const CatalogBrowseSheet({
    required this.source,
    required this.store,
    this.initialKind,
    this.onInsertSample,
    this.preferSampleInsert = false,
    super.key,
  });

  final ContentSource source;
  final InstrumentLibraryStore store;
  final String? initialKind;
  final Future<void> Function(SampleClip clip)? onInsertSample;
  final bool preferSampleInsert;

  @override
  State<CatalogBrowseSheet> createState() => _CatalogBrowseSheetState();
}

class _CatalogBrowseSheetState extends State<CatalogBrowseSheet> {
  final _search = TextEditingController();
  List<LibraryItem> _all = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  _Kind _kind = _Kind.all;
  _Lic _lic = _Lic.all;

  @override
  void initState() {
    super.initState();
    final k = widget.initialKind;
    if (k != null) {
      _kind = _Kind.values.firstWhere(
        (v) => v.name == k,
        orElse: () => _Kind.all,
      );
    }
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.source.browse(limit: 1000);
      if (mounted) {
        setState(() {
          _all = items;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context)!.libraryLoadFailed;
          _loading = false;
        });
      }
    }
  }

  /// Client-side view: kind chip + licence chip + search text.
  List<LibraryItem> get _visible {
    final q = _search.text.trim().toLowerCase();
    return [
      for (final i in _all)
        if ((_kind == _Kind.all || i.collection == _kind.name) &&
            (_lic == _Lic.all || _licBucket(i.declaredLicense) == _lic) &&
            (q.isEmpty ||
                i.title.toLowerCase().contains(q) ||
                i.composer.toLowerCase().contains(q)))
          i,
    ];
  }

  Future<Uint8List?> _download(LibraryItem item) async {
    setState(() => _busy = true);
    try {
      final bytes = await widget.source.fetch(item);
      if (mounted) setState(() => _busy = false);
      return bytes;
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = AppLocalizations.of(context)!.libraryImportFailed;
        });
      }
      return null;
    }
  }

  // ── editor paths ──────────────────────────────────────────────────────────

  /// SoundFont → audition + pick a preset, then offer the live keyboard.
  Future<void> _openSoundFont(LibraryItem item) async {
    final bytes = await _download(item);
    if (bytes == null || !mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final inst = await showSoundFontSheet(
      context,
      pick: () async => (bytes: bytes, name: item.title),
      // Confirming a preset also saves it as a reusable library voice (a tiny
      // soundfont_ref; the font is cached once). Native only — a no-op on web.
      onPresetChosen: (fontBytes, preset) async {
        final saved = await persistSoundFontPreset(
          fontBytes: fontBytes,
          bank: preset.bank,
          program: preset.program,
          presetName: preset.name,
          saveName: item.title,
          store: widget.store,
        );
        if (saved != null && mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(l10n.catalogAdded)));
        }
      },
    );
    if (inst != null && mounted) _play(inst, item.title);
  }

  /// SFZ instrument → batch-download the whole sample tree into the on-device
  /// cache (kept; the Downloads manager surfaces + frees it) and play it. Shows
  /// live download progress. FLAC-sampled instruments cache but can't play yet.
  Future<void> _installInstrument(LibraryItem item) async {
    final l10n = AppLocalizations.of(context)!;
    final progress = ValueNotifier<double>(0);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Text(l10n.catalogInstalling),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, v, __) =>
                LinearProgressIndicator(value: v == 0 ? null : v),
          ),
        ),
      ),
    );
    InstalledInstrument? installed;
    try {
      installed = await installSfzInstrument(
        sfzUrl: item.downloadUrl.toString(),
        name: item.title,
        http: defaultHttpGet,
        onProgress: (done, total) =>
            progress.value = total == 0 ? 0 : done / total,
      );
    } catch (_) {
      installed = null;
    }
    if (!mounted) return;
    Navigator.of(context).pop(); // close the progress dialog
    progress.dispose();
    if (installed != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.catalogInstrumentInstalled(installed.fileCount)),
        ),
      );
      _play(installed.instrument, item.title);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.catalogInstallUnplayable)),
      );
    }
  }

  /// Module → decode + open the (advanced) Tracker on it.
  Future<void> _openModule(LibraryItem item) async {
    final bytes = await _download(item);
    if (bytes == null || !mounted) return;
    final TrackerSong song;
    try {
      song = songFromModuleBytes(bytes);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.libraryImportFailed),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(); // close the browser first
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AdvancedTrackerScreen(initialSong: song),
        ),
      ),
    );
  }

  Future<SampleClip?> _sampleClipFromCatalog(LibraryItem item) async {
    final bytes = await _download(item);
    if (bytes == null || !mounted) return null;
    final l10n = AppLocalizations.of(context)!;
    final imported = importAudioMono(bytes);
    if (imported == null || imported.pcm.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.libraryImportFailed)));
      return null;
    }
    return SampleClip(
      name: item.title,
      sampleRate: imported.sampleRate,
      pcm: imported.pcm,
      source: item.sourceName,
      license: item.declaredLicense,
      sourceUrl: item.sourceUrl,
    );
  }

  /// WAV sample → decode to mono PCM + persist into the library (no file needed).
  Future<void> _installSample(LibraryItem item) async {
    final clip = await _sampleClipFromCatalog(item);
    if (clip == null || !mounted) return;
    final l10n = AppLocalizations.of(context)!;
    await widget.store.save(
      SavedInstrument.fromSampleClip(clip),
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.catalogAdded)));
    }
  }

  Future<void> _insertSample(LibraryItem item) async {
    final clip = await _sampleClipFromCatalog(item);
    if (clip == null || !mounted) return;
    await widget.onInsertSample?.call(clip);
    if (mounted) Navigator.of(context).pop(true);
  }

  void _play(TrackerInstrument inst, String name) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InstrumentPlayScreen(instrument: inst, name: name),
      ),
    );
  }

  Future<void> _openSource(LibraryItem item) async {
    final url = item.sourceUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Per-item detail + actions — the "paths to editors".
  void _openDetail(LibraryItem item) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                item.title,
                style: Theme.of(sheetCtx).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                [
                  item.format.toUpperCase(),
                  item.declaredLicense,
                  if (item.composer.isNotEmpty) item.composer,
                ].where((s) => s.isNotEmpty).join(' · '),
                style: Theme.of(sheetCtx).textTheme.bodySmall,
              ),
            ),
            for (final action in _actionsFor(item, l10n))
              ListTile(
                dense: true,
                leading: Icon(action.icon),
                title: Text(action.label),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  action.run();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  List<({IconData icon, String label, VoidCallback run})> _actionsFor(
    LibraryItem item,
    AppLocalizations l10n,
  ) {
    if (item.collection == 'sample') {
      final add = (
        icon: Icons.library_add,
        label: l10n.catalogAddToLibrary,
        run: () => _installSample(item),
      );
      final insert = widget.onInsertSample == null
          ? null
          : (
              icon: Icons.playlist_add,
              label: l10n.catalogInsertInAudioTrack,
              run: () => _insertSample(item),
            );
      return [
        if (widget.preferSampleInsert && insert != null) insert,
        add,
        if (!widget.preferSampleInsert && insert != null) insert,
        if (item.sourceUrl != null && item.sourceUrl!.isNotEmpty)
          (
            icon: Icons.open_in_new,
            label: l10n.catalogOpenSource,
            run: () => _openSource(item),
          ),
      ];
    }
    return [
      switch (item.collection) {
        'soundfont' => (
            icon: Icons.piano,
            label: l10n.catalogAudition,
            run: () => _openSoundFont(item),
          ),
        'module' => (
            icon: Icons.grid_on,
            label: l10n.catalogOpenInTracker,
            run: () => _openModule(item),
          ),
        'instrument' when instrumentInstallSupported => (
            icon: Icons.download_for_offline_outlined,
            label: l10n.catalogInstallInstrument,
            run: () => _installInstrument(item),
          ),
        _ => (
            icon: Icons.info_outline,
            label: l10n.catalogNotInstallable,
            run: () {},
          ),
      },
      if (item.sourceUrl != null && item.sourceUrl!.isNotEmpty)
        (
          icon: Icons.open_in_new,
          label: l10n.catalogOpenSource,
          run: () => _openSource(item),
        ),
    ];
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final visible = _visible;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.source.name} · ${widget.source.licenseSummary}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (!_loading)
                  Text(
                    l10n.catalogItemCount(visible.length),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: l10n.librarySearchHint,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            _filters(l10n),
            const SizedBox(height: 4),
            if (_busy) const LinearProgressIndicator(),
            SizedBox(height: 320, child: _list(l10n, visible)),
          ],
        ),
      ),
    );
  }

  Widget _filters(AppLocalizations l10n) {
    Widget kindChip(_Kind k, String label) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(label),
            selected: _kind == k,
            onSelected: (_) => setState(() => _kind = k),
          ),
        );
    Widget licChip(_Lic v, String label) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: FilterChip(
            label: Text(label),
            selected: _lic == v,
            onSelected: (_) => setState(() => _lic = _lic == v ? _Lic.all : v),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              kindChip(_Kind.all, l10n.catalogKindAll),
              kindChip(_Kind.soundfont, l10n.catalogKindSoundFonts),
              kindChip(_Kind.instrument, l10n.catalogKindInstruments),
              kindChip(_Kind.sample, l10n.catalogKindSamples),
              kindChip(_Kind.module, l10n.catalogKindModules),
            ],
          ),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              licChip(_Lic.cc0, 'CC0 · PD'),
              licChip(_Lic.ccby, 'CC-BY'),
              licChip(_Lic.mit, 'MIT'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _list(AppLocalizations l10n, List<LibraryItem> visible) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: Text(l10n.libraryRetry)),
          ],
        ),
      );
    }
    if (visible.isEmpty) return Center(child: Text(l10n.libraryNoResults));
    return ListView.builder(
      itemCount: visible.length,
      itemBuilder: (context, i) {
        final item = visible[i];
        final detail = [
          item.format.toUpperCase(),
          item.declaredLicense,
          if (item.composer.isNotEmpty) item.composer,
        ].where((s) => s.isNotEmpty).join(' · ');
        return ListTile(
          dense: true,
          leading: Icon(_iconFor(item.collection)),
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: _busy ? null : () => _openDetail(item),
        );
      },
    );
  }

  IconData _iconFor(String kind) => switch (kind) {
        'soundfont' => Icons.piano,
        'module' => Icons.grid_on,
        'sample' => Icons.graphic_eq,
        _ => Icons.music_note,
      };
}
