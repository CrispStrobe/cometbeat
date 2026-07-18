// The Sound Lab — a generate-your-own sound-effect screen over [sfx_engine].
// Pick a preset, tweak friendly sliders, randomize / mutate / A-B morph, hear
// it, export a WAV or copy a share token. Renders offline (a short buffer) and
// plays through the existing AudioService.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show kSampleRate, wavBytes;
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/sound_lab/sfx_engine.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// One exposed, kid-friendly slider (a param key + range + label).
class _Knob {
  final String key;
  final String Function(AppLocalizations) label;
  final double min;
  final double max;
  const _Knob(this.key, this.label, this.min, this.max);
}

final _knobs = <_Knob>[
  _Knob('baseFreq', (l) => l.soundLabPitch, 60, 2000),
  _Knob('freqRamp', (l) => l.soundLabSlide, -4000, 4000),
  _Knob('attack', (l) => l.soundLabAttack, 0, 0.4),
  _Knob('sustain', (l) => l.soundLabHold, 0.01, 0.6),
  _Knob('decay', (l) => l.soundLabFade, 0.02, 0.8),
  _Knob('punch', (l) => l.soundLabPunch, 0, 1),
  _Knob('duty', (l) => l.soundLabBuzz, 0.05, 0.95),
  _Knob('vibStrength', (l) => l.soundLabWobble, 0, 0.8),
  _Knob('lpf', (l) => l.soundLabBright, 0.1, 1),
  _Knob('distortion', (l) => l.soundLabCrunch, 0, 0.8),
  _Knob('delayFeedback', (l) => l.soundLabEcho, 0, 0.7),
];

/// Test seam.
abstract class SoundLabTester {
  SfxParams get params;
  Float64List get pcm;
  void loadPreset(String name);
  void randomizeSound();
  void setKnob(String key, double value);
}

class SoundLabScreen extends StatefulWidget {
  const SoundLabScreen({super.key});

  @override
  State<SoundLabScreen> createState() => _SoundLabScreenState();
}

class _SoundLabScreenState extends State<SoundLabScreen>
    implements SoundLabTester {
  SfxParams _params = kSfxPresets['coin']!;
  SfxParams? _slotA; // morph endpoints
  SfxParams? _slotB;
  double _morph = 0.5;
  int _seed = 1;
  late Float64List _pcm = _render();

  Float64List _render() =>
      sfxRender(_params, sampleRate: kSampleRate.toDouble());

  void _update(SfxParams p) => setState(() {
        _params = p;
        _pcm = _render();
      });

  // ── Tester seam ──────────────────────────────────────────────────────────
  @override
  SfxParams get params => _params;
  @override
  Float64List get pcm => _pcm;
  @override
  void loadPreset(String name) {
    final p = kSfxPresets[name];
    if (p != null) _update(p);
  }

  @override
  void randomizeSound() => _update(randomize(_params, seed: _seed++));
  @override
  void setKnob(String key, double value) =>
      _update(_params.copyWith({key: value}));

  // ── Actions ──────────────────────────────────────────────────────────────
  Uint8List _wav() {
    final i16 = Int16List(_pcm.length);
    for (var i = 0; i < _pcm.length; i++) {
      i16[i] = (_pcm[i].clamp(-1.0, 1.0) * 32767).round();
    }
    return wavBytes(i16);
  }

  void _play() => context.read<AudioService>().playWavBytes(_wav());

  Future<void> _export() =>
      showAudioExportSheet(context, pcm: _pcm, baseName: 'sound');

  Future<void> _copyToken() async {
    await Clipboard.setData(ClipboardData(text: _params.shareToken));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.soundLabCopied)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.soundLabTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: l10n.soundLabPlay,
            onPressed: _play,
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: l10n.soundLabExport,
            onPressed: _export,
          ),
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: l10n.soundLabShare,
            onPressed: _copyToken,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Waveform preview.
          SizedBox(
            height: 90,
            child: CustomPaint(
              painter: _WavePainter(
                _pcm,
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              size: Size.infinite,
            ),
          ),
          const SizedBox(height: 8),
          // Presets.
          Wrap(
            spacing: 6,
            children: [
              for (final name in kSfxPresets.keys)
                ActionChip(
                  label: Text(name),
                  onPressed: () => loadPreset(name),
                ),
            ],
          ),
          const Divider(),
          // Waveform + generate row.
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final w in SfxWave.values)
                ChoiceChip(
                  label: Text(_waveLabel(l10n, w)),
                  selected: _params.wave == w,
                  onSelected: (_) =>
                      _update(_params.copyWith({'wave': w.index})),
                ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.casino),
                label: Text(l10n.soundLabRandomize),
                onPressed: randomizeSound,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.auto_fix_high),
                label: Text(l10n.soundLabMutate),
                onPressed: () => _update(mutate(_params, seed: _seed++)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Sliders.
          for (final k in _knobs)
            _slider(
              k.label(l10n),
              (_params.toJson()[k.key] as num).toDouble(),
              k.min,
              k.max,
              (v) => setKnob(k.key, v),
            ),
          const Divider(),
          // A/B morph: snapshot the current sound into slot A or B, then blend.
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                onPressed: () => setState(() => _slotA = _params),
                child: Text(l10n.soundLabSetA),
              ),
              OutlinedButton(
                onPressed: () => setState(() => _slotB = _params),
                child: Text(l10n.soundLabSetB),
              ),
            ],
          ),
          if (_slotA != null && _slotB != null)
            Row(
              children: [
                const Text('A'),
                Expanded(
                  child: Slider(
                    value: _morph,
                    onChanged: (v) {
                      _morph = v;
                      _update(_slotA!.morph(_slotB!, v));
                    },
                  ),
                ),
                const Text('B'),
              ],
            )
          else
            Text(
              l10n.soundLabMorphHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    final v = value.clamp(min, max);
    return Row(
      children: [
        SizedBox(width: 92, child: Text(label)),
        Expanded(
          child: Slider(value: v, min: min, max: max, onChanged: onChanged),
        ),
      ],
    );
  }

  String _waveLabel(AppLocalizations l10n, SfxWave w) => switch (w) {
        SfxWave.square => l10n.soundLabSquare,
        SfxWave.sawtooth => l10n.soundLabSaw,
        SfxWave.sine => l10n.soundLabSine,
        SfxWave.noise => l10n.soundLabNoise,
      };
}

/// Paints the rendered PCM as a filled waveform.
class _WavePainter extends CustomPainter {
  final Float64List pcm;
  final Color color;
  final Color bg;
  _WavePainter(this.pcm, this.color, this.bg);

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(6),
    );
    canvas.drawRRect(r, Paint()..color = bg);
    if (pcm.isEmpty) return;
    final mid = size.height / 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final n = size.width.round().clamp(1, pcm.length);
    final step = pcm.length / n;
    for (var x = 0; x < n; x++) {
      var peak = 0.0;
      final start = (x * step).floor();
      final end = ((x + 1) * step).floor().clamp(start + 1, pcm.length);
      for (var i = start; i < end; i++) {
        if (pcm[i].abs() > peak) peak = pcm[i].abs();
      }
      final h = peak * mid;
      canvas.drawLine(
        Offset(x.toDouble(), mid - h),
        Offset(x.toDouble(), mid + h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => !identical(old.pcm, pcm);
}
