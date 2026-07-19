// The Voice Lab — record (or load) a short clip and transform it: a character
// preset, decoupled pitch-shift + speed (time-stretch), tremolo, a noise gate,
// and a convolution-reverb tail. Reuses the app's voice DSP (voice_fx /
// pitch_shift / time_stretch) plus the new P0.1 dynamics + convolution reverb.
// Renders offline and plays through AudioService.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/convolution_reverb.dart';
import 'package:comet_beat/core/audio/crisp_dsp/dynamics.dart';
import 'package:comet_beat/core/audio/crisp_dsp/pitch_shift.dart';
import 'package:comet_beat/core/audio/crisp_dsp/time_stretch.dart';
import 'package:comet_beat/core/audio/crisp_dsp/voice_fx.dart';
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate, wavBytes;
import 'package:comet_beat/core/audio/voice_clip_recorder.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/sound_lab/my_samples_sheet.dart';
import 'package:comet_beat/features/sound_lab/sample_clip_store.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart';
import 'package:comet_beat/shared/music_io/audio_import.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const _sr = kSampleRate;

/// Applies a tremolo (amplitude LFO) at [rateHz]; [depth] 0..1.
Float64List tremoloFx(Float64List x, double depth, {double rateHz = 5}) {
  if (depth <= 0 || x.isEmpty) return x;
  final out = Float64List(x.length);
  for (var i = 0; i < x.length; i++) {
    final lfo = 0.5 + 0.5 * math.sin(2 * math.pi * rateHz * i / _sr);
    out[i] = x[i] * (1 - depth + depth * lfo);
  }
  return out;
}

/// The full transform chain (pure): pitch → speed → character → tremolo → gate
/// → reverb. Exposed so it is unit-testable without the UI.
Float64List voiceLabProcess(
  Float64List clip, {
  VoiceEffect effect = VoiceEffect.normal,
  double semitones = 0,
  double speed = 1,
  double tremolo = 0,
  double gate = 0, // 0 = off; 1 = aggressive
  double reverb = 0, // wet mix
}) {
  if (clip.isEmpty) return clip;
  var x = clip;
  if (semitones != 0) x = granularPitchShift(x, semitones);
  if (speed != 1 && speed > 0) x = timeStretch(x, speed);
  x = applyVoiceEffect(x, effect);
  if (tremolo > 0) x = tremoloFx(x, tremolo);
  if (gate > 0) {
    x = gateFx(x, sampleRate: _sr.toDouble(), thresholdDb: -60 + gate * 45);
  }
  if (reverb > 0) {
    x = convolutionReverbFx(x, sampleRate: _sr.toDouble(), mix: reverb);
  }
  return x;
}

/// Test seam.
abstract class VoiceLabTester {
  void debugSetClip(Float64List clip);
  Float64List? get output;
  VoiceEffect get effect;
  void setEffect(VoiceEffect e);
  void setParam(String key, double value);
  Future<void> saveToLibrary(String name);
  List<SampleClip> get library;
  void recall(int index);
}

class VoiceLabScreen extends StatefulWidget {
  const VoiceLabScreen({super.key});

  @override
  State<VoiceLabScreen> createState() => _VoiceLabScreenState();
}

