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
import 'package:comet_beat/features/games/composition/multipart_to_tracker.dart'
    show multiPartScoreFromTrackerSong;
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
import 'package:comet_beat/shared/music/music_picker.dart' show decodeMusicFile;
import 'package:comet_beat/shared/music/score_router.dart'
    show openScoreInTracker, showScoreDestinations;
import 'package:comet_beat/shared/music_io/audio_import.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// The kind filter (matches LibraryItem.collection = the catalog `kind`).
enum _Kind { all, soundfont, instrument, sample, module, score }

/// A coarse licence bucket for filtering (the raw string stays visible).
enum _Lic { all, cc0, ccby, mit }

_Lic _licBucket(String raw) {
  final l = raw.toLowerCase();
  if (l.contains('cc0') || l.contains('public domain')) return _Lic.cc0;
  if (l.contains('mit')) return _Lic.mit;
  if (l.contains('cc') && l.contains('by')) return _Lic.ccby;
  return _Lic.all; // unbucketed → only shows under "all"
}

/// The catalog kinds a sound/instrument browser is scoped to. Deliberately
/// EXCLUDES `module` and `score` — a "choose an instrument" surface must not
/// list (or fetch the shards for) songs and tracker modules. Music browsers pass
/// their own {'score','module'} set.
const kSoundLibraryKinds = <String>{'soundfont', 'instrument', 'sample'};

/// Opens the capable catalog browser, scoped to [kinds] (defaults to the
/// sound-library kinds). [kinds] controls BOTH which shards are fetched (so an
/// instrument browse never downloads the large score shard) AND which kind
/// filter chips are shown; a single-kind browse hides the chip row entirely.
/// [source] and [store] are injectable for tests; [store] receives installed
/// samples. [initialKind] pre-selects a chip (must be one of [kinds]).
Future<bool?> showCatalogBrowseSheet(
  BuildContext context, {
  ContentSource? source,
  InstrumentLibraryStore? store,
  String? initialKind,
  Set<String> kinds = kSoundLibraryKinds,
  Future<void> Function(SampleClip clip)? onInsertSample,
  bool preferSampleInsert = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 900),
        child: CatalogBrowseSheet(
          source: source ?? CometbeatCatalogSource(defaultHttpGet, kinds: kinds),
          store: store ?? InstrumentLibraryStore(),
          initialKind: initialKind,
          kinds: kinds,
          onInsertSample: onInsertSample,
          preferSampleInsert: preferSampleInsert,
        ),
      ),
    ),
  );
}

@visibleForTesting
class CatalogBrowseSheet extends StatefulWidget {
  const CatalogBrowseSheet({
    required this.source,
    required this.store,
    this.initialKind,
    this.kinds = kSoundLibraryKinds,
    this.onInsertSample,
    this.preferSampleInsert = false,
    super.key,
  });

  final ContentSource source;
  final InstrumentLibraryStore store;
  final String? initialKind;

