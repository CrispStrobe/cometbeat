// lib/features/games/chords/chord_progression_screen.dart
//
// Chord-progression play-along with a MOVING CHART: chord names scroll past a
// "now" line; you strum/play the progression and each chord is scored by the
// fuzzy ChordDetector (ChordProgressionEngine). The chord analogue of
// play_along_screen.dart — same clock/mic/results plumbing, chords instead of
// single notes. No audible backing (the mic would hear it); use Preview.

import 'dart:async';

import 'package:comet_beat/core/audio/chord_progression.dart';
import 'package:comet_beat/core/audio/chroma_analysis.dart';
import 'package:comet_beat/core/audio/metronome.dart';
import 'package:comet_beat/core/audio/microphone_pitch_service.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/core/tuning.dart';
import 'package:comet_beat/features/games/note_reading/note_names.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/midi_pitch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

/// SRI item id for a play-along chord, e.g. `chords.play_along.g7`,
/// `chords.play_along.am` — the root spelled (s/f) + the quality suffix.
String chordProgressionSriId(String prefix, int rootPc, String suffix) {
  final p = pitchFromMidi(60 + rootPc);
  final acc =
      p.alter > 0 ? 's' * p.alter : (p.alter < 0 ? 'f' * (-p.alter) : '');
  return '$prefix.${p.step.name}$acc$suffix';
}

class ChordProgressionScreen extends StatefulWidget {
  const ChordProgressionScreen({
    super.key,
    required this.chart,
    required this.title,
    required this.gameId,
  });

  final ChordChart chart;
  final String title;
  final String gameId;

  @override
  State<ChordProgressionScreen> createState() => _ChordProgressionScreenState();
}

