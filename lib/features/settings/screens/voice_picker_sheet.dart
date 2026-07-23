// The "Instrument sound" voice picker — a searchable, category-filtered browser
// over the whole sound palette: the sample-free procedural voices the Tracker /
// Sound Library expose (Tonal additive + FM + subtractive, Chiptune sfxr,
// Plucked Karplus) AND your saved "My Library" instruments (which include
// installed catalog samples / soundfont voices). Tap a voice to hear it,
// long-press (or tap the check) to choose it as the app's global playback voice.
// "Browse catalog" installs more from the curated HF catalog into the library.
//
// Returns the chosen voice as a (id, resolved) record: built-in ids resolve
// themselves (main.dart / SettingsService), a library voice carries its
// already-built TrackerInstrument so it plays without a store round-trip.

import 'dart:async';

import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/voice_options.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/sound_lab/catalog_browse_sheet.dart';
import 'package:comet_beat/features/sound_lab/instrument_library_store.dart';
import 'package:comet_beat/features/sound_lab/soundfont_persist.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart'
    show pcmFloatToWav;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// A chosen voice: its persisted [id] and, for library voices, the already-built
/// [resolved] instrument (null for built-ins, which resolve from the id).
typedef VoiceChoice = ({String id, TrackerInstrument? resolved});

/// Opens the voice picker. [currentId] marks the current selection; [store] is
/// injectable for tests.
Future<VoiceChoice?> showVoicePicker(
  BuildContext context, {
  String? currentId,
  InstrumentLibraryStore? store,
}) {
  return showModalBottomSheet<VoiceChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => VoicePickerSheet(
      currentId: currentId,
      store: store ?? InstrumentLibraryStore(),
    ),
  );
}

/// A display label for a built-in voice id (l10n where named, else humanized).
String voiceLabel(AppLocalizations l10n, String id) => switch (id) {
      'piano' => l10n.instrumentPiano,
      'cello' => l10n.instrumentCello,
      'flute' => l10n.instrumentFlute,
      'musicBox' => l10n.instrumentMusicBox,
      'zap' => l10n.trackerSfxrZap,
      'blip' => l10n.trackerSfxrBlip,
      'laser' => l10n.trackerSfxrLaser,
      'coin' => l10n.trackerSfxrCoin,
      'bell' => l10n.trackerSfxrBell,
      'explosion' => l10n.trackerSfxrExplosion,
      'pluck' => l10n.voicePluck,
      'harp' => l10n.voiceHarp,
      'pluckBass' => l10n.voicePluckBass,
      'ePiano' => l10n.voiceEPiano,
      'fmBell' => l10n.voiceFmBell,
      'fmBass' => l10n.voiceFmBass,
      'pad' => l10n.voicePad,
      'lead' => l10n.voiceLead,
      'synthBass' => l10n.voiceSynthBass,
      _ => libraryVoiceName(id) ?? _humanize(id),
    };

String _humanize(String id) {
  final spaced = id.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (m) => '${m[1]} ${m[2]}',
  );
  return spaced.isEmpty ? id : spaced[0].toUpperCase() + spaced.substring(1);
}

IconData _categoryIcon(SoundCategory c) => switch (c) {
      SoundCategory.tonal => Icons.piano,
      SoundCategory.plucked => Icons.music_note,
      SoundCategory.chiptune => Icons.videogame_asset,
      SoundCategory.drum => Icons.album,
      SoundCategory.recorded => Icons.graphic_eq,
    };

/// One selectable row: a built-in procedural voice or a saved library voice.
class _Voice {
  _Voice({
    required this.id,
    required this.label,
    required this.icon,
    required this.build,
    this.isLibrary = false,
    this.saved,
  });
  final String id; // 'blip' or 'lib:My Cello'
  final String label;
  final IconData icon;
  final TrackerInstrument? Function() build;
  final bool isLibrary;

  /// For a library voice, the saved record — resolved async (a soundfont_ref
  /// re-reads its cached font file) when [build] returns null.
  final SavedInstrument? saved;

  /// Builds the voice, resolving a soundfont_ref library voice if needed.
  Future<TrackerInstrument?> resolve() async {
    final direct = build();
    if (direct != null || saved == null) return direct;
    return resolveSavedVoice(saved!);
  }
}

@visibleForTesting
class VoicePickerSheet extends StatefulWidget {
  const VoicePickerSheet({required this.store, this.currentId, super.key});
  final String? currentId;
  final InstrumentLibraryStore store;

