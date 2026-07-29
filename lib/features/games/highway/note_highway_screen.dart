// lib/features/games/highway/note_highway_screen.dart
//
// THE NOTE HIGHWAY game screen — one screen, every instrument.
//
// It owns the clock, the audio, and the choices; the musical work is all
// elsewhere (chart → lanes → grading). The three settings that matter are:
//
//   MODE     watch (the piece plays itself — the fastest way to learn a tune)
//            or play (you answer the blocks on the rail).
//   HANDS    which voices YOU are responsible for. The rest keep falling and
//            play themselves, so hands-separate practice still shows you what
//            you are fitting into.
//   FEEL     difficulty (windows + scaffolds), skin, and flat vs arcade
//            projection. None of these change the music, only how much help
//            you get and how it looks.
//
// ⚠ AUDIO: the app plays through ONE player, so a per-tap note and a backing
// track cannot sound at once — starting one stops the other. Rather than fight
// that, the rule is explicit: with the backing track ON you hear the piece and
// your taps are graded silently; with it OFF you hear yourself. Wait-for-me
// holds the clock, which a pre-rendered backing WAV cannot follow, so the two
// are mutually exclusive by construction.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data' show Float64List, Int16List, Uint8List;

import 'package:comet_beat/core/audio/microphone_pitch_service.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart' show PitchReading;
import 'package:comet_beat/core/audio/play_along.dart' show scaledStarScore;
import 'package:comet_beat/core/audio/synth.dart'
    show
        Drum,
        Segment,
        midiToFrequency,
        renderDrum,
        renderDrumPattern,
        renderWav,
        wavBytes;
import 'package:comet_beat/core/games/highway/highway_chart.dart';
import 'package:comet_beat/core/games/highway/highway_grading.dart';
import 'package:comet_beat/core/games/highway/highway_instrument.dart';
import 'package:comet_beat/core/games/highway/highway_lanes.dart';
import 'package:comet_beat/core/games/highway/highway_library.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/tuning.dart';
import 'package:comet_beat/features/games/highway/highway_strip.dart';
import 'package:comet_beat/features/games/highway/highway_theme.dart';
import 'package:comet_beat/features/games/highway/highway_view.dart';
import 'package:comet_beat/features/games/note_reading/note_names.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart' show Score;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Watch the piece play, or play it yourself.
enum HighwayMode { watch, play }

/// How the player answers the blocks.
enum HighwayInput {
  /// The instrument rail under the hit line. Works everywhere, needs no
  /// permission, and is what a phone is actually good at.
  touch,

  /// A real instrument, heard through the microphone. MONOPHONIC — the detector
  /// tracks one pitch at a time, so a chord is credited for whichever of its
  /// notes is heard, and the piano's two hands cannot both be graded this way.
  /// Being honest about that in the UI matters more than hiding it.
  microphone,
}

class NoteHighwayScreen extends StatefulWidget {
  const NoteHighwayScreen({
    super.key,
    this.instrument = HighwayInstrument.piano,
    required this.gameId,
    this.chart,
    this.score,
    this.title,
  });

  /// Which instrument the tile opened on. The player can still switch.
  final HighwayInstrument instrument;

  /// Key into [kStarThresholds] and [ProgressService].
  final String gameId;

  /// An external piece (a Song Book song, a Workshop score) instead of the
  /// built-in library. When set, the piece picker is hidden.
  final HighwayChart? chart;

  /// The engraved source behind [chart], when there is one. Its only job is the
  /// reading strip: with a score the strip shows the REAL BAR, lit as it plays,
  /// instead of note-name chips.
  final Score? score;

  final String? title;

  @override
  State<NoteHighwayScreen> createState() => _NoteHighwayScreenState();
}

