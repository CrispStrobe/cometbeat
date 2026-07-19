// The shared "My Instruments" browser over [InstrumentLibraryStore] — the
// instrument sibling of "My Samples". Lists the playable instruments you've
// saved (a shaped Voice Lab voice, later a SoundFont preset, …), auditions one
// by rendering a note, and deletes. Opened for management, or as a picker that
// resolves to the chosen instrument.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/sound_lab/instrument_library_store.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Shows the library. Resolves to the picked [SavedInstrument], or null
/// (cancelled, or opened with [pickable] false).
Future<SavedInstrument?> showMyInstrumentsSheet(
  BuildContext context, {
  InstrumentLibraryStore? store,
  bool pickable = true,
}) {
  return showModalBottomSheet<SavedInstrument>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => MyInstrumentsSheet(
      store: store ?? InstrumentLibraryStore(),
      pickable: pickable,
    ),
  );
}

/// Renders one note ([midi], default middle C) from [inst] for a preview.
Float64List renderInstrumentNote(TrackerInstrument inst, [int midi = 60]) =>
    inst.renderChannel(
      [TrackerCell(midi: midi)],
      const TrackerTiming(rows: 4),
    );

/// One octave of white keys, C4..C5 — the play keyboard's notes + labels.
const List<int> kKeyboardMidi = [60, 62, 64, 65, 67, 69, 71, 72];
const List<String> kKeyboardLabels = ['C', 'D', 'E', 'F', 'G', 'A', 'B', 'C'];

/// Test seam — drive the sheet without tapping through the UI.
abstract class MyInstrumentsTester {
  List<SavedInstrument> get instruments;
  Future<void> deleteAt(int index);
}

@visibleForTesting
class MyInstrumentsSheet extends StatefulWidget {
  const MyInstrumentsSheet({
    required this.store,
    this.pickable = true,
    super.key,
  });

  final InstrumentLibraryStore store;
  final bool pickable;

  @override
  State<MyInstrumentsSheet> createState() => _MyInstrumentsSheetState();
}

class _MyInstrumentsSheetState extends State<MyInstrumentsSheet>
    implements MyInstrumentsTester {
  List<SavedInstrument> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.store.load().then((list) {
      if (mounted) {
        setState(() {
          _items = list;
          _loading = false;
        });
      }
    });
  }

  @override
  List<SavedInstrument> get instruments => _items;

  @override
  Future<void> deleteAt(int index) async {
    final list = await widget.store.delete(_items[index].name);
    if (mounted) setState(() => _items = list);
  }

  void _playNote(TrackerInstrument inst, int midi) {
    final pcm = renderInstrumentNote(inst, midi);
    if (pcm.isEmpty) return;
    context.read<AudioService>().playWavBytes(pcmFloatToWav(pcm));
  }

  void _audition(SavedInstrument s) {
    final inst = s.instrument;
    if (inst != null) _playNote(inst, 60); // references need the font — skip
  }

  /// Opens a one-octave keyboard that plays [s] at each tapped pitch.
  Future<void> _showKeyboard(SavedInstrument s) async {
    final inst = s.instrument;
    if (inst == null) return;
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${l10n.myInstrumentsPlay} · ${s.name}'),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (var i = 0; i < kKeyboardMidi.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: SizedBox(
                          height: 96,
                          child: ElevatedButton(
                            onPressed: () => _playNote(inst, kKeyboardMidi[i]),
                            child: Text(kKeyboardLabels[i]),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.piano_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    l10n.myInstrumentsTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  if (_items.isNotEmpty)
                    Text(
                      '${_items.length}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            Expanded(
              child: _items.isEmpty && !_loading
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l10n.myInstrumentsEmpty,
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (ctx, i) {
                        final s = _items[i];
                        final subtitle = [
                          if (s.source != null) s.source!,
                          s.kind,
                        ].join(' · ');
                        return ListTile(
                          title: Text(s.name),
                          subtitle: Text(subtitle),
                          onTap: widget.pickable
                              ? () => Navigator.of(context).pop(s)
                              : null,
                          leading: IconButton(
                            icon: const Icon(Icons.play_arrow),
                            tooltip: l10n.myInstrumentsAudition,
                            onPressed:
                                s.isReference ? null : () => _audition(s),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.piano),
                                tooltip: l10n.myInstrumentsPlay,
                                onPressed: s.isReference
                                    ? null
                                    : () => _showKeyboard(s),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: l10n.myInstrumentsDelete,
                                onPressed: () => deleteAt(i),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
