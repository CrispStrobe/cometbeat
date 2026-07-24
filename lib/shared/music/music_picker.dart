// The music side of the CometBeat asset library: pick actual MUSIC (a score) —
// from the Song Book (built-in + your imported songs) or by importing a file
// (MIDI · MusicXML/.mxl · ABC · GP/GPX · MEI · **kern · MuseScore). Resolves to a
// [MultiPartScore], so any caller — the Audio Editor especially — can drop real
// music onto a track (as a ScoreSource clip), alongside the instrument/sample
// pickers. Complements [showMyInstrumentsSheet] (instruments/samples): together
// they are the library, parameterised by what you ask it to show.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tracker_song_module.dart'
    show songFromModuleBytes;
import 'package:comet_beat/core/notation/multi_part_export.dart'
    show multiTrackMidiToMultiPart;
import 'package:comet_beat/features/games/composition/multipart_to_tracker.dart'
    show multiPartScoreFromTrackerSong;
import 'package:comet_beat/features/games/songs/song_book.dart' show kSongs;
import 'package:comet_beat/features/games/songs/user_songs_service.dart'
    show UserSongsService;
import 'package:comet_beat/features/library/content_source.dart'
    show LibraryItem;
import 'package:comet_beat/features/library/source_registry.dart'
    show defaultHttpGet;
import 'package:comet_beat/features/library/sources/cometbeat_catalog_source.dart'
    show CometbeatCatalogSource;
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show
        MultiPartScore,
        StaffSystem,
        multiPartScoreFromAbc,
        multiPartScoreFromKern,
        multiPartScoreFromMei,
        multiPartScoreFromMusicXml,
        readGpifFromGp,
        readGpifFromGpx,
        readMscxFromMscz,
        readMusicXmlFromMxl,
        scoreFromGabc,
        scoreFromGpif,
        scoreFromLilyPond,
        scoreFromMscx;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Decode a notation file into a [MultiPartScore] by extension — every part
/// kept where a multi-part reader exists (MusicXML/.mxl/ABC/MEI/**kern/MIDI);
/// MuseScore (.mscx/.mscz), GP/GPX and Gregorio chant (.gabc) wrap their
/// single-staff read. Pure; throws on a bad or unsupported file.
MultiPartScore decodeMusicFile(String fileName, Uint8List bytes) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  String text() => utf8.decode(bytes);
  return switch (ext) {
    'musicxml' || 'xml' => multiPartScoreFromMusicXml(text()),
    'mxl' => multiPartScoreFromMusicXml(readMusicXmlFromMxl(bytes)),
    'abc' => multiPartScoreFromAbc(text()),
    'mei' => multiPartScoreFromMei(text()),
    'krn' || 'kern' => multiPartScoreFromKern(text()),
    'mid' || 'midi' => multiTrackMidiToMultiPart(bytes),
    'mscx' => MultiPartScore([scoreFromMscx(text())]),
    'mscz' => MultiPartScore([scoreFromMscx(readMscxFromMscz(bytes))]),
    'gp' => MultiPartScore([scoreFromGpif(readGpifFromGp(bytes))]),
    'gpx' => MultiPartScore([scoreFromGpif(readGpifFromGpx(bytes))]),
    'ly' || 'lilypond' => MultiPartScore.fromStaffSystem(
        StaffSystem([scoreFromLilyPond(text())]),
      ),
    'gabc' =>
      MultiPartScore.fromStaffSystem(StaffSystem([scoreFromGabc(text())])),
    _ => throw FormatException('Unsupported music format: .$ext'),
  };
}

/// Decodes either a notation score or a tracker module from a catalog item.
/// Catalog metadata carries the collection because module extensions overlap
/// with the broader music browser's destination model.
MultiPartScore decodeMusicAsset(
  String fileName,
  Uint8List bytes, {
  String? collection,
}) {
  if (collection == 'module') {
    return multiPartScoreFromTrackerSong(songFromModuleBytes(bytes));
  }
  return decodeMusicFile(fileName, bytes);
}

/// The notation formats the file importer accepts (the ones with a reader).
const _kMusicExtensions = [
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

/// Shows the music picker. Resolves to the chosen music as a [MultiPartScore],
/// or null if cancelled.
Future<MultiPartScore?> showMusicPicker(BuildContext context) {
  return showModalBottomSheet<MultiPartScore>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _MusicPickerSheet(),
  );
}

