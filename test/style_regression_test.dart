import 'package:comet_beat/core/audio/wav_io.dart';
import 'package:comet_beat/core/harmony/band_playback.dart';
import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:comet_beat/core/harmony/style_library.dart';
import 'package:flutter_test/flutter_test.dart';

/// BB-Q2 — style regression fingerprints.
///
/// Enforces two of the arc's four standing rules:
///   · **Rule 3, deterministic from a seed.** `(chart, style, seed)` is a pure
///     function. A shared chart must sound the same on two devices, and an
///     acceptance test cannot assert on a coin flip.
///   · **Rule 1, the byte-identical guard.** Editing one style must not change
///     another's output. Styles share `mixStems`, the humaniser and the bass
///     and drum generators, so cross-contamination is a live hazard rather
///     than a theoretical one.
///
/// ⚠️ **Why the fingerprints carry a TOLERANCE rather than being exact.** The
/// render is pure Dart, but it goes through `sin`/`tanh`, which are libm calls
/// that may differ by an ulp between macOS and the Linux CI runner. An exact
/// pin would be a red main on a platform difference — a test that cries wolf
/// gets deleted. The tolerance is 1e-4 while the styles differ from each other
/// by ~3e-3, so it is 30x smaller than the signal it has to detect.

/// One fixed chart for every style, so a difference is the STYLE and nothing
/// else.
Chart _chart() =>
    parseChartText('key: C\ntempo: 120\n| C | Am | Dm7 | G7 |').chart;

const _seed = 7;

/// What a rendered style measures out at. Length is exact (it is integer
/// arithmetic); loudness carries the tolerance explained above.
typedef Print = ({int totalMs, int bars, double rms});

const _pinned = <String, Print>{
  'straight': (totalMs: 12000, bars: 6, rms: 0.037779),
  'swing': (totalMs: 12000, bars: 6, rms: 0.035045),
  'ballad': (totalMs: 12000, bars: 6, rms: 0.037415),
  'bossa': (totalMs: 12000, bars: 6, rms: 0.032778),
  'waltz': (totalMs: 12000, bars: 6, rms: 0.035170),
  'rock': (totalMs: 12000, bars: 6, rms: 0.036618),
};

/// The tolerance on [Print.rms]. See the header for why it is not zero.
const _rmsTolerance = 1e-4;

Print _fingerprint(BandPerformance performance) {
  final mono = wavToMonoFloat(readWavPcm16(performance.wav));
  var sum = 0.0;
  for (final sample in mono) {
    sum += sample * sample;
  }
  return (
    totalMs: performance.totalMs,
    bars: performance.bars.length,
    rms: mono.isEmpty ? 0.0 : sum / mono.length,
  );
}

bool _identical(BandPerformance a, BandPerformance b) {
  if (a.wav.length != b.wav.length) return false;
  for (var i = 0; i < a.wav.length; i++) {
    if (a.wav[i] != b.wav[i]) return false;
  }
  return true;
}

void main() {
  group('rule 3 — deterministic from a seed', () {
    test('the same chart, style and seed render BYTE-IDENTICALLY', () {
      // Not "similar". A shared chart has to sound the same on two devices,
      // and every acceptance test above this one assumes it.
      for (final style in kStyles) {
        final once = renderBand(_chart(), style: style, seed: _seed)!;
        final twice = renderBand(_chart(), style: style, seed: _seed)!;
        expect(
          _identical(once, twice),
          isTrue,
          reason: '${style.id} is not deterministic',
        );
      }
    });

    test('a different seed really does change the performance', () {
      // The other half: a seed that changes nothing would make the determinism
      // test above pass for the wrong reason.
      for (final style in kStyles) {
        final a = renderBand(_chart(), style: style, seed: 7)!;
        final b = renderBand(_chart(), style: style, seed: 8)!;
        expect(
          _identical(a, b),
          isFalse,
          reason: '${style.id} ignores its seed',
        );
      }
    });

    test('the seed drives more than humanising — fills too', () {
      // ⚠️ I expected `humanize: false` to make the seed irrelevant. It does
      // not, and that is CORRECT: `drum_generator._shapeIndex(seed, barIndex)`
      // picks the fill shape, which is a generative choice in its own right.
      //
      // It matters for anyone building a byte-identical baseline (rule 1): a
      // fixed seed is required, and turning humanising off is NOT sufficient.
      for (final style in kStyles) {
        final a = renderBand(_chart(), style: style, seed: 7, humanize: false)!;
        final b =
            renderBand(_chart(), style: style, seed: 99, humanize: false)!;
        expect(
          _identical(a, b),
          isFalse,
          reason: '${style.id}: the seed should still pick fills',
        );
      }
    });

    test('humanising off is still deterministic for a GIVEN seed', () {
      // Which is the property a baseline actually needs.
      for (final style in kStyles) {
        final a = renderBand(_chart(), style: style, seed: 7, humanize: false)!;
        final b = renderBand(_chart(), style: style, seed: 7, humanize: false)!;
        expect(
          _identical(a, b),
          isTrue,
          reason: '${style.id} is not deterministic with humanising off',
        );
      }
    });
  });

  group('rule 1 — one style cannot quietly change another', () {
    for (final entry in _pinned.entries) {
      test('${entry.key} still renders as it did', () {
        final performance = renderBand(
          _chart(),
          style: styleFor(entry.key),
          seed: _seed,
        );
        expect(performance, isNotNull, reason: '${entry.key} did not render');
        final actual = _fingerprint(performance!);

        expect(actual.totalMs, entry.value.totalMs, reason: 'length changed');
        expect(actual.bars, entry.value.bars, reason: 'bar count changed');
        expect(
          actual.rms,
          closeTo(entry.value.rms, _rmsTolerance),
          reason: 'the sound of ${entry.key} changed. If that was DELIBERATE, '
              'update its pin to ${actual.rms.toStringAsFixed(6)}. If you were '
              'editing a different style, this is the bug this test exists for.',
        );
      });
    }

    test('every shipped style is pinned', () {
      // Otherwise a new style silently escapes the guard — the failure mode
      // where a regression test slowly stops covering the thing it names.
      expect(
        kStyles.map((s) => s.id).toSet(),
        _pinned.keys.toSet(),
        reason: 'a style was added or renamed without a fingerprint',
      );
    });
  });

  group('the styles are actually different from each other', () {
    test('no two render the same audio', () {
      // A copy-paste in `style_library` would otherwise ship two names for one
      // groove, and every test above would still pass.
      final rendered = {
        for (final style in kStyles)
          style.id: renderBand(_chart(), style: style, seed: _seed)!,
      };
      final ids = rendered.keys.toList();
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          expect(
            _identical(rendered[ids[i]]!, rendered[ids[j]]!),
            isFalse,
            reason: '${ids[i]} and ${ids[j]} render identically',
          );
        }
      }
    });
  });
}
