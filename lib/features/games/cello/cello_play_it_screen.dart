// lib/features/games/cello/cello_play_it_screen.dart
//
// "Play It" for the Cello Corner — mic grading on the real instrument
// (docs/PLAN.md live-mic follow-ups). A first-position note is shown on the
// bass staff, with a string + finger hint; the child bows it on their real
// cello and the live pitch detector verifies it. Matching is octave-agnostic
// and must hold for a moment to shrug off the bow's scratchy attack. Turns the
// finger/string knowledge active — the child actually plays, not taps.
//
// Feeds the cello play pool: SRI 'cello.play.<step><octave>'.

import 'dart:async';
import 'dart:math';

import 'package:comet_beat/core/audio/microphone_pitch_service.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/core/tuning.dart';
import 'package:comet_beat/features/games/cello/cello_first_position.dart';
import 'package:comet_beat/features/games/note_reading/note_names.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:comet_beat/shared/widgets/note_mascot.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

class CelloPlayItScreen extends StatefulWidget {
  const CelloPlayItScreen({super.key});

  static const _kNotes = 8;

  /// Clarity floor + how long the right pitch must hold to count as played.
  /// A hair longer than the sung games — bow attacks are noisy.
  static const _minClarity = 0.6;
  static const _holdMs = 360;

  @override
  State<CelloPlayItScreen> createState() => _CelloPlayItScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class CelloPlayItTester {
  int get targetMidi;
  int get score;
  int get done;
  bool get finished;

  /// Simulate having played the current target note correctly.
  void debugPlayed();

  /// Skip the current note (advance without credit).
  void debugSkip();
}

class _CelloPlayItScreenState extends State<CelloPlayItScreen>
    implements CelloPlayItTester {
  final MicrophonePitchService _service = MicrophonePitchService();
  StreamSubscription<PitchReading>? _sub;
  final _random = Random();

  late CelloNote _target;
  int _done = 0; // notes resolved (played or skipped)
  int _score = 0;
  bool _finished = false;

  PitchReading _reading = PitchReading.silent();
  int? _matchStartMs; // wall-clock ms of the first matching frame in a streak
  bool _hitFlash = false;
  NoteMascotMood _mascot = NoteMascotMood.idle;
  ({PitchCaptureError reason, String? detail})? _error;

  @override
  int get targetMidi => _target.pitch.midiNumber;
  @override
  int get score => _score;
  @override
  int get done => _done;
  @override
  bool get finished => _finished;

  @override
  void initState() {
    super.initState();
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
    _target = kCelloFirstPosition[_random.nextInt(kCelloFirstPosition.length)];
    _matchStartMs = null;
  }

  String _sriId() =>
      'cello.play.${_target.pitch.step.name}${_target.pitch.octave}';

  void _playTarget() =>
      context.read<AudioService>().playMidiNote(_target.pitch.midiNumber);

  // Octave-agnostic: the note NAME matters, not the register. (Kind to the
  // low C string, which some mics track an octave high.)
  bool _matches(PitchReading r) =>
      r.hasPitch &&
      r.clarity >= CelloPlayItScreen._minClarity &&
      r.nearestMidi % 12 == _target.pitch.midiNumber % 12;

  void _onReading(PitchReading r) {
    if (!mounted || _finished) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    setState(() => _reading = r);
    if (_matches(r)) {
      _matchStartMs ??= now;
      if (now - _matchStartMs! >= CelloPlayItScreen._holdMs) _onHit();
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
    if (_done >= CelloPlayItScreen._kNotes) {
      _finish();
    } else {
      setState(_nextTarget);
    }
  }

  void _finish() {
    _sub?.cancel();
    _service.stop();
    final stars = scoreToStars('cello_play_it', _score, true);
    context.read<ProgressService>().recordResult(
          'cello_play_it',
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
  void debugPlayed() => _onHit();
  @override
  void debugSkip() => _skip();

  String _errorText(AppLocalizations l) => switch (_error!.reason) {
        PitchCaptureError.permissionDenied => l.micPermissionDenied,
        PitchCaptureError.unsupported => l.micUnsupported,
        _ => l.micStartFailed(_error!.detail ?? _error!.reason.name),
      };

  String _hint(AppLocalizations l) {
    final string = _target.string.label(l);
    return _target.finger == 0
        ? l.celloPlayItOpenString(string)
        : l.celloPlayItFingered(string, _target.finger);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final onTarget = _matches(_reading);

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameCelloPlayIt),
      body: SafeArea(
        child: _finished
            ? GameResultView(
                gameType: 'cello_play_it',
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
                          '${_done + 1} / ${CelloPlayItScreen._kNotes}',
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
                      l10n.celloPlayItPrompt,
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    Expanded(
                      child: Center(
                        child: Card(
                          color: _hitFlash ? Colors.green.shade100 : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 16,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                StaffView(
                                  score: Score.simple(
                                    clef: Clef.bass,
                                    notes: '${_target.pitch.step.name}'
                                        '${_target.pitch.octave}:w',
                                  ),
                                  staffSpace: 14,
                                  theme: kidsScoreTheme,
                                ),
                                const SizedBox(height: 12),
                                Chip(
                                  avatar: const Icon(Icons.back_hand, size: 18),
                                  label: Text(_hint(l10n)),
                                ),
                              ],
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _playTarget,
                          icon: const Icon(Icons.volume_up),
                          label: Text(l10n.singBackListen),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: _skip,
                          icon: const Icon(Icons.skip_next),
                          label: Text(l10n.performItSkip),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
