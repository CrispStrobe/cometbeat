// The unified "Sound Library" browser over [InstrumentLibraryStore] — the old
// "My Instruments" + "My Samples" in one place. Lists every saved playable item
// (a shaped Voice Lab voice, a recorded sample, a SoundFont preset, a generated
// FX…), grouped into rubric tabs by [SavedInstrument.category]; auditions one by
// rendering a note; deletes; and can GENERATE a new sfxr sound effect straight
// into the library. Opened for management, or as a picker.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/sfxr.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_instrument_codec.dart';
import 'package:comet_beat/core/audio/tracker_song_module.dart'
    show songFromModuleBytes;
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/games/composition/multipart_to_tracker.dart'
    show multiPartScoreFromTrackerSong;
import 'package:comet_beat/features/library/modarchive_sheet.dart';
import 'package:comet_beat/features/library/soundfont_sheet.dart';
import 'package:comet_beat/features/sound_lab/catalog_browse_sheet.dart';
import 'package:comet_beat/features/sound_lab/instrument_library_store.dart';
import 'package:comet_beat/features/sound_lab/instrument_play_screen.dart';
import 'package:comet_beat/features/sound_lab/sample_clip_store.dart';
import 'package:comet_beat/features/sound_lab/sample_extractor_screen.dart';
import 'package:comet_beat/features/sound_lab/sound_lab_screen.dart';
import 'package:comet_beat/features/sound_lab/voice_lab_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/music/music_picker.dart'
    show decodeMusicFile, showMusicPicker;
import 'package:comet_beat/shared/music/score_router.dart'
    show showScoreDestinations;
import 'package:comet_beat/shared/music_io/audio_export.dart';
import 'package:comet_beat/shared/music_io/audio_import.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show MultiPartScore;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const _kMusicLibraryExtensions = [
  'musicxml',
  'xml',
  'mxl',
  'abc',
  'mei',
  'krn',
  'kern',
  'mid',
  'midi',
  'mscx',
  'mscz',
  'gp',
  'gpx',
  'gabc',
  'ly',
  'lilypond',
];
const _kModuleLibraryExtensions = ['mod', 'xm', 's3m', 'it'];

/// Shows the library. Resolves to the picked [SavedInstrument], or null
/// (cancelled, or opened with [pickable] false).
Future<SavedInstrument?> showMyInstrumentsSheet(
  BuildContext context, {
  InstrumentLibraryStore? store,
  bool pickable = true,
  String? restrictToCategory,
  bool includeBuiltIns = false,
  Future<void> Function(SampleClip clip)? onCatalogSampleInsert,
  bool preferCatalogSampleInsert = false,
  Future<void> Function(SampleClip clip)? onSampleInsert,
  Future<void> Function(MultiPartScore score)? onMusicSelected,
  Future<void> Function(Uint8List bytes)? onModuleSelected,
  Future<void> Function(TrackerInstrument instrument)? onSoundFontSelected,
}) {
  return showModalBottomSheet<SavedInstrument>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => MyInstrumentsSheet(
      store: store ?? InstrumentLibraryStore(),
      pickable: pickable,
      restrictToCategory: restrictToCategory,
      includeBuiltIns: includeBuiltIns,
      onCatalogSampleInsert: onCatalogSampleInsert,
      preferCatalogSampleInsert: preferCatalogSampleInsert,
      onSampleInsert: onSampleInsert,
      onMusicSelected: onMusicSelected,
      onModuleSelected: onModuleSelected,
      onSoundFontSelected: onSoundFontSelected,
    ),
  );
}

/// Renders one note ([midi], default middle C) from [inst] for a preview.
Float64List renderInstrumentNote(TrackerInstrument inst, [int midi = 60]) =>
    inst.renderChannel([TrackerCell(midi: midi)], const TrackerTiming(rows: 4));

/// Test seam — drive the sheet without tapping through the UI.
abstract class MyInstrumentsTester {
  List<SavedInstrument> get instruments;
  Future<void> deleteAt(int index);
}

/// The localized label for a rubric [category].
String _categoryLabel(AppLocalizations l10n, String category) =>
    switch (category) {
      'Samples' => l10n.soundLibraryCatSamples,
      'FX' => l10n.soundLibraryCatFx,
      'SoundFonts' => l10n.soundLibraryCatSoundfonts,
      'Drums' => l10n.soundLibraryCatDrums,
      _ => l10n.soundLibraryCatInstruments,
    };