class _MusicPickerSheet extends StatelessWidget {
  const _MusicPickerSheet();

  /// Pick a notation file and decode it to a [MultiPartScore] (all parts kept
  /// where a multi-part reader exists). Pops the score, or toasts on a bad file.
  Future<void> _importFile(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Music', extensions: _kMusicExtensions),
        ],
      );
      if (file == null) return;
      final score = decodeMusicFile(file.name, await file.readAsBytes());
      navigator.pop(score);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.musicPickerFailed)));
    }
  }

  /// Browse the curated CometBeat catalog's Songs and Modules, fetch a chosen
  /// item, and convert it into a score for the caller's destination.
  Future<void> _browseCatalog(BuildContext context) async {
    final score = await showModalBottomSheet<MultiPartScore>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _CatalogMusicSheet(),
    );
    if (score != null && context.mounted) Navigator.of(context).pop(score);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Read once — a modal doesn't need to track later library edits.
    // Some embedders (notably the Sound Library bottom sheet) are mounted
    // outside the Song Book provider. Built-ins, catalog, and file import are
    // still useful there, so treat the saved-song section as empty instead of
    // crashing the whole picker.
    final yours = context.read<UserSongsService?>()?.songs ?? const [];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  const Icon(Icons.library_music_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    l10n.musicPickerTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: Text(l10n.musicPickerImport),
              onTap: () => _importFile(context),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: Text(l10n.musicPickerCatalog),
              onTap: () => _browseCatalog(context),
            ),
            const Divider(),
            _header(context, l10n.musicPickerBuiltin),
            for (final song in kSongs)
              _songTile(
                context,
                song.title,
                () => Navigator.of(context).pop(MultiPartScore([song.score])),
              ),
            _header(context, l10n.musicPickerYours),
            if (yours.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  l10n.musicPickerEmpty,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              for (final s in yours)
                _songTile(
                  context,
                  s.title,
                  () => Navigator.of(context)
                      .pop(multiPartScoreFromMusicXml(s.musicXml)),
                ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext ctx, String label) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
        child: Text(
          label,
          style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                color: Theme.of(ctx).colorScheme.primary,
              ),
        ),
      );

  Widget _songTile(BuildContext ctx, String title, VoidCallback onTap) =>
      ListTile(
        dense: true,
        leading: const Icon(Icons.music_note),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );
}

/// Lists the CometBeat catalog's CC0/PD scores; tapping one fetches + decodes it
/// and pops with the [MultiPartScore]. Network-backed, so it loads lazily.
class _CatalogMusicSheet extends StatefulWidget {
  const _CatalogMusicSheet();

  @override
  State<_CatalogMusicSheet> createState() => _CatalogMusicSheetState();
}

class _CatalogMusicSheetState extends State<_CatalogMusicSheet> {
  final _source = CometbeatCatalogSource.all(defaultHttpGet);
  List<LibraryItem>? _items;
  bool _failed = false;
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _source.browse();
      if (mounted) setState(() => _items = items);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _pick(LibraryItem item) async {
    if (_fetching) return;
    setState(() => _fetching = true);
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final bytes = await _source.fetch(item);
      final score = decodeMusicAsset(
        'x.${item.format}',
        bytes,
        collection: item.collection,
      );
      navigator.pop(score);
    } catch (_) {
      if (mounted) setState(() => _fetching = false);
      messenger.showSnackBar(SnackBar(content: Text(l10n.musicPickerFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = _items;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  const Icon(Icons.cloud_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    l10n.musicPickerCatalog,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
            ),
            if (_fetching) const LinearProgressIndicator(),
            Expanded(
              child: _failed
                  ? Center(child: Text(l10n.musicPickerCatalogFailed))
                  : items == null
                      ? const Center(child: CircularProgressIndicator())
                      : items.isEmpty
                          ? Center(child: Text(l10n.musicPickerCatalogEmpty))
                          : ListView.builder(
                              itemCount: items.length,
                              itemBuilder: (_, i) {
                                final it = items[i];
                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    it.collection == 'module'
                                        ? Icons.grid_on
                                        : Icons.music_note,
                                  ),
                                  title: Text(it.title),
                                  subtitle: Text(
                                    [
                                      if (it.composer.isNotEmpty) it.composer,
                                      it.declaredLicense,
                                    ].join(' · '),
                                  ),
                                  trailing: Text(it.format.toUpperCase()),
                                  onTap: () => _pick(it),
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
