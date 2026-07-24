// Setting a saved-instrument voice on a pitched Loop Mixer track re-renders that
// track through the instrument (the tracker's own render path) instead of its
// built-in timbre — so the rendered loop changes, and clearing the voice
// restores it. Drums (no midi cells) are untouched by a voice override.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:flutter_test/flutter_test.dart';

TrackerInstrument _voice() {
  final pcm = Float64List(2048);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = 0.4 * math.sin(2 * math.pi * 220 * i / 44100);
  }
  return SampleInstrument('v', pcm);
}

void main() {
  test(
      'voicing a pitched track changes the rendered loop; clearing restores it',
      () {
    final engine = LoopEngine();
    engine.toggle('bass'); // enable the pitched track we voice
    final before = engine.renderLoop();

    engine.setTrackVoice('bass', _voice());
    final voiced = engine.renderLoop();
    expect(voiced, isNot(before), reason: 'the voiced bass should differ');
    expect(engine.trackVoice('bass'), isNotNull);

    engine.setTrackVoice('bass', null);
    final restored = engine.renderLoop();
    expect(restored, before, reason: 'clearing the voice restores the timbre');
    expect(engine.trackVoice('bass'), isNull);
  });

  test('a voice on the drum track leaves the loop unchanged (no midi cells)',
      () {
    final engine = LoopEngine();
    engine.toggle('drums');
    final before = engine.renderLoop();
    engine.setTrackVoice('drums', _voice());
    expect(engine.renderLoop(), before);
  });

  test('serializable track voices survive a groove share roundtrip', () {
    final engine = LoopEngine()
      ..toggle('bass')
      ..setTrackVoice('bass', _voice());

    final decoded = decodeGrooveToken(encodeGrooveToken(engine.spec));
    expect(decoded?.trackVoices?['bass'], isNotNull);

    final restored = LoopEngine()..applySpec(decoded!);
    expect(restored.trackVoice('bass'), isNotNull);
    final originalPcm = Int16List.sublistView(engine.renderLoop(), 44);
    final restoredPcm = Int16List.sublistView(restored.renderLoop(), 44);
    expect(restoredPcm.length, originalPcm.length);
    var maxError = 0;
    for (var i = 0; i < originalPcm.length; i++) {
      final error = (originalPcm[i] - restoredPcm[i]).abs();
      if (error > maxError) maxError = error;
    }
    expect(maxError, lessThanOrEqualTo(2));
  });
}