class _NoteHighwayScreenState extends State<NoteHighwayScreen>
    with SingleTickerProviderStateMixin {
  late HighwayInstrument _instrument = widget.instrument;
  HighwayPiece? _piece;

  HighwayDifficulty _difficulty = HighwayDifficulty.easy;
  HighwaySkin _skin = HighwaySkin.midnight;
  HighwayProjection _projection = HighwayProjection.flat;
  HighwayMode _mode = HighwayMode.play;
  HighwayInput _input = HighwayInput.touch;
  bool _showStrip = true;
  bool _backing = false;
  double _tempoScale = 1;

  /// Voices the player takes on. Empty = decided at start (all of them).
  Set<int> _hands = {};

  /// The bars being drilled, 1-based and inclusive. Null = the whole piece.
  ///
  /// A loop is PRACTICE, not a run: it repeats until you stop it and records no
  /// score. Anything else would be dishonest — eight bars played twenty times
  /// is not the same achievement as the piece, and letting it count would make
  /// stars measure patience.
  (int, int)? _loopBars;

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  bool _running = false;
  bool _finished = false;
  double _beat = 0;
  int _lastClick = -99;

  HighwayChart? _chart;

  /// The chart's length, resolved ONCE per run — `totalBeats` walks every event
  /// and this is read on every tick.
  double _totalBeats = 0;
  HighwayLaneMap? _laneMap;
  HighwayGrader? _grader;
  final List<HighwayFlash> _flashes = [];

  /// Physical-keyboard play. The number row maps to the lanes left to right —
  /// 1 = kick … 5 = crash — which is how a drum machine has always been typed,
  /// and it is the only way this is playable on a desktop or with a keyboard
  /// case. Pitched instruments keep the letter row for a later slice; the pads
  /// are what needed it.
  final FocusNode _keyFocus = FocusNode(debugLabel: 'highway-keys');

  // --- microphone ------------------------------------------------------------
  final MicrophonePitchService _mic = MicrophonePitchService();
  StreamSubscription<PitchReading>? _micSub;
  ({PitchCaptureError reason, String? detail})? _micError;

  /// The pitch last fed to the grader. A detector reports the SAME note on
  /// every frame it is held, and feeding each frame would hammer the grader
  /// with a note it has already answered; a new note only counts once the
  /// heard pitch changes.
  int? _lastHeardMidi;

  /// The live pitch, for the marker on the pitch-axis view.
  double? _livePitch;

  static const double _countInBeats = 4;

  @override
  void initState() {
    super.initState();
    // A Ticker must be created eagerly — a lazy `late final` one can be built
    // during dispose and throws a deactivated-ancestor error.
    _ticker = createTicker(_onTick);
    _piece = _piecesForInstrument.isEmpty ? null : _piecesForInstrument.first;
  }

  @override
  void dispose() {
    _keyFocus.dispose();
    _ticker.dispose();
    unawaited(_micSub?.cancel());
    _mic.dispose();
    super.dispose();
  }

  /// True when this instrument can be graded by ear at all. The detector is
  /// monophonic, so the pad/drum maps (no pitch to hear) are excluded.
  bool get _micUsable =>
      _instrument != HighwayInstrument.drums &&
      _instrument != HighwayInstrument.pads;

  Future<void> _startMic() async {
    setState(() => _micError = null);
    try {
      _micSub = _mic.readings.listen(
        _onHeard,
        onError: (Object e) {
          if (mounted) {
            setState(
              () => _micError = (
                reason: PitchCaptureError.unknown,
                detail: '$e',
              ),
            );
          }
        },
      );
      await _mic.start();
    } on PitchCaptureException catch (e) {
      await _micSub?.cancel();
      _micSub = null;
      if (mounted) {
        setState(() => _micError = (reason: e.reason, detail: e.detail));
      }
    }
  }

  Future<void> _stopMic() async {
    await _micSub?.cancel();
    _micSub = null;
    await _mic.stop();
    _lastHeardMidi = null;
    _livePitch = null;
    // The mic can leave the mobile audio session on the quiet earpiece; put
    // playback back on the speaker or the rest of the app goes silent.
    if (mounted) await context.read<AudioService>().configurePlaybackRoute();
  }

  /// One analysed window from the microphone.
  void _onHeard(PitchReading reading) {
    if (!mounted || !_running) return;
    _livePitch = reading.hasPitch ? reading.midi : null;
    final grader = _grader;
    if (grader == null || _mode == HighwayMode.watch) return;
    if (!reading.hasPitch) {
      _lastHeardMidi = null; // silence re-arms the next note
      return;
    }
    final midi = reading.nearestMidi;
    if (midi == _lastHeardMidi) return; // still the same note being held
    _lastHeardMidi = midi;
    if (_beat < -_rules.hitWindowBeats) return; // still counting in

    final key = _laneMap?.keyForMidi(midi);
    if (key == null) return;
    final result = grader.tap(key, _beat, breaksStreak: false);
    // Heard something the chart did not ask for: noise, not a mistake.
    if (!result.isHit) return;
    setState(() {
      _flashes.add(
        HighwayFlash(
          unitX: key.slot.center,
          beat: _beat,
          perfect: result.quality == HighwayHitQuality.perfect,
        ),
      );
    });
  }

  HighwayInstrumentProfile get _profile =>
      HighwayInstrumentProfile.of(_instrument);

  List<HighwayPiece> get _piecesForInstrument =>
      HighwayLibrary.forInstrument(_instrument);

  HighwayRules get _rules => HighwayRules.of(_difficulty);

  HighwayPalette get _palette => HighwayPalette.of(_skin);

  HighwayChart? get _sourceChart => widget.chart ?? _piece?.chart;

  // --- running ---------------------------------------------------------------

  void _start() {
    final full = _sourceChart;
    if (full == null) return;
    final loop = _loopBars;
    final source = loop == null ? full : full.section(loop.$1, loop.$2);
    if (source.isEmpty) return;
    final prepared = _profile.prepare(source.atTempo(source.bpm * _tempoScale));
    final laneMap = _profile.laneMapFor(prepared);
    final voices = prepared.voices;
    final graded = _mode == HighwayMode.watch
        ? <int>{}
        : (_hands.isEmpty
            ? voices.toSet()
            : _hands.intersection(voices.toSet()));

    setState(() {
      _chart = prepared;
      _totalBeats = prepared.totalBeats;
      _laneMap = laneMap;
      _grader = HighwayGrader(
        chart: prepared,
        rules: _rules,
        laneMap: laneMap,
        gradedVoices: graded,
      );
      _flashes.clear();
      _beat = _loopStartBeat - _countInBeats;
      _lastClick = -99;
      _finished = false;
      _running = true;
    });
    _lastTick = Duration.zero;
    _ticker
      ..stop()
      ..start();
    if (_usingMic) unawaited(_startMic());
  }

  /// Microphone input is only actually in use when the player asked for it, the
  /// instrument can be heard, and they are playing rather than watching.
  bool get _usingMic =>
      _input == HighwayInput.microphone &&
      _micUsable &&
      _mode == HighwayMode.play;

  /// The beat the clock starts (and, when looping, returns) to.
  double get _loopStartBeat {
    final loop = _loopBars;
    final chart = _sourceChart;
    if (loop == null || chart == null) return 0;
    return chart.beatOfBar(loop.$1);
  }

  /// One past the last beat of the loop.
  double get _loopEndBeat {
    final loop = _loopBars;
    final chart = _sourceChart;
    if (loop == null || chart == null) return double.infinity;
    return chart.beatOfBar(loop.$2 + 1);
  }

  /// Re-arms the section for another pass. A fresh grader is the whole trick:
  /// the notes go back to pending, so the second time through is graded like
  /// the first instead of showing last pass's verdicts.
  void _restartLoop() {
    final chart = _chart;
    final laneMap = _laneMap;
    final previous = _grader;
    if (chart == null || laneMap == null || previous == null) return;
    setState(() {
      _grader = HighwayGrader(
        chart: chart,
        rules: _rules,
        laneMap: laneMap,
        gradedVoices: previous.gradedVoices,
      );
      _flashes.clear();
      _beat = _loopStartBeat;
    });
  }

  void _stop() {
    _ticker.stop();
    context.read<AudioService>().stop();
    unawaited(_stopMic());
    setState(() => _running = false);
  }

  void _onTick(Duration elapsed) {
    if (!_running || _chart == null) return;
    final dtMs = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1000.0;
    _lastTick = elapsed;
    final chart = _chart!;
    final grader = _grader!;

    var next = _beat + dtMs / chart.beatMs;
    final hold = grader.holdBeat;
    if (hold != null && next > hold) next = math.max(_beat, hold);

    // Count-in clicks, and the backing track at the downbeat.
    final clickBeat = next.floor();
    if (next < 0 && clickBeat != _lastClick) {
      _lastClick = clickBeat;
      context.read<AudioService>().playTick(accent: clickBeat == -4);
    }
    if (_beat < 0 && next >= 0 && _backingWanted) {
      unawaited(context.read<AudioService>().playWavBytes(_renderBacking()));
    }

    _beat = next;
    grader.advanceTo(_beat);
    _flashes.removeWhere((f) => _beat - f.beat > 1.0);

    // A loop never finishes: it comes round again until the player stops it.
    if (_loopBars != null) {
      if (_beat > _loopEndBeat) {
        _restartLoop();
        return;
      }
      setState(() {});
      return;
    }

    if (_beat > _totalBeats + 1.2 || (grader.total > 0 && grader.finished)) {
      _finish();
      return;
    }
    setState(() {});
  }

  /// A backing track can only run when nothing else needs the player and the
  /// clock is free-running (see the audio note at the top of the file).
  bool get _backingWanted =>
      _mode == HighwayMode.watch || (_backing && !_rules.waitForMe);

  void _finish() {
    _ticker.stop();
    unawaited(_stopMic());
    final grader = _grader;
    setState(() {
      _running = false;
      _finished = true;
    });
    if (grader == null ||
        _mode == HighwayMode.watch ||
        _loopBars != null ||
        grader.total == 0) {
      return; // watching and drilling a section are not scored runs
    }
    context.read<ProgressService>().recordResult(
          widget.gameId,
          score: grader.hits,
          stars: scoreToStars(widget.gameId, _starScore, grader.hits > 0),
        );
  }

  int get _starScore {
    final grader = _grader;
    if (grader == null) return 0;
    return scaledStarScore(
      grader.hits,
      grader.total,
      kStarThresholds[widget.gameId] ?? const [1, 2, 3],
    );
  }

  // --- audio -----------------------------------------------------------------

  /// Which voices the backing track plays: everything in watch mode, and in
  /// hands-separate play the hand the learner did NOT take on — so practising
  /// one hand still sounds like the whole piece.
  Set<int> get _backingVoices {
    final all = (_chart?.voices ?? const <int>[]).toSet();
    final graded = _grader?.gradedVoices;
    if (graded == null || graded.isEmpty) return all;
    return all.difference(graded);
  }

  /// The backing rendered with THIS instrument's voice — a guitar highway must
  /// not sound like a piano, and a drum groove is not a chord at all.
  Uint8List _renderBacking() {
    final chart = _chart!;
    if (_instrument == HighwayInstrument.drums) {
      final beatMs = chart.beatMs;
      final hits = <(int, Drum)>[
        for (final e in chart.events)
          if (e.lane != null && e.lane! < kHighwayDrumLanes.length)
            ((e.startBeat * beatMs).round(), kHighwayDrumLanes[e.lane!]),
      ];
      return wavBytes(
        _pcm16(
          renderDrumPattern(
            hits,
            totalMs: ((_totalBeats + 1) * beatMs).round(),
          ),
        ),
      );
    }
    final keep = _backingVoices;
    final events = chart.timedChords(keep: keep.isEmpty ? null : keep);
    final segments = <Segment>[
      for (final (midis, ms) in events)
        if (ms > 0)
          (freqs: [for (final m in midis) midiToFrequency(m)], ms: ms),
    ];
    return renderWav(segments, timbre: _profile.timbre);
  }

  Int16List _pcm16(Float64List pcm) {
    final out = Int16List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      out[i] = (pcm[i].clamp(-1.0, 1.0) * 32767).round();
    }
    return out;
  }

  /// A kit piece, played the moment its pad is hit. Drums have no pitch, so
  /// this is a different path from [_playTapSound] rather than a special case
  /// of it.
  void _playDrum(int lane) {
    if (_backingWanted) return; // the backing owns the single player
    if (lane < 0 || lane >= kHighwayDrumLanes.length) return;
    unawaited(
      context
          .read<AudioService>()
          .playWavBytes(wavBytes(_pcm16(renderDrum(kHighwayDrumLanes[lane])))),
    );
  }

  void _playTapSound(int midi) {
    if (_backingWanted) return; // the backing owns the player
    unawaited(
      context.read<AudioService>().playWavBytes(
            renderWav(
              [
                (freqs: [midiToFrequency(midi)], ms: 420),
              ],
              timbre: _profile.timbre,
            ),
          ),
    );
  }

  /// Which lane a key press means, or null. Digits 1..9 and the numpad both
  /// work; a laptop's number row is the obvious target but a numpad is what a
  /// desk player will reach for.
  int? _laneForKey(LogicalKeyboardKey key) {
    const digits = [
      [LogicalKeyboardKey.digit1, LogicalKeyboardKey.numpad1],
      [LogicalKeyboardKey.digit2, LogicalKeyboardKey.numpad2],
      [LogicalKeyboardKey.digit3, LogicalKeyboardKey.numpad3],
      [LogicalKeyboardKey.digit4, LogicalKeyboardKey.numpad4],
      [LogicalKeyboardKey.digit5, LogicalKeyboardKey.numpad5],
      [LogicalKeyboardKey.digit6, LogicalKeyboardKey.numpad6],
      [LogicalKeyboardKey.digit7, LogicalKeyboardKey.numpad7],
      [LogicalKeyboardKey.digit8, LogicalKeyboardKey.numpad8],
      [LogicalKeyboardKey.digit9, LogicalKeyboardKey.numpad9],
    ];
    for (var i = 0; i < digits.length; i++) {
      if (digits[i].contains(key)) return i;
    }
    return null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // Only key DOWN: a repeat would machine-gun the lane, and a key-up would
    // double every hit.
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final laneMap = _laneMap;
    if (!_running || laneMap == null || _mode == HighwayMode.watch) {
      return KeyEventResult.ignored;
    }
    final lane = _laneForKey(event.logicalKey);
    if (lane == null || lane >= laneMap.laneCount) {
      return KeyEventResult.ignored;
    }
    final key = laneMap.railKeys().firstWhere(
          (k) => k.lane == lane,
          orElse: () => laneMap.railKeys().first,
        );
    _onRailTap(key);
    return KeyEventResult.handled;
  }

  void _onRailTap(HighwayRailKey key) {
    final grader = _grader;
    if (!_running || grader == null || _mode == HighwayMode.watch) return;
    if (_beat < -_rules.hitWindowBeats) return; // still counting in
    final result = grader.tap(key, _beat);
    if (_instrument == HighwayInstrument.drums) {
      _playDrum(key.lane);
    } else {
      final midi = result.note?.event.midi ?? key.midi;
      if (midi != null) _playTapSound(midi);
    }
    setState(() {
      _flashes.add(
        HighwayFlash(
          unitX: key.slot.center,
          beat: _beat,
          perfect: result.quality == HighwayHitQuality.perfect,
          missed: !result.isHit,
        ),
      );
    });
  }

  // --- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final title = widget.title ?? l.gameNoteHighway;
    return Scaffold(
      appBar: GameAppBar(
        title: title,
        actions: [
          if (_running || _finished)
            IconButton(
              tooltip: l.highwayOptions,
              icon: const Icon(Icons.tune),
              onPressed: () {
                if (_running) _stop();
                setState(() => _finished = false);
              },
            ),
        ],
      ),
      body: SafeArea(child: _body(context, l)),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l) {
    if (_finished &&
        _mode == HighwayMode.play &&
        _loopBars == null &&
        (_grader?.total ?? 0) > 0) {
      return GameResultView(
        gameType: widget.gameId,
        score: _grader!.hits,
        starScore: _starScore,
        onRestart: _start,
      );
    }
    if (!_running) return _setup(context, l);
    return _playing(context, l);
  }

  // --- setup -----------------------------------------------------------------

  Widget _setup(BuildContext context, AppLocalizations l) {
    final pieces = _piecesForInstrument;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _sectionLabel(l.highwayInstrument),
        _chips<HighwayInstrument>(
          values: HighwayInstrument.values,
          selected: _instrument,
          label: (i) => _instrumentName(l, i),
          onSelect: (i) => setState(() {
            _instrument = i;
            final list = HighwayLibrary.forInstrument(i);
            _piece = list.isEmpty ? null : list.first;
          }),
        ),
        if (widget.chart == null) ...[
          _sectionLabel(l.highwayPiece),
          if (pieces.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(l.highwayNoPieces),
            )
          else
            _chips<HighwayPiece>(
              values: pieces,
              selected: _piece,
              label: (p) => p.title,
              onSelect: (p) => setState(() => _piece = p),
            ),
        ],
        _sectionLabel(l.highwayMode),
        _chips<HighwayMode>(
          values: HighwayMode.values,
          selected: _mode,
          label: (m) =>
              m == HighwayMode.watch ? l.highwayModeWatch : l.highwayModePlay,
          onSelect: (m) => setState(() => _mode = m),
        ),
        if (_micUsable && _mode == HighwayMode.play) ...[
          _sectionLabel(l.highwayInput),
          _chips<HighwayInput>(
            values: HighwayInput.values,
            selected: _input,
            label: (i) => i == HighwayInput.touch
                ? l.highwayInputTouch
                : l.highwayInputMic,
            onSelect: (i) => setState(() => _input = i),
          ),
          if (_input == HighwayInput.microphone)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l.highwayInputMicHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_micError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _micErrorText(l),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
        _sectionLabel(l.highwayDifficulty),
        _chips<HighwayDifficulty>(
          values: HighwayDifficulty.values,
          selected: _difficulty,
          label: (d) => _difficultyName(l, d),
          onSelect: (d) => setState(() => _difficulty = d),
        ),
        _sectionLabel(l.highwaySkin),
        _chips<HighwaySkin>(
          values: HighwaySkin.values,
          selected: _skin,
          label: (s) => _skinName(l, s),
          onSelect: (s) => setState(() => _skin = s),
        ),
        _sectionLabel(l.highwayLook),
        _chips<HighwayProjection>(
          values: HighwayProjection.values,
          selected: _projection,
          label: (p) => p == HighwayProjection.flat
              ? l.highwayLookFlat
              : l.highwayLookArcade,
          onSelect: (p) => setState(() => _projection = p),
        ),
        if (_handsAvailable.length > 1) ...[
          _sectionLabel(l.highwayHands),
          _chips<String>(
            values: const ['all', '0', '1'],
            selected: _hands.isEmpty
                ? 'all'
                : (_hands.contains(0) && _hands.length == 1 ? '0' : '1'),
            label: (v) => switch (v) {
              'all' => l.highwayHandsBoth,
              '0' => l.highwayHandsFirst,
              _ => l.highwayHandsSecond,
            },
            onSelect: (v) => setState(() {
              _hands = switch (v) {
                'all' => <int>{},
                '0' => {0},
                _ => {1},
              };
            }),
          ),
        ],
        if (_barCount > 2) ...[
          _sectionLabel(l.highwayLoop),
          _loopControl(context, l),
        ],
        _sectionLabel('${l.highwayTempo} ${(_tempoScale * 100).round()}%'),
        Slider(
          value: _tempoScale,
          min: 0.5,
          max: 1.25,
          divisions: 15,
          label: '${(_tempoScale * 100).round()}%',
          onChanged: (v) => setState(() => _tempoScale = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _showStrip,
          onChanged: (v) => setState(() => _showStrip = v),
          title: Text(l.highwayShowStrip),
          subtitle: Text(
            _profile.isStringed
                ? l.highwayShowStripTab
                : l.highwayShowStripNames,
          ),
        ),
        if (_mode == HighwayMode.play)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _backing && !_rules.waitForMe,
            onChanged:
                _rules.waitForMe ? null : (v) => setState(() => _backing = v),
            title: Text(l.highwayBacking),
            subtitle: Text(
              _rules.waitForMe ? l.highwayBackingWaits : l.highwayBackingHint,
            ),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _sourceChart == null ? null : _start,
          icon: const Icon(Icons.play_arrow),
          label: Text(l.highwayStart),
        ),
      ],
    );
  }

  List<int> get _handsAvailable => _sourceChart?.voices ?? const [];

  int get _barCount => _sourceChart?.barCount ?? 1;

  /// Pick the bars to drill. A range slider rather than two steppers because
  /// the useful gesture is "that bit there", grabbed with a thumb, not two
  /// numbers typed in.
  Widget _loopControl(BuildContext context, AppLocalizations l) {
    final bars = _barCount;
    final loop = _loopBars;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                loop == null
                    ? l.highwayLoopWhole
                    : l.highwayLoopBars(loop.$1, loop.$2),
              ),
            ),
            if (loop != null)
              TextButton(
                onPressed: () => setState(() => _loopBars = null),
                child: Text(l.highwayLoopWhole),
              ),
          ],
        ),
        RangeSlider(
          values: RangeValues(
            (loop?.$1 ?? 1).toDouble(),
            (loop?.$2 ?? bars).toDouble(),
          ),
          min: 1,
          max: bars.toDouble(),
          divisions: bars > 1 ? bars - 1 : null,
          labels: RangeLabels(
            '${loop?.$1 ?? 1}',
            '${loop?.$2 ?? bars}',
          ),
          onChanged: (v) => setState(() {
            final from = v.start.round();
            final to = v.end.round();
            // The whole range is not a loop — it is just the piece.
            _loopBars = (from <= 1 && to >= bars) ? null : (from, to);
          }),
        ),
        if (loop != null)
          Text(
            l.highwayLoopHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      );

  Widget _chips<T>({
    required List<T> values,
    required T? selected,
    required String Function(T) label,
    required void Function(T) onSelect,
  }) =>
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final v in values)
            ChoiceChip(
              label: Text(label(v)),
              selected: v == selected,
              onSelected: (_) => onSelect(v),
            ),
        ],
      );

  // --- playing ---------------------------------------------------------------

  Widget _playing(BuildContext context, AppLocalizations l) {
    final chart = _chart!;
    final laneMap = _laneMap!;
    final grader = _grader!;
    final palette = _palette;
    final naming = context.read<SettingsService>().noteNaming;
    String noteName(int midi) => spelledMidiNameWith(l, naming, midi);

    final sounding = chart.eventsAt(_beat);
    final litMidi = <int>{
      for (final e in sounding)
        if (e.midi != null) e.midi!,
    };
    final litLanes = <int>{
      for (final e in sounding)
        if (e.lane != null) e.lane!,
    };

    // The keyboard only reaches the game while it is the focused thing.
    _keyFocus.requestFocus();
    return Column(
      children: [
        if (_showStrip)
          HighwayReadingStrip(
            chart: chart,
            laneMap: laneMap,
            beat: _beat,
            palette: palette,
            mode: switch (_instrument) {
              _ when _profile.isStringed => HighwayStripMode.tab,
              // A score behind the chart earns the engraved bar; without one
              // the chips are the honest fallback.
              _ when widget.score != null => HighwayStripMode.notation,
              _ => HighwayStripMode.names,
            },
            score: widget.score,
            noteNameOf: noteName,
          ),
        Expanded(
          child: Focus(
            focusNode: _keyFocus,
            onKeyEvent: _onKey,
            child: HighwayView(
              chart: chart,
              laneMap: laneMap,
              notes: grader.notes,
              beat: _beat,
              rules: _rules,
              palette: palette,
              projection: _projection,
              flashes: _flashes,
              litMidi: litMidi,
              litLanes: litLanes,
              noteNameOf: noteName,
              energy: (grader.multiplier - 1) / 3,
              livePitch: _livePitch,
              // With the microphone answering, the rail is a picture of the
              // instrument, not a control: tapping it would let you "play" the
              // piece with your thumbs while claiming to play it for real.
              onRailTap:
                  _mode == HighwayMode.play && !_usingMic ? _onRailTap : null,
            ),
          ),
        ),
        _hud(context, l, grader),
      ],
    );
  }

  Widget _hud(BuildContext context, AppLocalizations l, HighwayGrader grader) {
    final holding = grader.holdBeat != null && _beat >= (grader.holdBeat ?? 0);
    final counting = _beat < 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (counting)
            Expanded(
              child: Text(
                '${l.highwayCountIn} ${(-_beat).ceil()}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            )
          else if (holding)
            Expanded(
              child: Text(
                l.highwayWaiting,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            )
          else if (_mode == HighwayMode.watch)
            Expanded(child: Text(_chart?.name ?? ''))
          else
            Expanded(
              child: Wrap(
                spacing: 12,
                children: [
                  Text('${l.highwayHits} ${grader.hits}/${grader.total}'),
                  Text('${l.highwayStreak} ${grader.streak}'),
                  if (grader.multiplier > 1) Text('×${grader.multiplier}'),
                ],
              ),
            ),
          IconButton(
            tooltip: l.highwayStop,
            onPressed: _stop,
            icon: const Icon(Icons.stop_circle_outlined),
          ),
        ],
      ),
    );
  }

  // --- names -----------------------------------------------------------------

  String _micErrorText(AppLocalizations l) => switch (_micError!.reason) {
        PitchCaptureError.permissionDenied => l.micPermissionDenied,
        PitchCaptureError.unsupported => l.micUnsupported,
        _ => l.micStartFailed(_micError!.detail ?? _micError!.reason.name),
      };

  String _instrumentName(AppLocalizations l, HighwayInstrument i) =>
      switch (i) {
        HighwayInstrument.piano => l.highwayInstrumentPiano,
        HighwayInstrument.guitar => l.highwayInstrumentGuitar,
        HighwayInstrument.bass => l.highwayInstrumentBass,
        HighwayInstrument.ukulele => l.highwayInstrumentUkulele,
        HighwayInstrument.cello => l.highwayInstrumentCello,
        HighwayInstrument.pads => l.highwayInstrumentPads,
        HighwayInstrument.drums => l.highwayInstrumentDrums,
      };

  String _difficultyName(AppLocalizations l, HighwayDifficulty d) =>
      switch (d) {
        HighwayDifficulty.relaxed => l.highwayDifficultyRelaxed,
        HighwayDifficulty.easy => l.highwayDifficultyEasy,
        HighwayDifficulty.medium => l.highwayDifficultyMedium,
        HighwayDifficulty.hard => l.highwayDifficultyHard,
        HighwayDifficulty.expert => l.highwayDifficultyExpert,
      };

  String _skinName(AppLocalizations l, HighwaySkin s) => switch (s) {
        HighwaySkin.midnight => l.highwaySkinMidnight,
        HighwaySkin.neon => l.highwaySkinNeon,
        HighwaySkin.sunrise => l.highwaySkinSunrise,
        HighwaySkin.ink => l.highwaySkinInk,
      };
}
