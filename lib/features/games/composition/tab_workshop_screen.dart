import 'dart:async';
import 'dart:convert';

import 'package:comet_beat/core/audio/microphone_pitch_service.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/games/composition/tab_chords.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:comet_beat/features/games/composition/tab_mic_capture.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// A small built-in ASCII-tab riff so the screen is never empty. Parsed with
/// [asciiTabToScore], then made editable via [TabDocument.fromScore].
const _demoTab = '''
e|---0-------3-----0-------|
B|-----1-------1-------1---|
G|-------0-------0-------0-|
D|-------------------------|
A|-------------------------|
E|-0-------3-------0-------|
''';

/// Tuning presets offered in the picker (label ← [Tuning.name]).
final List<Tuning> tabTuningPresets = <Tuning>[
  Tuning.standardGuitar,
  Tuning.dropDGuitar,
  Tuning.dadgadGuitar,
  Tuning.openGGuitar,
  Tuning.sevenStringGuitar,
  Tuning.eightStringGuitar,
  Tuning.standardBass,
  Tuning.fiveStringBass,
  Tuning.ukulele,
  Tuning.mandolin,
  Tuning.banjoOpenG,
];

/// Extensions the tab reader accepts. Guitar Pro (`.gp`/`.gpx`) carry real
/// tab/fret data; the rest are read as pitches and placed on the fretboard by
/// lowest-fret when converted to a [TabDocument].
const List<String> tabImportExtensions = <String>[
  'gp',
  'gpx',
  'musicxml',
  'xml',
  'mxl',
  'mid',
  'midi',
  'abc',
];

/// Parses an opened file into a [Score] by its extension — the tab editor's own
/// import (kept separate from the Workshop's `importScore` so this screen stays
/// self-contained). Pure given the raw [bytes], so it is unit-testable without a
/// file picker. Throws a [FormatException] on an unknown extension.
Score parseTabFile(String fileName, Uint8List bytes) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  String text() => utf8.decode(bytes);
  return switch (ext) {
    'gp' => scoreFromGpif(readGpifFromGp(bytes)),
    'gpx' => scoreFromGpif(readGpifFromGpx(bytes)),
    'musicxml' || 'xml' => scoreFromMusicXml(text()),
    'mxl' => scoreFromMusicXml(readMusicXmlFromMxl(bytes)),
    'mid' || 'midi' => scoreFromMidi(bytes),
    'abc' => scoreFromAbc(text()),
    _ => throw FormatException('Unsupported file type: .$ext'),
  };
}

/// Test seam onto [TabWorkshopScreen]'s state — drives editing + file-open with
/// injected bytes, and reads back what's shown, without the platform picker.
abstract class TabWorkshopTester {
  Future<void> openScoreFile({String? pickedName, Uint8List? pickedBytes});
  String? get sourceName;
  Tuning get tuning;
  int get capo;
  int get columnCount;

  /// The fret on [string] at [col], or null if empty.
  int? fretAt(int col, int string);
  void selectCell(int col, int string);
  void enterFret(int fret);
  void deleteCell();
  void addColumn();
  void removeColumnAtCursor();
  void play();
  bool get isPlaying;
  Set<String> get highlightedIds;
  void toggleTechnique(TabTechnique t);
  Set<TabTechnique> techniquesAt(int col);
  void setChordByName(String? name);
  String? chordNameAt(int col);
  void saveToSongBook(String title);
  int get bpm;
  int get trackCount;
  int get activeTrack;
  void selectTrack(int index);
  void addTrack();
  void removeTrack();
  bool get isListening;

  /// Feeds a reading straight into the mic-capture path, bypassing the plugin,
  /// so the wiring is testable without a microphone.
  void debugFeedReading(PitchReading reading);
}