String _instrumentLabel(String id) {
  final spaced = id.replaceAll(RegExp(r'[_-]+'), ' ');
  return spaced
      .split(' ')
      .where((p) => p.isNotEmpty)
      .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
      .join(' ');
}

@visibleForTesting
class MyInstrumentsSheet extends StatefulWidget {
  const MyInstrumentsSheet({
    required this.store,
    this.pickable = true,
    this.restrictToCategory,
    this.includeBuiltIns = false,
    this.onCatalogSampleInsert,
    this.preferCatalogSampleInsert = false,
    this.onSampleInsert,
    this.onMusicSelected,
    this.onModuleSelected,
    this.onSoundFontSelected,
    super.key,
  });

  final InstrumentLibraryStore store;
  final bool pickable;

  /// When set (e.g. 'Samples'), the sheet is a picker for JUST that rubric — no
  /// tabs, only its items. Used so the old sample-only pickers become thin
  /// adapters over this one dialog.
  final String? restrictToCategory;

  /// When true, the picker includes the built-in [kTrackerInstruments] palette
  /// before saved user/library items. Instrument selectors use this; management
  /// tests/screens keep the saved-only default.
  final bool includeBuiltIns;
  final Future<void> Function(SampleClip clip)? onCatalogSampleInsert;
  final bool preferCatalogSampleInsert;

  /// Adds a saved sample directly to the host timeline. When set, sample rows
  /// expose the same explicit insertion action as catalog sample rows.
  final Future<void> Function(SampleClip clip)? onSampleInsert;
  final Future<void> Function(MultiPartScore score)? onMusicSelected;
  final Future<void> Function(Uint8List bytes)? onModuleSelected;
  final Future<void> Function(TrackerInstrument instrument)?
      onSoundFontSelected;

  @override
  State<MyInstrumentsSheet> createState() => _MyInstrumentsSheetState();
}

