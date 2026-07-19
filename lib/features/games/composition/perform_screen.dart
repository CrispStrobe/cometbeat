// lib/features/games/composition/perform_screen.dart
//
// Live Looper — "Perform" (the Advanced tile of the loop ladder). A loop-station:
// tap a loop to start it, stack more layers on top (they loop in sync), and
// mute / undo layers as you build a track live. Every layer is one bar-cycle of
// PCM held in a LoopStack; the active layers are summed by `renderLoopStack`
// into one seamless loop and hot-swapped IN PHASE, so a new layer drops in on
// the beat instead of restarting the bar.
//
// S1 seeds layers from a few built-in loops (beat/bass/chords/melody); later
// slices add recording your own (sing / beatbox / play-in keyboard + pads).

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/loop_record.dart';
import 'package:comet_beat/core/audio/loop_stack_render.dart';
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate, wavBytes;
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/loop_player_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/piano_keyboard.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// One overdub layer: a label + one bar-cycle of mono PCM.
class _PerformLayer {
  const _PerformLayer(this.label, this.pcm);
  final String label;
  final Float64List pcm;
}

/// Test seam onto the Perform screen — build/mute/undo layers + read the mix
/// without audio hardware.
abstract class PerformTester {
  void addSeed(String kind);

  /// Play-in a melody: start capturing, tap notes, then finish — the played
  /// notes render into a new melodic loop layer.
  void startPlayIn();
  void playInNote(int midi);
  void finishPlayIn();
  void cancelPlayIn();
  bool get isPlayingIn;

  int get layerCount;
  String layerLabel(int i);
  bool isMuted(int i);
  void toggleMute(int i);
  void removeLayer(int i);
  void undoLayer();
  void redoLayer();
  bool get canUndo;
  bool get canRedo;
  void clearAll();
  void play();
  void stop();
  bool get isPlaying;

  /// The current summed mix (active layers) — for tests.
  Float64List debugMix();
}

class PerformScreen extends StatefulWidget {
  const PerformScreen({super.key});

  @override
  State<PerformScreen> createState() => _PerformScreenState();
}

