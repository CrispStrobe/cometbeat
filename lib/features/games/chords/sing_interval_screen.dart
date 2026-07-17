// lib/features/games/chords/sing_interval_screen.dart
//
// "Sing the Interval" — ear→voice interval training (docs/PLAN.md mic
// follow-ups). Two notes play, low then high — an interval — and its name is
// shown ("a fifth"). The child sings the TOP note back; the mic checks the pitch
// (octave-agnostic, so any comfortable register counts), held briefly to avoid
// false hits. Builds interval vocabulary AND the voice to reproduce it — the
// sung twin of Interval Ear. No instrument needed.
//
// Third / fourth / fifth for beginners; second + sixth join at 2★. Feeds the
// interval pool: SRI 'intervals.sing.<name>'.

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
// Material also exports `Step` and `Interval` (a curve); crisp_notation's win.
import 'package:flutter/material.dart' hide Interval, Step;
import 'package:provider/provider.dart';

class SingIntervalScreen extends StatefulWidget {
  const SingIntervalScreen({super.key});

  static const _kNotes = 8;
  static const _minClarity = 0.6;
  static const _holdMs = 320;

  // Comfortable low-ish roots, so the top note stays singable.
  static const _roots = [Step.c, Step.d, Step.e, Step.f, Step.g];

  // Consonant, easy-to-pitch intervals first; the 2nd and 6th widen at 2★.
  static const _easy = [
    Interval.majorThird,
    Interval.perfectFourth,
    Interval.perfectFifth,
  ];
  static const _wideExtra = [Interval.majorSecond, Interval.majorSixth];

  @override
  State<SingIntervalScreen> createState() => _SingIntervalScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class SingIntervalTester {
  /// Pitch class (0–11) the child must sing — the interval's top note.
  int get targetPitchClass;
  int get score;
  int get done;
  bool get finished;
  void debugSang();
  void debugSkip();
}

class _SingIntervalScreenState extends State<SingIntervalScreen>
    implements SingIntervalTester {
  final MicrophonePitchService _service = MicrophonePitchService();
  StreamSubscription<PitchReading>? _sub;
  final _random = Random();

  late Pitch _root;
  late Interval _interval;
  int _done = 0;
  int _score = 0;
  bool _finished = false;
  bool _revealed = false; // show the answer after a correct sing

  PitchReading _reading = PitchReading.silent();
  int? _matchStartMs;
  NoteMascotMood _mascot = NoteMascotMood.idle;
  ({PitchCaptureError reason, String? detail})? _error;

  Pitch get _top => _root.transposeBy(_interval);

  @override
  int get targetPitchClass => _top.midiNumber % 12;
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _playInterval());
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
              () => _error = (reason: PitchCaptureError.unknown, detail: '$e'),
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

  List<Interval> get _pool {
    final wide = context.read<ProgressService>().starsFor('sing_interval') >= 2;
    return [
      ...SingIntervalScreen._easy,
      if (wide) ...SingIntervalScreen._wideExtra,
    ];
  }

  void _nextTarget() {
    _root = Pitch(SingIntervalScreen._roots[_random.nextInt(5)]);
    final pool = _pool;
    _interval = pool[_random.nextInt(pool.length)];
    _matchStartMs = null;
    _revealed = false;
  }

  void _playInterval() => context.read<AudioService>().playSequence([
        (_root.midiNumber, 600),
        (_top.midiNumber, 900),
      ]);

  String get _intervalKey => switch (_interval.number) {
        2 => 'second',
        3 => 'third',
        4 => 'fourth',
        5 => 'fifth',
        _ => 'sixth',
      };

  String _intervalName(AppLocalizations l10n) => switch (_interval.number) {
        2 => l10n.intervalSecond,
        3 => l10n.intervalThird,
        4 => l10n.intervalFourth,
        5 => l10n.intervalFifth,
        _ => l10n.intervalSixth,
      };

  String _sriId() => 'intervals.sing.$_intervalKey';

  bool _matches(PitchReading r) =>
      r.hasPitch &&
      r.clarity >= SingIntervalScreen._minClarity &&
      r.nearestMidi % 12 == targetPitchClass;

  void _onReading(PitchReading r) {
    if (!mounted || _finished || _revealed) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    setState(() => _reading = r);
    if (_matches(r)) {
      _matchStartMs ??= now;
      if (now - _matchStartMs! >= SingIntervalScreen._holdMs) _onCorrect();
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
    if (_done >= SingIntervalScreen._kNotes) {
      _finish();
    } else {
      setState(_nextTarget);
      _playInterval();
    }
  }

  void _finish() {
    _sub?.cancel();
    _service.stop();
    final stars = scoreToStars('sing_interval', _score, true);
    context
        .read<ProgressService>()
        .recordResult('sing_interval', score: _score, stars: stars);
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
    _playInterval();
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
      appBar: GameAppBar(title: l10n.gameSingInterval),
      body: SafeArea(
        child: _finished
            ? GameResultView(
                gameType: 'sing_interval',
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
                          '${_done + 1} / ${SingIntervalScreen._kNotes}',
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
                      l10n.singIntervalPrompt(_intervalName(l10n)),
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    Expanded(
                      child: Center(
                        child: _revealed
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _intervalName(l10n),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(color: scheme.primary),
                                  ),
                                  Text(
                                    spelledMidiName(context, _top.midiNumber),
                                    style: Theme.of(context)
                                        .textTheme
                                        .displayMedium
                                        ?.copyWith(
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ],
                              )
                            : IconButton.filledTonal(
                                iconSize: 88,
                                padding: const EdgeInsets.all(28),
                                icon: const Icon(Icons.volume_up),
                                tooltip: l10n.singBackListen,
                                onPressed: _playInterval,
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
