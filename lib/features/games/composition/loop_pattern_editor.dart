// lib/features/games/composition/loop_pattern_editor.dart
//
// The Loop Studio's pattern editor, as ONE overlay over the whole band.
//
// WHY THIS REPLACES THE TWO INLINE CARDS. The old editor was a pair of cards
// (`_buildBeatEditor` / `_buildTuneEditor`) wired to a hardcoded list of five
// track ids and a hardcoded one-octave C-pentatonic row grid. It showed an
// EMPTY GRID for most parts most of the time, for four independent reasons —
// each of which is fixed here, and each of which is worth stating because they
// are the kind of bug that reads to a user as "the editor is broken" rather
// than as four separate defects:
//
//   1. It seeded from `LoopEngine.cellsFor`, which in progression mode returns
//      the four-bar RESOLVED shape, then rejected anything whose length was not
//      exactly `kPatternSteps`. A progression is the normal state of a Loop
//      Studio groove, so melody/chords/bass were blank almost always. Here the
//      seed falls back through override → authored → the first bar-pair of the
//      resolved shape, so there is always something real to edit.
//   2. Chord-FOLLOWER tracks (chords, bass) carry no `MelodicPattern` at all,
//      so there was nothing 2-bar to find even in principle. They now seed from
//      what they actually sound, and say plainly that editing pins them.
//   3. The pitch rows were fixed at C4..C5 (or C6). A bass part lives an octave
//      or more below that, and `StepGridView` snaps to the NEAREST row, so
//      every bass note collapsed onto the bottom lane — present, but unreadable
//      and untouchable. Rows are now fitted to the notes that are actually
//      there.
//   4. The beat grid drew three lanes (kick/snare/hat) out of a twelve-voice
//      `Drum` enum. Any pattern using clap/tom/ride/crash was editing rows it
//      could not draw. Every lane the pattern uses is now shown.
//
// THE DATA CONTRACT IS UNCHANGED, DELIBERATELY. Cells are authored in C and the
// engine's `pitchTranspose` shifts them into the current key/scale at render
// time. This editor keeps authoring in C — it does NOT write sounding pitches —
// because every other producer of cells (capture, share tokens, the built-in
// stems) does the same, and a grid that wrote sounding pitch would desync from
// all of them the moment the key changed. What Precise mode adds is a READOUT
// of the sounding pitch, which is the part the user actually wanted to see.
//
// PRECISE IS A LENS, NOT A MODE SWITCH. Simple and Precise edit the same cells
// with the same gestures; Precise only adds information (note names, lengths,
// velocity, bar/beat) and finer rows. Nothing is only reachable in one of them,
// so a user can leave it on or off without losing a capability.

import 'dart:math';

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/synth.dart' show Drum, Instrument;
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/music/drum_labels.dart';
import 'package:comet_beat/shared/widgets/step_grid.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

/// How a pitched target's cells were obtained, which is what decides whether
/// editing it is lossless or pins a chord-following part to fixed notes.
enum LoopPatternSeed {
  /// The track already carries a user override — editing continues it.
  override,

  /// The track's own authored 2-bar pattern.
  authored,

  /// The first bar-pair of a longer or chord-resolved shape. Editing this
  /// REPLACES the following behaviour, so the UI warns.
  resolved,

  /// Nothing to seed from — a genuinely empty part (the user track before
  /// anything is sung or tapped).
  empty,
}

/// One editable target: a track the editor can open, and what kind it is.
class LoopEditTarget {
  const LoopEditTarget({
    required this.id,
    required this.label,
    required this.percussive,
  });

  final String id;
  final String label;
  final bool percussive;
}

