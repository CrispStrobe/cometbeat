// Instrument (de)serialization: every authored TrackerInstrument survives a
// JSON round-trip and renders identically afterwards (the safety net — a missed
// field would change the decoded render and fail here).

import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/envelope.dart';
import 'package:comet_beat/core/audio/crisp_dsp/fm.dart';
import 'package:comet_beat/core/audio/crisp_dsp/sfxr.dart';
import 'package:comet_beat/core/audio/crisp_dsp/subtractive.dart';
import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_instrument_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
  final cells = [
    const TrackerCell(midi: 60),
    ...List<TrackerCell>.filled(3, TrackerCell.empty),
  ];
  Float64List renderNote(TrackerInstrument i) => i.renderChannel(cells, timing);

  // Assert the decoded twin renders identically (byte-identical unless [tol],
  // for the Float32-PCM sample case).
  void expectRoundTrips(TrackerInstrument original, {double tol = 0}) {
    final decoded = instrumentFromJsonString(instrumentToJsonString(original));
    expect(decoded.runtimeType, original.runtimeType);
    expect(decoded.id, original.id);
    final a = renderNote(original), b = renderNote(decoded);
    expect(b.length, a.length);
    for (var i = 0; i < a.length; i++) {
      if (tol == 0) {
        expect(b[i], a[i], reason: 'sample $i');
      } else {
        expect(b[i], closeTo(a[i], tol), reason: 'sample $i');
      }
    }
  }

  group('instrument codec round-trip (render-identical)', () {
    test('additive', () {
      expectRoundTrips(const AdditiveInstrument('a', Instrument.cello));
    });

    test('sfxr (every param non-default)', () {
      // Distinct value per field so a dropped field changes the render.
      const params = SfxrParams(
        waveType: SfxrWave.sawtooth,
        noiseType: 1,
        attack: 0.02,
        sustain: 0.5,
        punch: 0.3,
        decay: 0.6,
        baseFreq: 0.4,
        freqRamp: 0.1,
        vibStrength: 0.2,
        vibSpeed: 0.3,
        arpMod: 0.15,
        arpSpeed: 0.25,
        duty: 0.35,
        dutyRamp: 0.05,
        repeatSpeed: 0.4,
        lpfFreq: 0.8,
        hpfFreq: 0.1,
        subBass: 0.2,
        distortion: 0.3,
        bitCrush: 0.25,
        soundVol: 0.45,
        fmDepth: 0.1,
        fmRatio: 1.5,
        lfoDepth: 0.2,
        lfoSpeed: 0.3,
      );
      expectRoundTrips(const SfxrInstrument('s', params, seed: 7));
    });

    test('karplus', () {
      expectRoundTrips(
        const KarplusInstrument('k', damping: 0.99, blend: 0.7, seed: 3),
      );
    });

    test('fm', () {
      expectRoundTrips(
        const FmInstrument(
          'f',
          FmPreset(ratio: 2.5, index: 3.1, indexDecay: 1.7, ampDecay: 1.2),
        ),
      );
    });

    test('subtractive', () {
      expectRoundTrips(
        const SubtractiveInstrument(
          'sub',
          SubPreset(
            wave: SubWave.square,
            cutoffStart: 0.7,
            cutoffEnd: 0.2,
            cutoffDecay: 2.2,
            ampDecay: 0.9,
          ),
        ),
      );
    });

    test('sample (base64 Float32 PCM, loop + envelope)', () {
      final pcm = Float64List(400);
      for (var i = 0; i < pcm.length; i++) {
        pcm[i] = (i % 40 < 20 ? 0.6 : -0.6); // a simple square-ish buzz
      }
      final inst = SampleInstrument(
        'smp',
        pcm,
        baseMidi: 55,
        loopStart: 40,
        loopLength: 120,
        offsetScale: 0.5,
        envelope: const Envelope(attack: 0.01, release: 0.02, sustain: 0.8),
        nativePitchEnvelope: const PitchEnvelope([
          (ms: 0, semitones: 12),
          (ms: 500, semitones: 0),
        ]),
      );
      // Float32 PCM → tiny precision loss; render is near-identical.
      expectRoundTrips(inst, tol: 1e-5);

      // Metadata survives exactly.
      final d = instrumentFromJsonString(instrumentToJsonString(inst))
          as SampleInstrument;
      expect(d.baseMidi, 55);
      expect(d.loopStart, 40);
      expect(d.loopLength, 120);
      expect(d.offsetScale, 0.5);
      expect(d.sample.length, pcm.length);
      expect(d.envelope.attack, closeTo(0.01, 1e-9));
      expect(d.envelope.sustain, closeTo(0.8, 1e-9));
      expect(d.nativePitchEnvelope, isNotNull);
      expect(d.nativePitchEnvelope!.points.last.semitones, 0);
    });

    test('percussion', () {
      expectRoundTrips(const PercussionInstrument('drum'));
    });

    test('native multi-sample zones preserve mapping and sample metadata', () {
      final left = Float64List(400)..fillRange(0, 400, 0.4);
      final right = Float64List(400)..fillRange(0, 400, -0.2);
      final inst = MultiSampleInstrument(
        'zones',
        {
          60: SampleInstrument(
            'low',
            left,
            sampleRight: right,
            volume: 0.75,
            normalize: false,
            nativeNna: 1,
          ),
          72: SampleInstrument('high', right),
        },
        polyphonic: true,
        nativeVoiceSemantics: true,
      );
      final decoded = instrumentFromJsonString(instrumentToJsonString(inst))
          as MultiSampleInstrument;
      expect(decoded.polyphonic, isTrue);
      expect(decoded.nativeVoiceSemantics, isTrue);
      final low = decoded.zones[60] as SampleInstrument;
      expect(low.sampleRight, isNotNull);
      expect(low.volume, closeTo(0.75, 1e-9));
      expect(low.normalize, isFalse);
      expect(low.nativeNna, 1);
      expectRoundTrips(inst, tol: 1e-5);
    });
  });

  group('instrument codec errors + guards', () {
    test('unknown type throws a clear error', () {
      expect(
        () => instrumentFromJson({'type': 'nope', 'id': 'x'}),
        throwsA(isA<InstrumentCodecException>()),
      );
    });

    test('isSerializableInstrument is true for authored voices', () {
      const additive = AdditiveInstrument('a', Instrument.flute);
      expect(isSerializableInstrument(additive), isTrue);
      expect(
        isSerializableInstrument(SampleInstrument('s', Float64List(8))),
        isTrue,
      );
    });

    test('serializing an unsupported type throws (not silent)', () {
      // A minimal fake instrument type outside the supported set.
      expect(
        () => instrumentToJson(_UnsupportedInstrument()),
        throwsA(isA<InstrumentCodecException>()),
      );
    });
  });
}

class _UnsupportedInstrument implements TrackerInstrument {
  @override
  String get id => 'x';
  @override
  Float64List renderChannel(List<TrackerCell> cells, TrackerTiming timing) =>
      Float64List(timing.totalSamples);
}