class _VoiceLabScreenState extends State<VoiceLabScreen>
    implements VoiceLabTester {
  final _recorder = VoiceClipRecorder();
  final _store = SampleClipStore();
  Float64List? _clip;
  Float64List? _out;
  bool _recording = false;
  List<SampleClip> _library = const [];

  VoiceEffect _effect = VoiceEffect.normal;
  double _pitch = 0;
  double _speed = 1;
  double _tremolo = 0;
  double _gate = 0;
  double _reverb = 0;

  @override
  void initState() {
    super.initState();
    _store.load().then((list) {
      if (mounted) setState(() => _library = list);
    });
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  void _reprocess() {
    final clip = _clip;
    setState(() {
      _out = clip == null
          ? null
          : voiceLabProcess(
              clip,
              effect: _effect,
              semitones: _pitch,
              speed: _speed,
              tremolo: _tremolo,
              gate: _gate,
              reverb: _reverb,
            );
    });
  }

  // ── Tester seam ──────────────────────────────────────────────────────────
  @override
  void debugSetClip(Float64List clip) {
    _clip = clip;
    _reprocess();
  }

  @override
  Float64List? get output => _out;
  @override
  VoiceEffect get effect => _effect;
  @override
  void setEffect(VoiceEffect e) {
    _effect = e;
    _reprocess();
  }

  @override
  void setParam(String key, double value) {
    switch (key) {
      case 'pitch':
        _pitch = value;
      case 'speed':
        _speed = value;
      case 'tremolo':
        _tremolo = value;
      case 'gate':
        _gate = value;
      case 'reverb':
        _reverb = value;
    }
    _reprocess();
  }

  // ── Actions ──────────────────────────────────────────────────────────────
  Future<void> _record() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) _snack(l10n.voiceLabNoMic);
        return;
      }
      setState(() => _recording = true);
      final clip = await _recorder.record();
      if (!mounted) return;
      setState(() => _recording = false);
      _clip = clip;
      _reprocess();
    } catch (_) {
      if (!mounted) return;
      setState(() => _recording = false);
      _snack(l10n.voiceLabRecordFailed);
    }
  }

  Future<void> _loadWav() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [kAudioImportGroup],
      );
      if (file == null || !mounted) return;
      final imported = importAudioMono(await file.readAsBytes());
      if (imported == null) {
        if (mounted) _snack(AppLocalizations.of(context)!.voiceLabRecordFailed);
        return;
      }
      _clip = imported.pcm;
      _reprocess();
    } catch (_) {
      if (mounted) _snack(AppLocalizations.of(context)!.voiceLabRecordFailed);
    }
  }

  Uint8List _wav(Float64List pcm) {
    final i16 = Int16List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      i16[i] = (pcm[i].clamp(-1.0, 1.0) * 32767).round();
    }
    return wavBytes(i16);
  }

  void _play() {
    final out = _out;
    if (out != null && out.isNotEmpty) {
      context.read<AudioService>().playWavBytes(_wav(out));
    }
  }

  Future<void> _export() async {
    final out = _out;
    if (out == null || out.isEmpty) return;
    await showAudioExportSheet(context, pcm: out, baseName: 'voice');
  }

  // ── My Samples (persistence) ─────────────────────────────────────────────
  @override
  List<SampleClip> get library => _library;

  @override
  Future<void> saveToLibrary(String name) async {
    final out = _out;
    if (out == null || out.isEmpty) return;
    final list = await _store.save(
      SampleClip(name: name, sampleRate: _sr, pcm: out, source: 'Voice Lab'),
    );
    if (mounted) setState(() => _library = list);
  }

  @override
  void recall(int index) {
    _clip = _library[index].pcm;
    _reprocess();
  }

  Future<void> _saveDialog() async {
    final l10n = AppLocalizations.of(context)!;
    if (_out == null || _out!.isEmpty) return;
    final controller = TextEditingController(
      text: l10n.voiceLabDefaultName(_library.length + 1),
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.voiceLabSaveTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.voiceLabSaveName),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.voiceLabCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(l10n.voiceLabSave),
          ),
        ],
      ),
    );
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    await saveToLibrary(trimmed);
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _openLibrary() async {
    final picked = await showMySamplesSheet(context, store: _store);
    if (picked == null || !mounted) return;
    _clip = picked.pcm;
    _reprocess();
    // Keep the in-screen list in step with any deletes made in the sheet.
    final list = await _store.load();
    if (mounted) setState(() => _library = list);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasClip = _clip != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.voiceLabTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: l10n.voiceLabPlay,
            onPressed: hasClip ? _play : null,
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: l10n.voiceLabExport,
            onPressed: hasClip ? _export : null,
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: l10n.voiceLabSaveTitle,
            onPressed: hasClip ? _saveDialog : null,
          ),
          IconButton(
            icon: const Icon(Icons.bookmarks_outlined),
            tooltip: l10n.voiceLabMyTitle,
            onPressed: _openLibrary,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              FilledButton.icon(
                icon: Icon(_recording ? Icons.mic : Icons.mic_none),
                label: Text(l10n.voiceLabRecord),
                onPressed: _recording ? null : _record,
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.audio_file_outlined),
                label: Text(l10n.voiceLabLoad),
                onPressed: _loadWav,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!hasClip)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.voiceLabHint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else ...[
            Text(
              l10n.voiceLabCharacter,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Wrap(
              spacing: 6,
              children: [
                for (final e in VoiceEffect.values)
                  ChoiceChip(
                    label: Text(e.name),
                    selected: _effect == e,
                    onSelected: (_) => setEffect(e),
                  ),
              ],
            ),
            const Divider(),
            _slider(l10n.voiceLabPitch, _pitch, -12, 12, 'pitch'),
            _slider(l10n.voiceLabSpeed, _speed, 0.5, 2, 'speed'),
            _slider(l10n.voiceLabTremolo, _tremolo, 0, 1, 'tremolo'),
            _slider(l10n.voiceLabGate, _gate, 0, 1, 'gate'),
            _slider(l10n.voiceLabReverb, _reverb, 0, 0.8, 'reverb'),
          ],
        ],
      ),
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    String key,
  ) {
    return Row(
      children: [
        SizedBox(width: 92, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChangeEnd: (v) => setParam(key, v),
            onChanged: (v) => setState(() {
              switch (key) {
                case 'pitch':
                  _pitch = v;
                case 'speed':
                  _speed = v;
                case 'tremolo':
                  _tremolo = v;
                case 'gate':
                  _gate = v;
                case 'reverb':
                  _reverb = v;
              }
            }),
          ),
        ),
      ],
    );
  }
}