/// The pitched cells to edit for [id], plus where they came from.
///
/// The fallback chain is the whole point: an override is the user's own work
/// and always wins; an authored pattern is the track's real content; and a
/// resolved shape is what the track SOUNDS even when it has no 2-bar pattern of
/// its own. Only when all three are absent is the grid legitimately empty.
({List<PatternCell> cells, LoopPatternSeed seed}) seedCellsFor(
  LoopEngine engine,
  String id,
) {
  final override = engine.trackCellsOverride(id);
  if (override != null && override.isNotEmpty) {
    return (cells: List.of(override), seed: LoopPatternSeed.override);
  }
  if (id == LoopEngine.userTrackId) {
    final own = engine.userTrackCells;
    if (own != null && own.isNotEmpty) {
      return (cells: List.of(own), seed: LoopPatternSeed.authored);
    }
    return (cells: const [], seed: LoopPatternSeed.empty);
  }
  final sounding = engine.cellsFor(id);
  if (sounding == null || sounding.isEmpty) {
    return (cells: const [], seed: LoopPatternSeed.empty);
  }
  final total = sounding.fold<int>(0, (a, c) => a + c.steps);
  if (total == kPatternSteps) {
    return (cells: List.of(sounding), seed: LoopPatternSeed.authored);
  }
  // Longer than one editable bar-pair (a progression tiles a stem across four
  // bars): take the first kPatternSteps' worth. Truncating mid-cell is fine —
  // the cell is shortened, not dropped, so nothing vanishes from the grid.
  final head = <PatternCell>[];
  var pos = 0;
  for (final c in sounding) {
    if (pos >= kPatternSteps) break;
    final room = kPatternSteps - pos;
    head.add(
      c.steps <= room
          ? c
          : PatternCell(midis: c.midis, steps: room, velocity: c.velocity),
    );
    pos += c.steps;
  }
  return (cells: head, seed: LoopPatternSeed.resolved);
}

/// The MIDI rows the pitched grid should draw for [cells].
///
/// Built from the authored-C pentatonic collection so a tap always lands on a
/// consonant degree, but over the octave span the cells ACTUALLY occupy rather
/// than a fixed C4..C5 — that fixed window is what made bass parts invisible.
/// Any pitch present that is not on the pentatonic grid (a chord voicing can
/// resolve a minor third, which is not in `{0,2,4,7,9}`) is added as its own
/// row, so the editor never draws a note onto a lane that is not its own.
///
/// [chromatic] widens the grid to every semitone in range — the Precise lens,
/// for a user who wants exact placement rather than a scale-locked one.
///
/// [extraOctaves] pads the fitted range above AND below, which is what the
/// "wide range" toggle now means. Fitting alone can only show notes that are
/// already there; padding is how a part gets somewhere new to go.
List<int> pitchRowsFor(
  List<PatternCell> cells, {
  bool chromatic = false,
  int extraOctaves = 0,
  int fallbackLow = 60,
  int fallbackHigh = 72,
}) {
  final present = <int>{
    for (final c in cells) ...?c.midis,
  };
  var lo = present.isEmpty ? fallbackLow : present.reduce(min);
  var hi = present.isEmpty ? fallbackHigh : present.reduce(max);
  // Always give at least an octave of room, and a little headroom above and
  // below what is there so a melody can be moved without re-fitting the grid.
  // Widen around the CENTRE so a one-note part does not sit on the very edge.
  final span = hi - lo;
  if (span < 12) {
    final short = 12 - span;
    lo -= short ~/ 2;
    hi += short - short ~/ 2;
  }
  lo = (lo - 2 - 12 * extraOctaves).clamp(0, 127);
  hi = (hi + 2 + 12 * extraOctaves).clamp(0, 127);
  if (chromatic) {
    return [for (var m = lo; m <= hi; m++) m];
  }
  const pentatonic = {0, 2, 4, 7, 9};
  final rows = <int>{
    for (var m = lo; m <= hi; m++)
      if (pentatonic.contains(((m % 12) + 12) % 12)) m,
    ...present, // never hide a note that exists
  };
  final sorted = rows.toList()..sort();
  return sorted;
}