class _PerformScreenState extends State<PerformScreen>
    implements PerformTester {
  final LoopStack<_PerformLayer> _stack = LoopStack<_PerformLayer>();
  final LoopPlayerService _loop = LoopPlayerService();
  final Stopwatch _clock = Stopwatch();
  bool _playing = false;

  // Play-in recording: captured `(midi, loop-phase ms)` while the keyboard is up.
  bool _playIn = false;
  final List<(int midi, int phaseMs)> _playInNotes = [];

  static const int _bpm = 120;

  /// One bar (4 beats) of samples at [_bpm] — the master loop length.
  int get _loopSamples => (kSampleRate * 4 * 60 / _bpm).round();

  /// The seed loops S1 offers (kind → label key builder).
  static const List<String> _kinds = ['beat', 'bass', 'chords', 'melody'];

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  // ── Layer editing ─────────────────────────────────────────────────────────
  @override
  void addSeed(String kind) {
    _stack.add(_PerformLayer(kind, _seedLoop(kind)));
    _refresh();
  }

  // ── Play-in a melody (S2) ─────────────────────────────────────────────────
  @override
  bool get isPlayingIn => _playIn;

  @override
  void startPlayIn() {
    _playInNotes.clear();
    _playIn = true;
    // Run the clock so taps get a loop-phase; if there are layers, play along.
    if (!_clock.isRunning) {
      _clock
        ..reset()
        ..start();
    }
    if (_stack.activeLayers.isNotEmpty && !_playing) play();
    setState(() {});
  }

  @override
  void playInNote(int midi) {
    if (!_playIn) return;
    final loopMs = _loopSamples / kSampleRate * 1000;
    _playInNotes.add((midi, (_clock.elapsedMilliseconds % loopMs).round()));
  }

  @override
  void finishPlayIn() {
    _playIn = false;
    if (_playInNotes.isNotEmpty) {
      _stack.add(_PerformLayer('melody', _renderMelody(_playInNotes)));
    }
    _playInNotes.clear();
    _refresh();
  }

  @override
  void cancelPlayIn() {
    _playIn = false;
    _playInNotes.clear();
    setState(() {});
  }

  /// Render captured `(midi, phaseMs)` notes into a one-bar loop: each note is
  /// snapped to the nearest 16th, held until the next note (capped at a beat),
  /// and synthesised with a soft decay.
  Float64List _renderMelody(List<(int, int)> notes) {
    final n = _loopSamples;
    final buf = Float64List(n);
    final sixteenth = n ~/ 16;
    final beat = n ~/ 4;
    // Snap each note to a 16th-note sample position, sorted in time.
    final placed = [
      for (final (midi, ms) in notes)
        (midi, ((ms / 1000 * kSampleRate) / sixteenth).round() * sixteenth % n),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    for (var i = 0; i < placed.length; i++) {
      final (midi, start) = placed[i];
      final next = i + 1 < placed.length ? placed[i + 1].$2 : n;
      final dur = (next - start).clamp(sixteenth, beat);
      _tone(buf, _midiToFreq(midi), start, dur, gain: 0.28, decay: 6);
    }
    return buf;
  }

  double _midiToFreq(int midi) => 440.0 * pow(2, (midi - 69) / 12).toDouble();

  @override
  int get layerCount => _stack.layers.length;
  @override
  String layerLabel(int i) => _stack.layers[i].label;
  @override
  bool isMuted(int i) => _stack.isMuted(i);
  @override
  void toggleMute(int i) {
    _stack.toggleMute(i);
    _refresh();
  }

  @override
  void removeLayer(int i) {
    // LoopStack only pops the newest via undo; for an arbitrary layer we mute it
    // (kept for undo/redo integrity — a full delete lands with S4's editing).
    if (!_stack.isMuted(i)) _stack.toggleMute(i);
    _refresh();
  }

  @override
  bool get canUndo => _stack.canUndo;
  @override
  bool get canRedo => _stack.canRedo;
  @override
  void undoLayer() {
    _stack.undo();
    _refresh();
  }

  @override
  void redoLayer() {
    _stack.redo();
    _refresh();
  }

  @override
  void clearAll() {
    _stack.clear();
    _refresh();
  }

  // ── Playback ──────────────────────────────────────────────────────────────
  @override
  bool get isPlaying => _playing;

  Duration get _phase {
    final loopMs = _loopSamples / kSampleRate * 1000;
    if (loopMs <= 0 || !_clock.isRunning) return Duration.zero;
    return Duration(
      milliseconds: (_clock.elapsedMilliseconds % loopMs).round(),
    );
  }

  @override
  Float64List debugMix() =>
      renderLoopStack(_activePcm, loopSamples: _loopSamples);

  List<Float64List> get _activePcm =>
      [for (final l in _stack.activeLayers) l.pcm];

  @override
  void play() {
    if (_stack.activeLayers.isEmpty) return;
    _playing = true;
    if (!_clock.isRunning) {
      _clock
        ..reset()
        ..start();
    }
    _swap();
    setState(() {});
  }

  @override
  void stop() {
    _playing = false;
    _clock.stop();
    _loop.stop();
    setState(() {});
  }

  /// Re-render the mix and, if playing, hot-swap the looping WAV in phase.
  void _refresh() {
    if (_playing) {
      if (_stack.activeLayers.isEmpty) {
        stop();
        return;
      }
      _swap();
    }
    setState(() {});
  }

  void _swap() {
    final mix = renderLoopStack(_activePcm, loopSamples: _loopSamples);
    _loop.playLoop(wavBytes(_toInt16(mix)), position: _phase);
  }

  Int16List _toInt16(Float64List f) {
    final out = Int16List(f.length);
    for (var i = 0; i < f.length; i++) {
      out[i] = (f[i].clamp(-1.0, 1.0) * 32767).round();
    }
    return out;
  }

  // ── Built-in seed loops (S1) ──────────────────────────────────────────────
  Float64List _seedLoop(String kind) {
    final n = _loopSamples;
    final beat = n ~/ 4;
    final eighth = n ~/ 8;
    final buf = Float64List(n);
    final rng = Random(kind.hashCode & 0x7fffffff);
    switch (kind) {
      case 'beat':
        for (var b = 0; b < 4; b++) {
          if (b.isEven) _tone(buf, 55, b * beat, eighth, gain: 0.6, decay: 22);
          if (b.isOdd) _noise(buf, b * beat, eighth, rng, gain: 0.4);
        }
        for (var e = 0; e < 8; e++) {
          _noise(buf, e * eighth, eighth ~/ 3, rng, gain: 0.08, decay: 90);
        }
      case 'bass':
        const roots = [65.41, 65.41, 87.31, 98.0]; // C2 C2 F2 G2
        for (var b = 0; b < 4; b++) {
          _tone(buf, roots[b], b * beat, beat, gain: 0.4, decay: 4);
        }
      case 'chords':
        const chord = [261.63, 329.63, 392.0]; // C E G
        for (var b = 0; b < 4; b += 2) {
          for (final f in chord) {
            _tone(buf, f, b * beat, beat * 2, gain: 0.18, decay: 3);
          }
        }
      case 'melody':
        const riff = [
          523.25,
          587.33,
          659.25,
          783.99,
          659.25,
          587.33,
          523.25,
          783.99,
        ]; // C D E G E D C G (pentatonic-ish)
        for (var e = 0; e < 8; e++) {
          _tone(buf, riff[e], e * eighth, eighth, gain: 0.22, decay: 10);
        }
    }
    return buf;
  }

  void _tone(
    Float64List b,
    double freq,
    int start,
    int dur, {
    double gain = 0.3,
    double decay = 8,
  }) {
    for (var i = 0; i < dur && start + i < b.length; i++) {
      final t = i / kSampleRate;
      b[start + i] += gain * exp(-decay * t) * sin(2 * pi * freq * t);
    }
  }

  void _noise(
    Float64List b,
    int start,
    int dur,
    Random rng, {
    double gain = 0.3,
    double decay = 30,
  }) {
    for (var i = 0; i < dur && start + i < b.length; i++) {
      b[start + i] +=
          gain * exp(-decay * i / kSampleRate) * (rng.nextDouble() * 2 - 1);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  String _seedLabel(AppLocalizations l10n, String kind) => switch (kind) {
        'beat' => l10n.performSeedBeat,
        'bass' => l10n.performSeedBass,
        'chords' => l10n.performSeedChords,
        _ => l10n.performSeedMelody,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.performTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: l10n.performUndo,
            onPressed: canUndo ? undoLayer : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            tooltip: l10n.performRedo,
            onPressed: canRedo ? redoLayer : null,
          ),
          IconButton(
            icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
            tooltip: _playing ? l10n.performStop : l10n.performPlay,
            onPressed:
                _stack.activeLayers.isEmpty ? null : (_playing ? stop : play),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.performClear,
            onPressed: _stack.layers.isEmpty ? null : clearAll,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.performPrompt,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final kind in _kinds)
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.add),
                      label: Text(_seedLabel(l10n, kind)),
                      onPressed: () => addSeed(kind),
                    ),
                  FilledButton.icon(
                    icon: const Icon(Icons.piano),
                    label: Text(l10n.performPlayIn),
                    onPressed: _playIn ? null : startPlayIn,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _stack.layers.isEmpty
                    ? Center(
                        child: Text(
                          l10n.performEmptyHint,
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        itemCount: _stack.layers.length,
                        itemBuilder: (context, i) {
                          final muted = _stack.isMuted(i);
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: muted
                                    ? scheme.surfaceContainerHighest
                                    : scheme.primaryContainer,
                                child: Text('${i + 1}'),
                              ),
                              title: Text(
                                _seedLabel(l10n, _stack.layers[i].label),
                              ),
                              trailing: IconButton(
                                icon: Icon(
                                  muted ? Icons.volume_off : Icons.volume_up,
                                ),
                                tooltip: muted
                                    ? l10n.performUnmute
                                    : l10n.performMute,
                                onPressed: () => toggleMute(i),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (_playIn) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.performPlayInHint,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: cancelPlayIn,
                      child: Text(l10n.performCancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.check),
                      label: Text(l10n.performDone),
                      onPressed: finishPlayIn,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 140,
                  child: PianoKeyboard(
                    whiteKeyCount: 8,
                    onKeyTap: (midi) {
                      context.read<AudioService>().playMidiNote(midi, ms: 400);
                      playInNote(midi);
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