  /// The catalog kinds this browser lists; the kind filter chips are limited to
  /// these and the row is hidden when there is only one.
  final Set<String> kinds;
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
        // Scope is authoritative: never show a kind outside this browser's set
        // (e.g. a stray module/score) even if the source over-returns.
        if (widget.kinds.contains(i.collection) &&
            (_kind == _Kind.all || i.collection == _kind.name) &&
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

  Future<void> _openModuleInScore(LibraryItem item) async {
    final bytes = await _download(item);
    if (bytes == null || !mounted) return;
    try {
      final score = multiPartScoreFromTrackerSong(songFromModuleBytes(bytes));
      if (!mounted) return;
      final navigator = Navigator.of(context);
      navigator.pop();
      await showScoreDestinations(navigator.context, score);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.libraryImportFailed),
          ),
        );
      }
    }
  }

  /// Score → decode every supported notation format and open the full editor.
  Future<void> _openScore(LibraryItem item) async {
    final bytes = await _download(item);
    if (bytes == null || !mounted) return;
    try {
      final score = decodeMusicFile('x.${item.format}', bytes);
      if (!mounted) return;
      final navigator = Navigator.of(context);
      navigator.pop();
      await showScoreDestinations(navigator.context, score);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.libraryImportFailed),
          ),
        );
      }
    }
  }

  Future<void> _openScoreInTracker(LibraryItem item) async {
    final bytes = await _download(item);
    if (bytes == null || !mounted) return;
    try {
      final score = decodeMusicFile('x.${item.format}', bytes);
      final navigator = Navigator.of(context);
      navigator.pop();
      openScoreInTracker(navigator.context, score);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.libraryImportFailed),
          ),
        );
      }
    }
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
        'score' => (
            icon: Icons.music_note,
            label: l10n.scoreRouterTitle,
            run: () => _openScore(item),
          ),
        'instrument' when instrumentInstallSupported => (
            icon: Icons.download_for_offline_outlined,
            label: l10n.catalogInstallInstrument,
            run: () => _installInstrument(item),
          ),
        // Instrument install caches a whole sample set on the device, which the
        // web build can't do — say so accurately and make the tile a working
        // fallback that opens the instrument's source page to preview it.
        _ => (
            icon: Icons.public,
            label: l10n.catalogNotInstallable,
            run: () {
              if (item.sourceUrl != null && item.sourceUrl!.isNotEmpty) {
                _openSource(item);
              }
            },
          ),
      },
      if (item.collection == 'module')
        (
          icon: Icons.edit_note,
          label: l10n.trackerOpenWorkshop,
          run: () => _openModuleInScore(item),
        ),
      if (item.collection == 'score')
        (
          icon: Icons.grid_on,
          label: l10n.catalogOpenInTracker,
          run: () => _openScoreInTracker(item),
        ),
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
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1 — title · count · close.
            Row(
              children: [
                const Icon(Icons.cloud_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.source.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (!_loading)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      l10n.catalogItemCount(visible.length),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Row 2 — search + kind & licence filters, all inline (wrapping to a
            // second line only when truly cramped).
            _controls(l10n),
            const SizedBox(height: 8),
            if (_busy) const LinearProgressIndicator(),
            Expanded(child: _list(l10n, visible)),
          ],
        ),
      ),
    );
  }

  /// Search field + the kind/licence filters as compact dropdowns.
  Widget _controls(AppLocalizations l10n) {
    final showKind = widget.kinds.length > 1;
    final kindItems = <DropdownMenuItem<_Kind>>[
      DropdownMenuItem(value: _Kind.all, child: Text(l10n.catalogKindAll)),
      for (final (k, label) in <(_Kind, String)>[
        (_Kind.soundfont, l10n.catalogKindSoundFonts),
        (_Kind.instrument, l10n.catalogKindInstruments),
        (_Kind.sample, l10n.catalogKindSamples),
        (_Kind.module, l10n.catalogKindModules),
        (_Kind.score, l10n.catalogKindSongs),
      ])
        if (widget.kinds.contains(k.name))
          DropdownMenuItem(value: k, child: Text(label)),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 240,
          child: TextField(
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
        ),
        if (showKind)
          DropdownButton<_Kind>(
            key: const ValueKey('kindFilter'),
            value: _kind,
            items: kindItems,
            onChanged: (k) => setState(() => _kind = k ?? _Kind.all),
          ),
        DropdownButton<_Lic>(
          key: const ValueKey('licenceFilter'),
          value: _lic,
          items: [
            DropdownMenuItem(
              value: _Lic.all,
              child: Text(l10n.catalogLicenseAll),
            ),
            const DropdownMenuItem(value: _Lic.cc0, child: Text('CC0 · PD')),
            const DropdownMenuItem(value: _Lic.ccby, child: Text('CC-BY')),
            const DropdownMenuItem(value: _Lic.mit, child: Text('MIT')),
          ],
          onChanged: (v) => setState(() => _lic = v ?? _Lic.all),
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
        'score' => Icons.library_music,
        'sample' => Icons.graphic_eq,
        _ => Icons.music_note,
      };
}
