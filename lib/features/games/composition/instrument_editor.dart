import 'dart:typed_data';

import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/games/composition/sample_waveform_widget.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart';
import 'package:comet_beat/shared/widgets/piano_keyboard.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

Future<TrackerInstrument?> showInstrumentEditor(
  BuildContext context,
  TrackerInstrument initial,
) async {
  return showModalBottomSheet<TrackerInstrument>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _InstrumentEditorSheet(initial: initial),
  );
}

class _InstrumentEditorSheet extends StatefulWidget {
  const _InstrumentEditorSheet({required this.initial});
  final TrackerInstrument initial;

  @override
  State<_InstrumentEditorSheet> createState() => _InstrumentEditorSheetState();
}

class _InstrumentEditorSheetState extends State<_InstrumentEditorSheet> {
  late TrackerInstrument _inst;

  @override
  void initState() {
    super.initState();
    _inst = widget.initial;
  }

  void _playNote(int midi) {
    // Generate a short note run to audition the instrument.
    final pcm = _inst.renderChannel(
      [TrackerCell(midi: midi, volume: 1.0), const TrackerCell()],
      const TrackerTiming(tempoBpm: 120, rows: 2),
    );
    if (pcm.isEmpty) return;
    
    // We could use context.read<AudioService>() if available, but
    // since AudioService is often accessed globally or passed around...
    // Wait, let me just check how AudioService is retrieved.
    // I'll import it and use context.read<AudioService>()!
    final audio = context.read<AudioService>();
    final wav = pcmFloatToWav(pcm);
    audio.playWavBytes(wav);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  "Edit Instrument",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(_inst),
                  child: const Text('Done'),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: _buildEditorBody(),
            ),
            const Divider(),
            // Testing keyboard
            SizedBox(
              height: 120,
              child: PianoKeyboard(
                startMidi: 48,
                whiteKeyCount: 15,
                onKeyTap: _playNote,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorBody() {
    if (_inst is SampleInstrument) {
      return _SampleEditor(
        inst: _inst as SampleInstrument,
        onChanged: (newInst) => setState(() => _inst = newInst),
      );
    } else if (_inst is SfxrInstrument) {
      return const Center(child: Text('Sfxr Editor (coming soon)'));
    } else {
      return const Center(child: Text('Preset Instrument (Not editable)'));
    }
  }
}

class _SampleEditor extends StatelessWidget {
  const _SampleEditor({required this.inst, required this.onChanged});
  final SampleInstrument inst;
  final ValueChanged<SampleInstrument> onChanged;

  @override
  Widget build(BuildContext context) {
    final len = inst.sample.length;
    final startFrac = len == 0 ? 0.0 : inst.loopStart / len;
    final endFrac = len == 0 ? 1.0 : (inst.loopStart + inst.loopLength) / len;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Loop Editor',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        SampleWaveform(
          pcm: inst.sample,
          start: startFrac,
          end: endFrac,
          onChanged: (s, e) {
            if (len == 0) return;
            final loopStart = (s * len).round();
            final loopEnd = (e * len).round();
            onChanged(
              SampleInstrument(
                inst.id,
                inst.sample,
                baseMidi: inst.baseMidi,
                envelope: inst.envelope,
                loopStart: loopStart,
                loopLength: loopEnd - loopStart,
                offsetScale: inst.offsetScale,
                pingPong: inst.pingPong,
              ),
            );
          },
          wave: Theme.of(context).colorScheme.primary,
          bg: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Ping-Pong Loop'),
          subtitle: const Text('Bounces forward and backward'),
          value: inst.pingPong,
          onChanged: (v) {
            onChanged(
              SampleInstrument(
                inst.id,
                inst.sample,
                baseMidi: inst.baseMidi,
                envelope: inst.envelope,
                loopStart: inst.loopStart,
                loopLength: inst.loopLength,
                offsetScale: inst.offsetScale,
                pingPong: v,
              ),
            );
          },
        ),
        ListTile(
          title: const Text('Base Note (Tuning)'),
          subtitle: Text('MIDI: ${inst.baseMidi}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: () => onChanged(
                  SampleInstrument(
                    inst.id,
                    inst.sample,
                    baseMidi: (inst.baseMidi - 1).clamp(0, 127),
                    envelope: inst.envelope,
                    loopStart: inst.loopStart,
                    loopLength: inst.loopLength,
                    offsetScale: inst.offsetScale,
                    pingPong: inst.pingPong,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => onChanged(
                  SampleInstrument(
                    inst.id,
                    inst.sample,
                    baseMidi: (inst.baseMidi + 1).clamp(0, 127),
                    envelope: inst.envelope,
                    loopStart: inst.loopStart,
                    loopLength: inst.loopLength,
                    offsetScale: inst.offsetScale,
                    pingPong: inst.pingPong,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
