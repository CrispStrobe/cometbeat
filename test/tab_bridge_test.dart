import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/features/games/composition/tab_bridge.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('trackerChannelToTab resolves midi notes to string/fret positions', () {
    final channel = TrackerChannel(
      id: 'guitar',
      instrument: const PercussionInstrument('dummy'),
      rows: 4,
    );
    channel.cells.setAll(0, [
      const TrackerCell(midi: 40), // E2 (standard guitar lowest note)
      const TrackerCell(),
      const TrackerCell(midi: 45), // A2
      const TrackerCell(),
    ]);

    final doc = trackerChannelToTab(channel, Tuning.standardGuitar);

    expect(doc.columns.length, 4);
    expect(
        doc.columns[0].frets, {5: 0}); // 6th string (index 5), open fret (E2)
    expect(doc.columns[1].frets, isEmpty);
    expect(
        doc.columns[2].frets, {4: 0}); // 5th string (index 4), open fret (A2)
    expect(doc.columns[3].frets, isEmpty);
  });
}