/// The drum lanes to draw for [pattern].
///
/// Every lane the pattern uses, in the enum's own order so the kit reads
/// consistently, plus kick/snare/hat as a floor so an empty drum track still
/// offers the three lanes a beat is usually built from. The old editor drew
/// exactly those three and nothing else, which silently hid every clap, tom,
/// ride and crash a built-in style places.
List<Drum> drumLanesFor(DrumRowsPattern? pattern) {
  final used = <Drum>{
    Drum.kick,
    Drum.snare,
    Drum.hat,
    if (pattern != null)
      for (final e in pattern.rows.entries)
        if (e.value.any((h) => h)) e.key,
  };
  return [
    for (final d in Drum.values)
      if (used.contains(d)) d,
  ];
}

/// The sounding name of authored-C [midi] once the engine's key/scale shift is
/// applied — what Precise mode reports, so the readout matches what is heard.
String soundingNoteName(int midi, int transpose) {
  const names = [
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
  final sounding = (midi + transpose).clamp(0, 127);
  return '${names[sounding % 12]}${(sounding ~/ 12) - 1}';
}

/// A step index as a musical position, 1-based, on the eighth-note loop grid.
String barBeatOf(int step) {
  final bar = step ~/ LoopTiming.stepsPerBar;
  final within = step % LoopTiming.stepsPerBar;
  final beat = within ~/ 2;
  final off = within.isOdd;
  return '${bar + 1}.${beat + 1}${off ? '+' : ''}';
}

/// A note length in eighth-steps, named the way it is written.
String noteLengthLabel(int steps) => switch (steps) {
      1 => '♪',
      2 => '♩',
      3 => '♩.',
      4 => '𝅗𝅥',
      6 => '𝅗𝅥.',
      8 => '𝅝',
      _ => '$steps⁄8',
    };

/// The note lengths a tap cycles through, in eighth-steps: 1/8 · 1/4 · 1/2.
const kLoopNoteLengths = [1, 2, 4, 8];

/// A soft note's velocity — accent parity with the Beginner Tracker's "soft".
const kLoopSoftVelocity = 0.45;

// ---------------------------------------------------------------------------
// The overlay
// ---------------------------------------------------------------------------

/// Opens the pattern editor over the current screen.
///
/// A full-screen route rather than a bottom sheet: the grid wants the width, and
/// a half-height sheet is what forced the old inline editors down to three drum
/// lanes and one octave in the first place.
Future<void> showLoopPatternEditor(
  BuildContext context, {
  required LoopEngine engine,
  required String initialTrackId,
  required String Function(String id) labelOf,
  required VoidCallback onChanged,
  ValueListenable<int>? playStep,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => LoopPatternEditorScreen(
        engine: engine,
        initialTrackId: initialTrackId,
        labelOf: labelOf,
        onChanged: onChanged,
        playStep: playStep,
      ),
    ),
  );
}

class LoopPatternEditorScreen extends StatefulWidget {
  const LoopPatternEditorScreen({
    super.key,
    required this.engine,
    required this.initialTrackId,
    required this.labelOf,
    required this.onChanged,
    this.playStep,
  });

  final LoopEngine engine;
  final String initialTrackId;
  final String Function(String id) labelOf;

  /// Called after every write so the host can re-render and re-swap the loop.
  final VoidCallback onChanged;
  final ValueListenable<int>? playStep;

  @override
  State<LoopPatternEditorScreen> createState() =>
      _LoopPatternEditorScreenState();
}

class _LoopPatternEditorScreenState extends State<LoopPatternEditorScreen> {
  late String _trackId = widget.initialTrackId;
  bool _precise = false;

  /// The last cell touched — what the Precise readout describes. Null until the
  /// user touches something, so the readout never invents a selection.
  ({int row, int step})? _touched;

  LoopEngine get _engine => widget.engine;

