// WS-X3 — an effect chain that belongs to a score PART.
//
// Two properties carry the feature, and neither is about the UI:
//
//   1. The chain SURVIVES the Workshop's own save path. Score's save is
//      MusicXML text, so a chain that does not round-trip through MusicXML is
//      a setting that disappears the first time you close the screen — which
//      is worse than not offering it.
//   2. It CHANGES THE SOUND. A rack that persists beautifully and does nothing
//      when you press play is a control in name only, and that is the failure
//      this ladder has hit repeatedly (a field existing is not a feature).
//
// So these tests go through the real writer/reader and the real renderer.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/fx/fx_chain_codec.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:comet_beat/core/audio/score_fx.dart';
import 'package:comet_beat/core/audio/score_instrument_render.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show PulseInstrument, TrackerInstrument;
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter_test/flutter_test.dart';

Score _part({ScoreMetadata metadata = const ScoreMetadata()}) => Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q e4 g4 c5',
      metadata: metadata,
    );

TrackerInstrument _voice() => const PulseInstrument('square');

double _rms(Float64List pcm) {
  if (pcm.isEmpty) return 0;
  var sum = 0.0;
  for (final s in pcm) {
    sum += s * s;
  }
  return sum / pcm.length;
}

void main() {
  const chain = 'lowpass freq=400 | gain gainDb=-6';

  group('storing a chain on a part', () {
    test('it round-trips through the model', () {
      final specs = parsedChain(chain);
      final meta = withScoreFxChain(const ScoreMetadata(title: 'Air'), specs);
      expect(scoreFxChainString(meta), isNotNull);
      expect(
        scoreFxChain(meta).map((f) => f.type),
        specs.map((f) => f.type),
      );
      expect(meta.title, 'Air', reason: 'the rest of the metadata is intact');
    });

    test('an EMPTY chain removes the key rather than storing ""', () {
      // Otherwise a score someone merely glanced at carries a miscellaneous
      // block forever, and every export differs from one that never had a rack.
      final tagged =
          withScoreFxChain(const ScoreMetadata(), parsedChain(chain));
      final cleared = withScoreFxChain(tagged, const []);
      expect(cleared.extras, isEmpty);
      expect(cleared.isEmpty, isTrue, reason: 'back to no header at all');
    });

    test('a part with no chain reads back empty, not null-ish', () {
      expect(scoreFxChain(const ScoreMetadata()), isEmpty);
      expect(scoreFxChainString(const ScoreMetadata()), isNull);
    });

    test('garbage in the field does not throw mid-render', () {
      // The value is text. It may come from an older build, a hand-edited XML
      // file, or another program that used the same key — and a render is the
      // worst possible place to discover that.
      const meta = ScoreMetadata(extras: {kScoreFxKey: 'not-an-effect ???'});
      expect(() => scoreFxChain(meta), returnsNormally);
      expect(
        () => applyScoreFx(Float64List(64), meta),
        returnsNormally,
      );
    });

    test('automation is reported as lossy rather than dropped silently', () {
      // The Workshop's rack cannot make automation, but a chain pasted from the
      // Audio Editor can, and the string form has no syntax for it.
      final automated = [
        const FxSpec(
          type: FxType.gain,
          params: {'db': -6},
          automation: {
            'db': [
              FxAutomationPoint(ms: 0, value: -12),
              FxAutomationPoint(ms: 1000, value: 0),
            ],
          },
        ),
      ];
      expect(scoreFxIsLossless(automated), isFalse);
      expect(scoreFxIsLossless(parsedChain(chain)), isTrue);
    });
  });

  group('it survives the Workshop save path, which is MusicXML', () {
    test('single part', () {
      final source = _part(
        metadata: withScoreFxChain(
          const ScoreMetadata(title: 'Air'),
          parsedChain(chain),
        ),
      );
      final back = scoreFromMusicXml(scoreToMusicXml(source));
      expect(
        scoreFxChainString(back.metadata),
        scoreFxChainString(source.metadata),
      );
      expect(scoreFxChain(back.metadata).map((f) => f.type), [
        FxType.lowpass,
        FxType.gain,
      ]);
    });

    test('MULTI part — and each part keeps its OWN', () {
      // The case the Workshop actually takes for a two-instrument score, and
      // the one that would have failed had the chain been written
      // document-level: a bass line playing the lead's effects.
      final source = MultiPartScore([
        _part(
          metadata: withScoreFxChain(
            const ScoreMetadata(instrument: 'Lead'),
            parsedChain('lowpass freq=400'),
          ),
        ),
        _part(
          metadata: withScoreFxChain(
            const ScoreMetadata(instrument: 'Bass'),
            parsedChain('gain gainDb=-6'),
          ),
        ),
      ]);
      final back = multiPartScoreFromMusicXml(multiPartToMusicXml(source));
      expect(scoreFxChain(back.parts[0].metadata).single.type, FxType.lowpass);
      expect(scoreFxChain(back.parts[1].metadata).single.type, FxType.gain);
    });

    test('a part with no chain gains nothing on the way through', () {
      final back = scoreFromMusicXml(scoreToMusicXml(_part()));
      expect(scoreFxChain(back.metadata), isEmpty);
    });
  });

  group('it changes the SOUND', () {
    test('a gain stage makes the part quieter', () {
      // Chosen because it is the one effect whose direction is not arguable.
      final dry = renderScoreWithScoreFx(_part(), _voice());
      final wet = renderScoreWithScoreFx(
        _part(
          metadata: withScoreFxChain(
            const ScoreMetadata(),
            parsedChain('gain gainDb=-12'),
          ),
        ),
        _voice(),
      );
      expect(_rms(wet), lessThan(_rms(dry) * 0.5));
      expect(_rms(wet), greaterThan(0), reason: 'quieter, not silent');
    });

    test('a part with no chain renders EXACTLY as it did before', () {
      // The upgrade guarantee: every score that predates this feature must
      // sound identical, sample for sample.
      final plain = renderScoreWithInstrument(_part(), _voice());
      final through = renderScoreWithScoreFx(_part(), _voice());
      expect(through.length, plain.length);
      for (var i = 0; i < plain.length; i++) {
        if (through[i] != plain[i]) {
          fail('sample $i differs: ${through[i]} vs ${plain[i]}');
        }
      }
    });

    test('in a multi-part mix, only the part with the chain changes', () {
      // What "per part" has to mean audibly. Silencing ONE part must leave the
      // other one's contribution untouched.
      final lead = _part(metadata: const ScoreMetadata(instrument: 'Lead'));
      final bass = _part(metadata: const ScoreMetadata(instrument: 'Bass'));
      final dry = renderMultiPartWithScoreFx(
        MultiPartScore([lead, bass]),
        _voice(),
      );
      final oneMuted = renderMultiPartWithScoreFx(
        MultiPartScore([
          _part(
            metadata: withScoreFxChain(
              const ScoreMetadata(instrument: 'Lead'),
              parsedChain('gain gainDb=-60'),
            ),
          ),
          bass,
        ]),
        _voice(),
      );
      final soloBass = renderScoreWithInstrument(bass, _voice());

      expect(_rms(oneMuted), lessThan(_rms(dry)));
      // What is left is (near enough) the bass alone.
      expect(_rms(oneMuted), closeTo(_rms(soloBass), _rms(soloBass) * 0.05));
    });

    test("⚠️ a reverb/delay TAIL is cut at the part's end", () {
      // Measured, not assumed: I wrote this expecting the opposite. Every
      // effect in `applyFxChain` returns a buffer the same length as its input,
      // so a tail has nowhere to ring into — the score's own length is the end.
      // App-wide behaviour (the Tracker, Tab and Loop racks share this engine),
      // not something the Score rack introduces, and stated here so the next
      // person does not have to discover it by ear.
      final tailed = renderScoreWithScoreFx(
        _part(
          metadata: withScoreFxChain(
            const ScoreMetadata(),
            parsedChain('delay delayMs=500 feedback=0.6 mix=60%'),
          ),
        ),
        _voice(),
      );
      final dry = renderScoreWithInstrument(_part(), _voice());
      expect(tailed.length, dry.length);
    });

    test('parts of DIFFERENT lengths still sum without truncation', () {
      // The mix is as long as the longest part; the shorter one just stops.
      final long = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q e4 g4 c5 c4 e4 g4 c5',
      );
      final mix = renderMultiPartWithScoreFx(
        MultiPartScore([_part(), long]),
        _voice(),
      );
      expect(
        mix.length,
        renderScoreWithInstrument(long, _voice()).length,
      );
    });
  });
}

/// The chain a string describes, failing the test if it does not parse — these
/// are fixtures, so a typo in one should not read as an empty rack.
List<FxSpec> parsedChain(String source) {
  final parsed = parseFxChain(source);
  expect(parsed.errors, isEmpty, reason: 'fixture chain "$source"');
  expect(parsed.chain, isNotEmpty);
  return parsed.chain;
}
