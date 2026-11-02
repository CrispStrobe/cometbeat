// Loop Studio's export render: the worker must reproduce EXACTLY what the
// live engine plays, and the message it is sent must cross an isolate.

import 'dart:isolate';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/loop_export_render.dart';
import 'package:comet_beat/core/audio/wav_io.dart';
import 'package:flutter_test/flutter_test.dart';

LoopEngine _band() =>
    LoopEngine()..enabled.addAll(['drums', 'bass', 'chords', 'melody']);

void main() {
  test('a plain groove renders identically off-thread', () async {
    final engine = _band();
    final job = grooveRenderJob(engine);
    final off = await Isolate.run(() => renderGrooveJob(job));
    expect(off, engine.renderLoop());
  });

  test('the MASTER BUS reaches the export (it is not in the spec)', () async {
    // The send, FX chain and master filter are live controls outside the share
    // token. Rendering the export from the spec alone dropped them, so the
    // file did not sound like what was playing.
    final engine = _band()
      ..send = LoopSend.reverb
      ..masterFilter = -0.5
      ..masterFxChain = [
        const FxSpec(type: FxType.chorus),
      ];
    final fromSpecOnly = (LoopEngine()..applySpec(engine.spec)).renderLoop();
    expect(fromSpecOnly, isNot(engine.renderLoop()), reason: 'precondition');

    final job = grooveRenderJob(engine);
    final off = await Isolate.run(() => renderGrooveJob(job));
    expect(off, engine.renderLoop());
  });

  test('a panned groove exports STEREO', () async {
    final engine = _band()..pans['chords'] = -0.7;
    final job = grooveRenderJob(engine);
    final wav = readWavPcm16(await Isolate.run(() => renderGrooveJob(job)));
    expect(wav.channels, 2);
    final ch = wavToChannels(wav);
    expect(ch.right, isNotNull);
  });

  test('an audio track keeps the render on the calling isolate', () {
    final engine = _band();
    expect(canRenderGrooveOffThread(engine), isTrue);
    engine.addAudioTrack(Float64List(4410));
    expect(canRenderGrooveOffThread(engine), isFalse);
  });
}