  /// Every track the editor can open, pitched or percussive.
  ///
  /// Derived from the engine rather than the old hardcoded five-id list, so an
  /// added or captured track is editable like any other — that list was why
  /// "my own track" had no way in.
  List<LoopEditTarget> get _targets => [
        for (final t in _engine.tracks)
          LoopEditTarget(
            id: t.id,
            label: widget.labelOf(t.id),
            percussive: _isPercussive(t.id),
          ),
      ];

  bool _isPercussive(String id) =>
      id == LoopEngine.beatTrackId || _engine.drumRowsFor(id) != null;

  LoopEditTarget get _target => _targets.firstWhere(
        (t) => t.id == _trackId,
        orElse: () => LoopEditTarget(
          id: _trackId,
          label: widget.labelOf(_trackId),
          percussive: false,
        ),
      );

  void _commit(VoidCallback write) {
    setState(write);
    widget.onChanged();
  }

  // --- pitched ---------------------------------------------------------------

  ({List<PatternCell> cells, LoopPatternSeed seed}) get _seed =>
      seedCellsFor(_engine, _trackId);

  /// The seeded cells flattened to one entry per sounding pitch per onset.
  List<StepNote> _notes() {
    final out = <StepNote>[];
    var pos = 0;
    for (final c in _seed.cells) {
      for (final m in c.midis ?? const <int>[]) {
        out.add(StepNote(m, pos, len: c.steps, velocity: c.velocity));
      }
      pos += c.steps;
    }
    return out;
  }

  /// Notes → the engine's cell run. Rests bridge the gaps; a note never
  /// overruns the following onset or the grid end.
  List<PatternCell> _toCells(List<StepNote> notes) {
    final midisAt = <int, List<int>>{};
    final velAt = <int, double>{};
    final lenAt = <int, int>{};
    for (final n in notes) {
      if (n.step < 0 || n.step >= kPatternSteps) continue;
      (midisAt[n.step] ??= []).add(n.row);
      velAt[n.step] = n.velocity;
      lenAt[n.step] = max(lenAt[n.step] ?? 1, n.len);
    }
    final onsets = midisAt.keys.toList()..sort();
    final out = <PatternCell>[];
    var pos = 0;
    for (var i = 0; i < onsets.length; i++) {
      final onset = onsets[i];
      if (onset > pos) out.add(PatternCell(steps: onset - pos));
      final next = i + 1 < onsets.length ? onsets[i + 1] : kPatternSteps;
      out.add(
        PatternCell(
          midis: midisAt[onset],
          steps: (lenAt[onset] ?? 1).clamp(1, next - onset),
          velocity: velAt[onset] ?? 1.0,
        ),
      );
      pos = onset + out.last.steps;
    }
    if (pos < kPatternSteps) out.add(PatternCell(steps: kPatternSteps - pos));
    return out;
  }

  void _writeNotes(List<StepNote> notes) {
    final cells = notes.isEmpty ? <PatternCell>[] : _toCells(notes);
    _commit(() {
      if (_trackId == LoopEngine.userTrackId) {
        if (notes.isEmpty) {
          _engine.clearUserTrack();
        } else {
          _engine.setUserTrack(cells, instrument: Instrument.musicBox);
          _engine.enabled.add(LoopEngine.userTrackId);
        }
      } else {
        _engine.setTrackCells(_trackId, cells);
        if (notes.isNotEmpty) _engine.enabled.add(_trackId);
      }
    });
  }

  /// How far a note at [step] may grow before it meets the next onset.
  int _growCap(List<StepNote> notes, int step) {
    var next = kPatternSteps;
    for (final n in notes) {
      if (n.step > step && n.step < next) next = n.step;
    }
    return min(kLoopNoteLengths.last, next - step);
  }

