// lib/features/games/playalong/play_along_screen.dart
//
// Play-along / sing-along with a MOVING SCORE. Scoring is delegated to the pure
// PlayAlongEngine; this screen drives the clock (a Ticker), feeds it the mic's
// readings, and draws the score in one of four switchable views:
//   • highway  — piano-roll: notes scroll past a fixed "now" line (pitch on Y)
//   • falling  — vertical: notes fall toward a hit-line (like Falling Notes)
//   • notation — a real engraved staff (crisp_notation) with a moving cursor
//   • coach    — minimal: the current + next note, huge, for beginners
//
// One screen serves both instruments and voice — pass a cello chart for
// play-along or an octave-agnostic vocal chart for sing-along. A count-in
// metronome sets the tempo. Optional audible backing (Tier 0/1): off by default
// because the mic would grade the speaker; turning it on plays the melody at the
// downbeat and flips on the platform echo-canceller — use headphones for the
// cleanest pitch accuracy. See the AEC notes for why real cancellation of a
// same-pitch echo needs the OS/native audio path, not a Dart pitch gate.

import 'dart:async';

import 'package:crisp_notation/crisp_notation.dart'
    show
        Clef,
        DurationBase,
        EditorMark,
        ElementRegionController,
        Measure,
        MultiSystemView,
        NoteDuration,
        NoteElement,
        Score,
        ScoreEditorController;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:klang_universum/core/audio/metronome.dart';
import 'package:klang_universum/core/audio/microphone_pitch_service.dart';
import 'package:klang_universum/core/audio/pitch_analysis.dart';
import 'package:klang_universum/core/audio/play_along.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/settings_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/core/tuning.dart';
import 'package:klang_universum/features/games/note_reading/note_names.dart';
import 'package:klang_universum/features/games/widgets/game_app_bar.dart';
import 'package:klang_universum/features/games/widgets/game_widgets.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/midi_pitch.dart';
import 'package:klang_universum/shared/score_theme.dart';
import 'package:provider/provider.dart';

/// How the moving score is drawn. The child can switch live.
enum PlayAlongView { highway, notation, falling, coach }

/// How forgiving the scoring is (independent of tempo): easy = wide cents
/// window + less coverage needed; hard = tight intonation.
enum PlayAlongDifficulty { easy, medium, hard }

extension PlayAlongDifficultyParams on PlayAlongDifficulty {
  /// Cents a note may be off and still count.
  double get centsTolerance => switch (this) {
        PlayAlongDifficulty.easy => 70,
        PlayAlongDifficulty.medium => 45,
        PlayAlongDifficulty.hard => 25,
      };

  /// Fraction of a note's frames that must be on pitch to count as a hit.
  double get hitCoverage => switch (this) {
        PlayAlongDifficulty.easy => 0.3,
        PlayAlongDifficulty.medium => 0.4,
        PlayAlongDifficulty.hard => 0.5,
      };
}

/// The spaced-repetition item id for a play-along note, e.g.
/// `cello.play_along.fs3`. The accidental is spelled (s/f) so C and C# don't
/// collide onto the same review item.
String playAlongSriId(String prefix, int midi) {
  final p = pitchFromMidi(midi);
  final acc =
      p.alter > 0 ? 's' * p.alter : (p.alter < 0 ? 'f' * (-p.alter) : '');
  return '$prefix.${p.step.name}$acc${p.octave}';
}

class PlayAlongScreen extends StatefulWidget {
  const PlayAlongScreen({
    super.key,
    required this.chart,
    required this.title,
    required this.gameId,
    required this.sriPrefix,
    this.scaleStarsToLength = false,
  });

  final PlayAlongChart chart;
  final String title;

  /// Key into [kStarThresholds] and [ProgressService] (e.g. 'cello_play_along').
  final String gameId;

  /// SRI namespace for the notes (e.g. 'cello.play_along'); each note's outcome
  /// is recorded under `<sriPrefix>.<note>` for spaced-repetition review.
  final String sriPrefix;

  /// Grade stars by the **fraction** of the chart hit rather than a raw count —
  /// so a chart of any length (e.g. a Song Book song) scores fairly against the
  /// game's fixed bracket. Off by default: every built-in chart is unchanged.
  final bool scaleStarsToLength;

  @override
  State<PlayAlongScreen> createState() => _PlayAlongScreenState();
}

