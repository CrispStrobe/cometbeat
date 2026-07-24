import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cell mutators preserve key-off state while changing one field', () {
    final engine = TrackerEngine(
      channels: [
        TrackerChannel(
          id: 'test',
          instrument: const AdditiveInstrument('piano', Instrument.piano),
          rows: 4,
          cells: [
            const TrackerCell(midi: 60, keyOff: true),
            TrackerCell.empty,
            TrackerCell.empty,
            TrackerCell.empty,
          ],
        ),
      ],
      timing: const TrackerTiming(rows: 4),
    );

    engine.setCellVolume(0, 0, 0.5);
    engine.setCellEffect(0, 0, TrackerEffect.vibrato);
    engine.setCellInstrument(0, 0, 2);

    final cell = engine.cellAt(0, 0);
    expect(cell.keyOff, isTrue);
    expect(cell.midi, 60);
    expect(cell.volume, 0.5);
    expect(cell.effect, TrackerEffect.vibrato);
    expect(cell.instrument, 2);
  });
}
