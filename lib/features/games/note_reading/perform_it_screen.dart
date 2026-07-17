// lib/features/games/note_reading/perform_it_screen.dart
//
// "Perform It" — mic-graded reading (docs/PLAN.md live-mic follow-ups). A note is
// shown; instead of tapping a letter, the child PLAYS or SINGS it and the live
// pitch detector verifies it. Matching is octave-agnostic (kind for voices and
// small instruments) and must hold for a moment to avoid transient false hits.
// Turns reading practice active; the kid-scale core of performance grading.
//
// Feeds the shared reading pool: SRI 'note_reading.<clef>.<step><octave>'.

import 'dart:async';
import 'dart:math';

import 'package:comet_beat/core/audio/microphone_pitch_service.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/core/tuning.dart';
import 'package:comet_beat/features/games/note_reading/note_colors.dart';
import 'package:comet_beat/features/games/note_reading/note_names.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:comet_beat/shared/widgets/note_mascot.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material also exports `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

class PerformItScreen extends StatefulWidget {
  const PerformItScreen({super.key, this.clef = Clef.treble});

  final Clef clef;

  static const _kNotes = 8;

  /// Clarity floor + how long the right pitch must hold to count as performed.
  static const _minClarity = 0.6;
  static const _holdMs = 320;

  @override
  State<PerformItScreen> createState() => _PerformItScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class PerformItTester {
  int get targetMidi;
  int get score;
  int get done;
  bool get finished;

  /// Simulate having performed the current target note correctly.
  void debugPerform();

  /// Skip the current note (advance without credit).
  void debugSkip();
}

class _PerformItScreenState extends State<PerformItScreen>
    implements PerformItTester {
  final MicrophonePitchService _service = MicrophonePitchService();
  StreamSubscription<PitchReading>? _sub;
  final _random = Random();

  late Pitch _target;
  int _done = 0; // notes resolved (performed or skipped)
  int _score = 0;
  bool _finished = false;
  bool _wide = false;

  PitchReading _reading = PitchReading.silent();
  int? _matchStartMs; // wall-clock ms of the first matching frame in a streak
  bool _hitFlash = false;
  NoteMascotMood _mascot = NoteMascotMood.idle;
  ({PitchCaptureError reason, String? detail})? _error;

  String get _gameId =>
      widget.clef == Clef.bass ? 'perform_read_bass' : 'perform_read';

  @override
  int get targetMidi => _target.midiNumber;
  @override
  int get score => _score;
  @override
  int get done => _done;
  @override
  bool get finished => _finished;

  @override
  void initState() {
    super.initState();
    _wide = context.read<ProgressService>().starsFor(_gameId) >= 2;
    _nextTarget();
    _startMic();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _service.dispose();
    super.dispose();
  }

  Future<void> _startMic() async {
    try {
      _sub = _service.readings.listen(
        _onReading,
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
    } on PitchCaptureException catch (e) {
      await _sub?.cancel();
      if (mounted) {
        setState(() => _error = (reason: e.reason, detail: e.detail));
      }
    }
  }

  void _nextTarget() {
    // Singable / playable range; widens with mastery like the reading quizzes.
    final pos = _wide ? -2 + _random.nextInt(11) : _random.nextInt(8);
    _target = widget.clef.pitchAt(pos);
    _matchStartMs = null;
  }

  String _sriId() =>
      'note_reading.${widget.clef.name}.${_target.step.name}${_target.octave}';

  // Octave-agnostic: the note NAME matters, not the register.
  bool _matches(PitchReading r) =>
      r.hasPitch &&
      r.clarity >= PerformItScreen._minClarity &&
      r.nearestMidi % 12 == _target.midiNumber % 12;

  void _onReading(PitchReading r) {
    if (!mounted || _finished) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    setState(() => _reading = r);
    if (_matches(r)) {
      _matchStartMs ??= now;
      if (now - _matchStartMs! >= PerformItScreen._holdMs) _onHit();
    } else {
      _matchStartMs = null;
    }
  }

  void _onHit() {
    if (_finished) return;
    context.read<SriService>().recordResponse(_sriId(), true);
    context.read<AudioService>().playCorrect();
    _score += 10;
    _mascot = NoteMascotMood.happy;
    _hitFlash = true;
    _advance();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _hitFlash = false);
    });
  }

  void _skip() {
    if (_finished) return;
    _mascot = NoteMascotMood.oops;
    _advance();
  }

  void _advance() {
    _done++;
    if (_done >= PerformItScreen._kNotes) {
      _finish();
    } else {
      setState(_nextTarget);
    }
  }

  void _finish() {
    _sub?.cancel();
    _service.stop();
    final stars = scoreToStars(_gameId, _score, true);
    context.read<ProgressService>().recordResult(
          _gameId,
          score: _score,
          stars: stars,
        );
    context.read<AudioService>().playFanfare();
    setState(() => _finished = true);
  }

  void _restart() {
    setState(() {
      _done = 0;
      _score = 0;
      _finished = false;
      _mascot = NoteMascotMood.idle;
      _nextTarget();
    });
    _startMic();
  }

  @override
  void debugPerform() => _onHit();
  @override
  void debugSkip() => _skip();

  String _errorText(AppLocalizations l) => switch (_error!.reason) {
        PitchCaptureError.permissionDenied => l.micPermissionDenied,
        PitchCaptureError.unsupported => l.micUnsupported,
        _ => l.micStartFailed(_error!.detail ?? _error!.reason.name),
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final onTarget = _matches(_reading);

    return Scaffold(
      appBar: GameAppBar(title: l10n.gamePerformIt),
      body: SafeArea(
        child: _finished
            ? GameResultView(
                gameType: _gameId,
                score: _score,
                onRestart: _restart,
              )
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        NoteMascot(mood: _mascot, size: 30),
                        const SizedBox(width: 8),
                        Text(
                          '${_done + 1} / ${PerformItScreen._kNotes}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        const Icon(Icons.star, color: Colors.amber, size: 20),
                        const SizedBox(width: 4),
                        Text(
                          '$_score',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.performItPrompt,
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    Expanded(
                      child: Center(
                        child: Card(
                          color: _hitFlash ? Colors.green.shade100 : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 40,
                              vertical: 16,
                            ),
                            child: StaffView(
                              score: Score(
                                clef: widget.clef,
                                measures: [
                                  Measure([
                                    NoteElement.note(
                                      _target,
                                      const NoteDuration(DurationBase.whole),
                                      id: 'target',
                                    ),
                                  ]),
                                ],
                              ),
                              staffSpace: 16,
                              theme: kidsScoreTheme.copyWith(
                                elementColors: {
                                  'target': onTarget
                                      ? Colors.green
                                      : pitchClassColor(_target.step),
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Live detected-pitch readout.
                    Text(
                      _reading.hasPitch
                          ? spelledMidiName(context, _reading.nearestMidi)
                          : '—',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(
                            color: onTarget ? Colors.green : scheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      onTarget ? l10n.performItOnTarget : ' ',
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          _errorText(l10n),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _skip,
                      icon: const Icon(Icons.skip_next),
                      label: Text(l10n.performItSkip),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