/// A guitar/bass **tablature editor** (B1) — the Tab Workshop. Author tab on a
/// string×step grid (tap a cell, type a fret) for any [Tuning] + capo, hear it,
/// and open Guitar Pro / MusicXML / MIDI / ABC files as editable tab. The
/// engraved staff (with a synced standard staff) previews the [TabDocument];
/// the same model round-trips to the Score Workshop and Tracker.
class TabWorkshopScreen extends StatefulWidget {
  /// Optional score to open as editable tab (e.g. from the Workshop). When null
  /// a built-in demo riff is shown.
  final Score? initialScore;

  const TabWorkshopScreen({super.key, this.initialScore});

  @override
  State<TabWorkshopScreen> createState() => _TabWorkshopScreenState();
}

class _TabWorkshopScreenState extends State<TabWorkshopScreen>
    with SingleTickerProviderStateMixin
    implements TabWorkshopTester {
  late List<TabTrack> _tracks;
  int _active = 0;

  /// The document being edited — the active track's.
  TabDocument get _doc => _tracks[_active].doc;

  int _capo = 0;
  bool _showStandard = true;
  NoteDuration _dur = NoteDuration.quarter;
  int _selCol = 0;
  int _selString = 0;
  int _bpm = 120;
  String? _sourceName;
  final _focus = FocusNode();

  // Mic capture: play a note, it lands on the fretboard at the cursor.
  final MicrophonePitchService _mic = MicrophonePitchService();
  StreamSubscription<PitchReading>? _micSub;
  TabMicCapture? _capture;
  bool _listening = false;

  // Playback highlight: a Ticker lights the sounding column's note id in time.
  late final Ticker _ticker;
  bool _playing = false;
  Set<String> _highlightedIds = const {};
  List<({int col, int start, int end, bool note})> _schedule = const [];
  int _totalMs = 0;

  @override
  void initState() {
    super.initState();
    final score = widget.initialScore ?? asciiTabToScore(_demoTab);
    _tracks = [
      TabTrack('Guitar', TabDocument.fromScore(score, Tuning.standardGuitar)),
    ];
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _micSub?.cancel();
    _mic.dispose();
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ── Tester seam ──────────────────────────────────────────────────────────
  @override
  String? get sourceName => _sourceName;
  @override
  Tuning get tuning => _doc.tuning;
  @override
  int get capo => _capo;
  @override
  int get columnCount => _doc.columns.length;
  @override
  int? fretAt(int col, int string) =>
      col < _doc.columns.length ? _doc.columns[col].frets[string] : null;
  @override
  void selectCell(int col, int string) => setState(() {
        _selCol = col.clamp(0, _doc.columns.length - 1);
        _selString = string.clamp(0, _doc.stringCount - 1);
      });

  @override
  void enterFret(int fret) => setState(() {
        _doc.setDuration(_selCol, _dur);
        _doc.setFret(_selCol, _selString, fret);
      });

  @override
  void deleteCell() => setState(() => _doc.clearCell(_selCol, _selString));

  @override
  void addColumn() => setState(() {
        _doc.insertColumn(_selCol + 1);
        _selCol = (_selCol + 1).clamp(0, _doc.columns.length - 1);
      });

  @override
  void removeColumnAtCursor() => setState(() {
        _doc.removeColumn(_selCol);
        _selCol = _selCol.clamp(0, _doc.columns.length - 1);
      });

  @override
  void play() => _play();
  @override
  bool get isPlaying => _playing;
  @override
  Set<String> get highlightedIds => _highlightedIds;
  @override
  void toggleTechnique(TabTechnique t) =>
      setState(() => _doc.toggleTechnique(_selCol, t));
  @override
  Set<TabTechnique> techniquesAt(int col) =>
      col < _doc.columns.length ? _doc.columns[col].techniques : const {};
  @override
  void setChordByName(String? name) => setState(
        () => _doc.setChord(_selCol, name == null ? null : kGuitarChords[name]),
      );
  @override
  String? chordNameAt(int col) =>
      col < _doc.columns.length ? _doc.columns[col].chord?.name : null;
  @override
  int get bpm => _bpm;
  @override
  bool get isListening => _listening;

  @override
  void debugFeedReading(PitchReading reading) => _onReading(reading);

  /// A committed note from the mic lands at the cursor, then the cursor steps
  /// on — so playing a phrase writes it across the grid.
  void _onReading(PitchReading reading) {
    final placement = (_capture ??= TabMicCapture(_doc.tuning)).accept(reading);
    if (placement == null) return;
    setState(() {
      _doc.setDuration(_selCol, _dur);
      _doc.setFret(_selCol, placement.$1, placement.$2);
      _selCol++; // setFret grows the document as needed
      _selString = placement.$1;
    });
  }

  Future<void> _toggleMic() async {
    final l10n = AppLocalizations.of(context)!;
    if (_listening) {
      await _micSub?.cancel();
      _micSub = null;
      await _mic.stop();
      if (!mounted) return;
      setState(() => _listening = false);
      return;
    }
    try {
      if (!await _mic.hasPermission()) {
        if (!mounted) return;
        _snack(l10n.tabMicDenied);
        return;
      }
      _capture = TabMicCapture(_doc.tuning);
      _micSub = _mic.readings.listen(_onReading);
      await _mic.start();
      if (!mounted) return;
      setState(() => _listening = true);
    } catch (_) {
      await _micSub?.cancel();
      _micSub = null;
      if (!mounted) return;
      _snack(l10n.tabMicFailed);
    }
  }

  @override
  int get trackCount => _tracks.length;
  @override
  int get activeTrack => _active;

  @override
  void selectTrack(int index) => setState(() {
        _active = index.clamp(0, _tracks.length - 1);
        _selCol = _selCol.clamp(0, _doc.columns.length - 1);
        _selString = _selString.clamp(0, _doc.stringCount - 1);
      });

  @override
  void addTrack() => setState(() {
        _tracks.add(
          TabTrack(
            'Track ${_tracks.length + 1}',
            TabDocument.blank(Tuning.standardGuitar),
          ),
        );
        _active = _tracks.length - 1;
        _selCol = 0;
        _selString = 0;
      });

  @override
  void removeTrack() => setState(() {
        if (_tracks.length <= 1) return; // always keep one track
        _tracks.removeAt(_active);
        _active = _active.clamp(0, _tracks.length - 1);
        _selCol = _selCol.clamp(0, _doc.columns.length - 1);
        _selString = _selString.clamp(0, _doc.stringCount - 1);
      });

  /// MusicXML for the whole band — multi-part when there is more than one
  /// track, else the single active track.
  String _bandMusicXml() => _tracks.length > 1
      ? multiPartToMusicXml(
          MultiPartScore([for (final t in _tracks) t.doc.toScore()]),
        )
      : scoreToMusicXml(_doc.toScore());

  @override
  void saveToSongBook(String title) {
    final name = title.trim().isEmpty ? 'Tab' : title.trim();
    final xml = _bandMusicXml();
    context.read<UserSongsService>().addSong(
          ImportedSong(
            id: 'tab_${name}_${_doc.columns.length}',
            title: name,
            musicXml: xml,
          ),
        );
    _snack(AppLocalizations.of(context)!.tabSaved(name));
  }

  // ── Actions ──────────────────────────────────────────────────────────────
  @override
  Future<void> openScoreFile({
    String? pickedName,
    Uint8List? pickedBytes,
  }) async {
    String name;
    Uint8List bytes;
    if (pickedBytes != null && pickedName != null) {
      name = pickedName;
      bytes = pickedBytes;
    } else {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Scores & tabs', extensions: tabImportExtensions),
        ],
      );
      if (file == null) return;
      name = file.name;
      bytes = await file.readAsBytes();
    }
    try {
      final score = parseTabFile(name, bytes);
      if (!mounted) return;
      setState(() {
        _tracks[_active].doc = TabDocument.fromScore(score, _doc.tuning);
        _sourceName = name;
        _selCol = 0;
        _selString = 0;
      });
    } catch (_) {
      if (!mounted) return;
      _snack(AppLocalizations.of(context)!.tabImportFailed);
    }
  }

  void _loadDemo() => setState(() {
        _tracks[_active].doc =
            TabDocument.fromScore(asciiTabToScore(_demoTab), _doc.tuning);
        _sourceName = null;
        _selCol = 0;
        _selString = 0;
      });

  void _clearAll() => setState(() {
        _tracks[_active].doc = TabDocument.blank(_doc.tuning);
        _sourceName = null;
        _selCol = 0;
        _selString = 0;
      });

  void _play() {
    if (_playing) {
      _stopPlayback();
      return;
    }
    // Audio: every track sounding together. Highlight: the ACTIVE track's own
    // column timeline (that's what the preview shows).
    final events = _doc.toPlaybackEvents(bpm: _bpm);
    final band = mergePlaybackEvents(
      [for (final t in _tracks) t.doc.toPlaybackEvents(bpm: _bpm)],
    );
    context.read<AudioService>().playTimedChords(band);
    final schedule = <({int col, int start, int end, bool note})>[];
    var t = 0;
    for (var c = 0; c < events.length; c++) {
      final (midis, ms) = events[c];
      schedule.add((col: c, start: t, end: t + ms, note: midis.isNotEmpty));
      t += ms;
    }
    if (_ticker.isActive) _ticker.stop();
    setState(() {
      _schedule = schedule;
      _totalMs = t;
      _playing = true;
      _highlightedIds = const {};
    });
    _ticker.start();
  }

  void _stopPlayback() {
    if (_ticker.isActive) _ticker.stop();
    setState(() {
      _playing = false;
      _highlightedIds = const {};
    });
  }

  void _onTick(Duration elapsed) {
    final ms = elapsed.inMilliseconds;
    if (ms >= _totalMs) {
      _stopPlayback();
      return;
    }
    Set<String> ids = const {};
    for (final e in _schedule) {
      if (e.note && ms >= e.start && ms < e.end) {
        ids = {'t${e.col}'};
        break;
      }
    }
    if (!setEquals(ids, _highlightedIds)) {
      setState(() => _highlightedIds = ids);
    }
  }

  // ── Export ───────────────────────────────────────────────────────────────
  Future<void> _export(String format) async {
    final score = _doc.toScore();
    final base = (_sourceName ?? 'tab').replaceAll(RegExp(r'\.[^.]*$'), '');
    switch (format) {
      case 'gp':
        await _saveBytes(
          writeGpFromGpif(scoreToGpif(score, tuning: _doc.tuning)),
          '$base.gp',
          'Guitar Pro',
          const ['gp'],
        );
      case 'musicxml':
        await _saveBytes(
          Uint8List.fromList(utf8.encode(_bandMusicXml())),
          '$base.musicxml',
          'MusicXML',
          const ['musicxml'],
        );
      case 'midi':
        await _saveBytes(
          scoreToMidi(score),
          '$base.mid',
          'MIDI',
          const ['mid'],
        );
    }
  }

  Future<void> _saveBytes(
    Uint8List bytes,
    String suggestedName,
    String label,
    List<String> extensions,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final location = await getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: [
          XTypeGroup(label: label, extensions: extensions),
        ],
      );
      if (location == null || !mounted) return;
      await XFile.fromData(bytes, name: suggestedName).saveTo(location.path);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.tabSavedTo(location.path))),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.tabExportFailed)));
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  String _tuningLabel(Tuning t) => t.name ?? '${t.stringCount}-string';

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft) {
      selectCell(_selCol - 1, _selString);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      selectCell(_selCol + 1, _selString);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      selectCell(_selCol, _selString - 1);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      selectCell(_selCol, _selString + 1);
    } else if (k == LogicalKeyboardKey.backspace ||
        k == LogicalKeyboardKey.delete) {
      deleteCell();
    } else {
      final digit = int.tryParse(event.character ?? '');
      if (digit != null) {
        enterFret(digit);
      } else {
        return KeyEventResult.ignored;
      }
    }
    return KeyEventResult.handled;
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final score = _doc.toScore();
    final view = _showStandard
        ? NotationTabView(
            score: score,
            tuning: _doc.tuning,
            capo: _capo,
            showTuning: true,
            highlightedIds: _highlightedIds,
          )
        : TabStaffView(
            score: score,
            tuning: _doc.tuning,
            capo: _capo,
            showTuning: true,
            highlightedIds: _highlightedIds,
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(_sourceName ?? l10n.tabWorkshopTitle),
        actions: [
          IconButton(
            icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
            tooltip: l10n.tabPlay,
            onPressed: _play,
          ),
          IconButton(
            icon: Icon(_listening ? Icons.mic : Icons.mic_none),
            tooltip: l10n.tabMic,
            color: _listening ? Theme.of(context).colorScheme.error : null,
            onPressed: _toggleMic,
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: l10n.tabImport,
            onPressed: openScoreFile,
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: l10n.tabSaveSongBook,
            onPressed: _promptSave,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.ios_share),
            tooltip: l10n.tabExport,
            onSelected: _export,
            itemBuilder: (_) => [
              PopupMenuItem(value: 'gp', child: Text(l10n.tabExportGp)),
              PopupMenuItem(
                value: 'musicxml',
                child: Text(l10n.tabExportMusicXml),
              ),
              PopupMenuItem(value: 'midi', child: Text(l10n.tabExportMidi)),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.music_note),
            tooltip: l10n.tabDemo,
            onPressed: _loadDemo,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.tabClear,
            onPressed: _clearAll,
          ),
        ],
      ),
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(
          children: [
            _trackStrip(l10n),
            const Divider(height: 1),
            _controls(l10n),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: view,
                      ),
                    ),
                    const Divider(height: 1),
                    _grid(),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            _editorPanel(l10n),
          ],
        ),
      ),
    );
  }

  /// The band's track strip: pick the track you're editing, add or remove one.
  Widget _trackStrip(AppLocalizations l10n) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Text(l10n.tabTracks),
          const SizedBox(width: 8),
          for (var i = 0; i < _tracks.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(_tracks[i].name),
                selected: i == _active,
                onSelected: (_) => selectTrack(i),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.library_add_outlined),
            tooltip: l10n.tabAddTrack,
            onPressed: addTrack,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: l10n.tabRemoveTrack,
            onPressed: _tracks.length > 1 ? removeTrack : null,
          ),
        ],
      ),
    );
  }

  Widget _controls(AppLocalizations l10n) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(l10n.tabTuning),
          const SizedBox(width: 8),
          DropdownButton<Tuning>(
            value: _doc.tuning,
            onChanged: (t) => setState(() {
              if (t != null) {
                _doc.tuning = t;
                _selString = _selString.clamp(0, t.stringCount - 1);
              }
            }),
            items: [
              for (final t in tabTuningPresets)
                DropdownMenuItem(value: t, child: Text(_tuningLabel(t))),
            ],
          ),
          const SizedBox(width: 20),
          Text(l10n.tabCapo),
          IconButton(
            icon: const Icon(Icons.remove),
            tooltip: l10n.tabCapo,
            onPressed: _capo > 0 ? () => setState(() => _capo--) : null,
          ),
          Text('$_capo'),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.tabCapo,
            onPressed: _capo < 12 ? () => setState(() => _capo++) : null,
          ),
          const SizedBox(width: 20),
          Text(l10n.tabTempo),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: l10n.tabTempo,
            onPressed: _bpm > 40 ? () => setState(() => _bpm -= 10) : null,
          ),
          Text('$_bpm'),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: l10n.tabTempo,
            onPressed: _bpm < 240 ? () => setState(() => _bpm += 10) : null,
          ),
          const SizedBox(width: 20),
          Text(l10n.tabShowStandard),
          Switch(
            value: _showStandard,
            onChanged: (v) => setState(() => _showStandard = v),
          ),
        ],
      ),
    );
  }

  Future<void> _promptSave() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: _sourceName ?? 'My Tab');
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tabSaveSongBook),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
    if (title == null || !mounted) return;
    saveToSongBook(title);
  }

  /// The editable string×step grid.
  Widget _grid() {
    final n = _doc.stringCount;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Chord-name header aligned above the columns.
          Row(
            children: [
              const SizedBox(width: 40),
              for (int c = 0; c < _doc.columns.length; c++)
                SizedBox(
                  width: 34,
                  child: Text(
                    _doc.columns[c].chord?.name ?? '',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          for (int s = 0; s < n; s++)
            Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    _doc.tuning.strings[s].toString().toUpperCase(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                for (int c = 0; c < _doc.columns.length; c++) _cell(c, s),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(int col, int string) {
    final fret = _doc.columns[col].frets[string];
    final selected = col == _selCol && string == _selString;
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => selectCell(col, string),
      child: Container(
        width: 32,
        height: 30,
        margin: const EdgeInsets.all(1),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          fret?.toString() ?? '·',
          style: TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            color: fret == null ? scheme.onSurfaceVariant : scheme.onSurface,
          ),
        ),
      ),
    );
  }

  /// Duration palette + fret keypad + column add/remove.
  Widget _editorPanel(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(l10n.tabDuration),
              for (final (dur, steps) in kTabDurations)
                ChoiceChip(
                  label: Text(_durLabel(steps)),
                  selected: _dur == dur,
                  onSelected: (_) => setState(() {
                    _dur = dur;
                    _doc.setDuration(_selCol, dur);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (int f = 0; f <= 12; f++)
                SizedBox(
                  width: 40,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(40, 36),
                    ),
                    onPressed: () => enterFret(f),
                    child: Text('$f'),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.backspace_outlined),
                tooltip: l10n.tabClearCell,
                onPressed: deleteCell,
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                icon: const Icon(Icons.playlist_add),
                tooltip: l10n.tabAddColumn,
                onPressed: addColumn,
              ),
              IconButton.filledTonal(
                icon: const Icon(Icons.playlist_remove),
                tooltip: l10n.tabRemoveColumn,
                onPressed: removeColumnAtCursor,
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.grid_goldenratio, size: 18),
                label: Text(l10n.tabChord),
                onPressed: _pickChord,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(l10n.tabTechnique),
              for (final t in TabTechnique.values)
                FilterChip(
                  label: Text(_techLabel(l10n, t)),
                  selected: _selCol < _doc.columns.length &&
                      _doc.columns[_selCol].techniques.contains(t),
                  onSelected: (_) => toggleTechnique(t),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// A bottom-sheet grid of guitar chord diagrams; picking one attaches it to
  /// the selected column (or clears it).
  Future<void> _pickChord() async {
    final l10n = AppLocalizations.of(context)!;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.tabChordPick,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final entry in kGuitarChords.entries)
                    InkWell(
                      onTap: () => Navigator.of(ctx).pop(entry.key),
                      child: ChordDiagramView(entry.value),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.clear),
                label: Text(l10n.tabChordNone),
                onPressed: () => Navigator.of(ctx).pop(''),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    setChordByName(picked.isEmpty ? null : picked);
  }

  String _techLabel(AppLocalizations l10n, TabTechnique t) => switch (t) {
        TabTechnique.hammer => l10n.tabTechHammer,
        TabTechnique.slide => l10n.tabTechSlide,
        TabTechnique.bend => l10n.tabTechBend,
        TabTechnique.dead => l10n.tabTechDead,
        TabTechnique.ghost => l10n.tabTechGhost,
        TabTechnique.harmonic => l10n.tabTechHarmonic,
      };

  String _durLabel(int steps) => switch (steps) {
        8 => '𝅝',
        6 => '𝅗𝅥.',
        4 => '𝅗𝅥',
        3 => '♩.',
        2 => '♩',
        _ => '♪',
      };
}
