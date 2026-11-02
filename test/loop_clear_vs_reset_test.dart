// "Clear part" must EMPTY a built-in part; resetting to the preset is a
// separate action. Root cause of the old bug: the engine treated an all-rest /
// all-off override as "no override", so clearing silently restored the preset.
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:flutter_test/flutter_test.dart';

LoopEngine _engine() {
  final e = LoopEngine(tempoBpm: 120);
  e.enabled
    ..clear()
    ..addAll(['drums', 'bass', 'melody', 'chords']);
  return e;
}

void main() {
  test('pitched: an all-rest run stays empty; clearTrackCells restores', () {
    final e = _engine();
    final preset = e.cellsFor('melody')!;
    expect(preset.any((c) => c.midis != null), isTrue);

    e.setTrackCells('melody', [const PatternCell(steps: kPatternSteps)]);
    expect(e.trackCellsOverride('melody'), isNotNull);
    expect(e.cellsFor('melody')!.every((c) => c.midis == null), isTrue);
    expect(e.renderLoop(), isNotEmpty); // empty voice still renders

    e.clearTrackCells('melody');
    expect(e.trackCellsOverride('melody'), isNull);
    expect(e.cellsFor('melody')!.any((c) => c.midis != null), isTrue);
  });

  test('drums: an all-off grid stays empty; null restores the preset', () {
    final e = _engine();
    final preset = e.drumRowsFor('drums')!;
    final empty = DrumRowsPattern({
      for (final d in preset.rows.keys)
        d: List<bool>.filled(kPatternSteps, false),
    });
    e.setTrackDrums('drums', empty);
    expect(
      e.drumRowsFor('drums')!.rows.values.every((r) => r.every((h) => !h)),
      isTrue,
    );
    expect(e.renderLoop(), isNotEmpty);
    // survives the share token
    final back = GrooveSpec.fromJson(e.spec.toJson());
    expect(back.drumOverrides?['drums'], isNotNull);

    e.setTrackDrums('drums', null);
    expect(e.trackDrumsOverride('drums'), isNull);
    expect(
      e.drumRowsFor('drums')!.rows.values.any((r) => r.any((h) => h)),
      isTrue,
    );
    expect(Drum.values, isNotEmpty);
  });
}
