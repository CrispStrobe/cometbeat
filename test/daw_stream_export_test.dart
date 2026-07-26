// streamTimelineWav (daw_timeline.dart) — bounded-memory WAV export for the DAW
// timeline. It renders the mix in windows via renderTimelineWindowStereo and
// emits WAV bytes chunk by chunk, so a long arrangement exports in the memory of
// one window instead of the whole-song mix.
//
// The load-bearing property: the streamed bytes are BYTE-IDENTICAL to
// pcmFloatToWav(renderTimelineStereo(...)) — the real whole-buffer export — and
// stay identical no matter the block size (a streamed export that drifts from
// the bake would make the file lie about the mix).

// The export sample rate is spelled out even where it matches pcmFloatToWav's
// default — the whole point is that the streamed and whole exports agree at the
// DAW's rate, so leaving it implicit would hide the thing under test.
// ignore_for_file: avoid_redundant_argument_values

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart'
    show pcmFloatToWav;
import 'package:flutter_test/flutter_test.dart';

const _rate = kDawSampleRate;

Float64List _tone(double freq, int samples, {double amp = 0.4}) =>
    Float64List.fromList([
      for (var i = 0; i < samples; i++)
        amp * math.sin(2 * math.pi * freq * i / _rate),
    ]);

DawTimeline _twoLanes() => DawTimeline(
      tracks: [
        DawTrack(
          name: 'A',
          clips: [
            Clip(source: SampleSource(_tone(220, _rate)), gain: 0.8),
            Clip(
              source: SampleSource(_tone(330, _rate ~/ 2)),
              startMs: 1500,
              pan: -0.5,
            ),
          ],
        ),
        DawTrack(
          name: 'B',
          gain: 0.6,
          clips: [
            Clip(
              source: SampleSource(_tone(440, _rate)),
              startMs: 500,
              fadeInMs: 100,
              fadeOutMs: 200,
            ),
          ],
        ),
      ],
    );

Uint8List _stream(DawTimeline t, {int blockSamples = 1 << 15}) {
  final bb = BytesBuilder();
  streamTimelineWav(t, onBytes: bb.add, blockSamples: blockSamples);
  return bb.toBytes();
}

Uint8List _wholeWav(DawTimeline t) {
  final mix = renderTimelineStereo(t, cache: {});
  return pcmFloatToWav(mix.left, right: mix.right, sampleRate: _rate);
}

void main() {
  test('streamed bytes are byte-identical to the whole-buffer export', () {
    final t = _twoLanes();
    expect(_stream(t), _wholeWav(t));
  });

  test('output is independent of block size', () {
    final t = _twoLanes();
    final ref = _wholeWav(t);
    for (final block in [1, 333, 997, 4096, 1 << 15, 1 << 20]) {
      expect(_stream(t, blockSamples: block), ref, reason: 'block=$block');
    }
  });

  test('length matches the full render frame count', () {
    final t = _twoLanes();
    final mix = renderTimelineStereo(t, cache: {});
    expect(dawTimelineLengthSamples(t), mix.left.length);
  });

  test('an empty timeline is a valid 44-byte header with no data', () {
    final bytes = _stream(DawTimeline(tracks: const []));
    expect(bytes, hasLength(44));
    final bd = ByteData.sublistView(bytes);
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(bd.getUint16(22, Endian.little), 2, reason: 'stereo');
    expect(bd.getUint32(24, Endian.little), _rate);
    expect(bd.getUint16(34, Endian.little), 16, reason: '16-bit');
    expect(bd.getUint32(40, Endian.little), 0, reason: 'no data');
  });
}
