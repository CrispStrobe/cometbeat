// lib/features/games/practice/practice_stems_screen.dart
//
// "Practise with your song": the learner picks a song of their own, CrispASR
// splits it into stems on the device (voice / drums / bass / the rest, or just
// voice / accompaniment), and they play along with one part taken out — mute,
// solo and level per stem, instant. From the same split they can sing the
// song's own melody on the note highway, over the song minus its voice.
//
// The song never leaves the device: decoding, separation, beat tracking and the
// melody all run locally, and nothing is stored. Native only (the separators
// run in libcrispasr); on the web the screen says so instead of offering a
// button that cannot work.

import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/time_stretch.dart';
import 'package:comet_beat/core/audio/practice/practice_mix.dart';
import 'package:comet_beat/core/audio/practice/practice_song_split.dart';
import 'package:comet_beat/core/audio/practice/sing_melody.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_beats.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_separate.dart';
import 'package:comet_beat/core/audio/transcription/engine_config.dart';
import 'package:comet_beat/core/services/transcription_config_service.dart';
import 'package:comet_beat/features/games/playalong/play_along_screen.dart';
import 'package:comet_beat/features/games/practice/stem_player.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Beat-this's download, added to the separator's in the first-use note.
const int _beatModelMb = 41;

enum _Phase { idle, decoding, separating, beats, ready }

enum _Mode { fourStems, voiceOnly }

/// A picked song file (name for display, path for decoders that read files).
typedef PickedSong = ({String name, String path, Uint8List bytes});

class PracticeStemsScreen extends StatefulWidget {
  const PracticeStemsScreen({super.key, this.debugPickSong});

  /// Test seam: replaces the file dialog (integration tests drive the real
  /// pipeline with a song they made). Null in the app.
  final Future<PickedSong?> Function()? debugPickSong;

  @override
  State<PracticeStemsScreen> createState() => _PracticeStemsScreenState();
}

class _PracticeStemsScreenState extends State<PracticeStemsScreen> {
  _Phase _phase = _Phase.idle;
  _Mode _mode = _Mode.fourStems;
  String? _error;
  String _songName = '';
  double _songSeconds = 0;

  StemPlayer? _player;
  List<StemControl> _strips = const [];

  /// The separated song as loaded — the source every playing buffer (a loop,
  /// a slowed version) is derived from, and what sing-along transcribes.
  List<SeparatedStem> _whole = const [];

  /// Unmaps [_whole] (its stems may be mapped from disk). Called only once
  /// nothing reads them: see [_retire].
  void Function()? _releaseWhole;

  /// Async readers of [_whole] in flight (the slow-down guide); releases wait
  /// for them.
  int _reading = 0;
  final _pendingReleases = <void Function()>[];

  /// A practice loop over song time, in seconds (null = the whole song).
  RangeValues? _loop;
  bool _looping = false;

  /// Playback speed (1 = as recorded). Below 1 the stems are time-stretched
  /// — pitch kept — with one shared plan so the parts stay together.
  double _speed = 1;
  bool _preparing = false;
  BeatGrid? _grid;
  Timer? _uiTick;
  bool _findingMelody = false;

  CrispasrSeparatorModel get _model {
    if (_mode == _Mode.voiceOnly) return CrispasrSeparatorModel.melBandRoformer;
    final chosen = context
        .read<TranscriptionConfigService?>()
        ?.config
        .crispasrSeparatorModel;
    // The settings may name the vocal-only model; this mode wants four stems.
    return chosen == null || chosen == CrispasrSeparatorModel.melBandRoformer
        ? CrispasrSeparatorModel.auto
        : chosen;
  }

  @override
  void dispose() {
    _uiTick?.cancel();
    // stop() cancels the feeder before its first await: nothing reads the
    // stems after this line, so they can go.
    _player?.stop();
    _retire(_releaseWhole);
    _releaseWhole = null;
    super.dispose();
  }

  /// Releases a split's stems now, or once the async readers finish.
  void _retire(void Function()? release) {
    if (release == null) return;
    if (_reading > 0) {
      _pendingReleases.add(release);
    } else {
      release();
    }
  }

  void _doneReading() {
    if (--_reading > 0) return;
    for (final r in _pendingReleases) {
      r();
    }
    _pendingReleases.clear();
  }