  @override
  State<VoicePickerSheet> createState() => _VoicePickerSheetState();
}

class _VoicePickerSheetState extends State<VoicePickerSheet> {
  final _search = TextEditingController();
  String _filter = 'all'; // 'all' | SoundCategory.name | 'library'
  List<SavedInstrument> _library = const [];

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadLibrary() async {
    final items = await widget.store.load();
    if (mounted) {
      // Voices we can play: an embedded instrument, or (on native) a
      // soundfont_ref we can re-read from its cached font file.
      setState(
        () => _library = [
          for (final s in items)
            if (s.instrument != null ||
                (s.isReference && soundFontPersistSupported))
              s,
        ],
      );
    }
  }

  /// The procedural categories present, in a stable order.
  List<SoundCategory> get _categories {
    const order = [
      SoundCategory.tonal,
      SoundCategory.chiptune,
      SoundCategory.plucked,
      SoundCategory.drum,
      SoundCategory.recorded,
    ];
    final present = kTrackerInstruments.map((o) => o.category).toSet();
    return [
      for (final c in order)
        if (present.contains(c)) c,
    ];
  }

  List<_Voice> _allVoices(AppLocalizations l10n) => [
        if (_filter == 'all' || _filter != 'library')
          for (final o in kTrackerInstruments)
            if (_filter == 'all' || o.category.name == _filter)
              _Voice(
                id: o.id,
                label: voiceLabel(l10n, o.id),
                icon: _categoryIcon(o.category),
                build: o.build,
              ),
        if (_filter == 'all' || _filter == 'library')
          for (final s in _library)
            _Voice(
              id: libraryVoiceId(s.name),
              label: s.name,
              icon: Icons.library_music,
              build: () => s.instrument,
              isLibrary: true,
              saved: s,
            ),
      ];

  List<_Voice> _visible(AppLocalizations l10n) {
    final q = _search.text.trim().toLowerCase();
    return [
      for (final v in _allVoices(l10n))
        if (q.isEmpty || v.label.toLowerCase().contains(q)) v,
    ];
  }

  Future<void> _preview(_Voice v) async {
    final inst = await v.resolve();
    if (inst == null || !mounted) return;
    final pcm = inst.renderChannel(
      [const TrackerCell(midi: 67)],
      const TrackerTiming(rows: 6),
    );
    if (pcm.isEmpty) return;
    unawaited(context.read<AudioService>().playWavBytes(pcmFloatToWav(pcm)));
  }

  Future<void> _choose(_Voice v) async {
    final resolved = v.isLibrary ? await v.resolve() : null;
    if (!mounted) return;
    Navigator.of(context).pop<VoiceChoice>((id: v.id, resolved: resolved));
  }

  Future<void> _browseCatalog() async {
    await showCatalogBrowseSheet(
      context,
      store: widget.store,
      initialKind: 'instrument',
    );
    await _loadLibrary(); // surface anything installed
  }

  Widget _chip(String key, String label) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: _filter == key,
          onSelected: (_) => setState(() => _filter = key),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final visible = _visible(l10n);
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
                Expanded(
                  child: Text(
                    l10n.voicePickerTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.cloud_outlined, size: 18),
                  label: Text(l10n.soundLibraryBrowseCatalog),
                  onPressed: _browseCatalog,
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: l10n.voiceSearchHint,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip('all', l10n.voiceCatAll),
                  for (final c in _categories)
                    _chip(c.name, _categoryLabelText(l10n, c)),
                  if (_library.isNotEmpty)
                    _chip('library', l10n.soundLibraryTitle),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.voicePreview,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 320,
              child: visible.isEmpty
                  ? Center(child: Text(l10n.libraryNoResults))
                  : ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, i) {
                        final v = visible[i];
                        final selected = v.id == widget.currentId;
                        return ListTile(
                          dense: true,
                          leading: Icon(v.icon),
                          title: Text(v.label),
                          trailing: selected
                              ? const Icon(Icons.check, size: 20)
                              : null,
                          selected: selected,
                          onTap: () => _preview(v), // hear it
                          onLongPress: () => _choose(v), // choose it
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

String _categoryLabelText(AppLocalizations l10n, SoundCategory c) =>
    switch (c) {
      SoundCategory.tonal => l10n.voiceCatTonal,
      SoundCategory.plucked => l10n.voiceCatPlucked,
      SoundCategory.chiptune => l10n.voiceCatChiptune,
      SoundCategory.drum => l10n.soundLibraryCatDrums,
      SoundCategory.recorded => l10n.soundLibraryCatSamples,
    };
