import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:comet_beat/features/games/composition/tab_arranger.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';

/// Translates a monophonic [TrackerChannel] into a [TabDocument] by resolving
/// its MIDI notes into idiomatic string/fret positions using the Viterbi arranger.
TabDocument trackerChannelToTab(TrackerChannel channel, Tuning tuning) {
  final midiColumns = channel.cells.map((c) {
    if (c.midi != null && c.midi! > 0) return [c.midi!];
    return <int>[];
  }).toList();

  final frettings = arrangeTab(midiColumns, tuning);
  
  final tabColumns = frettings.map((f) => TabColumn(frets: f)).toList();
  
  return TabDocument(tuning: tuning, columns: tabColumns);
}