  /// Tap: place a note, or grow one already there (1/8 → 1/4 → 1/2 → whole),
  /// or clear it once it cannot grow further. Length editing with no extra
  /// controls — the same gesture the old tune grid used, kept deliberately.
  void _tapPitch(int midi, int step) {
    final notes = _notes();
    final i = notes.indexWhere((n) => n.row == midi && n.step == step);
    final next = [...notes];
    if (i < 0) {
      next.add(StepNote(midi, step, len: kLoopNoteLengths.first));
    } else {
      final cur = notes[i];
      final cap = _growCap(notes, step);
      final grown = kLoopNoteLengths.firstWhere(
        (t) => t > cur.len && t <= cap,
        orElse: () => -1,
      );
      if (grown < 0) {
        next.removeAt(i);
      } else {
        next[i] = StepNote(
          cur.row,
          cur.step,
          len: grown,
          velocity: cur.velocity,
        );
      }
    }
    _touched = (row: midi, step: step);
    _writeNotes(next);
  }

  /// Long-press: cycle the whole time-slice's dynamics soft ↔ normal.
  void _holdPitch(int midi, int step) {
    final notes = _notes();
    final atStep = notes.where((n) => n.step == step);
    if (atStep.isEmpty) return;
    final vel = atStep.first.velocity >= 1.0 ? kLoopSoftVelocity : 1.0;
    _touched = (row: midi, step: step);
    _writeNotes([
      for (final n in notes)
        if (n.step == step)
          StepNote(n.row, n.step, len: n.len, velocity: vel)
        else
          n,
    ]);
  }

  // --- percussive ------------------------------------------------------------

  DrumRowsPattern? get _drums => _engine.drumRowsFor(_trackId);

  ({Map<Drum, List<bool>> rows, Map<Drum, List<double>> vels}) _drumGrids() {
    final p = _drums;
    final rows = <Drum, List<bool>>{};
    final vels = <Drum, List<double>>{};
    for (final e in p?.rows.entries ?? const <MapEntry<Drum, List<bool>>>[]) {
      final row = List<bool>.filled(kPatternSteps, false);
      final vel = List<double>.filled(kPatternSteps, 1.0);
      final pv = p?.velocities?[e.key];
      for (var i = 0; i < e.value.length && i < kPatternSteps; i++) {
        row[i] = e.value[i];
        if (pv != null && i < pv.length) vel[i] = pv[i];
      }
      rows[e.key] = row;
      vels[e.key] = vel;
    }
    return (rows: rows, vels: vels);
  }

  void _writeDrums(Map<Drum, List<bool>> rows, Map<Drum, List<double>> vels) {
    final ghosted = vels.values.any((r) => r.any((v) => v != 1.0));
    final pattern = DrumRowsPattern(rows, velocities: ghosted ? vels : null);
    _commit(() {
      if (_trackId == LoopEngine.beatTrackId) {
        _engine.setUserBeatTrack(pattern);
        _engine.enabled.add(LoopEngine.beatTrackId);
      } else {
        _engine.setTrackDrums(_trackId, pattern);
        _engine.enabled.add(_trackId);
      }
    });
  }

  void _tapDrum(Drum drum, int step) {
    final g = _drumGrids();
    final lane =
        g.rows.putIfAbsent(drum, () => List<bool>.filled(kPatternSteps, false));
    g.vels.putIfAbsent(drum, () => List<double>.filled(kPatternSteps, 1.0));
    lane[step] = !lane[step];
    if (!lane[step]) g.vels[drum]![step] = 1.0;
    _touched = (row: Drum.values.indexOf(drum), step: step);
    _writeDrums(g.rows, g.vels);
  }

  void _holdDrum(Drum drum, int step) {
    final g = _drumGrids();
    final lane = g.rows[drum];
    if (lane == null || step >= lane.length || !lane[step]) return;
    final vel =
        g.vels.putIfAbsent(drum, () => List<double>.filled(kPatternSteps, 1.0));
    vel[step] = vel[step] >= 1.0 ? kLoopSoftVelocity : 1.0;
    _touched = (row: Drum.values.indexOf(drum), step: step);
    _writeDrums(g.rows, g.vels);
  }

