// lib/features/games/note_reading/connect_line_screen.dart
//
// "Verbinde die Noten" / "Connect the Notes" — a connect-a-line matching drill
// (docs/PLAN.md gamified backlog, the last of the surveyed interaction
// mechanics). Two columns: a symbol on the left (a note on a real crisp_notation
// staff, or a note-value glyph), its names shuffled down the right. The child
// drags a line from each symbol to its name; a correct link locks in colour
// (and plays the pitch, when there is one), a wrong drop buzzes and snaps back
// (the app's no-fail loop). Match all four to clear the round.
//
// One screen, three modes (like the reading quiz serves several clefs):
//   • notes     — pitch ↔ letter name         → SRI 'note_reading.treble.*'
//   • symbols   — note-value glyph ↔ its name  → SRI 'note_values.symbol.*'
//   • intervals — interval on a staff ↔ its number (count the note-names,
//                 e.g. C→G spans 5) → SRI 'intervals.size.*'
//   • dynamics  — dynamic mark glyph ↔ its meaning (pp ↔ very soft)
//                 → SRI 'reading.dynamics.*' (shared with dynamics_duel)
//   • rests     — rest glyph ↔ the note it equals in length (quarter rest ↔
//                 "quarter note") → SRI 'note_values.rest.*'
//   • tempo     — Italian tempo word ↔ its meaning (Largo ↔ "very slow")
//                 → SRI 'reading.tempo.*' (shared with tempo_duel)
//   • beats     — note-value glyph ↔ how many beats it lasts in 4/4 (half ↔
//                 "2 beats") → SRI 'note_values.beats.*'

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/note_colors.dart';
import 'package:comet_beat/features/games/note_reading/note_names.dart';
import 'package:comet_beat/features/games/note_values/dynamics_duel_screen.dart'
    show kDynamicMarks;
import 'package:comet_beat/features/games/note_values/symbol_catalog.dart';
import 'package:comet_beat/features/games/note_values/tempo_duel_screen.dart'
    show kTempoTerms;
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:comet_beat/shared/widgets/music_glyph.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

/// What the two columns hold.
enum ConnectMode {
  notes,
  symbols,
  intervals,
  dynamics,
  rests,
  tempo,
  beats,
  degrees,
}

/// One matchable item: a left visual, a (unique) right name, a match key, the
/// colour of its wire, the pitch to sound on a correct link (if any), and the
/// SM-2 id it scores into. Names/colours that need context are resolved lazily.
class _ConnectItem {
  _ConnectItem({
    required this.card,
    required this.matchKey,
    required this.sriId,
    required this.playMidi,
    required this.label,
    required this.color,
  });

  final Widget card;
  final String matchKey; // unique within a round
  final String sriId;
  final int? playMidi;
  final String Function(BuildContext) label;
  final Color Function(ColorScheme, bool colorScaffold) color;
}

class ConnectLineScreen extends StatefulWidget {
  const ConnectLineScreen({
    super.key,
    this.mode = ConnectMode.notes,
    this.clef = Clef.treble,
  });

  final ConnectMode mode;

  /// Reading clef for notes mode (symbols mode ignores it).
  final Clef clef;

  /// Pairs to connect per round.
  static const pairs = 4;

  static const _cardW = 92.0;
  static const _chipW = 92.0;
  static const _pad = 12.0;

  /// Key on the drag board, so tests can locate its rect for gestures.
  @visibleForTesting
  static const boardKey = ValueKey('connect_board');

  @override
  State<ConnectLineScreen> createState() => _ConnectLineScreenState();
}

/// Typed window into the game for widget tests (the state class is private).
@visibleForTesting
abstract interface class ConnectLineTester {
  int get score;
  bool get finished;
  int get round;
  int get matchedCount;

  /// The right-column index whose name matches left item [leftIndex].
  int matchingRight(int leftIndex);
}

