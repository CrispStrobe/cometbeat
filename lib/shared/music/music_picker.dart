// The music side of the CometBeat asset library: pick actual MUSIC (a score) —
// from the Song Book (built-in + your imported songs) or by importing a file
// (MIDI · MusicXML/.mxl · ABC · GP/GPX · MEI · **kern · MuseScore). Resolves to a
// [MultiPartScore], so any caller — the Audio Editor especially — can drop real
// music onto a track (as a ScoreSource clip), alongside the instrument/sample
// pickers. Complements [showMyInstrumentsSheet] (instruments/samples): together
// they are the library, parameterised by what you ask it to show.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/microphone_pitch_service.dart';
import 'package:comet_beat/core/audio/tracker_song_module.dart'
    show songFromModuleBytes;
import 'package:comet_beat/core/licensing/license_obligations.dart';
import 'package:comet_beat/core/music/melodic_search.dart';
import 'package:comet_beat/core/music/sung_melody.dart';
import 'package:comet_beat/core/notation/multi_part_export.dart'
    show multiTrackMidiToMultiPart;
import 'package:comet_beat/features/games/composition/multipart_to_tracker.dart'
    show multiPartScoreFromTrackerSong;
import 'package:comet_beat/features/games/songs/song_book.dart' show kSongs;
import 'package:comet_beat/features/games/songs/user_songs_service.dart'
    show UserSongsService;
import 'package:comet_beat/features/library/content_source.dart'
    show ContentSource, LibraryItem;
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
/// A picked piece of music plus the licence it came with (null when it carries
/// none — a built-in, or a file the user opened themselves).
typedef PickedMusic = ({MultiPartScore score, LicensedWork? provenance});

/// Pick music AND learn what it obliges.
///
/// The licence has to travel with the score: an editor can only honour an
/// obligation it was told about, and this picker is the doorway the library
/// uses into the Audio Editor, Tracker and Workshop alike. See
/// `docs/CORPUS_LICENSING.md` (SA-propagation).
Future<PickedMusic?> showMusicPickerWithLicense(BuildContext context) {
  return showModalBottomSheet<PickedMusic>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _MusicPickerSheet(),
  );
}

/// "What is this tune?" — opens the catalog straight onto the melody lens with
/// [melody] already entered, and searches immediately.
///
/// The third way into melodic search, beside tapping it and singing it: the
/// query comes from music the user ALREADY has open. Skipping the outer picker
/// sheet is deliberate — they are not choosing a source, they are asking a
/// question about something in front of them.
Future<PickedMusic?> showMelodicSearch(
  BuildContext context, {
  required List<int> melody,
}) {
  return showModalBottomSheet<PickedMusic>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => CatalogMusicSheet(initialMelody: melody),
  );
}

/// Pick music, ignoring provenance — for callers that don't export.
Future<MultiPartScore?> showMusicPicker(BuildContext context) async =>
    (await showMusicPickerWithLicense(context))?.score;

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
      // A file the user opened themselves declares nothing and owes nothing.
      navigator.pop((score: score, provenance: null));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.musicPickerFailed)));
    }
  }

  /// Browse the curated CometBeat catalog's Songs and Modules, fetch a chosen
  /// item, and convert it into a score for the caller's destination.
  Future<void> _browseCatalog(BuildContext context) async {
    final picked = await showModalBottomSheet<PickedMusic>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const CatalogMusicSheet(),
    );
    if (picked != null && context.mounted) Navigator.of(context).pop(picked);
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
                () => Navigator.of(context).pop(
                  (
                    score: MultiPartScore([song.score]),
                    provenance: null, // built-in, ours, owes nothing
                  ),
                ),
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

/// A live source of pitch readings for the "sing it" search.
///
/// An interface rather than the plugin directly, for one reason that matters:
/// the sheet is otherwise untestable. A widget test cannot open a microphone,
/// so without this seam the entire sung path would be verifiable only by hand
/// on a device — which is how a feature ends up shipped unverified.
abstract class MelodyMicrophone {
  Future<void> start();

