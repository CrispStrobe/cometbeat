// lib/features/games/scales/sing_back_screen.dart
//
// "Sing Back" — ear→voice training (docs/PLAN.md live-mic follow-ups). A note
// plays; the child sings it back and the mic checks the pitch (octave-agnostic,
// so any comfortable register counts), held briefly to avoid false hits. The
// target is HEARD, not shown, so it trains pitch memory and matching — and needs
// no instrument. Feeds the ear pool: SRI 'scales.hear.sing_<step>'.

import 'dart:async';
import 'dart:math';

import 'package:comet_beat/core/audio/microphone_pitch_service.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/core/tuning.dart';
import 'package:comet_beat/features/games/note_reading/note_names.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/note_mascot.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material also exports `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

class SingBackScreen extends StatefulWidget {
  const SingBackScreen({super.key});

  static const _kNotes = 8;
  static const _minClarity = 0.6;
  static const _holdMs = 320;

  // Comfortable kid singing range: naturals from middle C up.
  static const _steps = [
    Step.c,
    Step.d,
    Step.e,
    Step.f,
    Step.g,
    Step.a,
    Step.b,
  ];

  @override
  State<SingBackScreen> createState() => _SingBackScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class SingBackTester {
  int get targetMidi;
  int get score;
  int get done;
  bool get finished;
  void debugSang();
  void debugSkip();
}

class _SingBackScreenState extends State<SingBackScreen>
    implements SingBackTester {
  final MicrophonePitchService _service = MicrophonePitchService();
  StreamSubscription<PitchReading>? _sub;
  final _random = Random();

  late Pitch _target;
  int _done = 0;
  int _score = 0;
  bool _finished = false;
  bool _revealed = false; // show the answer after a correct sing

  PitchReading _reading = PitchReading.silent();
  int? _matchStartMs;
  NoteMascotMood _mascot = NoteMascotMood.idle;
  ({PitchCaptureError reason, String? detail})? _error;

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
    _nextTarget();
    _startMic();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playTarget());
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
    final step = SingBackScreen._steps[_random.nextInt(7)];
    _target = Pitch(step);
    _matchStartMs = null;
    _revealed = false;
  }

  void _playTarget() =>
      context.read<AudioService>().playMidiNote(_target.midiNumber);

  String _sriId() => 'scales.hear.sing_${_target.step.name}';

  bool _matches(PitchReading r) =>
      r.hasPitch &&
      r.clarity >= SingBackScreen._minClarity &&
      r.nearestMidi % 12 == _target.midiNumber % 12;

  void _onReading(PitchReading r) {
    if (!mounted || _finished || _revealed) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    setState(() => _reading = r);
    if (_matches(r)) {
      _matchStartMs ??= now;
      if (now - _matchStartMs! >= SingBackScreen._holdMs) _onCorrect();
    } else {
      _matchStartMs = null;
    }
  }

  void _onCorrect() {
    if (_finished || _revealed) return;
    context.read<SriService>().recordResponse(_sriId(), true);
    _score += 10;
    _mascot = NoteMascotMood.happy;
    setState(() => _revealed = true);
    // Show the answer for a beat, then move on.
    Future.delayed(const Duration(milliseconds: 900), _advance);
  }

  void _skip() {
    if (_finished) return;
    _mascot = NoteMascotMood.oops;
    _advance();
  }

  void _advance() {
    if (_finished) return;
    _done++;
    if (_done >= SingBackScreen._kNotes) {
      _finish();
    } else {
      setState(_nextTarget);
      _playTarget();
    }
  }

  void _finish() {
    _sub?.cancel();
    _service.stop();
    final stars = scoreToStars('sing_back', _score, true);
    context
        .read<ProgressService>()
        .recordResult('sing_back', score: _score, stars: stars);
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
    _playTarget();
  }

  @override
  void debugSang() => _onCorrect();
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
      appBar: GameAppBar(title: l10n.gameSingBack),
      body: SafeArea(
        child: _finished
            ? GameResultView(
                gameType: 'sing_back',
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
                          '${_done + 1} / ${SingBackScreen._kNotes}',
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
                      l10n.singBackPrompt,
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    Expanded(
                      child: Center(
                        child: _revealed
                            ? Text(
                                spelledMidiName(context, _target.midiNumber),
                                style: Theme.of(context)
                                    .textTheme
                                    .displayMedium
                                    ?.copyWith(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                              )
                            : IconButton.filledTonal(
                                iconSize: 88,
                                padding: const EdgeInsets.all(28),
                                icon: const Icon(Icons.volume_up),
                                tooltip: l10n.singBackListen,
                                onPressed: _playTarget,
                              ),
                      ),
                    ),
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