class _MyInstrumentsSheetState extends State<MyInstrumentsSheet>
    implements MyInstrumentsTester {
  List<SavedInstrument> _items = const [];
  bool _loading = true;

  /// Selected rubric; null = All.
  String? _category;

  @override
  void initState() {
    super.initState();
    _category = widget.restrictToCategory;
    _reload();
  }

  /// Imports audio into the sound library, or opens notation/modules in their
  /// native editors. Sound Library is the entry point, not an audio-only file
  /// picker.
  Future<void> _import() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Audio, scores, and modules',
            extensions: [
              ...kAudioImportExtensions,
              ..._kMusicLibraryExtensions,
              ..._kModuleLibraryExtensions,
            ],
          ),
        ],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final ext = file.name.split('.').length > 1
          ? file.name.split('.').last.toLowerCase()
          : '';
      if (_kModuleLibraryExtensions.contains(ext)) {
        // Tracker callers need the original module bytes so they can preserve
        // the native pattern data. Score Workshop remains the general fallback.
        final onModuleSelected = widget.onModuleSelected;
        if (onModuleSelected != null) {
          if (!mounted) return;
          final navigator = Navigator.of(context);
          navigator.pop();
          await onModuleSelected(bytes);
          return;
        }
        final song = songFromModuleBytes(bytes);
        final score = multiPartScoreFromTrackerSong(song);
        if (!mounted) return;
        final navigator = Navigator.of(context);
        navigator.pop();
        if (score.parts.isEmpty) return;
        await showScoreDestinations(navigator.context, score);
        return;
      }
      if (_kMusicLibraryExtensions.contains(ext)) {
        final score = decodeMusicFile(file.name, bytes);
        if (!mounted) return;
        final navigator = Navigator.of(context);
        navigator.pop();
        await showScoreDestinations(navigator.context, score);
        return;
      }
      final imported = importAudioMono(bytes);
      if (imported == null || imported.pcm.isEmpty) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.mySamplesImportFailed)),
        );
        return;
      }
      final taken = {for (final s in _items) s.name};
      var name = _cleanName(file.name);
      if (taken.contains(name)) {
        var i = 2;
        while (taken.contains('$name $i')) {
          i++;
        }
        name = '$name $i';
      }
      await widget.store.save(
        SavedInstrument.fromSampleClip(
          SampleClip(
            name: name,
            sampleRate: imported.sampleRate,
            pcm: imported.pcm,
            source: 'Imported',
          ),
        ),
      );
      await _reload();
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.mySamplesImportFailed)),
      );
    }
  }

  /// Filename → a clean sample name (basename, no extension, safe characters).
  String _cleanName(String filename) {
    var s = filename;
    final slash = s.lastIndexOf(RegExp(r'[/\\]'));
    if (slash >= 0) s = s.substring(slash + 1);
    final dot = s.lastIndexOf('.');
    if (dot > 0) s = s.substring(0, dot);
    s = s.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim();
    return s.isEmpty ? 'sample' : s;
  }

  Future<void> _reload() async {
    final list = await widget.store.load();
    if (mounted) {
      setState(() {
        _items = [..._builtInItems(), ...list];
        _loading = false;
      });
    }
  }

  List<SavedInstrument> _builtInItems() {
    if (!widget.includeBuiltIns) return const [];
    if (widget.restrictToCategory != null &&
        widget.restrictToCategory != 'Instruments' &&
        widget.restrictToCategory != 'Drums') {
      return const [];
    }
    final out = <SavedInstrument>[];
    for (final opt in kTrackerInstruments) {
      final inst = opt.build();
      final saved = SavedInstrument(
        name: _instrumentLabel(opt.id),
        json: instrumentToJsonString(inst),
        source: 'Built-in',
      );
      if (widget.restrictToCategory == null ||
          saved.category == widget.restrictToCategory) {
        out.add(saved);
      }
    }
    return out;
  }

  @override
  List<SavedInstrument> get instruments => _items;

  List<SavedInstrument> get _visible => _category == null
      ? _items
      : [
          for (final s in _items)
            if (s.category == _category) s,
        ];

  @override
  Future<void> deleteAt(int index) async {
    // deleteAt indexes the FULL list (test seam); the UI deletes by name.
    if (_items[index].source == 'Built-in') return;
    final list = await widget.store.delete(_items[index].name);
    if (mounted) setState(() => _items = [..._builtInItems(), ...list]);
  }

  Future<void> _deleteByName(String name) async {
    final item = _items.where((s) => s.name == name).firstOrNull;
    if (item?.source == 'Built-in') return;
    final list = await widget.store.delete(name);
    if (mounted) setState(() => _items = [..._builtInItems(), ...list]);
  }

  void _playNote(TrackerInstrument inst, int midi) {
    final pcm = renderInstrumentNote(inst, midi);
    if (pcm.isEmpty) return;
    context.read<AudioService>().playWavBytes(pcmFloatToWav(pcm));
  }

  void _audition(SavedInstrument s) {
    final inst = s.instrument;
    if (inst != null) _playNote(inst, 60); // references need the font — skip
  }

  /// Opens the full-keyboard live-play screen for [s].
  Future<void> _showKeyboard(SavedInstrument s) async {
    final inst = s.instrument;
    if (inst == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InstrumentPlayScreen(instrument: inst, name: s.name),
      ),
    );
  }

  Future<void> _insertSample(SavedInstrument s) async {
    final clip = sampleClipFromSaved(s);
    if (clip == null || widget.onSampleInsert == null) return;
    Navigator.of(context).pop();
    await widget.onSampleInsert!(clip);
  }

  /// The catalog kind a library rubric maps to (null category → all kinds),
  /// or null when the rubric has no catalog counterpart (FX / Drums).
  static String? _catalogKindFor(String? category) => switch (category) {
        null => null, // full library → browse everything
        'Samples' => 'sample',
        'SoundFonts' => 'soundfont',
        'Instruments' => 'instrument',
        _ => 'none', // FX / Drums: no catalog kind → button hidden
      };

  /// Whether the Browse-catalog button shows for the current rubric.
  bool get _canBrowseCatalog =>
      _catalogKindFor(widget.restrictToCategory) != 'none';

  /// Browses OUR curated Hugging Face catalog (SoundFonts / instruments /
  /// samples), pre-filtered to the current rubric; installs land in this store.
  Future<void> _browseCatalog() async {
    final inserted = await showCatalogBrowseSheet(
      context,
      store: widget.store,
      initialKind: _catalogKindFor(widget.restrictToCategory),
      onInsertSample: widget.onCatalogSampleInsert,
      preferSampleInsert: widget.preferCatalogSampleInsert,
    );
    if (inserted == true && mounted) {
      Navigator.of(context).pop();
      return;
    }
    if (mounted) await _reload(); // surface anything installed from the catalog
  }

  Future<void> _browseMusicLibrary() async {
    final score = await showMusicPicker(context);
    if (score == null || !mounted) return;
    Navigator.of(context).pop();
    if (widget.onMusicSelected case final onMusicSelected?) {
      await onMusicSelected(score);
    } else if (mounted) {
      await showScoreDestinations(context, score);
    }
  }

  Future<void> _browseModArchive() async {
    final bytes = await showModArchiveSheet(context);
    if (bytes == null || !mounted) return;
    Navigator.of(context).pop();
    await widget.onModuleSelected?.call(bytes);
  }

  Future<void> _loadSoundFont() async {
    final instrument = await showSoundFontSheet(context);
    if (instrument == null || !mounted) return;
    Navigator.of(context).pop();
    await widget.onSoundFontSelected?.call(instrument);
  }

  /// Opens the Sample Extractor (lift PCM samples out of a tracker module or a
  /// sample-pack archive into "My Samples"); refreshes on return.
  Future<void> _extractSamples() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SampleExtractorScreen()),
    );
    await _reload();
  }

  /// Opens the Sound Lab (design an sfxr sound effect) / Voice Lab (record + shape
  /// a voice); both save into this library, which refreshes on return. These are
  /// the standalone entry points now that the Labs live as tools here + as Audio
  /// Editor modals, rather than as separate top-level Workshop screens.
  Future<void> _openSoundLab() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SoundLabScreen()),
    );
    await _reload();
  }

  Future<void> _openVoiceLab() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const VoiceLabScreen()),
    );
    await _reload();
  }

  /// One row of the "create" menu (icon + label).
  Widget _createRow(IconData icon, String label) => Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 12),
          Text(label),
        ],
      );

  /// Generates a new sfxr sound effect and, on save, adds it to the library.
  Future<void> _generateFx() async {
    final saved = await showModalBottomSheet<SavedInstrument>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _FxGeneratorSheet(store: widget.store),
    );
    if (saved != null) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final present = {for (final s in _items) s.category};
    final tabs = [
      for (final c in kLibraryCategories)
        if (present.contains(c)) c,
    ];
    final visible = _visible;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.62,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
              child: Row(
                children: [
                  const Icon(Icons.library_music_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    l10n.soundLibraryTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  if (_canBrowseCatalog)
                    IconButton(
                      icon: const Icon(Icons.cloud_outlined, size: 20),
                      tooltip: l10n.soundLibraryBrowseCatalog,
                      onPressed: _browseCatalog,
                    ),
                  if (widget.restrictToCategory == null)
                    IconButton(
                      icon: const Icon(Icons.library_music, size: 20),
                      tooltip: l10n.musicPickerTitle,
                      onPressed: _browseMusicLibrary,
                    ),
                  if (widget.restrictToCategory == null &&
                      widget.onModuleSelected != null)
                    IconButton(
                      icon: const Icon(Icons.travel_explore, size: 20),
                      tooltip: l10n.trackerModArchive,
                      onPressed: _browseModArchive,
                    ),
                  if (widget.restrictToCategory == null &&
                      widget.onSoundFontSelected != null)
                    IconButton(
                      icon: const Icon(Icons.piano, size: 20),
                      tooltip: l10n.trackerLoadSoundFont,
                      onPressed: _loadSoundFont,
                    ),
                  if (widget.restrictToCategory == null ||
                      widget.restrictToCategory == 'Samples')
                    IconButton(
                      icon: const Icon(Icons.file_upload_outlined, size: 20),
                      tooltip: l10n.mySamplesImport,
                      onPressed: _import,
                    ),
                  // One "create" menu gathers the sound-making tools: the sfxr FX
                  // generator, the Sound Lab + Voice Lab (which also open as Audio
                  // Editor modals), and the module/pack Sample Extractor.
                  if (widget.restrictToCategory == null)
                    PopupMenuButton<int>(
                      icon: const Icon(Icons.add, size: 22),
                      tooltip: l10n.soundLibraryNewFx,
                      onSelected: (v) {
                        switch (v) {
                          case 0:
                            _generateFx();
                          case 1:
                            _openSoundLab();
                          case 2:
                            _openVoiceLab();
                          case 3:
                            _extractSamples();
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 0,
                          child: _createRow(
                            Icons.auto_awesome,
                            l10n.soundLibraryNewFx,
                          ),
                        ),
                        PopupMenuItem(
                          value: 1,
                          child:
                              _createRow(Icons.graphic_eq, l10n.soundLabTitle),
                        ),
                        PopupMenuItem(
                          value: 2,
                          child: _createRow(
                            Icons.record_voice_over,
                            l10n.voiceLabTitle,
                          ),
                        ),
                        PopupMenuItem(
                          value: 3,
                          child: _createRow(
                            Icons.colorize,
                            l10n.sampleExtractTitle,
                          ),
                        ),
                      ],
                    )
                  else if (widget.restrictToCategory == 'Samples')
                    IconButton(
                      icon: const Icon(Icons.colorize, size: 20),
                      tooltip: l10n.sampleExtractTitle,
                      onPressed: _extractSamples,
                    ),
                ],
              ),
            ),
            if (widget.restrictToCategory == null && tabs.length > 1)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(l10n.soundLibraryAll),
                        selected: _category == null,
                        onSelected: (_) => setState(() => _category = null),
                      ),
                    ),
                    for (final c in tabs)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(_categoryLabel(l10n, c)),
                          selected: _category == c,
                          onSelected: (_) => setState(() => _category = c),
                        ),
                      ),
                  ],
                ),
              ),
            if (_loading) const LinearProgressIndicator(),
            Expanded(
              child: visible.isEmpty && !_loading
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l10n.myInstrumentsEmpty,
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (ctx, i) {
                        final s = visible[i];
                        final subtitle = [
                          if (s.source != null) s.source!,
                          _categoryLabel(l10n, s.category),
                        ].join(' · ');
                        return ListTile(
                          title: Row(
                            children: [
                              Flexible(child: Text(s.name)),
                              if (s.needsAttribution) ...[
                                const SizedBox(width: 6),
                                Tooltip(
                                  message: l10n.soundLibraryAttribution,
                                  child: Icon(
                                    Icons.copyright_outlined,
                                    size: 15,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(subtitle),
                          onTap: widget.pickable
                              ? () => Navigator.of(context).pop(s)
                              : null,
                          leading: IconButton(
                            icon: const Icon(Icons.play_arrow),
                            tooltip: l10n.myInstrumentsAudition,
                            onPressed:
                                s.isReference ? null : () => _audition(s),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.piano),
                                tooltip: l10n.myInstrumentsPlay,
                                onPressed: s.isReference
                                    ? null
                                    : () => _showKeyboard(s),
                              ),
                              if (s.category == 'Samples' &&
                                  widget.onSampleInsert != null)
                                IconButton(
                                  icon: const Icon(Icons.playlist_add),
                                  tooltip: l10n.catalogInsertInAudioTrack,
                                  onPressed: () => _insertSample(s),
                                ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: l10n.myInstrumentsDelete,
                                onPressed: s.source == 'Built-in'
                                    ? null
                                    : () => _deleteByName(s.name),
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

/// A compact sfxr sound-effect generator: pick a preset (which previews it),
/// tweak by re-rolling, name it, and save it into the library as `kind='sfxr'`.
class _FxGeneratorSheet extends StatefulWidget {
  const _FxGeneratorSheet({required this.store});

  final InstrumentLibraryStore store;

  @override
  State<_FxGeneratorSheet> createState() => _FxGeneratorSheetState();
}

class _FxGeneratorSheetState extends State<_FxGeneratorSheet> {
  final _rng = Random();
  final _nameCtrl = TextEditingController();
  String? _preset;
  SfxrParams? _params;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _pick(String preset, {bool keepName = false}) {
    final params = kSfxrPresets[preset]!(_rng);
    setState(() {
      _preset = preset;
      _params = params;
      if (!keepName || _nameCtrl.text.trim().isEmpty) _nameCtrl.text = preset;
    });
    _preview(params);
  }

  void _preview(SfxrParams params) {
    final pcm = renderInstrumentNote(SfxrInstrument('preview', params));
    if (pcm.isEmpty) return;
    context.read<AudioService>().playWavBytes(pcmFloatToWav(pcm));
  }

  Future<void> _save() async {
    final params = _params;
    if (params == null) return;
    final name = _nameCtrl.text.trim().isEmpty
        ? (_preset ?? 'fx')
        : _nameCtrl.text.trim();
    final inst = SfxrInstrument(name, params);
    final saved = SavedInstrument(
      name: name,
      json: instrumentToJsonString(inst),
      source: 'FX',
    );
    await widget.store.save(saved);
    if (mounted) Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.soundLibraryFxTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.soundLibraryFxHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in kSfxrPresets.keys)
                  ChoiceChip(
                    label: Text(preset),
                    selected: _preset == preset,
                    onSelected: (_) => _pick(preset),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.soundLabSaveName,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  icon: const Icon(Icons.casino_outlined),
                  tooltip: l10n.soundLabRandomize,
                  onPressed: _preset == null
                      ? null
                      : () => _pick(_preset!, keepName: true),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.soundLabCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _params == null ? null : _save,
                  child: Text(l10n.soundLabSave),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