class _ConnectLineScreenState extends State<ConnectLineScreen>
    with QuizRoundMixin
    implements ConnectLineTester {
  final _random = Random();

  late List<_ConnectItem> _lefts; // symbols, top → bottom
  late List<_ConnectItem> _rights; // the same items, shuffled, shown as names
  final Map<int, int> _matched = {}; // left index → right index (locked)
  final Set<int> _recorded = {}; // left indices already scored into SRI

  int? _dragFrom; // left index being dragged
  Offset? _dragPos; // current finger position (local)

  @override
  int get matchedCount => _matched.length;

  @override
  int matchingRight(int leftIndex) =>
      _rights.indexWhere((r) => r.matchKey == _lefts[leftIndex].matchKey);

  @override
  int get totalRounds => 6;

  // Both modes share the star bracket; progress is tracked per mode.
  @override
  String get gameType => 'connect_line';

  @override
  String get progressId => switch (widget.mode) {
        ConnectMode.symbols => 'connect_symbols',
        ConnectMode.intervals => 'connect_intervals',
        ConnectMode.dynamics => 'connect_dynamics',
        ConnectMode.rests => 'connect_rests',
        ConnectMode.tempo => 'connect_tempo',
        ConnectMode.beats => 'connect_beats',
        ConnectMode.degrees => 'connect_degrees',
        ConnectMode.notes =>
          widget.clef == Clef.bass ? 'connect_line_bass' : 'connect_line',
      };

  // We play each linked note's own pitch (and a buzz on a miss).
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    final items = switch (widget.mode) {
      ConnectMode.symbols => _symbolItems(),
      ConnectMode.intervals => _intervalItems(),
      ConnectMode.dynamics => _dynamicsItems(),
      ConnectMode.rests => _restItems(),
      ConnectMode.tempo => _tempoItems(),
      ConnectMode.beats => _beatItems(),
      ConnectMode.degrees => _degreeItems(),
      ConnectMode.notes => _noteItems(),
    };
    _lefts = items;
    _rights = [...items]..shuffle(_random);
    _matched.clear();
    _recorded.clear();
    _dragFrom = null;
    _dragPos = null;
  }

  // --- Content ---------------------------------------------------------------

  List<_ConnectItem> _noteItems() {
    // Four notes with *distinct* step letters, so every name on the right is
    // unique. Star-driven width like the reading quizzes: naturals on the
    // staff → the middle-C ledger neighbourhood.
    final wide = context.read<ProgressService>().starsFor(progressId) >= 2;
    final pool = [for (var p = wide ? -3 : 0; p <= (wide ? 10 : 8); p++) p]
      ..shuffle(_random);

    final picked = <Pitch>[];
    final usedSteps = <Step>{};
    for (final p in pool) {
      final pitch = widget.clef.pitchAt(p);
      if (usedSteps.add(pitch.step)) {
        picked.add(pitch);
        if (picked.length == ConnectLineScreen.pairs) break;
      }
    }

    return [
      for (final pitch in picked)
        _ConnectItem(
          card: StaffView(
            score: Score.simple(
              clef: widget.clef,
              notes: '${pitch.step.name}${pitch.octave}:w',
            ),
            staffSpace: 7,
            theme: kidsScoreTheme,
          ),
          matchKey: pitch.step.name,
          sriId: 'note_reading.${widget.clef.name}.'
              '${pitch.step.name}${pitch.octave}',
          playMidi: pitch.midiNumber,
          label: (ctx) => noteNameFor(ctx, pitch.step),
          color: (scheme, colorScaffold) =>
              colorScaffold ? pitchClassColor(pitch.step) : scheme.secondary,
        ),
    ];
  }

  List<_ConnectItem> _symbolItems() {
    // Whole/half/quarter/eighth notes for beginners; rests + sixteenths join at
    // two stars. Distinct symbols → distinct names.
    final wide = context.read<ProgressService>().starsFor(progressId) >= 2;
    final pool = [...(wide ? kNoteSymbols : kNoteSymbols.take(4))]
      ..shuffle(_random);
    final picked = pool.take(ConnectLineScreen.pairs).toList();

    return [
      for (var i = 0; i < picked.length; i++)
        _ConnectItem(
          card: MusicGlyph(picked[i].glyph, size: 46),
          matchKey: picked[i].id,
          sriId: picked[i].sriId,
          playMidi: null,
          label: (ctx) => picked[i].label(AppLocalizations.of(ctx)!),
          color: (_, __) => _symbolPalette[i % _symbolPalette.length],
        ),
    ];
  }

  List<_ConnectItem> _intervalItems() {
    // Four distinct interval *numbers*: a 2nd spans two note-names, a 5th spans
    // five, an octave eight. The child counts note-names bottom→top and matches
    // the interval to its number. Quality (major/minor/perfect) is ignored —
    // this is the "how far?" skill: diatonic steps on the staff. Two half-notes
    // side by side read left→right, low then high. Sixths/sevenths join at 2★.
    final wide = context.read<ProgressService>().starsFor(progressId) >= 2;
    final pool = (wide ? const [2, 3, 4, 5, 6, 7, 8] : const [2, 3, 4, 5])
        .toList()
      ..shuffle(_random);
    final picked = pool.take(ConnectLineScreen.pairs).toList();

    return [
      for (var k = 0; k < picked.length; k++)
        _intervalItem(picked[k], _symbolPalette[k % _symbolPalette.length]),
    ];
  }

  _ConnectItem _intervalItem(int ordinal, Color color) {
    final steps = ordinal - 1; // diatonic staff positions between the two notes
    // Keep the bottom low enough that the top stays on/just above the staff.
    final maxBottom = 9 - steps;
    final bottomPos = -1 + _random.nextInt(maxBottom + 2);
    final bottom = widget.clef.pitchAt(bottomPos);
    final top = widget.clef.pitchAt(bottomPos + steps);
    return _ConnectItem(
      card: StaffView(
        score: Score.simple(
          clef: widget.clef,
          notes: '${bottom.step.name}${bottom.octave}:h '
              '${top.step.name}${top.octave}:h',
        ),
        staffSpace: 7,
        theme: kidsScoreTheme,
      ),
      matchKey: '$ordinal',
      sriId: 'intervals.size.$ordinal',
      playMidi: top.midiNumber,
      label: (_) => '$ordinal',
      color: (_, __) => color,
    );
  }

  List<_ConnectItem> _dynamicsItems() {
    // Dynamic marks paired with their meaning word. Four clear steps for
    // beginners (pp / p / f / ff → very soft … very loud); the two "medium"
    // marks (mp / mf) join at 2★, where the softer/louder shades get subtler.
    final wide = context.read<ProgressService>().starsFor(progressId) >= 2;
    final pool = [
      for (final m in kDynamicMarks)
        if (wide || (m.name != 'mp' && m.name != 'mf')) m,
    ]..shuffle(_random);
    final picked = pool.take(ConnectLineScreen.pairs).toList();

    return [
      for (var i = 0; i < picked.length; i++)
        _ConnectItem(
          card: MusicGlyph(String.fromCharCode(picked[i].code), size: 40),
          matchKey: picked[i].name,
          sriId: 'reading.dynamics.${picked[i].name}',
          playMidi: null,
          label: (ctx) =>
              _dynMeaning(AppLocalizations.of(ctx)!, picked[i].name),
          color: (_, __) => _symbolPalette[i % _symbolPalette.length],
        ),
    ];
  }

  static String _dynMeaning(AppLocalizations l10n, String name) =>
      switch (name) {
        'pp' => l10n.dynVerySoft,
        'p' => l10n.dynSoft,
        'mp' => l10n.dynMediumSoft,
        'mf' => l10n.dynMediumLoud,
        'f' => l10n.dynLoud,
        _ => l10n.dynVeryLoud, // 'ff'
      };

  List<_ConnectItem> _restItems() {
    // Each rest paired with the note it equals in length. Whole/half/quarter/
    // eighth rests for beginners; the sixteenth rest joins at 2★.
    final wide = context.read<ProgressService>().starsFor(progressId) >= 2;
    final rests = [
      for (final s in kNoteSymbols)
        if (s.id.endsWith('_rest') && (wide || s.id != 'sixteenth_rest')) s,
    ]..shuffle(_random);
    final picked = rests.take(ConnectLineScreen.pairs).toList();

    return [
      for (var i = 0; i < picked.length; i++)
        _restItem(picked[i], _symbolPalette[i % _symbolPalette.length]),
    ];
  }

  _ConnectItem _restItem(NoteSymbol rest, Color color) {
    // 'quarter_rest' → base 'quarter' → the 'quarter_note' whose name we show.
    final base = rest.id.replaceAll('_rest', '');
    final note = kNoteSymbols.firstWhere((s) => s.id == '${base}_note');
    return _ConnectItem(
      card: MusicGlyph(rest.glyph, size: 40),
      matchKey: base,
      sriId: 'note_values.rest.$base',
      playMidi: null,
      label: (ctx) => note.label(AppLocalizations.of(ctx)!),
      color: (_, __) => color,
    );
  }

  List<_ConnectItem> _tempoItems() {
    // Italian tempo word paired with its meaning. Four clear terms for
    // beginners (Largo / Adagio / Allegro / Presto → very slow … very fast);
    // the middle terms (Andante / Moderato / Vivace) join at 2★.
    const easy = {'Largo', 'Adagio', 'Allegro', 'Presto'};
    final wide = context.read<ProgressService>().starsFor(progressId) >= 2;
    final pool = [
      for (final t in kTempoTerms)
        if (wide || easy.contains(t.name)) t,
    ]..shuffle(_random);
    final picked = pool.take(ConnectLineScreen.pairs).toList();

    return [
      for (var i = 0; i < picked.length; i++)
        _ConnectItem(
          card: Text(
            picked[i].name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              fontStyle: FontStyle.italic,
            ),
          ),
          matchKey: picked[i].name,
          sriId: 'reading.tempo.${picked[i].name}',
          playMidi: null,
          label: (ctx) =>
              _tempoMeaning(AppLocalizations.of(ctx)!, picked[i].name),
          color: (_, __) => _symbolPalette[i % _symbolPalette.length],
        ),
    ];
  }

  static String _tempoMeaning(AppLocalizations l10n, String name) =>
      switch (name) {
        'Largo' => l10n.tempoVerySlow,
        'Adagio' => l10n.tempoSlow,
        'Andante' => l10n.tempoWalking,
        'Moderato' => l10n.tempoModerate,
        'Allegro' => l10n.tempoFast,
        'Vivace' => l10n.tempoLively,
        _ => l10n.tempoVeryFast, // 'Presto'
      };

  List<_ConnectItem> _degreeItems() {
    // Match a scale-degree number to its name, and hear the degree in C major.
    // The four functional pillars for beginners (1 tonic, 4 subdominant,
    // 5 dominant, 7 leading tone); the colour tones (2, 3, 6) join at 2★.
    const pillars = {1, 4, 5, 7};
    // (degree, C-major midi): 1=C4 … 7=B4.
    const midi = {1: 60, 2: 62, 3: 64, 4: 65, 5: 67, 6: 69, 7: 71};
    final wide = context.read<ProgressService>().starsFor(progressId) >= 2;
    final pool = [
      for (var d = 1; d <= 7; d++)
        if (wide || pillars.contains(d)) d,
    ]..shuffle(_random);
    final picked = pool.take(ConnectLineScreen.pairs).toList();

    return [
      for (var i = 0; i < picked.length; i++)
        _ConnectItem(
          card: Text(
            '${picked[i]}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          matchKey: 'degree${picked[i]}',
          sriId: 'harmony.degree.${picked[i]}',
          playMidi: midi[picked[i]],
          label: (ctx) => _degreeName(AppLocalizations.of(ctx)!, picked[i]),
          color: (_, __) => _symbolPalette[i % _symbolPalette.length],
        ),
    ];
  }

  static String _degreeName(AppLocalizations l10n, int degree) =>
      switch (degree) {
        1 => l10n.degreeTonic,
        2 => l10n.degreeSupertonic,
        3 => l10n.degreeMediant,
        4 => l10n.degreeSubdominant,
        5 => l10n.degreeDominant,
        6 => l10n.degreeSubmediant,
        _ => l10n.degreeLeadingTone, // 7
      };

  List<_ConnectItem> _beatItems() {
    // Each note-value glyph paired with how many beats it lasts in 4/4:
    // whole = 4, half = 2, quarter = 1, eighth = ½. Whole/half/quarter/eighth
    // for beginners; the sixteenth (¼ beat) joins at 2★.
    final wide = context.read<ProgressService>().starsFor(progressId) >= 2;
    final notes = [
      for (final s in kNoteSymbols)
        if (s.id.endsWith('_note') && (wide || s.id != 'sixteenth_note')) s,
    ]..shuffle(_random);
    final picked = notes.take(ConnectLineScreen.pairs).toList();

    return [
      for (var i = 0; i < picked.length; i++)
        _ConnectItem(
          card: MusicGlyph(picked[i].glyph, size: 40),
          matchKey: picked[i].id.replaceAll('_note', ''),
          sriId: 'note_values.beats.${picked[i].id.replaceAll('_note', '')}',
          playMidi: null,
          label: (ctx) => _beatLabel(AppLocalizations.of(ctx)!, picked[i].id),
          color: (_, __) => _symbolPalette[i % _symbolPalette.length],
        ),
    ];
  }

  static String _beatLabel(AppLocalizations l10n, String noteId) =>
      switch (noteId) {
        'whole_note' => l10n.beatCount4,
        'half_note' => l10n.beatCount2,
        'quarter_note' => l10n.beatCount1,
        'eighth_note' => l10n.beatCountHalf,
        _ => l10n.beatCountQuarter, // 'sixteenth_note'
      };

  static const _symbolPalette = [
    Color(0xFF3949AB), // indigo
    Color(0xFF00897B), // teal
    Color(0xFFF9A825), // amber
    Color(0xFFD81B60), // pink
  ];

  // --- Linking ---------------------------------------------------------------

  void _tryConnect(int leftIndex, int rightIndex) {
    final left = _lefts[leftIndex];
    final correct = left.matchKey == _rights[rightIndex].matchKey;

    // Score the read into SM-2 on the first attempt for this item.
    if (_recorded.add(leftIndex)) {
      context.read<SriService>().recordResponse(left.sriId, correct);
    }

    if (correct) {
      final midi = left.playMidi;
      if (midi != null) {
        context.read<AudioService>().playMidiNote(midi, ms: 450);
      } else {
        context.read<AudioService>().playCorrect();
      }
      setState(() => _matched[leftIndex] = rightIndex);
      if (_matched.length == ConnectLineScreen.pairs) {
        resolveAnswer(correct: true); // round cleared
      }
    } else {
      context.read<AudioService>().playWrong();
      setState(() => answeredWrong = true);
    }
  }

  // --- Gesture → anchors (row bands, forgiving for small hands) --------------

  void _onPanStart(Offset local, Size size) {
    final rowH = size.height / ConnectLineScreen.pairs;
    final i = (local.dy ~/ rowH).clamp(0, ConnectLineScreen.pairs - 1);
    if (local.dx < size.width / 2 && !_matched.containsKey(i)) {
      setState(() {
        _dragFrom = i;
        _dragPos = local;
      });
    }
  }

  void _onPanUpdate(Offset local) {
    if (_dragFrom != null) setState(() => _dragPos = local);
  }

  void _onPanEnd(Size size) {
    final from = _dragFrom;
    final pos = _dragPos;
    if (from != null && pos != null) {
      final rowH = size.height / ConnectLineScreen.pairs;
      final j = (pos.dy ~/ rowH).clamp(0, ConnectLineScreen.pairs - 1);
      final rightTaken = _matched.values.contains(j);
      if (pos.dx > size.width / 2 && !rightTaken) {
        _tryConnect(from, j);
      }
    }
    setState(() {
      _dragFrom = null;
      _dragPos = null;
    });
  }

  // --- UI --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScaffold = context.watch<SettingsService>().colorScaffold;
    final title = switch (widget.mode) {
      ConnectMode.symbols => l10n.gameConnectSymbols,
      ConnectMode.intervals => l10n.gameConnectIntervals,
      ConnectMode.dynamics => l10n.gameConnectDynamics,
      ConnectMode.rests => l10n.gameConnectRests,
      ConnectMode.tempo => l10n.gameConnectTempo,
      ConnectMode.beats => l10n.gameConnectBeats,
      ConnectMode.degrees => l10n.gameConnectDegrees,
      ConnectMode.notes => l10n.gameConnectLine,
    };
    final prompt = switch (widget.mode) {
      ConnectMode.symbols => l10n.connectSymbolsPrompt,
      ConnectMode.intervals => l10n.connectIntervalsPrompt,
      ConnectMode.dynamics => l10n.connectDynamicsPrompt,
      ConnectMode.rests => l10n.connectRestsPrompt,
      ConnectMode.tempo => l10n.connectTempoPrompt,
      ConnectMode.beats => l10n.connectBeatsPrompt,
      ConnectMode.degrees => l10n.connectDegreesPrompt,
      ConnectMode.notes => l10n.connectLinePrompt,
    };

    return Scaffold(
      appBar: GameAppBar(
        title: title,
      ),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: gameType,
                score: score,
                onRestart: restartGame,
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    RoundHeader(
                      correct: _matched.length == ConnectLineScreen.pairs
                          ? true
                          : (answeredWrong ? false : null),
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: prompt,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      // Keep the two columns close together, not pinned to the
                      // screen edges on wide/web layouts.
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final size = constraints.biggest;
                              return _buildBoard(context, size, colorScaffold);
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FeedbackLine(
                      correct: _matched.length == ConnectLineScreen.pairs
                          ? true
                          : (answeredWrong ? false : null),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildBoard(BuildContext context, Size size, bool colorScaffold) {
    final scheme = Theme.of(context).colorScheme;
    final rowH = size.height / ConnectLineScreen.pairs;
    const leftPortX = ConnectLineScreen._pad + ConnectLineScreen._cardW;
    final rightPortX =
        size.width - ConnectLineScreen._pad - ConnectLineScreen._chipW;
    final lineColors = [
      for (final it in _lefts) it.color(scheme, colorScaffold),
    ];

    return GestureDetector(
      key: ConnectLineScreen.boardKey,
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) => _onPanStart(d.localPosition, size),
      onPanUpdate: (d) => _onPanUpdate(d.localPosition),
      onPanEnd: (_) => _onPanEnd(size),
      child: Stack(
        children: [
          // Left column: the symbols.
          for (var i = 0; i < _lefts.length; i++)
            Positioned(
              left: ConnectLineScreen._pad,
              top: i * rowH,
              width: ConnectLineScreen._cardW,
              height: rowH,
              child: _ItemCard(
                connected: _matched.containsKey(i),
                active: _dragFrom == i,
                child: _lefts[i].card,
              ),
            ),
          // Right column: the names.
          for (var j = 0; j < _rights.length; j++)
            Positioned(
              right: ConnectLineScreen._pad,
              top: j * rowH,
              width: ConnectLineScreen._chipW,
              height: rowH,
              child: _NameChip(
                label: _rights[j].label(context),
                color: _rights[j].color(scheme, colorScaffold),
                connected: _matched.values.contains(j),
              ),
            ),
          // The lines + ports, drawn on top so a link is always visible.
          Positioned.fill(
            child: CustomPaint(
              painter: _WirePainter(
                pairs: ConnectLineScreen.pairs,
                rowH: rowH,
                leftPortX: leftPortX,
                rightPortX: rightPortX,
                matched: Map.of(_matched),
                lineColors: lineColors,
                dragFrom: _dragFrom,
                dragPos: _dragPos,
                dragColor: scheme.primary,
                portColor: scheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.connected,
    required this.active,
    required this.child,
  });

  final bool connected;
  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = connected
        ? Colors.green
        : active
            ? scheme.primary
            : scheme.outlineVariant;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color:
            connected ? Colors.green.withValues(alpha: 0.10) : scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: border, width: connected || active ? 2.5 : 1.5),
      ),
      child: Center(child: child),
    );
  }
}

class _NameChip extends StatelessWidget {
  const _NameChip({
    required this.label,
    required this.color,
    required this.connected,
  });

  final String label;
  final Color color;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: connected ? 0.85 : 0.22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: connected ? Colors.green : color,
          width: connected ? 2.5 : 1.5,
        ),
      ),
      child: Center(
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: connected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
              ),
        ),
      ),
    );
  }
}