  /// Adds a kit voice the pattern is not using yet, so the extended kit is
  /// reachable instead of only visible when a preset happens to use it.
  Future<void> _addLane() async {
    final l10n = AppLocalizations.of(context)!;
    final shown = drumLanesFor(_drums).toSet();
    final missing = [
      for (final d in Drum.values)
        if (!shown.contains(d)) d,
    ];
    if (missing.isEmpty) return;
    final picked = await showModalBottomSheet<Drum>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final d in missing)
              ListTile(
                dense: true,
                leading: const Icon(Icons.graphic_eq),
                title: Text(drumLabel(l10n, d)),
                onTap: () => Navigator.of(ctx).pop(d),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _extraLanes.add(picked));
  }

  /// Lanes the user asked for that carry no hit yet. Held in the widget rather
  /// than the pattern because an all-silent lane is not part of the document —
  /// `setTrackDrums` would drop it, and re-adding it on every rebuild would
  /// make the pattern grow forever.
  final Set<Drum> _extraLanes = {};

  List<Drum> get _lanes {
    final base = drumLanesFor(_drums).toSet()..addAll(_extraLanes);
    return [
      for (final d in Drum.values)
        if (base.contains(d)) d,
    ];
  }

  // --- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final target = _target;
    return Scaffold(
      appBar: AppBar(
        title: Text(target.label),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment<bool>(
                  value: false,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: Text(l10n.loopEditorSimple),
                ),
                ButtonSegment<bool>(
                  value: true,
                  icon: const Icon(Icons.straighten, size: 18),
                  label: Text(l10n.loopEditorPrecise),
                ),
              ],
              selected: {_precise},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => _precise = v.first),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _trackChips(),
            if (!target.percussive && _seed.seed == LoopPatternSeed.resolved)
              _followerNotice(l10n),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: target.percussive ? _drumGrid(l10n) : _pitchGrid(l10n),
              ),
            ),
            _readout(l10n, target),
          ],
        ),
      ),
    );
  }

  Widget _trackChips() => SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          children: [
            for (final t in _targets)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  avatar: Icon(
                    t.percussive ? Icons.album : Icons.music_note,
                    size: 16,
                  ),
                  label: Text(t.label),
                  selected: t.id == _trackId,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() {
                    _trackId = t.id;
                    _touched = null;
                    _extraLanes.clear();
                  }),
                ),
              ),
          ],
        ),
      );

  /// Says plainly that editing a chord-following part pins it. The old editor
  /// simply drew nothing here, which taught the user the part was uneditable
  /// rather than that it was following something.
  Widget _followerNotice(AppLocalizations l10n) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l10n.loopEditorFollowsChords,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      );

  Widget _pitchGrid(AppLocalizations l10n) {
    final notes = _notes();
    final rows = pitchRowsFor(_seed.cells, chromatic: _precise);
    final transpose = _engine.pitchTranspose;
    final rowH = _precise ? 16.0 : 22.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.loopMixerTuneEditHint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The label gutter. Same row order as the painter (top = highest),
            // equal-height rows, so the names line up with the lanes.
            if (_precise)
              SizedBox(
                width: 40,
                height: rows.length * rowH,
                child: Column(
                  children: [
                    for (final m in rows.reversed)
                      SizedBox(
                        height: rowH,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text(
                              soundingNoteName(m, transpose),
                              style: TextStyle(
                                fontSize: 9,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: _withPlayStep(
                (hl) => StepGridView(
                  cells: [
                    for (final n in notes)
                      StepCell(n.row, n.step, len: n.len, velocity: n.velocity),
                  ],
                  steps: kPatternSteps,
                  melodyRows: rows,
                  height: rows.length * rowH,
                  playStep: hl,
                  onToggle: _tapPitch,
                  onLongPress: _holdPitch,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: notes.isEmpty ? null : () => _writeNotes(const []),
              icon: const Icon(Icons.clear, size: 18),
              label: Text(l10n.loopEditorClear),
            ),
          ],
        ),
      ],
    );
  }

  Widget _drumGrid(AppLocalizations l10n) {
    final g = _drumGrids();
    final lanes = _lanes;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.loopMixerBeatEditHint,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        _withPlayStep(
          (hl) => Column(
            children: [
              for (final drum in lanes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 62,
                        child: Text(
                          drumLabel(l10n, drum),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                      for (var s = 0; s < kPatternSteps; s++)
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _tapDrum(drum, s),
                            onLongPress: () => _holdDrum(drum, s),
                            child: Container(
                              height: _precise ? 22 : 28,
                              margin: const EdgeInsets.all(1),
                              decoration: BoxDecoration(
                                color: _drumCellColour(g, drum, s, hl, scheme),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: _addLane,
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.loopEditorAddLane),
            ),
          ],
        ),
      ],
    );
  }

  Color _drumCellColour(
    ({Map<Drum, List<bool>> rows, Map<Drum, List<double>> vels}) g,
    Drum drum,
    int step,
    int? playStep,
    ColorScheme scheme,
  ) {
    final on = (g.rows[drum]?.length ?? 0) > step && g.rows[drum]![step];
    if (on) {
      final v = g.vels[drum]?[step] ?? 1.0;
      return scheme.primary.withValues(alpha: v >= 1.0 ? 1.0 : 0.4 + 0.6 * v);
    }
    if (playStep == step) return scheme.tertiary.withValues(alpha: 0.35);
    return step % 4 == 0
        ? scheme.surfaceContainerHighest
        : scheme.surfaceContainerHigh;
  }

  /// Rebuilds [child] on every playhead step when the host supplies one.
  Widget _withPlayStep(Widget Function(int? step) child) {
    final ls = widget.playStep;
    if (ls == null) return child(null);
    return ValueListenableBuilder<int>(
      valueListenable: ls,
      builder: (_, v, __) => child(v >= 0 ? v % kPatternSteps : null),
    );
  }

  /// The Precise readout. Reports the cell last touched — pitch as it SOUNDS,
  /// its written length, its dynamics, and where it sits in the bar.
  Widget _readout(AppLocalizations l10n, LoopEditTarget target) {
    if (!_precise) return const SizedBox.shrink();
    final t = _touched;
    final scheme = Theme.of(context).colorScheme;
    String text;
    if (t == null) {
      text = l10n.loopEditorPreciseIdle;
    } else if (target.percussive) {
      final drum = Drum.values[t.row.clamp(0, Drum.values.length - 1)];
      final v = _drumGrids().vels[drum]?[t.step] ?? 1.0;
      text = '${drumLabel(l10n, drum)} · ${barBeatOf(t.step)} · '
          '${(v * 100).round()}%';
    } else {
      final n =
          _notes().where((n) => n.row == t.row && n.step == t.step).firstOrNull;
      text = n == null
          ? '${soundingNoteName(t.row, _engine.pitchTranspose)} · '
              '${barBeatOf(t.step)}'
          : '${soundingNoteName(n.row, _engine.pitchTranspose)} · '
              '${noteLengthLabel(n.len)} · ${barBeatOf(n.step)} · '
              '${(n.velocity * 100).round()}%';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      color: scheme.surfaceContainerHighest,
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// One placed note while editing: a MIDI pitch at a step, with a length.
///
/// Deliberately its own type rather than reusing `StepCell`: that one is the
/// grid WIDGET's input, and letting the editor's model be the widget's model is
/// what let the old code write a grid row back as if it were a pattern.
class StepNote {
  const StepNote(this.row, this.step, {this.len = 1, this.velocity = 1.0});
  final int row;
  final int step;
  final int len;
  final double velocity;
}
