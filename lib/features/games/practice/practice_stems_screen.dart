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
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/practice/practice_mix.dart';
import 'package:comet_beat/core/audio/practice/song_audio.dart';
import 'package:comet_beat/core/audio/practice/song_audio_file.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_beats.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_separate.dart';
import 'package:comet_beat/core/audio/transcription/engine_config.dart';
import 'package:comet_beat/core/audio/transcription/route.dart'
    show transcribeMonophonic;
import 'package:comet_beat/core/services/transcription_config_service.dart';
import 'package:comet_beat/features/games/playalong/play_along_screen.dart';
import 'package:comet_beat/features/games/practice/stem_player.dart';
import 'package:comet_beat/features/games/transcribe/transcribe_engines.dart'
    show resolveEngines;
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Beat-this's download, added to the separator's in the first-use note.
const int _beatModelMb = 41;

enum _Phase { idle, decoding, separating, beats, ready }

enum _Mode { fourStems, voiceOnly }

class PracticeStemsScreen extends StatefulWidget {
  const PracticeStemsScreen({super.key});

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
    _player?.stop();
    super.dispose();
  }

  Future<void> _pickAndSplit() async {
    const group = XTypeGroup(
      label: 'Audio',
      extensions: ['wav', 'mp3', 'flac'],
    );
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null || !mounted) return;
    final model = _model;
    setState(() {
      _error = null;
      _phase = _Phase.decoding;
      _songName = file.name;
    });
    final l = AppLocalizations.of(context)!;
    try {
      final SongAudio? song = await decodeSongFile(
        file.path,
        await file.readAsBytes(),
      );
      if (song == null || song.frames == 0) {
        throw StateError('undecodable');
      }
      if (!mounted) return;
      setState(() {
        _phase = _Phase.separating;
        _songSeconds = song.seconds;
      });
      final stems = await separateStereoCrispasr(
        song.left,
        song.right,
        song.sampleRate,
        model: model,
        download: true,
      );
      if (stems == null || stems.isEmpty) throw StateError('separation');
      // All stems on must sound like the song that was loaded.
      final whole = await Isolate.run(
        () => mixtureConsistent(
          stems,
          _atRate(song.left, song.sampleRate, stems.first.sampleRate),
          _atRate(song.right, song.sampleRate, stems.first.sampleRate),
        ),
      );
      if (!mounted) return;
      setState(() => _phase = _Phase.beats);
      // Best effort: a song without a clear beat still plays and separates.
      final grid = await crispasrBeatGrid(
        song.mono(),
        song.sampleRate,
        download: true,
      );
      if (!mounted) return;
      final ordered = _ordered(whole);
      await _player?.stop();
      setState(() {
        _player = StemPlayer(ordered);
        _strips = [for (final s in ordered) StemControl(name: s.name)];
        _grid = grid;
        _phase = _Phase.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _error = l.practiceStemsFailed;
      });
    }
  }

  static Float32List _atRate(Float32List x, int from, int to) {
    if (from == to) return x;
    final y = resampleLinear(Float64List.fromList(x), from / to);
    return Float32List.fromList(y);
  }

  /// Voice first, then the rhythm section, then the rest — the order a
  /// learner looks for them in.
  static List<SeparatedStem> _ordered(List<SeparatedStem> stems) {
    const rank = {'vocals': 0, 'drums': 1, 'bass': 2};
    return [...stems]
      ..sort((a, b) => (rank[a.name] ?? 3).compareTo(rank[b.name] ?? 3));
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
    final to = p.position + Duration(seconds: seconds);
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
    final vocals = p.stems.where((s) => s.name == 'vocals').firstOrNull;
    if (vocals == null) return;
    final l = AppLocalizations.of(context)!;
    final cfg = context.read<TranscriptionConfigService?>()?.config ??
        const TranscriptionEngineConfig();
    await p.pause();
    _uiTick?.cancel();
    setState(() => _findingMelody = true);
    try {
      final engines = await resolveEngines(cfg);
      final notes = await transcribeMonophonic(
        vocals.mono(),
        sampleRate: vocals.sampleRate,
        f0: engines.f0,
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
              for (final s in p.stems)
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
    setState(() {
      _player = null;
      _strips = const [];
      _grid = null;
      _phase = _Phase.idle;
    });
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
    final hasVocals = p.stems.any((s) => s.name == 'vocals');
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
          '${_clock(p.position)} / ${_clock(p.length)}',
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
        const SizedBox(height: 16),
        if (hasVocals)
          FilledButton.tonalIcon(
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

  Widget _strip(AppLocalizations l, int i) {
    final s = _strips[i];
    final audible = effectiveVolumes(_strips)[i] > 0;
    return Row(
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