/// Draws the locked links, the in-progress drag line, and the connection ports.
class _WirePainter extends CustomPainter {
  _WirePainter({
    required this.pairs,
    required this.rowH,
    required this.leftPortX,
    required this.rightPortX,
    required this.matched,
    required this.lineColors,
    required this.dragFrom,
    required this.dragPos,
    required this.dragColor,
    required this.portColor,
  });

  final int pairs;
  final double rowH;
  final double leftPortX;
  final double rightPortX;
  final Map<int, int> matched;
  final List<Color> lineColors;
  final int? dragFrom;
  final Offset? dragPos;
  final Color dragColor;
  final Color portColor;

  double _rowCenter(int index) => index * rowH + rowH / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final portStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = portColor;
    final portFill = Paint()..color = portColor.withValues(alpha: 0.35);

    // Ports.
    for (var i = 0; i < pairs; i++) {
      canvas.drawCircle(Offset(leftPortX, _rowCenter(i)), 6, portFill);
      canvas.drawCircle(Offset(leftPortX, _rowCenter(i)), 6, portStroke);
      canvas.drawCircle(Offset(rightPortX, _rowCenter(i)), 6, portFill);
      canvas.drawCircle(Offset(rightPortX, _rowCenter(i)), 6, portStroke);
    }

    // Locked links.
    matched.forEach((i, j) {
      final c = lineColors[i];
      final paint = Paint()
        ..color = c
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      final a = Offset(leftPortX, _rowCenter(i));
      final b = Offset(rightPortX, _rowCenter(j));
      canvas.drawLine(a, b, paint);
      canvas.drawCircle(a, 6, Paint()..color = c);
      canvas.drawCircle(b, 6, Paint()..color = c);
    });

    // The line being dragged.
    if (dragFrom != null && dragPos != null) {
      final paint = Paint()
        ..color = dragColor
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(leftPortX, _rowCenter(dragFrom!)),
        dragPos!,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WirePainter old) =>
      old.matched.length != matched.length ||
      old.dragFrom != dragFrom ||
      old.dragPos != dragPos;
}