  /// Frequency in Hz (0 for silence), a 0..1 clarity, and WHEN the frame
  /// occurred, one per analysis frame.
  ///
  /// ⚠️ `timeMs` belongs to the SOURCE, not to the consumer. The sheet used to
  /// stamp arrival times from a `Stopwatch`, which is real time — and under a
  /// widget test `pump()` advances FAKE time, so every frame landed at ~0 ms,
  /// every note came out zero-length, and the duration filter silently threw
  /// the whole phrase away. A capture source always knows its own frame times;
  /// asking the consumer to guess them was the bug.
  Stream<({double frequency, double clarity, double timeMs})> get readings;

  Future<void> stop();
}

/// The real microphone, wrapping the app's shared pitch service.
class _RealMelodyMicrophone implements MelodyMicrophone {
  final MicrophonePitchService _service = MicrophonePitchService();
  final Stopwatch _clock = Stopwatch();

  @override
  Stream<({double frequency, double clarity, double timeMs})> get readings =>
      _service.readings.map(
        (r) => (
          frequency: r.frequency,
          clarity: r.clarity,
          // `PitchReading` carries no time of its own, so the capture stamps
          // arrival — which is right HERE, where the clock and the audio run on
          // the same real timeline.
          timeMs: _clock.elapsedMilliseconds.toDouble(),
        ),
      );

  @override
  Future<void> start() {
    _clock
      ..reset()
      ..start();
    return _service.start();
  }

  @override
  Future<void> stop() async {
    _clock.stop();
    await _service.stop();
    await _service.dispose();
  }
}

/// Catalog rows → a searchable melodic pool, plus the way back to the row.
///
/// Pulled out of the sheet so the RULE is testable without a network or a
/// widget: a row is searchable only if its incipit has at least two notes,
/// because one note is zero intervals and therefore no shape at all — such a
/// row would otherwise sit in the pool matching everything equally.
({List<MelodicCandidate> pool, Map<String, LibraryItem> byId}) melodicPoolFrom(
  Iterable<LibraryItem> items,
) {
  final pool = <MelodicCandidate>[];
  final byId = <String, LibraryItem>{};
  for (final i in items) {
    final incipit = i.music?.incipit ?? const <int>[];
    if (incipit.length < 2) continue;
    pool.add(MelodicCandidate(i.id, incipit));
    byId[i.id] = i;
  }
  return (pool: pool, byId: byId);
}

/// Lists the CometBeat catalog's CC0/PD scores; tapping one fetches + decodes it
/// and pops with the [MultiPartScore]. Network-backed, so it loads lazily.
///
/// [source] exists so a test can drive this sheet at all. It used to construct
/// its own `CometbeatCatalogSource` inline, which made every behaviour here —
/// the search box, the melody lens, the empty states, picking a row — reachable
/// only over the real network, i.e. not testable. Production callers pass
/// nothing and get exactly what they got before.
class CatalogMusicSheet extends StatefulWidget {
  const CatalogMusicSheet({
    super.key,
    this.source,
    this.microphone,
    this.initialMelody,
  });

  final ContentSource? source;

  /// Opens on the melody lens with these notes already entered.
  final List<int>? initialMelody;

  /// Injected for tests; production passes nothing and gets the real mic.
  final MelodyMicrophone? microphone;

  @override
  State<CatalogMusicSheet> createState() => _CatalogMusicSheetState();
}

class _CatalogMusicSheetState extends State<CatalogMusicSheet> {
  // A MUSIC picker: only songs + tracker modules, so it never fetches the
  // instrument/sample/soundfont shards (the display already filters to these).
  late final ContentSource _source = widget.source ??
      CometbeatCatalogSource(defaultHttpGet, kinds: const {'score', 'module'});
  List<LibraryItem>? _items;
  bool _failed = false;
  bool _fetching = false;
  String _query = '';

