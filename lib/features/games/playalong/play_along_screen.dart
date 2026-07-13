// lib/features/games/playalong/play_along_screen.dart
//
// Play-along / sing-along with a MOVING SCORE. Scoring is delegated to the pure
// PlayAlongEngine; this screen drives the clock (a Ticker), feeds it the mic's
// readings, and draws the score in one of four switchable views:
//   • highway  — piano-roll: notes scroll past a fixed "now" line (pitch on Y)
//   • falling  — vertical: notes fall toward a hit-line (like Falling Notes)
//   • notation — a real engraved staff (partitura) with a moving cursor
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

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:klang_universum/core/audio/metronome.dart';
import 'package:klang_universum/core/audio/microphone_pitch_service.dart';
import 'package:klang_universum/core/audio/pitch_analysis.dart';
import 'package:klang_universum/core/audio/play_along.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/tuning.dart';
import 'package:klang_universum/features/games/note_reading/note_names.dart';
import 'package:klang_universum/features/games/widgets/game_widgets.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/midi_pitch.dart';
import 'package:partitura/partitura.dart'
    show
        Clef,
        DurationBase,
        Measure,
        MultiSystemView,
        NoteDuration,
        NoteElement,
        PartituraTheme,
        Score;
import 'package:provider/provider.dart';

/// How the moving score is drawn. The child can switch live.
enum PlayAlongView { highway, notation, falling, coach }

class PlayAlongScreen extends StatefulWidget {
  const PlayAlongScreen({
    super.key,
    required this.chart,
    required this.title,
    required this.gameId,
  });

  final PlayAlongChart chart;
  final String title;

  /// Key into [kStarThresholds] and [ProgressService] (e.g. 'cello_play_along').
  final String gameId;

  @override
  State<PlayAlongScreen> createState() => _PlayAlongScreenState();
}

class _PlayAlongScreenState extends State<PlayAlongScreen>
    with SingleTickerProviderStateMixin {
  final MicrophonePitchService _service = MicrophonePitchService();
  late final Ticker _ticker;
  StreamSubscription<PitchReading>? _sub;
  late PlayAlongEngine _engine = PlayAlongEngine(widget.chart);

  PitchReading _latest = PitchReading.silent();
  final CountInClicker _clicker = CountInClicker();
  PlayAlongView _view = PlayAlongView.highway;
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
        for (final n in widget.chart.notes)
          (n.midi, (n.beats * widget.chart.beatMs).round()),
      ];

  void _finish() {
    // Record the run so play/sing-along count toward stars like other games.
    context.read<ProgressService>().recordResult(
          widget.gameId,
          score: _engine.hits,
          stars: scoreToStars(widget.gameId, _engine.hits, _engine.hits > 0),
        );
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
      _engine = PlayAlongEngine(widget.chart);
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
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
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
    switch (_view) {
      case PlayAlongView.highway:
        return CustomPaint(
          painter: _HighwayPainter(
            engine: _engine,
            liveMidi: liveMidi,
            onPitch: onPitch,
            scheme: scheme,
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

class _HighwayPainter extends CustomPainter {
  _HighwayPainter({
    required this.engine,
    required this.liveMidi,
    required this.onPitch,
    required this.scheme,
  });

  final PlayAlongEngine engine;
  final double? liveMidi;
  final bool onPitch;
  final ColorScheme scheme;

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
  });

  final PlayAlongEngine engine;
  final double? liveMidi;
  final bool onPitch;
  final ColorScheme scheme;

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

/// Engraved-notation view: real staff (partitura) with a moving cursor. The
/// active note is highlighted (the cursor); notes already hit stay highlighted.
class _NotationView extends StatelessWidget {
  const _NotationView({
    required this.engine,
    required this.score,
    required this.scheme,
  });

  final PlayAlongEngine engine;
  final Score score;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    // Colour scored notes (green = hit, red = missed); highlight the active
    // note as the cursor (a highlight wins over a per-note colour, which is
    // fine — the active note is still pending, not yet coloured).
    final colors = <String, Color>{};
    for (var i = 0; i < engine.notes.length; i++) {
      switch (engine.notes[i].result) {
        case NoteResult.hit:
          colors['n$i'] = Colors.green;
        case NoteResult.missed:
          colors['n$i'] = scheme.error;
        case NoteResult.pending:
          break;
      }
    }
    final ai = engine.activeIndex;
    return Center(
      child: SingleChildScrollView(
        child: MultiSystemView(
          score: score,
          // Hit/miss note colours ride on theme.elementColors, which the shared
          // LayoutPainter honours on both StaffView and MultiSystemView (a
          // highlightedId still wins). This avoids depending on the newer
          // MultiSystemView(elementColors:) constructor param, which isn't on
          // partitura@main yet — keeps CI (which builds against it) green.
          theme: PartituraTheme.kids.copyWith(elementColors: colors),
          highlightedIds: {if (ai >= 0) 'n$ai'},
        ),
      ),
    );
  }
}
