import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/games/composition/sample_waveform_widget.dart';
import 'package:comet_beat/features/sound_lab/sound_lab_screen.dart';
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
      const TrackerTiming(rows: 2),
    );
    if (pcm.isEmpty) return;

    final audio = context.read<AudioService>();
    final wav = pcmFloatToWav(pcm);
    audio.playWavBytes(wav);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  'Edit Instrument',
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
    } else if (_inst is MultiSampleInstrument) {
      return _MultiSampleEditor(
        inst: _inst as MultiSampleInstrument,
        onChanged: (newInst) => setState(() => _inst = newInst),
      );
    } else {
      return SoundLabScreen(
        embedded: true,
        onChanged: (pcm) {
          setState(() {
            // Replace the instrument with a sample instrument of the new sound
            _inst = SampleInstrument(
              _inst.id,
              pcm,
            );
          });
        },
      );
    }
  }
}

class _MultiSampleEditor extends StatefulWidget {
  const _MultiSampleEditor({required this.inst, required this.onChanged});
  final MultiSampleInstrument inst;
  final ValueChanged<MultiSampleInstrument> onChanged;

  @override
  State<_MultiSampleEditor> createState() => _MultiSampleEditorState();
}

class _MultiSampleEditorState extends State<_MultiSampleEditor> {
  late int _selectedMidi;

  @override
  void initState() {
    super.initState();
    _selectedMidi =
        widget.inst.zones.isEmpty ? 60 : widget.inst.zones.keys.first;
  }

  @override
  Widget build(BuildContext context) {
    final keys = widget.inst.zones.keys.toList()..sort();
    if (keys.isEmpty) return const Center(child: Text('No mapped zones'));
    if (!keys.contains(_selectedMidi)) _selectedMidi = keys.first;
    final zone = widget.inst.zones[_selectedMidi];
    return ListView(
      children: [
        ListTile(
          title: const Text('Mapped Note'),
          trailing: DropdownButton<int>(
            value: _selectedMidi,
            items: [
              for (final key in keys)
                DropdownMenuItem(value: key, child: Text('MIDI $key')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _selectedMidi = value);
            },
          ),
        ),
        if (zone is SampleInstrument)
          _SampleEditor(
            inst: zone,
            onChanged: (edited) {
              final updated = Map<int, TrackerInstrument>.of(widget.inst.zones)
                ..[_selectedMidi] = edited;
              widget.onChanged(widget.inst.copyWith(zones: updated));
            },
          )
        else
          const ListTile(
            title: Text('This zone is procedural'),
            subtitle: Text('Use the sound editor to replace it with a sample.'),
          ),
      ],
    );
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
            onChanged(inst.copyWith(
              loopStart: loopStart,
              loopLength: loopEnd - loopStart,
            ));
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
            onChanged(inst.copyWith(pingPong: v));
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
                  inst.copyWith(
                    baseMidi: (inst.baseMidi - 1).clamp(0, 127),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => onChanged(
                  inst.copyWith(
                    baseMidi: (inst.baseMidi + 1).clamp(0, 127),
                  ),
                ),
              ),
            ],
          ),
        ),
        ListTile(
          title: const Text('Sample Volume'),
          subtitle: Text('${(inst.volume * 100).round()}%'),
          trailing: SizedBox(
            width: 180,
            child: Slider(
              value: inst.volume.clamp(0.0, 1.0),
              min: 0,
              max: 1,
              onChanged: (v) => onChanged(inst.copyWith(volume: v)),
            ),
          ),
        ),
        ListTile(
          title: const Text('New Note Action'),
          trailing: DropdownButton<int>(
            value: inst.nativeNna.clamp(0, 3).toInt(),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Cut')),
              DropdownMenuItem(value: 1, child: Text('Continue')),
              DropdownMenuItem(value: 2, child: Text('Note Off')),
              DropdownMenuItem(value: 3, child: Text('Fade')),
            ],
            onChanged: (v) =>
                v == null ? null : onChanged(inst.copyWith(nativeNna: v)),
          ),
        ),
        ListTile(
          title: const Text('Duplicate Check'),
          trailing: DropdownButton<int>(
            value: inst.nativeDct.clamp(0, 3).toInt(),
            items: const [
              DropdownMenuItem(value: 0, child: Text('None')),
              DropdownMenuItem(value: 1, child: Text('Note')),
              DropdownMenuItem(value: 2, child: Text('Sample')),
              DropdownMenuItem(value: 3, child: Text('Instrument')),
            ],
            onChanged: (v) =>
                v == null ? null : onChanged(inst.copyWith(nativeDct: v)),
          ),
        ),
        ListTile(
          title: const Text('Duplicate Action'),
          trailing: DropdownButton<int>(
            value: inst.nativeDca.clamp(0, 2).toInt(),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Cut')),
              DropdownMenuItem(value: 1, child: Text('Note Off')),
              DropdownMenuItem(value: 2, child: Text('Fade')),
            ],
            onChanged: (v) =>
                v == null ? null : onChanged(inst.copyWith(nativeDca: v)),
          ),
        ),
        ListTile(
          title: const Text('Fadeout'),
          subtitle: Text('${inst.nativeFadeout} / 1024'),
          trailing: SizedBox(
            width: 180,
            child: Slider(
              value: inst.nativeFadeout.clamp(0, 1024).toDouble(),
              min: 0,
              max: 1024,
              onChanged: (v) =>
                  onChanged(inst.copyWith(nativeFadeout: v.round())),
            ),
          ),
        ),
      ],
    );
  }
}