  /// Guards against an out-of-order result overwriting a newer one: typing
  /// fires a browse per keystroke and they can settle in any order.
  int _searchSeq = 0;

  final _searchController = TextEditingController();
  Timer? _debounce;

  /// How many rows a listing shows.
  ///
  /// ⚠️ This used to be a bare `browse(limit: 1000)` with no query, against a
  /// catalog of ~38,900 items. That is not a browse, it is an arbitrary 2.5%
  /// slice in whatever order the index happened to be in — the piece the user
  /// wanted was almost certainly not in it, and there was no way to ask for it.
  /// A search box is what makes the rest of the catalog reachable at all.
  static const _pageSize = 300;

  @override
  void initState() {
    super.initState();
    _load();
    final seed = widget.initialMelody;
    if (seed != null && seed.isNotEmpty) {
      _byMelody = true;
      _melody.addAll(seed);
      // The pool is what the seeded query is ranked against, so it has to be
      // fetched now rather than on the lens being opened by hand.
      unawaited(_ensurePool());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    // Release the microphone even if the sheet is dismissed mid-phrase.
    unawaited(_micSub?.cancel());
    if (_listening) unawaited(_mic.stop());
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    // Debounced: the source filters an in-memory catalog, but it also has to
    // FETCH it the first time, and a request per keystroke would queue them.
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _query = value);
      _load();
    });
  }

  Future<void> _load() async {
    final seq = ++_searchSeq;
    try {
      final items = await _source.browse(query: _query, limit: _pageSize);
      if (!mounted || seq != _searchSeq) return;
      setState(
        () => _items = [
          for (final item in items)
            if (item.collection == 'score' || item.collection == 'module') item,
        ],
      );
    } catch (_) {
      if (mounted && seq == _searchSeq) setState(() => _failed = true);
    }
  }

  // --- find by melody -------------------------------------------------------

  /// Which lens the sheet is searching through — words or notes.
  bool _byMelody = false;

  /// The notes tapped so far, as absolute MIDI. Absolute is what the user
  /// entered; the search derives intervals itself, so nothing here has to be
  /// normalised or transposed.
  final List<int> _melody = [];

  /// Every searchable row, loaded once. Melodic search cannot work on a PAGE —
  /// ranking 300 arbitrary rows out of 38k would almost never contain the piece
  /// being hummed. The source keeps the shard in memory after the first fetch,
  /// so asking for all of it costs no extra network.
  List<MelodicCandidate>? _pool;
  Map<String, LibraryItem> _byId = const {};
  bool _poolLoading = false;

  Future<void> _ensurePool() async {
    if (_pool != null || _poolLoading) return;
    setState(() => _poolLoading = true);
    try {
      final built = melodicPoolFrom(await _source.browse(limit: 100000));
      if (!mounted) return;
      setState(() {
        _pool = built.pool;
        _byId = built.byId;
        _poolLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _poolLoading = false);
    }
  }

  // --- "sing it" ------------------------------------------------------------

  late final MelodyMicrophone _mic =
      widget.microphone ?? _RealMelodyMicrophone();
  StreamSubscription<({double frequency, double clarity, double timeMs})>?
      _micSub;
  SungMelodyCollector? _collector;
  bool _listening = false;
  String? _micError;

  /// Starts (or stops) listening. Stopping is what runs the search: a live
  /// re-rank on every frame would flicker the list under the user's hand while
  /// they are still singing the phrase that decides it.
  Future<void> _toggleListening() async {
    if (_listening) {
      await _stopListening();
      return;
    }
    setState(() {
      _micError = null;
      _collector = SungMelodyCollector();
    });
    try {
      _micSub = _mic.readings.listen((r) {
        _collector?.add(
          frequency: r.frequency,
          clarity: r.clarity,
          timeMs: r.timeMs,
        );
      });
      await _mic.start();
      if (mounted) setState(() => _listening = true);
    } catch (e) {
      // Same rule as in `_stopListening`: do not make TELLING THE USER wait on
      // a subscription cancel. A denied or busy microphone is exactly when the
      // message matters, and awaiting cancel here swallowed it entirely.
      final sub = _micSub;
      _micSub = null;
      unawaited(sub?.cancel());
      if (mounted) {
        setState(() {
          _listening = false;
          _micError = '$e';
        });
      }
    }
  }

  Future<void> _stopListening() async {
    // ⚠️ Cancel is NOT awaited before releasing the microphone. The two are
    // independent, and ordering them the other way makes releasing the device
    // hostage to a subscription that may still be draining buffered frames —
    // which in a widget test never completed at all, and in production would
    // mean a held-open mic.
    final sub = _micSub;
    _micSub = null;
    unawaited(sub?.cancel());
    try {
      await _mic.stop();
    } catch (_) {
      // Already stopped, or the platform tore the recorder down first — the
      // query is in hand either way, so this must not lose it.
    }
    final query = _collector?.toQuery() ?? const [];
    if (!mounted) return;
    setState(() {
      _listening = false;
      if (query.isNotEmpty) {
        _melody
          ..clear()
          ..addAll(query);
      }
    });
  }

  /// The current ranked hits, or null when there is nothing to rank yet.
  List<LibraryItem>? get _melodyHits {
    final pool = _pool;
    if (pool == null || _melody.length < 2) return null;
    return [
      for (final h in searchMelodies(_melody, pool, limit: 40))
        if (_byId[h.id] != null) _byId[h.id]!,
    ];
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
      navigator.pop(
        (
          score: score,
          // The catalog states a licence and an attribution per item; both are
          // needed for the credit line, so carry them rather than re-deriving.
          provenance: item.declaredLicense.trim().isEmpty
              ? null
              : LicensedWork(
                  title: item.title,
                  license: item.declaredLicense,
                  creator: item.composer.trim().isEmpty ? null : item.composer,
                  source: _source.name,
                  url: item.sourceUrl,
                ),
        ),
      );
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
            // Two lenses on the same catalog: what a piece is CALLED, and how it
            // GOES. The second is the one that helps when the title is exactly
            // what you cannot remember.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment<bool>(
                    value: false,
                    icon: const Icon(Icons.search, size: 18),
                    label: Text(l10n.musicPickerByTitle),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    icon: const Icon(Icons.piano, size: 18),
                    label: Text(l10n.musicPickerByMelody),
                  ),
                ],
                selected: {_byMelody},
                showSelectedIcon: false,
                onSelectionChanged: (v) {
                  setState(() => _byMelody = v.first);
                  if (v.first) unawaited(_ensurePool());
                },
              ),
            ),
            if (!_byMelody)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onQueryChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    hintText: l10n.musicPickerSearchHint,
                    border: const OutlineInputBorder(),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _onQueryChanged('');
                            },
                          ),
                  ),
                ),
              )
            else
              _MelodyQueryBar(
                notes: _melody,
                listening: _listening,
                error: _micError,
                onAdd: (m) => setState(() => _melody.add(m)),
                onBackspace:
                    _melody.isEmpty ? null : () => setState(_melody.removeLast),
                onClear: _melody.isEmpty ? null : () => setState(_melody.clear),
                onToggleListening: () => unawaited(_toggleListening()),
              ),
            if (_fetching || (_byMelody && _poolLoading))
              const LinearProgressIndicator(),
            Expanded(child: _results(l10n, items)),
          ],
        ),
      ),
    );
  }

  Widget _results(AppLocalizations l10n, List<LibraryItem>? items) {
    if (_failed) {
      return Center(child: Text(l10n.musicPickerCatalogFailed));
    }

    if (_byMelody) {
      if (_pool == null) {
        return const Center(child: CircularProgressIndicator());
      }
      final hits = _melodyHits;
      // Two notes is one interval. Below that there is no shape to search on,
      // so say what to do rather than showing a ranked list of nothing.
      if (hits == null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.musicPickerMelodyHint(_pool!.length),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        );
      }
      return _tiles(hits);
    }

    if (items == null) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _query.isEmpty
                ? l10n.musicPickerCatalogEmpty
                : l10n.musicPickerNoMatch,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return _tiles(items);
  }

  Widget _tiles(List<LibraryItem> items) => ListView.builder(
        itemCount: items.length,
        itemBuilder: (_, i) {
          final it = items[i];
          return ListTile(
            dense: true,
            leading: Icon(
              it.collection == 'module' ? Icons.grid_on : Icons.music_note,
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
      );
}

/// Tap the opening notes of a tune.
///
/// A keyboard rather than a text field because the input is a MELODY, and
/// because nothing here has to be in the right key — the search compares
/// intervals, so the user can start wherever the shape feels right. Two octaves
/// so a tune that leaps still fits without an octave control to discover.
class _MelodyQueryBar extends StatelessWidget {
  const _MelodyQueryBar({
    required this.notes,
    required this.listening,
    required this.error,
    required this.onAdd,
    required this.onBackspace,
    required this.onClear,
    required this.onToggleListening,
  });

  final List<int> notes;
  final bool listening;
  final String? error;
  final ValueChanged<int> onAdd;
  final VoidCallback? onBackspace;
  final VoidCallback? onClear;
  final VoidCallback onToggleListening;

  static const _names = [
    'C',
    'C♯',
    'D',
    'D♯',
    'E',
    'F',
    'F♯',
    'G',
    'G♯',
    'A',
    'A♯',
    'B',
  ];

  static String nameOf(int midi) => '${_names[midi % 12]}${(midi ~/ 12) - 1}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  listening
                      ? l10n.musicPickerListening
                      : (notes.isEmpty ? '—' : notes.map(nameOf).join(' ')),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: listening ? scheme.primary : null,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Sing it. Stopping is what runs the search — re-ranking live
              // would flicker the list under the user's hand mid-phrase.
              IconButton(
                key: const Key('melody-listen'),
                icon: Icon(listening ? Icons.stop_circle : Icons.mic, size: 20),
                color: listening ? scheme.primary : null,
                tooltip: listening
                    ? l10n.musicPickerStopSinging
                    : l10n.musicPickerSingIt,
                onPressed: onToggleListening,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.backspace_outlined, size: 18),
                onPressed: listening ? null : onBackspace,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: listening ? null : onClear,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                l10n.musicPickerMicFailed,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.error),
              ),
            ),
          SizedBox(
            height: 44,
            child: ListView(
              key: const Key('melody-keyboard'),
              scrollDirection: Axis.horizontal,
              children: [
                for (var midi = 60; midi <= 83; midi++)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: SizedBox(
                      width: 40,
                      child: FilledButton.tonal(
                        // Keyed by pitch: the readout renders the SAME note
                        // names as the buttons, so finding a key by its text
                        // is ambiguous the moment a note has been entered.
                        key: ValueKey('melody-key-$midi'),
                        onPressed: () => onAdd(midi),
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          // Black keys read darker so the row scans like a
                          // keyboard rather than 24 identical buttons.
                          backgroundColor: _names[midi % 12].length > 1
                              ? scheme.surfaceContainerHighest
                              : null,
                        ),
                        // ⚠️ Labelled WITH the octave. Two octaves of bare
                        // note names give the row two identical "C" buttons
                        // and no way to tell which is which — a tap then lands
                        // an octave from where the user meant, which for an
                        // interval search is not a near miss but a different
                        // shape. (A widget test hit exactly this.)
                        child: Text(
                          nameOf(midi),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
