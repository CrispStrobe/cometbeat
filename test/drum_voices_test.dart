// The percussion palette: every Drum voice (the 3 classics + the extended kit
// voices) renders a non-silent, unit-peak one-shot, and the new voices are
// distinct from each other and from the originals.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  double peak(Float64List b) =>
      b.fold(0.0, (m, v) => v.abs() > m ? v.abs() : m);

  group('drum voices', () {
    test('every Drum renders a non-silent, unit-peak hit', () {
      for (final d in Drum.values) {
        final buf = renderDrum(d);
        expect(buf, isNotEmpty, reason: '$d empty');
        expect(peak(buf), closeTo(1.0, 1e-9), reason: '$d not unit-peak');
        expect(buf.any((v) => v != 0), isTrue, reason: '$d silent');
      }
    });

    test('the kit has 12 voices (3 classic + 9 extended)', () {
      expect(Drum.values.length, 12);
      // The classic three keep their positions (index/order is stable — call
      // sites index by Drum.values[i], and share tokens store the ordinal).
      expect(Drum.values[0], Drum.kick);
      expect(Drum.values[1], Drum.snare);
      expect(Drum.values[2], Drum.hat);
      // The first-wave extended voices keep their indices too (appended, never
      // reordered): cowbell was index 7 before the cymbals/toms were added.
      expect(Drum.values[7], Drum.cowbell);
      // The new voices are present.
      for (final d in [
        Drum.openHat,
        Drum.clap,
        Drum.tom,
        Drum.rim,
        Drum.cowbell,
        Drum.crash,
        Drum.ride,
        Drum.lowTom,
        Drum.highTom,
      ]) {
        expect(Drum.values.contains(d), isTrue);
      }
    });

    test('the tom family reads low → mid → high (rising fundamental)', () {
      // A tom fill wants distinct pitches. Estimate each tom's fundamental from
      // its first-half zero-crossing rate (the glide starts near the top).
      double crossRate(Float64List b) {
        var c = 0;
        final half = b.length ~/ 2;
        for (var i = 1; i < half; i++) {
          if ((b[i - 1] < 0) != (b[i] < 0)) c++;
        }
        return c / (half / kSampleRate);
      }

      final low = crossRate(renderDrum(Drum.lowTom));
      final mid = crossRate(renderDrum(Drum.tom));
      final high = crossRate(renderDrum(Drum.highTom));
      expect(low, lessThan(mid), reason: 'lowTom below the mid tom');
      expect(mid, lessThan(high), reason: 'highTom above the mid tom');
    });

    test('the crash rings longer than any hat (a cymbal wash)', () {
      // The crash decays slowly — its buffer is the longest in the kit.
      final crash = renderDrum(Drum.crash).length;
      expect(crash, greaterThan(renderDrum(Drum.hat).length));
      expect(crash, greaterThan(renderDrum(Drum.openHat).length));
    });

    test('each new voice is distinct from the others (length or content)', () {
      final voices = {for (final d in Drum.values) d: renderDrum(d)};
      // Every pair differs — either a different duration or clearly different
      // samples over the shared span (no two voices are the same buffer).
      const list = Drum.values;
      for (var i = 0; i < list.length; i++) {
        for (var j = i + 1; j < list.length; j++) {
          final a = voices[list[i]]!, b = voices[list[j]]!;
          var same = a.length == b.length;
          if (same) {
            for (var k = 0; k < a.length; k++) {
              if ((a[k] - b[k]).abs() > 1e-6) {
                same = false;
                break;
              }
            }
          }
          expect(same, isFalse, reason: '${list[i]} == ${list[j]}');
        }
      }
    });

    test('open hat rings longer than the closed hat', () {
      // The defining difference: a much longer tail.
      expect(
        renderDrum(Drum.openHat).length,
        greaterThan(renderDrum(Drum.hat).length * 3),
      );
    });
  });
}
