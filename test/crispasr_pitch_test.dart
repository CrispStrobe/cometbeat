// The CrispASR-CLI CREPE F0 provider. We can't run the `crispasr` binary
// headlessly, so we test the two pure/deterministic parts: parsing its
// `--pitch` text output into a PitchTrack, and the env-gating (no binary/model
// configured ⇒ null estimator, so the router falls back).

import 'package:comet_beat/core/audio/transcription/crispasr_pitch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parsePitchFrames reads tab-separated "time_ms f0_hz voiced_prob"', () {
    // Exactly what `crispasr --pitch --pitch-format text` prints, incl. an
    // unvoiced frame (f0 0) and a blank line to skip.
    const out = '0.0\t0.000\t0.0100\n'
        '10.0\t440.000\t0.9500\n'
        '20.0\t880.000\t0.8800\n'
        '\n';
    final track = parsePitchFrames(out);
    expect(track, hasLength(3));
    expect(track[1].timeMs, 10.0);
    expect(track[1].f0Hz, closeTo(440.0, 1e-6));
    expect(track[1].voicedProb, closeTo(0.95, 1e-6));
  });

  test('parsePitchFrames skips headers / malformed lines', () {
    const out = '# time_ms f0_hz voiced_prob\n'
        'garbage line\n'
        '5.0\t220.0\t0.7\n';
    final track = parsePitchFrames(out);
    expect(track, hasLength(1));
    expect(track.single.f0Hz, closeTo(220.0, 1e-6));
  });

  test('no binary/model configured ⇒ null estimator (falls back)', () {
    // Bogus paths that don't exist ⇒ unavailable.
    expect(
      crispasrCliCrepeF0(binary: '/no/such/crispasr', model: '/no/such.gguf'),
      isNull,
    );
    // And with nothing passed (env unset on CI) it's also null.
    expect(crispasrCrepeAvailable(), isFalse);
  });
}