  Future<void> _pickAndSplit() async {
    const group = XTypeGroup(
      label: 'Audio',
      extensions: ['wav', 'mp3', 'flac', 'ogg', 'opus', 'aac'],
    );
    final PickedSong? picked;
    if (widget.debugPickSong != null) {
      picked = await widget.debugPickSong!();
    } else {
      final file = await openFile(acceptedTypeGroups: const [group]);
      picked = file == null
          ? null
          : (name: file.name, path: file.path, bytes: await file.readAsBytes());
    }
    if (picked == null || !mounted) return;
    final model = _model;
    setState(() {
      _error = null;
      _phase = _Phase.decoding;
      _songName = picked!.name;
    });
    final l = AppLocalizations.of(context)!;
    try {
      // Decode, separate and mix-match in one worker isolate: the song's PCM
      // never sits on this isolate and is never copied between isolates.
      final split = await splitSongForPractice(
        picked.path,
        picked.bytes,
        model: model,
        download: true,
        onPhase: (phase, seconds) {
          if (!mounted || phase != PracticeSplitPhase.separating) return;
          setState(() {
            _phase = _Phase.separating;
            _songSeconds = seconds ?? 0;
          });
        },
      );
      final whole = split.stems;
      if (!mounted) {
        split.release();
        return;
      }
      setState(() => _phase = _Phase.beats);
      // Best effort: a song without a clear beat still plays and separates.
      final grid = await crispasrBeatGrid32(
        split.beatMono,
        split.beatRate,
        download: true,
      );
      if (!mounted) {
        split.release();
        return;
      }
      final ordered = _ordered(whole);
      await _player?.stop();
      final previous = _releaseWhole;
      setState(() {
        _whole = ordered;
        _releaseWhole = split.release;
        _player = StemPlayer(ordered);
        _strips = [for (final s in ordered) StemControl(name: s.name)];
        _grid = grid;
        _loop = null;
        _looping = false;
        _speed = 1;
        _preparing = false;
        _phase = _Phase.ready;
      });
      _retire(previous);
    } catch (e) {
      debugPrint('practice: split failed: $e');
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _error = e is PracticeSongTooLong
            ? l.practiceStemsTooLong(e.maxSeconds ~/ 60)
            : l.practiceStemsFailed;
      });
    }
  }

  // Isolate work lives in static helpers ON PURPOSE: a closure written inside
  // an instance method shares its context with the method's other closures
  // (the setState lambdas), drags `this` along, and the State is unsendable.
  /// The splice plan for slowing to [speed] (WSOLA's search is the slow part;
  /// only the guide goes over, and only the small plan comes back).
  static Future<StretchPlan?> _planInIsolate(Float32List guide, double speed) =>
      Isolate.run(
        () => planStretch(
          Float64List.fromList(guide),
          1 / speed,
          quality: StretchQuality.deep,
        ),
      );

  /// Voice first, then the rhythm section, then the rest — the order a
  /// learner looks for them in.
  static List<SeparatedStem> _ordered(List<SeparatedStem> stems) {
    const rank = {'vocals': 0, 'drums': 1, 'bass': 2};
    return [...stems]
      ..sort((a, b) => (rank[a.name] ?? 3).compareTo(rank[b.name] ?? 3));
  }

  /// Where the playing buffer starts in the song, in seconds.
  double get _regionStart => _looping ? (_loop?.start ?? 0) : 0;

  /// The song time of the playhead (the buffer may be a slowed loop).
  Duration get _songPosition {
    final p = _player;
    if (p == null) return Duration.zero;
    final s = _regionStart + p.position.inMicroseconds / 1e6 * _speed;
    return Duration(microseconds: (s * 1e6).round());
  }

  Duration get _songLength {
    final w = _whole;
    if (w.isEmpty) return Duration.zero;
    final frames = w.map((s) => s.frames).reduce(math.min);
    return Duration(microseconds: frames * 1000000 ~/ w.first.sampleRate);
  }

  /// Rebuilds the playing buffer from [_whole] for the current loop and
  /// speed, keeping the mixer and (if it was playing) playing on.
  Future<void> _rebuild() async {
    final whole = _whole;
    if (whole.isEmpty) return;
    final wasPlaying = _player?.playing ?? false;
    _uiTick?.cancel();
    await _player?.stop();
    setState(() => _preparing = _speed < 1);
    // A view of the stems (the loop, faded like loopRegion), slowed by a
    // frame plan — rendered window by window as the player feeds, so neither
    // the loop nor the slowed song is ever copied whole.
    final loop = _loop;
    final looping = _looping && loop != null;
    final sr = whole.first.sampleRate;
    var region = looping
        ? StemRegion(
            whole,
            start: (loop.start * sr).round(),
            end: (loop.end * sr).round(),
            fadeFrames: 220,
          )
        : StemRegion(whole);
    if (_speed < 1) {
      final Float32List guide;
      _reading++;
      try {
        guide = await region.stretchGuide();
      } finally {
        _doneReading();
      }
      // Replaced or reset meanwhile: these stems may be gone.
      if (!mounted || !identical(whole, _whole)) return;
      final plan = await _planInIsolate(guide, _speed);
      region = looping
          ? StemRegion(
              whole,
              start: (loop.start * sr).round(),
              end: (loop.end * sr).round(),
              fadeFrames: 220,
              plan: plan,
            )
          : StemRegion(whole, plan: plan);
    }
    if (!mounted || !identical(whole, _whole)) return;
    setState(() {
      _player = StemPlayer.source(region, loop: looping);
      _preparing = false;
    });
    if (wasPlaying) await _togglePlay();
  }

  Future<void> _setLoop(RangeValues v) async {
    final grid = _grid;
    // Snap both ends onto the beat, then keep at least a second between them.
    final a = snapToBeat(v.start * 1000, grid) / 1000;
    var b = snapToBeat(v.end * 1000, grid) / 1000;
    final len = _songLength.inMicroseconds / 1e6;
    if (b - a < 1) b = math.min(len, a + 1);
    _loop = RangeValues(a, b);
    if (_looping) await _rebuild();
  }

  void _setStrips(List<StemControl> strips) {
    setState(() => _strips = strips);
    _player?.setVolumes(effectiveVolumes(strips));
  }

  Future<void> _togglePlay() async {
    final p = _player;
    if (p == null) return;
    if (p.playing) {
      await p.pause();
      _uiTick?.cancel();
    } else {
      p.setVolumes(effectiveVolumes(_strips));
      if (!await p.play()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.practiceStemsNoAudio),
            ),
          );
        }
        return;
      }
      _uiTick = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        if (!p.playing) _uiTick?.cancel();
        setState(() {});
      });
    }
    if (mounted) setState(() {});
  }

  Future<void> _seekBy(int seconds) async {
    final p = _player;
    if (p == null) return;
    // Skip in SONG seconds, converted to the buffer's own time (a slowed
    // buffer runs longer; a loop's buffer starts at the loop).
    final to =
        p.position + Duration(microseconds: (seconds * 1e6 / _speed).round());
    final clamped =
        to.isNegative ? Duration.zero : (to > p.length ? p.length : to);
    if (p.playing) {
      await p.play(from: clamped);
    } else {
      await p.play(from: clamped);
      await p.pause();
    }
    if (mounted) setState(() {});
  }

  Future<void> _singAlong() async {
    final p = _player;
    if (p == null) return;
    // Always the original song, never a slowed loop of it.
    final vocals = _whole.where((s) => s.name == 'vocals').firstOrNull;
    if (vocals == null) return;
    final l = AppLocalizations.of(context)!;
    final cfg = context.read<TranscriptionConfigService?>()?.config ??
        const TranscriptionEngineConfig();
    await p.pause();
    _uiTick?.cancel();
    setState(() => _findingMelody = true);
    try {
      // Off the UI isolate: a whole song's vocal stem takes tens of seconds.
      final f0Choice = cfg.backendFor(TranscriptionStep.f0);
      final (:notes, engine: _) = await singMelody(
        vocals.mono(),
        vocals.sampleRate,
        useCrepe: f0Choice == Backend.auto || f0Choice == Backend.crispasr,
      );
      final chart = melodyChart(notes, grid: _grid, name: _songName);
      if (!mounted) return;
      setState(() => _findingMelody = false);
      if (chart.notes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.practiceStemsNoMelody)),
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlayAlongScreen(
            chart: chart,
            title: l.practiceStemsSingAlong,
            gameId: 'practice_sing_along',
            sriPrefix: 'voice.own_song',
            scaleStarsToLength: true,
            audioBacking: StemBacking([
              for (final s in _whole)
                if (s.name != 'vocals') s,
            ]),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _findingMelody = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.practiceStemsNoMelody)),
        );
      }
    }
  }

  Future<void> _reset() async {
    _uiTick?.cancel();
    await _player?.stop();
    final release = _releaseWhole;
    setState(() {
      _player = null;
      _releaseWhole = null;
      _whole = const [];
      _strips = const [];
      _grid = null;
      _preparing = false;
      _phase = _Phase.idle;
    });
    _retire(release);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: GameAppBar(title: l.gamePracticeStems),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.idle => _idle(l),
          _Phase.ready => _mixer(l),
          _ => _working(l),
        },
      ),
    );
  }

  Widget _idle(AppLocalizations l) {
    final supported = crispasrSeparatorSupported(_model);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.call_split, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          l.gamePracticeStemsSubtitle,
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        if (!supported)
          Text(l.practiceStemsUnavailable, textAlign: TextAlign.center)
        else ...[
          SegmentedButton<_Mode>(
            segments: [
              ButtonSegment(
                value: _Mode.fourStems,
                label: Text(l.practiceStemsModeFour),
              ),
              ButtonSegment(
                value: _Mode.voiceOnly,
                label: Text(l.practiceStemsModeVoice),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('practice-stems-pick'),
            onPressed: _pickAndSplit,
            icon: const Icon(Icons.library_music),
            label: Text(l.practiceStemsPick),
          ),
          const SizedBox(height: 8),
          Text(
            l.practiceStemsPickHint,
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          Text(
            l.practiceStemsDownloadNote(
              _model.approxDownloadBytes ~/ (1024 * 1024) + _beatModelMb,
            ),
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(
            _error!,
            style: TextStyle(color: theme.colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _working(AppLocalizations l) {
    // Separation runs at roughly real time on a laptop; round up so the
    // estimate errs long.
    final minutes = (_songSeconds / 60).ceil().clamp(1, 60);
    final text = switch (_phase) {
      _Phase.decoding => l.practiceStemsDecoding,
      _Phase.separating => l.practiceStemsSeparating(minutes),
      _ => l.practiceStemsBeats,
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 16),
            Text(_songName, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  String _stemLabel(AppLocalizations l, String name) => switch (name) {
        'vocals' => l.practiceStemVocals,
        'drums' => l.practiceStemDrums,
        'bass' => l.practiceStemBass,
        _ => l.practiceStemOther,
      };

  IconData _stemIcon(String name) => switch (name) {
        'vocals' => Icons.mic,
        'drums' => Icons.album,
        'bass' => Icons.graphic_eq,
        _ => Icons.piano,
      };

  static String _clock(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Widget _mixer(AppLocalizations l) {
    final p = _player!;
    final theme = Theme.of(context);
    final grid = _grid;
    final hasVocals = _whole.any((s) => s.name == 'vocals');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          _songName,
          style: theme.textTheme.titleMedium,
          overflow: TextOverflow.ellipsis,
        ),
        if (grid != null && !grid.isEmpty)
          Text(
            l.practiceStemsTempo(grid.bpm.round()),
            style: theme.textTheme.bodySmall,
          ),
        const SizedBox(height: 12),
        // One-tap "minus one" presets.
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ChoiceChip(
              label: Text(l.practiceStemsAll),
              selected: _strips.every((s) => !s.muted && !s.solo),
              onSelected: (_) => _setStrips([
                for (final s in _strips) s.copyWith(muted: false, solo: false),
              ]),
            ),
            for (final s in _strips)
              ChoiceChip(
                label: Text(l.practiceStemsWithout(_stemLabel(l, s.name))),
                selected: _strips.every(
                  (o) => !o.solo && o.muted == (o.name == s.name),
                ),
                onSelected: (_) => _setStrips(minusOne(_strips, s.name)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _strips.length; i++) _strip(l, i),
        const SizedBox(height: 16),
        Text(
          '${_clock(_songPosition)} / ${_clock(_songLength)}',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: l.practiceStemsBack,
              icon: const Icon(Icons.replay_10),
              onPressed: () => _seekBy(-10),
            ),
            IconButton.filled(
              key: const Key('practice-stems-play'),
              iconSize: 40,
              icon: Icon(p.playing ? Icons.pause : Icons.play_arrow),
              onPressed: _togglePlay,
            ),
            IconButton(
              tooltip: l.practiceStemsForward,
              icon: const Icon(Icons.forward_10),
              onPressed: () => _seekBy(10),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _loopAndSpeed(l),
        const SizedBox(height: 16),
        if (hasVocals)
          FilledButton.tonalIcon(
            key: const Key('practice-sing-along'),
            onPressed: _findingMelody ? null : _singAlong,
            icon: _findingMelody
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.mic_external_on),
            label: Text(
              _findingMelody
                  ? l.practiceStemsFindingMelody
                  : l.practiceStemsSingAlong,
            ),
          ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _reset,
          icon: const Icon(Icons.library_music),
          label: Text(l.practiceStemsAnother),
        ),
      ],
    );
  }

  Widget _loopAndSpeed(AppLocalizations l) {
    final len = _songLength.inMicroseconds / 1e6;
    final loop = _loop ?? RangeValues(0, math.min(len, 8));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const Key('practice-stems-loop'),
          contentPadding: EdgeInsets.zero,
          title: Text(l.practiceStemsLoop),
          subtitle: _looping
              ? Text(
                  '${_clock(Duration(milliseconds: (loop.start * 1000).round()))}'
                  ' – ${_clock(Duration(milliseconds: (loop.end * 1000).round()))}',
                )
              : null,
          value: _looping,
          onChanged: _preparing || len < 2
              ? null
              : (on) {
                  setState(() {
                    _looping = on;
                    _loop ??= loop;
                  });
                  _rebuild();
                },
        ),
        if (_looping)
          RangeSlider(
            values: RangeValues(
              loop.start.clamp(0, len).toDouble(),
              loop.end.clamp(0, len).toDouble(),
            ),
            max: len,
            onChanged: _preparing ? null : (v) => setState(() => _loop = v),
            onChangeEnd: _setLoop,
          ),
        Row(
          children: [
            Text(l.practiceStemsSpeed),
            const SizedBox(width: 12),
            Expanded(
              child: SegmentedButton<double>(
                key: const Key('practice-stems-speed'),
                showSelectedIcon: false,
                segments: [
                  for (final v in const [1.0, 0.85, 0.75, 0.5])
                    ButtonSegment(
                      value: v,
                      label: Text('${(v * 100).round()}%'),
                    ),
                ],
                selected: {_speed},
                onSelectionChanged: _preparing
                    ? null
                    : (sel) {
                        setState(() => _speed = sel.first);
                        _rebuild();
                      },
              ),
            ),
          ],
        ),
        if (_preparing) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
          const SizedBox(height: 4),
          Text(l.practiceStemsPreparing, textAlign: TextAlign.center),
        ],
      ],
    );
  }

  Widget _strip(AppLocalizations l, int i) {
    final s = _strips[i];
    final audible = effectiveVolumes(_strips)[i] > 0;
    return Row(
      key: Key('practice-stem-${s.name}'),
      children: [
        Icon(
          _stemIcon(s.name),
          color: audible ? null : Theme.of(context).disabledColor,
        ),
        const SizedBox(width: 8),
        SizedBox(width: 110, child: Text(_stemLabel(l, s.name))),
        Expanded(
          child: Slider(
            value: s.volume,
            onChanged: (v) => _setStrips([
              for (var j = 0; j < _strips.length; j++)
                j == i ? _strips[j].copyWith(volume: v) : _strips[j],
            ]),
          ),
        ),
        IconButton(
          key: Key('practice-mute-${s.name}'),
          tooltip: l.practiceStemsMute,
          isSelected: s.muted,
          icon: const Icon(Icons.volume_up),
          selectedIcon: const Icon(Icons.volume_off),
          onPressed: () => _setStrips([
            for (var j = 0; j < _strips.length; j++)
              j == i ? _strips[j].copyWith(muted: !s.muted) : _strips[j],
          ]),
        ),
        IconButton(
          tooltip: l.practiceStemsSolo,
          isSelected: s.solo,
          icon: const Icon(Icons.headphones_outlined),
          selectedIcon: const Icon(Icons.headphones),
          onPressed: () => _setStrips([
            for (var j = 0; j < _strips.length; j++)
              j == i ? _strips[j].copyWith(solo: !s.solo) : _strips[j],
          ]),
        ),
      ],
    );
  }
}
