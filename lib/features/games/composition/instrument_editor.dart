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

  Future<int?> _askMidi({int? initial}) async {
    final controller = TextEditingController(text: '${initial ?? 60}');
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('MIDI key'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '0-127'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final midi = int.tryParse(controller.text.trim());
              if (midi != null && midi >= 0 && midi <= 127) {
                Navigator.of(ctx).pop(midi);
              }
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _addMapping() async {
    final midi = await _askMidi();
    if (!mounted || midi == null || widget.inst.zones.containsKey(midi)) return;
    final source = widget.inst.zones[_selectedMidi];
    if (source == null) return;
    final zones = Map<int, TrackerInstrument>.of(widget.inst.zones)
      ..[midi] = source;
    widget.onChanged(widget.inst.copyWith(zones: zones));
    setState(() => _selectedMidi = midi);
  }

  Future<void> _remapSelected() async {
    final midi = await _askMidi(initial: _selectedMidi);
    if (!mounted || midi == null || midi == _selectedMidi) return;
    if (widget.inst.zones.containsKey(midi)) return;
    final zones = Map<int, TrackerInstrument>.of(widget.inst.zones)
      ..[midi] = widget.inst.zones[_selectedMidi]!
      ..remove(_selectedMidi);
    widget.onChanged(widget.inst.copyWith(zones: zones));
    setState(() => _selectedMidi = midi);
  }

  void _removeSelected() {
    final zones = Map<int, TrackerInstrument>.of(widget.inst.zones)
      ..remove(_selectedMidi);
    widget.onChanged(widget.inst.copyWith(zones: zones));
    setState(() {
      _selectedMidi = zones.isEmpty ? 60 : (zones.keys.toList()..sort()).first;
    });
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
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<int>(
                value: _selectedMidi,
                items: [
                  for (final key in keys)
                    DropdownMenuItem(value: key, child: Text('MIDI $key')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _selectedMidi = value);
                },
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add key mapping',
                onPressed: _addMapping,
              ),
              IconButton(
                icon: const Icon(Icons.drive_file_rename_outline),
                tooltip: 'Remap selected key',
                onPressed: _remapSelected,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove key mapping',
                onPressed: _removeSelected,
              ),
            ],
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

  Future<void> _editVolumeEnvelope(BuildContext context) async {
    final edited = await showDialog<VolumeEnvelope>(
      context: context,
      builder: (_) => _NativeVolumeEnvelopeDialog(
        initial: inst.nativeVolumeEnvelope,
      ),
    );
    if (edited != null) onChanged(inst.copyWith(nativeVolumeEnvelope: edited));
  }

  Future<void> _editPanEnvelope(BuildContext context) async {
    final edited = await showDialog<PanEnvelope>(
      context: context,
      builder: (_) => _NativePanEnvelopeDialog(
        initial: inst.nativePanEnvelope,
      ),
    );
    if (edited != null) onChanged(inst.copyWith(nativePanEnvelope: edited));
  }

  @override
  Widget build(BuildContext context) {
    final len = inst.sample.length;
    final startFrac = len == 0 ? 0.0 : inst.loopStart / len;
    final endFrac = len == 0 ? 1.0 : (inst.loopStart + inst.loopLength) / len;
    final sustainStartFrac = len == 0
        ? 0.0
        : (inst.sustainLoopStart.clamp(0, len) / len.toDouble()).toDouble();
    final sustainEndFrac = inst.sustainLoopLength <= 0 || len == 0
        ? 1.0
        : ((inst.sustainLoopStart + inst.sustainLoopLength).clamp(0, len) /
                len.toDouble())
            .toDouble();

    return ListView(
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
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Sustain Loop Editor',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        SampleWaveform(
          pcm: inst.sample,
          start: sustainStartFrac,
          end: sustainEndFrac,
          onChanged: (s, e) {
            if (len == 0) return;
            final sustainStart = (s * len).round();
            final sustainEnd = (e * len).round();
            onChanged(inst.copyWith(
              sustainLoopStart: sustainStart,
              sustainLoopLength: sustainEnd - sustainStart,
            ));
          },
          wave: Theme.of(context).colorScheme.secondary,
          bg: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        SwitchListTile(
          title: const Text('Ping-Pong Sustain'),
          subtitle: const Text('Bounces while the note is held'),
          value: inst.sustainPingPong,
          onChanged: (v) => onChanged(inst.copyWith(sustainPingPong: v)),
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
          title: const Text('Native Volume Envelope'),
          subtitle: Text(_envelopeSummary(inst.nativeVolumeEnvelope)),
          trailing: IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Edit native volume envelope',
            onPressed: () => _editVolumeEnvelope(context),
          ),
        ),
        ListTile(
          title: const Text('Native Pan Envelope'),
          subtitle: Text(
            _envelopeSummary(inst.nativePanEnvelope),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Edit native pan envelope',
            onPressed: () => _editPanEnvelope(context),
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

String _envelopeSummary(Object? envelope) {
  if (envelope == null) return 'Disabled';
  final points = envelope is VolumeEnvelope
      ? envelope.points.length
      : (envelope as PanEnvelope).points.length;
  return points == 0 ? 'Disabled' : '$points points';
}

class _NativeVolumeEnvelopeDialog extends StatefulWidget {
  const _NativeVolumeEnvelopeDialog({required this.initial});
  final VolumeEnvelope? initial;

  @override
  State<_NativeVolumeEnvelopeDialog> createState() =>
      _NativeVolumeEnvelopeDialogState();
}

class _NativeVolumeEnvelopeDialogState
    extends State<_NativeVolumeEnvelopeDialog> {
  late List<({TextEditingController ms, TextEditingController value})> _rows;
  int? _sustain;
  int? _loopStart;
  int? _loopEnd;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _rows = [
      for (final point in initial?.points ?? const <({int ms, double level})>[])
        (
          ms: TextEditingController(text: '${point.ms}'),
          value: TextEditingController(text: '${point.level}'),
        ),
    ];
    _sustain = initial?.sustain;
    _loopStart = initial?.loopStart;
    _loopEnd = initial?.loopEnd;
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.ms.dispose();
      row.value.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    final ms =
        _rows.isEmpty ? 0 : (int.tryParse(_rows.last.ms.text) ?? 0) + 100;
    setState(() {
      _rows.add((
        ms: TextEditingController(text: '$ms'),
        value: TextEditingController(text: '1'),
      ));
    });
  }

  void _removeRow(int index) {
    final row = _rows.removeAt(index);
    row.ms.dispose();
    row.value.dispose();
    setState(() {
      _sustain = _removePointIndex(_sustain, index);
      _loopStart = _removePointIndex(_loopStart, index);
      _loopEnd = _removePointIndex(_loopEnd, index);
    });
  }

  int? _removePointIndex(int? value, int removed) {
    if (value == null || value == removed) return null;
    return value > removed ? value - 1 : value;
  }

  void _apply() {
    final values = <({int index, int ms, double level})>[];
    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      final ms = int.tryParse(row.ms.text.trim());
      final level = double.tryParse(row.value.text.trim());
      if (ms == null || level == null || ms < 0) return;
      values.add((index: i, ms: ms, level: level.clamp(0.0, 1.0)));
    }
    values.sort((a, b) => a.ms.compareTo(b.ms));
    final remap = <int, int>{
      for (var i = 0; i < values.length; i++) values[i].index: i,
    };
    int? mapped(int? value) => value == null ? null : remap[value];
    Navigator.of(context).pop(VolumeEnvelope(
      [for (final value in values) (ms: value.ms, level: value.level)],
      sustain: mapped(_sustain),
      loopStart: mapped(_loopStart),
      loopEnd: mapped(_loopEnd),
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Native Volume Envelope'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _rows.length; i++)
                  _EnvelopePointRow(
                    index: i,
                    ms: _rows[i].ms,
                    value: _rows[i].value,
                    valueLabel: 'Level',
                    onRemove: () => _removeRow(i),
                  ),
                TextButton.icon(
                  onPressed: _addRow,
                  icon: const Icon(Icons.add),
                  label: const Text('Add point'),
                ),
                _EnvelopeIndexRow(
                  label: 'Sustain point',
                  value: _sustain,
                  count: _rows.length,
                  onChanged: (v) => setState(() => _sustain = v),
                ),
                _EnvelopeIndexRow(
                  label: 'Loop start',
                  value: _loopStart,
                  count: _rows.length,
                  onChanged: (v) => setState(() => _loopStart = v),
                ),
                _EnvelopeIndexRow(
                  label: 'Loop end',
                  value: _loopEnd,
                  count: _rows.length,
                  onChanged: (v) => setState(() => _loopEnd = v),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(onPressed: _apply, child: const Text('Apply')),
        ],
      );
}

class _NativePanEnvelopeDialog extends StatefulWidget {
  const _NativePanEnvelopeDialog({required this.initial});
  final PanEnvelope? initial;

  @override
  State<_NativePanEnvelopeDialog> createState() =>
      _NativePanEnvelopeDialogState();
}

class _NativePanEnvelopeDialogState extends State<_NativePanEnvelopeDialog> {
  late List<({TextEditingController ms, TextEditingController value})> _rows;
  int? _sustain;
  int? _loopStart;
  int? _loopEnd;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _rows = [
      for (final point in initial?.points ?? const <({int ms, double pan})>[])
        (
          ms: TextEditingController(text: '${point.ms}'),
          value: TextEditingController(text: '${point.pan}'),
        ),
    ];
    _sustain = initial?.sustain;
    _loopStart = initial?.loopStart;
    _loopEnd = initial?.loopEnd;
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.ms.dispose();
      row.value.dispose();
    }
    super.dispose();
  }

  void _addRow() => setState(() {
        final ms =
            _rows.isEmpty ? 0 : (int.tryParse(_rows.last.ms.text) ?? 0) + 100;
        _rows.add((
          ms: TextEditingController(text: '$ms'),
          value: TextEditingController(text: '0'),
        ));
      });

  void _removeRow(int index) {
    final row = _rows.removeAt(index);
    row.ms.dispose();
    row.value.dispose();
    setState(() {
      _sustain = _removePointIndex(_sustain, index);
      _loopStart = _removePointIndex(_loopStart, index);
      _loopEnd = _removePointIndex(_loopEnd, index);
    });
  }

  int? _removePointIndex(int? value, int removed) {
    if (value == null || value == removed) return null;
    return value > removed ? value - 1 : value;
  }

  void _apply() {
    final values = <({int index, int ms, double pan})>[];
    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      final ms = int.tryParse(row.ms.text.trim());
      final pan = double.tryParse(row.value.text.trim());
      if (ms == null || pan == null || ms < 0) return;
      values.add((index: i, ms: ms, pan: pan.clamp(-1.0, 1.0)));
    }
    values.sort((a, b) => a.ms.compareTo(b.ms));
    final remap = <int, int>{
      for (var i = 0; i < values.length; i++) values[i].index: i,
    };
    int? mapped(int? value) => value == null ? null : remap[value];
    Navigator.of(context).pop(PanEnvelope(
      [for (final value in values) (ms: value.ms, pan: value.pan)],
      sustain: mapped(_sustain),
      loopStart: mapped(_loopStart),
      loopEnd: mapped(_loopEnd),
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Native Pan Envelope'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _rows.length; i++)
                  _EnvelopePointRow(
                    index: i,
                    ms: _rows[i].ms,
                    value: _rows[i].value,
                    valueLabel: 'Pan (-1..1)',
                    onRemove: () => _removeRow(i),
                  ),
                TextButton.icon(
                  onPressed: _addRow,
                  icon: const Icon(Icons.add),
                  label: const Text('Add point'),
                ),
                _EnvelopeIndexRow(
                  label: 'Sustain point',
                  value: _sustain,
                  count: _rows.length,
                  onChanged: (v) => setState(() => _sustain = v),
                ),
                _EnvelopeIndexRow(
                  label: 'Loop start',
                  value: _loopStart,
                  count: _rows.length,
                  onChanged: (v) => setState(() => _loopStart = v),
                ),
                _EnvelopeIndexRow(
                  label: 'Loop end',
                  value: _loopEnd,
                  count: _rows.length,
                  onChanged: (v) => setState(() => _loopEnd = v),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(onPressed: _apply, child: const Text('Apply')),
        ],
      );
}

class _EnvelopePointRow extends StatelessWidget {
  const _EnvelopePointRow({
    required this.index,
    required this.ms,
    required this.value,
    required this.valueLabel,
    required this.onRemove,
  });
  final int index;
  final TextEditingController ms;
  final TextEditingController value;
  final String valueLabel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(
            width: 70,
            child: TextField(
              controller: ms,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'ms'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: value,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              decoration: InputDecoration(labelText: valueLabel),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove point $index',
            onPressed: onRemove,
          ),
        ],
      );
}

class _EnvelopeIndexRow extends StatelessWidget {
  const _EnvelopeIndexRow({
    required this.label,
    required this.value,
    required this.count,
    required this.onChanged,
  });
  final String label;
  final int? value;
  final int count;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        title: Text(label),
        trailing: DropdownButton<int?>(
          value: value,
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('None')),
            for (var i = 0; i < count; i++)
              DropdownMenuItem<int?>(value: i, child: Text('$i')),
          ],
          onChanged: onChanged,
        ),
      );
}