class _ChordProgressionScreenState extends State<ChordProgressionScreen>
    with SingleTickerProviderStateMixin {
  late final MicrophonePitchService _service =
      MicrophonePitchService(chordDetector: ChordDetector());
  late final Ticker _ticker;
  StreamSubscription<ChordReading>? _sub;
  late ChordProgressionEngine _engine = ChordProgressionEngine(widget.chart);

  ChordReading _latest = ChordReading.silent();
  final CountInClicker _clicker = CountInClicker();
  bool _running = false;
  bool _finished = false;
  ({PitchCaptureError reason, String? detail})? _error;

  @override
  void initState() {
    super.initState();
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
    if (_engine.finished) {
      _finish();
    } else {
      setState(() {});
    }
  }

  void _finish() {
    context.read<ProgressService>().recordResult(
          widget.gameId,
          score: _engine.hits,
          stars: scoreToStars(widget.gameId, _engine.hits, _engine.hits > 0),
        );
    // Feed each chord's outcome to spaced repetition, like the note play-along.
    final sri = context.read<SriService>();
    for (final cs in _engine.chords) {
      sri.recordResponse(
        chordProgressionSriId(
          'chords.play_along',
          cs.target.rootPc,
          cs.target.suffix,
        ),
        cs.result == ChordResult.hit,
      );
    }
    _stop();
    if (mounted) setState(() => _finished = true);
  }

  Future<void> _start() async {
    _clicker.reset();
    setState(() {
      _error = null;
      _finished = false;
      _engine = ChordProgressionEngine(widget.chart);
    });
    try {
      _sub = _service.chords.listen(
        (r) => _latest = r,
        onError: (Object e) {
          if (mounted) {
            setState(
              () => _error = (reason: PitchCaptureError.unknown, detail: '$e'),
            );
          }
        },
      );
      await _service.start();
      unawaited(_ticker.start());
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

  Future<void> _stop() async {
    _ticker.stop();
    await _service.stop();
    await _sub?.cancel();
    _latest = ChordReading.silent();
    if (mounted) setState(() => _running = false);
  }

  void _preview() {
    context.read<AudioService>().playChordSequence(
      [for (final c in widget.chart.chords) c.midis()],
      ms: (widget.chart.beatMs * 2).round(),
    );
  }

  String _errorText(AppLocalizations l) => switch (_error!.reason) {
        PitchCaptureError.permissionDenied => l.micPermissionDenied,
        PitchCaptureError.unsupported => l.micUnsupported,
        _ => l.micStartFailed(_error!.detail ?? _error!.reason.name),
      };

  /// A chord named in the learner's convention (root spelled via the setting).
  String _chordName(int rootPc, String suffix) =>
      '${spelledMidiName(context, 60 + rootPc, withOctave: false)}$suffix';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    final active = _engine.activeChord;
    final detected = _latest.best;

    return Scaffold(
      appBar: GameAppBar(title: widget.title),
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
                          l.playAlongScore,
                          '${_engine.hits}/${_engine.chords.length}',
                        ),
                        _stat(
                          l.playAlongNow,
                          _running
                              ? (_engine.inCountIn
                                  ? l.playAlongCountIn
                                  : (active != null
                                      ? _chordName(
                                          active.target.rootPc,
                                          active.target.suffix,
                                        )
                                      : '—'))
                              : '—',
                        ),
                        _stat(
                          l.playAlongYou,
                          detected == null
                              ? '—'
                              : _chordName(detected.rootPc, detected.suffix),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: CustomPaint(
                        painter: _ChordHighwayPainter(
                          engine: _engine,
                          labels: [
                            for (final c in _engine.chords)
                              _chordName(c.target.rootPc, c.target.suffix),
                          ],
                          scheme: scheme,
                        ),
                        child: const SizedBox.expand(),
                      ),
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
                    // Wrap, not Row: the play button's label is the game title,
                    // which with 'Preview' overflows a narrow phone — they stack.
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _running ? null : _preview,
                          icon: const Icon(Icons.volume_up),
                          label: Text(l.playAlongPreview),
                        ),
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

  Widget _stat(String label, String value) {
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
}

/// Chord-name boxes scrolling right-to-left past a fixed "now" line.
class _ChordHighwayPainter extends CustomPainter {
  _ChordHighwayPainter({
    required this.engine,
    required this.labels,
    required this.scheme,
  });

  final ChordProgressionEngine engine;
  final List<String> labels;
  final ColorScheme scheme;

  static const double _beatsVisible = 8;
  static const double _nowFrac = 0.28;

  @override
  void paint(Canvas canvas, Size size) {
    final chords = engine.chords;
    if (chords.isEmpty) return;

    final pxPerBeat = size.width / _beatsVisible;
    final nowX = size.width * _nowFrac;
    final beat = engine.currentBeat;
    double x(double b) => nowX + (b - beat) * pxPerBeat;

    final midY = size.height / 2;
    const boxH = 64.0;

    for (var i = 0; i < chords.length; i++) {
      final t = chords[i].target;
      final left = x(t.startBeat);
      final right = x(t.endBeat);
      if (right < 0 || left > size.width) continue;

      final color = switch (chords[i].result) {
        ChordResult.hit => Colors.green,
        ChordResult.missed => scheme.error,
        ChordResult.pending => chords[i] == engine.activeChord
            ? scheme.primary
            : scheme.primary.withValues(alpha: 0.45),
      };
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(left + 3, midY - boxH / 2, right - 3, midY + boxH / 2),
        const Radius.circular(10),
      );
      canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: 0.85));

      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: scheme.onPrimary,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: (right - left - 8).clamp(0, size.width));
      final cx = (left + right) / 2 - tp.width / 2;
      if (right - left > tp.width + 6) {
        tp.paint(canvas, Offset(cx, midY - tp.height / 2));
      }
    }

    canvas.drawLine(
      Offset(nowX, 0),
      Offset(nowX, size.height),
      Paint()
        ..color = scheme.onSurface.withValues(alpha: 0.35)
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_ChordHighwayPainter old) => true;
}