class _PlayAlongScreenState extends State<PlayAlongScreen>
    with SingleTickerProviderStateMixin {
  final MicrophonePitchService _service = MicrophonePitchService();
  late final Ticker _ticker;
  StreamSubscription<PitchReading>? _sub;
  late PlayAlongEngine _engine = _buildEngine();

  PlayAlongEngine _buildEngine() => PlayAlongEngine(
        _chart,
        centsTolerance: _difficulty.centsTolerance,
        hitCoverage: _difficulty.hitCoverage,
      );

  /// The chart at the selected tempo (notes unchanged, bpm scaled).
  PlayAlongChart get _chart => _tempo == 1.0
      ? widget.chart
      : widget.chart.copyWith(bpm: (widget.chart.bpm * _tempo).round());

  PitchReading _latest = PitchReading.silent();
  final CountInClicker _clicker = CountInClicker();
  // Default to real staff notation (clefs) — the clearest read; the labelled
  // highway / falling views are a tap away for a game-style scroll.
  PlayAlongView _view = PlayAlongView.notation;
  double _tempo = 1.0; // slow-down multiplier (1.0 = the chart's own tempo)
  PlayAlongDifficulty _difficulty = PlayAlongDifficulty.medium;
  bool _backing =
      false; // play audible backing (Tier 0/1: needs headphones/AEC)
  bool _backingStarted = false;
  bool _running = false;
  bool _finished = false;
  ({PitchCaptureError reason, String? detail})? _error;

  /// The chart rendered as engraved notation — built once (id 'n<i>' per note).
  late final Score _score = _buildScore();

  Score _buildScore() {
    final notes = widget.chart.notes;
    final clef = notes.any((n) => n.midi < 55) ? Clef.bass : Clef.treble;
    NoteDuration durFor(double beats) => switch (beats) {
          >= 4 => const NoteDuration(DurationBase.whole),
          >= 2 => const NoteDuration(DurationBase.half),
          >= 1 => const NoteDuration(DurationBase.quarter),
          _ => const NoteDuration(DurationBase.eighth),
        };
    // Chunk into ~4-beat measures so the staff wraps into readable systems.
    final measures = <Measure>[];
    var current = <NoteElement>[];
    var beatsInBar = 0.0;
    for (var i = 0; i < notes.length; i++) {
      if (beatsInBar >= 4 && current.isNotEmpty) {
        measures.add(Measure(current));
        current = <NoteElement>[];
        beatsInBar = 0;
      }
      current.add(
        NoteElement(
          pitches: [pitchFromMidi(notes[i].midi)],
          duration: durFor(notes[i].beats),
          id: 'n$i',
        ),
      );
      beatsInBar += notes[i].beats;
    }
    if (current.isNotEmpty) measures.add(Measure(current));
    return Score(clef: clef, measures: measures);
  }

  @override
  void initState() {
    super.initState();
    // Create the ticker eagerly so it is never lazily created during dispose
    // (which would look up an ancestor on a deactivated element).
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sub?.cancel();
    _service.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    _engine.update(
      elapsedMs: elapsed.inMicroseconds / 1000.0,
      reading: _latest,
    );
    final c = _clicker.update(_engine.currentBeat);
    if (c.click) context.read<AudioService>().playTick(accent: c.accent);
    // Tier 0/1: at the downbeat, start the backing track (headphones, or the
    // platform echo-canceller so the mic doesn't grade the speaker).
    if (_backing && !_backingStarted && _engine.currentBeat >= 0) {
      _backingStarted = true;
      context.read<AudioService>().playSequence(_melody());
    }
    if (_engine.finished) {
      _finish();
    } else {
      setState(() {});
    }
  }

  List<(int, int)> _melody() => [
        for (final n in _chart.notes)
          (n.midi, (n.beats * _chart.beatMs).round()),
      ];

  /// The value stars are graded from: the raw hit count, or — when
  /// [PlayAlongScreen.scaleStarsToLength] — a bracket-normalized score that
  /// reflects the fraction of the chart hit (so any-length charts grade fairly).
  int get _starScore => widget.scaleStarsToLength
      ? scaledStarScore(
          _engine.hits,
          _engine.notes.length,
          kStarThresholds[widget.gameId] ?? const [1, 1, 1],
        )
      : _engine.hits;

  void _finish() {
    // Record the run so play/sing-along count toward stars like other games.
    context.read<ProgressService>().recordResult(
          widget.gameId,
          score: _engine.hits,
          stars: scoreToStars(widget.gameId, _starScore, _engine.hits > 0),
        );
    // Feed each note's outcome to spaced repetition, so notes the child keeps
    // missing come back in Review — same as every other game.
    final sri = context.read<SriService>();
    for (final ns in _engine.notes) {
      sri.recordResponse(
        playAlongSriId(widget.sriPrefix, ns.note.midi),
        ns.result == NoteResult.hit,
      );
    }
    _stop();
    if (mounted) setState(() => _finished = true);
  }

  Future<void> _start() async {
    _clicker.reset();
    _backingStarted = false;
    _service.echoCancel = _backing; // cancel the speaker when backing is on
    setState(() {
      _error = null;
      _finished = false;
      _engine = _buildEngine();
    });
    try {
      _sub = _service.readings.listen(
        (r) => _latest = r,
        onError: (Object e) {
          if (mounted) {
            setState(
              () => _error = (
                reason: PitchCaptureError.unknown,
                detail: '$e',
              ),
            );
          }
        },
      );
      await _service.start();
      unawaited(_ticker.start()); // TickerFuture completes only when stopped
      if (mounted) setState(() => _running = true);
    } on PitchCaptureException catch (e) {
      await _sub?.cancel();
      if (mounted) {
        setState(() {
          _running = false;
          _error = (reason: e.reason, detail: e.detail);
        });
      }
    }
  }

  String _errorText(AppLocalizations l) => switch (_error!.reason) {
        PitchCaptureError.permissionDenied => l.micPermissionDenied,
        PitchCaptureError.unsupported => l.micUnsupported,
        _ => l.micStartFailed(_error!.detail ?? _error!.reason.name),
      };

  Future<void> _stop() async {
    _ticker.stop();
    await _service.stop();
    await _sub?.cancel();
    // The mic (record) can leave the iOS/Android audio session routed to the
    // quiet earpiece; put playback back on the speaker so the rest of the app
    // isn't silent afterwards.
    if (mounted) await context.read<AudioService>().configurePlaybackRoute();
    _latest = PitchReading.silent();
    if (mounted) setState(() => _running = false);
  }

  void _preview() => context.read<AudioService>().playSequence(_melody());

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    final active = _engine.activeNote;
    final liveMidi = _latest.hasPitch ? _latest.midi : null;
    final onPitch = active != null &&
        _latest.hasPitch &&
        _latest.cents.abs() <= _engine.centsTolerance &&
        (widget.chart.octaveAgnostic
            ? _latest.nearestMidi % 12 == active.note.midi % 12
            : _latest.nearestMidi == active.note.midi);

    return Scaffold(
      appBar: GameAppBar(
        title: widget.title,
        actions: [
          if (!_finished)
            PopupMenuButton<double>(
              icon: const Icon(Icons.speed),
              tooltip: l.playAlongTempo,
              initialValue: _tempo,
              // Read when the engine is built at Play, so only change stopped.
              enabled: !_running,
              onSelected: (t) => setState(() => _tempo = t),
              itemBuilder: (context) => [
                for (final t in const [0.5, 0.75, 1.0])
                  PopupMenuItem(
                    value: t,
                    child: Text(t == 1.0 ? '1×' : '${_fracLabel(t)}×'),
                  ),
              ],
            ),
          if (!_finished)
            PopupMenuButton<PlayAlongDifficulty>(
              icon: const Icon(Icons.tune),
              tooltip: l.playAlongDifficulty,
              initialValue: _difficulty,
              // Read when the engine is built at Play, so only change stopped.
              enabled: !_running,
              onSelected: (d) => setState(() => _difficulty = d),
              itemBuilder: (context) => [
                for (final d in PlayAlongDifficulty.values)
                  PopupMenuItem(value: d, child: Text(_difficultyName(l, d))),
              ],
            ),
          if (!_finished)
            IconButton(
              tooltip: l.playAlongBacking,
              isSelected: _backing,
              icon: const Icon(Icons.music_off),
              selectedIcon: const Icon(Icons.music_note),
              // Changing it takes effect on the next Play (echoCancel is read
              // at start), so only allow toggling while stopped.
              onPressed:
                  _running ? null : () => setState(() => _backing = !_backing),
            ),
          if (!_finished)
            PopupMenuButton<PlayAlongView>(
              icon: const Icon(Icons.grid_view),
              tooltip: l.playAlongViewLabel,
              initialValue: _view,
              onSelected: (v) => setState(() => _view = v),
              itemBuilder: (context) => [
                for (final v in PlayAlongView.values)
                  PopupMenuItem(value: v, child: Text(_viewName(l, v))),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: _finished
            ? GameResultView(
                gameType: widget.gameId,
                score: _engine.hits,
                starScore: _starScore,
                onRestart: _start,
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _stat(
                          context,
                          l.playAlongScore,
                          '${_engine.hits}/${_engine.notes.length}',
                        ),
                        _stat(
                          context,
                          l.playAlongNow,
                          _running
                              ? (_engine.inCountIn
                                  ? l.playAlongCountIn
                                  : (active != null
                                      ? spelledMidiName(
                                          context,
                                          active.note.midi,
                                        )
                                      : '—'))
                              : '—',
                        ),
                        _stat(
                          context,
                          l.playAlongYou,
                          _latest.hasPitch
                              ? spelledMidiName(context, _latest.nearestMidi)
                              : '—',
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: _buildView(context, l, liveMidi, onPitch, scheme),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        _errorText(l),
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _running ? null : _preview,
                          icon: const Icon(Icons.volume_up),
                          label: Text(l.playAlongPreview),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: _running ? _stop : _start,
                          icon: Icon(_running ? Icons.stop : Icons.play_arrow),
                          label: Text(_running ? l.micStop : widget.title),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        Text(value, style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }

  String _fracLabel(double t) => switch (t) {
        0.5 => '½',
        0.75 => '¾',
        _ => '$t',
      };

  String _difficultyName(AppLocalizations l, PlayAlongDifficulty d) =>
      switch (d) {
        PlayAlongDifficulty.easy => l.playAlongDifficultyEasy,
        PlayAlongDifficulty.medium => l.playAlongDifficultyMedium,
        PlayAlongDifficulty.hard => l.playAlongDifficultyHard,
      };

  String _viewName(AppLocalizations l, PlayAlongView v) => switch (v) {
        PlayAlongView.highway => l.playAlongViewHighway,
        PlayAlongView.notation => l.playAlongViewNotation,
        PlayAlongView.falling => l.playAlongViewFalling,
        PlayAlongView.coach => l.playAlongViewCoach,
      };

  Widget _buildView(
    BuildContext context,
    AppLocalizations l,
    double? liveMidi,
    bool onPitch,
    ColorScheme scheme,
  ) {
    // Name each pitch (respecting the note-naming setting) so the moving blocks
    // read as real notes, e.g. "C4" / "F♯5". Resolve the naming here in build —
    // a pure labeler, so the painter never touches an inherited widget.
    final naming = context.read<SettingsService>().noteNaming;
    String noteLabel(int midi) => spelledMidiNameWith(l, naming, midi);

    switch (_view) {
      case PlayAlongView.highway:
        return CustomPaint(
          painter: _HighwayPainter(
            engine: _engine,
            liveMidi: liveMidi,
            onPitch: onPitch,
            scheme: scheme,
            label: noteLabel,
          ),
          child: const SizedBox.expand(),
        );
      case PlayAlongView.falling:
        return CustomPaint(
          painter: _FallingPainter(
            engine: _engine,
            liveMidi: liveMidi,
            onPitch: onPitch,
            scheme: scheme,
            label: noteLabel,
          ),
          child: const SizedBox.expand(),
        );
      case PlayAlongView.coach:
        return _CoachView(
          engine: _engine,
          latest: _latest,
          onPitch: onPitch,
          scheme: scheme,
        );
      case PlayAlongView.notation:
        return _NotationView(engine: _engine, score: _score, scheme: scheme);
    }
  }
}

/// Draws a note name in white over a moving block. [anchor] is the left edge +
/// vertical centre (or the horizontal centre when [centerX]); [maxH] scales the
/// font to the block height.
void _paintNoteLabel(
  Canvas canvas,
  String text,
  Offset anchor,
  double maxH, {
  bool centerX = false,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: Colors.white,
        fontSize: maxH.clamp(9.0, 13.0),
        fontWeight: FontWeight.w700,
        height: 1.0,
        shadows: const [Shadow(color: Colors.black45, blurRadius: 1.5)],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final dx = centerX ? anchor.dx - tp.width / 2 : anchor.dx;
  tp.paint(canvas, Offset(dx, anchor.dy - tp.height / 2));
}

class _HighwayPainter extends CustomPainter {
  _HighwayPainter({
    required this.engine,
    required this.liveMidi,
    required this.onPitch,
    required this.scheme,
    required this.label,
  });

  final PlayAlongEngine engine;
  final double? liveMidi;
  final bool onPitch;
  final ColorScheme scheme;
  final String Function(int midi) label;

  static const double _beatsVisible = 8; // how many beats span the width
  static const double _nowFrac = 0.28; // where "now" sits, left-ish

  @override
  void paint(Canvas canvas, Size size) {
    final notes = engine.chart.notes;
    if (notes.isEmpty) return;

    // Pitch range with padding.
    var lo = notes.first.midi, hi = notes.first.midi;
    for (final n in notes) {
      lo = n.midi < lo ? n.midi : lo;
      hi = n.midi > hi ? n.midi : hi;
    }
    lo -= 3;
    hi += 3;
    final span = (hi - lo).toDouble();
    double y(num midi) => size.height - (midi - lo) / span * size.height;

    final pxPerBeat = size.width / _beatsVisible;
    final nowX = size.width * _nowFrac;
    final beat = engine.currentBeat;
    double x(double b) => nowX + (b - beat) * pxPerBeat;
    final semi = size.height / span;
    final barH = (semi * 0.8).clamp(6.0, 22.0);

    // Faint lane lines every octave.
    final lane = Paint()..color = scheme.onSurface.withValues(alpha: 0.06);
    for (var m = lo - (lo % 12); m <= hi; m += 12) {
      canvas.drawRect(Rect.fromLTWH(0, y(m) - 0.5, size.width, 1), lane);
    }

    // Notes.
    for (final ns in engine.notes) {
      final n = ns.note;
      final left = x(n.startBeat);
      final right = x(n.endBeat);
      if (right < 0 || left > size.width) continue;
      final color = switch (ns.result) {
        NoteResult.hit => Colors.green,
        NoteResult.missed => scheme.error,
        NoteResult.pending => ns == engine.activeNote
            ? scheme.primary
            : scheme.primary.withValues(alpha: 0.45),
      };
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(
          left + 1,
          y(n.midi) - barH / 2,
          right - 1,
          y(n.midi) + barH / 2,
        ),
        const Radius.circular(5),
      );
      canvas.drawRRect(rect, Paint()..color = color);
      // The note's name, so a block reads as a real pitch. Kept at the block's
      // left edge (clamped on-screen) so it stays legible as the note scrolls.
      _paintNoteLabel(
        canvas,
        label(n.midi),
        Offset(left.clamp(2.0, size.width) + 4, y(n.midi)),
        barH,
      );
    }

    // "Now" line.
    canvas.drawLine(
      Offset(nowX, 0),
      Offset(nowX, size.height),
      Paint()
        ..color = scheme.onSurface.withValues(alpha: 0.35)
        ..strokeWidth = 2,
    );

    // Live pitch dot at the now line.
    if (liveMidi != null) {
      final ly = y(liveMidi!.clamp(lo.toDouble(), hi.toDouble()));
      final p = Paint()..color = onPitch ? Colors.green : Colors.amber;
      canvas.drawCircle(Offset(nowX, ly), 9, p);
      canvas.drawCircle(
        Offset(nowX, ly),
        13,
        Paint()
          ..color = p.color.withValues(alpha: 0.25)
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(_HighwayPainter old) => true; // driven by the ticker
}

/// Vertical "falling notes": notes fall from the top toward a hit-line near the
/// bottom; pitch runs left→right, time top→bottom.
class _FallingPainter extends CustomPainter {
  _FallingPainter({
    required this.engine,
    required this.liveMidi,
    required this.onPitch,
    required this.scheme,
    required this.label,
  });

  final PlayAlongEngine engine;
  final double? liveMidi;
  final bool onPitch;
  final ColorScheme scheme;
  final String Function(int midi) label;

  static const double _beatsVisible = 6;
  static const double _hitFrac = 0.82;

  @override
  void paint(Canvas canvas, Size size) {
    final notes = engine.chart.notes;
    if (notes.isEmpty) return;

    var lo = notes.first.midi, hi = notes.first.midi;
    for (final n in notes) {
      lo = n.midi < lo ? n.midi : lo;
      hi = n.midi > hi ? n.midi : hi;
    }
    lo -= 3;
    hi += 3;
    final span = (hi - lo).toDouble();
    double x(num midi) => (midi - lo) / span * size.width;

    final hitY = size.height * _hitFrac;
    final pxPerBeat = hitY / _beatsVisible;
    final beat = engine.currentBeat;
    double y(double b) => hitY - (b - beat) * pxPerBeat;
    final laneW = size.width / span;
    final noteW = (laneW * 0.7).clamp(8.0, 44.0);

    final lane = Paint()..color = scheme.onSurface.withValues(alpha: 0.06);
    for (var m = lo - (lo % 12); m <= hi; m += 12) {
      canvas.drawRect(Rect.fromLTWH(x(m) - 0.5, 0, 1, size.height), lane);
    }

    for (final ns in engine.notes) {
      final n = ns.note;
      final top = y(n.endBeat);
      final bottom = y(n.startBeat);
      if (bottom < 0 || top > size.height) continue;
      final color = switch (ns.result) {
        NoteResult.hit => Colors.green,
        NoteResult.missed => scheme.error,
        NoteResult.pending => ns == engine.activeNote
            ? scheme.primary
            : scheme.primary.withValues(alpha: 0.45),
      };
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(
          x(n.midi) - noteW / 2,
          top + 1,
          x(n.midi) + noteW / 2,
          bottom - 1,
        ),
        const Radius.circular(5),
      );
      canvas.drawRRect(rect, Paint()..color = color);
      // Centre the note's name on the falling block.
      _paintNoteLabel(
        canvas,
        label(n.midi),
        Offset(x(n.midi), (top + bottom) / 2),
        noteW * 0.5,
        centerX: true,
      );
    }

    canvas.drawLine(
      Offset(0, hitY),
      Offset(size.width, hitY),
      Paint()
        ..color = scheme.onSurface.withValues(alpha: 0.35)
        ..strokeWidth = 2,
    );

    if (liveMidi != null) {
      final lx = x(liveMidi!.clamp(lo.toDouble(), hi.toDouble()));
      final p = Paint()..color = onPitch ? Colors.green : Colors.amber;
      canvas.drawCircle(Offset(lx, hitY), 9, p);
      canvas.drawCircle(
        Offset(lx, hitY),
        13,
        Paint()..color = p.color.withValues(alpha: 0.25),
      );
    }
  }

  @override
  bool shouldRepaint(_FallingPainter old) => true;
}

/// Minimal "coach" view for beginners: the current target note big, the next
/// one small, and what you're singing/playing — no scrolling.
class _CoachView extends StatelessWidget {
  const _CoachView({
    required this.engine,
    required this.latest,
    required this.onPitch,
    required this.scheme,
  });

  final PlayAlongEngine engine;
  final PitchReading latest;
  final bool onPitch;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final ai = engine.activeIndex;
    final nowNote = ai >= 0 ? engine.notes[ai].note : null;
    final ni = ai >= 0 ? ai + 1 : engine.nextIndex;
    final nextNote =
        (ni >= 0 && ni < engine.notes.length) ? engine.notes[ni].note : null;

    final nowLabel = nowNote != null
        ? spelledMidiName(context, nowNote.midi)
        : (engine.inCountIn ? l.playAlongCountIn : '—');

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            nowLabel,
            style: text.displayLarge?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 96,
              color: onPitch ? Colors.green : scheme.onSurface,
            ),
          ),
          if (nextNote != null)
            Text(
              '${l.playAlongNext}: ${spelledMidiName(context, nextNote.midi)}',
              style: text.titleLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
          const SizedBox(height: 32),
          Text(
            '${l.playAlongYou}: ${latest.hasPitch ? spelledMidiName(context, latest.nearestMidi) : '—'}'
            '${latest.hasPitch ? '  ${latest.cents >= 0 ? '+' : ''}${latest.cents.toStringAsFixed(0)}¢' : ''}',
            style: text.headlineSmall?.copyWith(
              color: onPitch ? Colors.green : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Engraved-notation view: real staff (crisp_notation) with a moving cursor. The
/// active note is highlighted (the cursor); notes already hit stay highlighted.
class _NotationView extends StatefulWidget {
  const _NotationView({
    required this.engine,
    required this.score,
    required this.scheme,
  });

  final PlayAlongEngine engine;
  final Score score;
  final ColorScheme scheme;

  @override
  State<_NotationView> createState() => _NotationViewState();
}

class _NotationViewState extends State<_NotationView> {
  final ScrollController _scroll = ScrollController();

  // C7 regions give each note's rect; the editor controller (crisp_notation) uses
  // that + our scroll controller to keep the active note in view.
  final ElementRegionController _regions = ElementRegionController();
  final ScoreEditorController _editor = ScoreEditorController();

  int _lastActive = -1;
  int? _loopAnchor; // first tapped note index, awaiting the loop's end note

  /// Tap a note to set a practice loop: first tap = start, second = end (loops
  /// that span on repeat); tapping while a loop is active clears it.
  void _onTapNote(String id) {
    final i = int.tryParse(id.startsWith('n') ? id.substring(1) : id);
    if (i == null || i < 0 || i >= widget.engine.notes.length) return;
    setState(() {
      if (widget.engine.isLooping) {
        widget.engine.setLoop(null, null);
        _editor.clearLoop();
        _loopAnchor = null;
      } else if (_loopAnchor == null) {
        _loopAnchor = i;
      } else {
        final lo = _loopAnchor! < i ? _loopAnchor! : i;
        final hi = _loopAnchor! < i ? i : _loopAnchor!;
        widget.engine.setLoop(
          widget.engine.notes[lo].note.startBeat,
          widget.engine.notes[hi].note.endBeat,
        );
        _editor.setLoop('n$lo', 'n$hi');
        _loopAnchor = null;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editor.attachViewport(
        scrollController: _scroll,
        rectOfElement: (id) {
          for (final r in _regions.elementRegions) {
            if (r.id == id) return r.bounds;
          }
          return null;
        },
      );
      _follow();
    });
  }

  @override
  void dispose() {
    _editor.detachViewport();
    _scroll.dispose();
    super.dispose();
  }

  /// Scroll so the active note sits ~a third down the viewport — a smooth
  /// follow-cursor that keeps the current bar visible on long, wrapped pieces.
  void _follow() {
    final ai = widget.engine.activeIndex;
    if (ai < 0) return;
    _editor.scrollToNote(
      'n$ai',
      alignment: 0.35,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // Green for hits; missed notes get an EditorMark (a wedge flag + a reason),
    // coloured by *why* — blue = flat, orange = sharp, red = never on pitch —
    // so after a run (or a loop) the learner sees which notes to drill.
    final colors = <String, Color>{};
    final marks = <String, EditorMark>{};
    for (var i = 0; i < widget.engine.notes.length; i++) {
      final n = widget.engine.notes[i];
      switch (n.result) {
        case NoteResult.hit:
          colors['n$i'] = Colors.green;
        case NoteResult.missed:
          final ac = n.avgCents;
          final (Color c, String msg) = ac == null
              ? (widget.scheme.error, l.playAlongMarkMiss)
              : ac < 0
                  ? (const Color(0xFF1E88E5), l.playAlongMarkFlat)
                  : (const Color(0xFFF57C00), l.playAlongMarkSharp);
          marks['n$i'] = EditorMark(c, message: msg);
        case NoteResult.pending:
          break;
      }
    }
    final ai = widget.engine.activeIndex;
    if (ai != _lastActive) {
      _lastActive = ai;
      WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
    }
    final hint = widget.engine.isLooping
        ? l.playAlongLooping
        : (_loopAnchor != null ? l.playAlongLoopEnd : l.playAlongLoopHint);
    return Column(
      children: [
        _LoopHint(text: hint, active: widget.engine.isLooping),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              controller: _scroll,
              child: MultiSystemView(
                score: widget.score,
                controller: _regions,
                theme: kidsScoreTheme.copyWith(elementColors: colors),
                highlightedIds: {if (ai >= 0) 'n$ai'},
                errorOverlay: marks,
                loopRange: _editor.loopRange,
                onElementTap: _onTapNote,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A slim banner above the staff explaining / confirming the practice-loop tap.
class _LoopHint extends StatelessWidget {
  const _LoopHint({required this.text, required this.active});

  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: active
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            active ? Icons.repeat_on : Icons.repeat,
            size: 16,
            color: active ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: active
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
