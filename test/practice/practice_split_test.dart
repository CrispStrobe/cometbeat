import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/crisp_dsp/time_stretch.dart';
import 'package:comet_beat/core/audio/practice/practice_mix.dart';
import 'package:comet_beat/core/audio/practice/practice_split.dart';
import 'package:comet_beat/core/audio/transcription/separated_stem.dart';
import 'package:flutter_test/flutter_test.dart';

Float32List _noise(int n, int seed) {
  final r = math.Random(seed);
  final x = Float32List(n);
  for (var i = 0; i < n; i++) {
    x[i] = r.nextDouble() - .5;
  }
  return x;
}

/// A fake two-stem separator: `low` = 0.3 × input, `high` = 0.7 × input —
/// linear and memoryless, so windowing must reproduce it exactly.
List<RawStem> _split(Float32List inter) => [
      (
        name: 'low',
        pcm: Float32List.fromList([for (final x in inter) .3 * x]),
      ),
      (
        name: 'high',
        pcm: Float32List.fromList([for (final x in inter) .7 * x]),
      ),
    ];

void main() {
  group('separationWindows', () {
    for (final frames in [1, 99, 100, 101, 250, 1000, 1234, 9999]) {
      test('weights sum to 1 everywhere, $frames frames', () {
        final ws = separationWindows(frames, window: 100, margin: 5, fade: 10);
        expect(ws.first.start, 0);
        expect(ws.last.end, frames);
        for (final w in ws) {
          expect(w.length, lessThanOrEqualTo(100));
        }
        for (var t = 0; t < frames; t++) {
          var sum = 0.0;
          for (final w in ws) {
            if (t >= w.start && t < w.end) sum += w.weight(t);
          }
          expect(sum, closeTo(1, 1e-12), reason: 'frame $t of $ws');
        }
      });
    }

    test('a song that fits is one window, no fades', () {
      final ws = separationWindows(100, window: 100, margin: 5, fade: 10);
      expect(ws, hasLength(1));
      expect(ws.single.weight(0), 1);
      expect(ws.single.weight(99), 1);
    });

    test('windows are spaced evenly: no sliver at the end', () {
      final ws = separationWindows(1010, window: 100, margin: 5, fade: 10);
      final lengths = ws.map((w) => w.length).toList();
      expect(lengths.reduce(math.max) - lengths.reduce(math.min), lessThan(3));
    });

    test('the discarded margins are outside every weight', () {
      final ws = separationWindows(1000, window: 100, margin: 5, fade: 10);
      final w = ws[1];
      for (var t = w.start; t < w.start + 5; t++) {
        expect(w.weight(t), 0);
      }
      for (var t = w.end - 5; t < w.end; t++) {
        expect(w.weight(t), 0);
      }
    });
  });

  group('separateInWindows', () {
    test('a linear separator comes back exactly, seams and all', () {
      const n = 5000;
      final l = _noise(n, 1), r = _noise(n, 2);
      var calls = 0;
      final stems = separateInWindows(
        l,
        r,
        44100,
        (inter) {
          calls++;
          expect(inter.length, lessThanOrEqualTo(2 * 600));
          return _split(inter);
        },
        windowFrames: 600,
        marginFrames: 20,
        fadeFrames: 40,
      );
      expect(calls, greaterThan(8));
      expect(stems.map((s) => s.name), ['low', 'high']);
      for (final (i, k) in [(0, .3), (1, .7)]) {
        final s = stems[i];
        expect(s.frames, n);
        expect(s.sampleRate, 44100);
        for (var t = 0; t < n; t++) {
          expect(s.left[t], closeTo(k * l[t], 1e-6));
          expect(s.right[t], closeTo(k * r[t], 1e-6));
        }
      }
    });

    for (final grid in [null, const SeparatorGrid(segment: 780, stride: 585)]) {
      test('the sink gets every frame once, in order (grid: ${grid != null})',
          () {
        const n = 9001;
        final l = _noise(n, 21), r = _noise(n, 22);
        var next = 0;
        final names = separateInWindowsTo(
          l,
          r,
          44100,
          _split,
          (start, names, bl, br) {
            expect(start, next);
            expect(names, ['low', 'high']);
            expect(bl.first.length, br.last.length);
            for (var i = 0; i < bl.first.length; i++) {
              expect(bl[0][i], closeTo(.3 * l[start + i], 1e-6));
              expect(br[1][i], closeTo(.7 * r[start + i], 1e-6));
            }
            next = start + bl.first.length;
          },
          grid: grid,
          windowFrames: 2000,
          marginFrames: 50,
          fadeFrames: 80,
        );
        expect(next, n);
        expect(names, ['low', 'high']);
      });
    }

    test('a short song is one call on the whole song', () {
      final l = _noise(300, 3);
      var calls = 0;
      final stems = separateInWindows(l, l, 44100, (inter) {
        calls++;
        return _split(inter);
      });
      expect(calls, 1);
      expect(stems.first.left[123], closeTo(.3 * l[123], 1e-7));
    });
  });

  group('grid-aligned windows reproduce a segmenting separator', () {
    // A stand-in model whose output for a sample depends on its WHOLE chunk
    // (like an attention model): stem s = x · (0.1·(s+1) + mean x² of chunk).
    List<Float32List> chunkModel(Float32List inter, int frames) {
      var e = 0.0;
      for (var i = 0; i < frames * 2; i++) {
        e += inter[i] * inter[i];
      }
      e /= frames * 2;
      return [
        for (var s = 0; s < 4; s++)
          Float32List.fromList([
            for (var i = 0; i < frames * 2; i++) inter[i] * (.1 * (s + 1) + e),
          ]),
      ];
    }

    List<RawStem> wrap(List<Float64List> acc) => [
          for (var s = 0; s < 4; s++)
            (name: 's$s', pcm: Float32List.fromList(acc[s])),
        ];

    // mini_bs_roformer_separate's loop: chunks every `hop` from 0, linear
    // fades of chunk/10, normalised by the summed weight; zero-padded tail.
    StemSeparator miniBs(int chunk, int hop) => (inter) {
          final n = inter.length ~/ 2, fade = chunk ~/ 10;
          final chunks = ((math.max(n - chunk, 0) + hop - 1) ~/ hop) + 1;
          final w = Float64List(chunk)..fillRange(0, chunk, 1);
          for (var t = 0; t < fade; t++) {
            w[t] = t / (fade - 1);
            w[chunk - fade + t] = 1 - t / (fade - 1);
          }
          final acc = [for (var s = 0; s < 4; s++) Float64List(n * 2)];
          final counts = Float64List(n);
          for (var i = 0; i < chunks; i++) {
            final start = i * hop, count = math.min(chunk, n - start);
            final block = Float32List(chunk * 2)
              ..setRange(0, count * 2, inter, start * 2);
            final r = chunkModel(block, chunk);
            for (var t = 0; t < count; t++) {
              counts[start + t] += w[t];
              for (var s = 0; s < 4; s++) {
                for (var c = 0; c < 2; c++) {
                  acc[s][(start + t) * 2 + c] += r[s][t * 2 + c] * w[t];
                }
              }
            }
          }
          for (var t = 0; t < n; t++) {
            for (var s = 0; s < 4; s++) {
              for (var c = 0; c < 2; c++) {
                acc[s][t * 2 + c] /= math.max(counts[t], 1e-8);
              }
            }
          }
          return wrap(acc);
        };

    // htdemucs_separate's loop (mel-band-roformer's is the same): whole
    // buffer when it fits one segment, else a chunk at every stride below n,
    // triangle weights, zero-padded tail.
    StemSeparator demucs(int seg, int stride) => (inter) {
          final n = inter.length ~/ 2;
          if (n <= seg) {
            return wrap([
              for (final x in chunkModel(inter, n)) Float64List.fromList(x),
            ]);
          }
          final half = seg ~/ 2;
          final w = Float64List(seg);
          for (var i = 0; i < seg; i++) {
            w[i] = (i < half ? i + 1 : seg - i).toDouble();
          }
          final wmax = w.reduce(math.max);
          for (var i = 0; i < seg; i++) {
            w[i] /= wmax;
          }
          final acc = [for (var s = 0; s < 4; s++) Float64List(n * 2)];
          final sum = Float64List(n);
          for (var off = 0; off < n; off += stride) {
            final valid = math.min(seg, n - off);
            final block = Float32List(seg * 2)
              ..setRange(0, valid * 2, inter, off * 2);
            final r = chunkModel(block, seg);
            for (var i = 0; i < valid; i++) {
              sum[off + i] += w[i];
              for (var s = 0; s < 4; s++) {
                for (var c = 0; c < 2; c++) {
                  acc[s][(off + i) * 2 + c] += w[i] * r[s][i * 2 + c];
                }
              }
            }
          }
          for (var t = 0; t < n; t++) {
            for (var s = 0; s < 4; s++) {
              for (var c = 0; c < 2; c++) {
                acc[s][t * 2 + c] /= sum[t];
              }
            }
          }
          return wrap(acc);
        };

    double maxDiff(List<SeparatedStem> a, List<SeparatedStem> b) {
      var d = 0.0;
      for (var s = 0; s < a.length; s++) {
        for (var t = 0; t < a[s].frames; t++) {
          d = math.max(d, (a[s].left[t] - b[s].left[t]).abs());
          d = math.max(d, (a[s].right[t] - b[s].right[t]).abs());
        }
      }
      return d;
    }

    for (final (name, sep, grid) in [
      (
        'mini-bs-roformer',
        miniBs(800, 400),
        const SeparatorGrid(segment: 800, stride: 400),
      ),
      (
        'htdemucs',
        demucs(780, 585),
        const SeparatorGrid(segment: 780, stride: 585),
      ),
    ]) {
      for (final n in [700, 5000, 10007]) {
        test('$name, $n frames', () {
          // Loud and quiet passages, so every chunk's gain differs.
          final l = _noise(n, 11), r = _noise(n, 12);
          for (var t = 0; t < n; t++) {
            final g = 1 + math.sin(t / 300);
            l[t] *= g;
            r[t] *= g;
          }
          final whole =
              separateInWindows(l, r, 44100, sep, windowFrames: n + 1);
          final aligned = separateInWindows(
            l,
            r,
            44100,
            sep,
            grid: grid,
            windowFrames: 3000,
          );
          expect(maxDiff(whole, aligned), lessThan(1e-6));
          if (n > 3000) {
            // The same windows OFF the grid do not: the model is chunk-
            // sensitive, which is why alignment matters.
            final loose = separateInWindows(
              l,
              r,
              44100,
              sep,
              windowFrames: 3000,
              marginFrames: 100,
              fadeFrames: 100,
            );
            expect(maxDiff(whole, loose), greaterThan(1e-3));
          }
        });
      }
    }

    test('aligned windows: on the grid, a segment of overlap, weights sum to 1',
        () {
      const grid = SeparatorGrid(segment: 780, stride: 585);
      final ws = alignedSeparationWindows(20000, grid, window: 3000);
      expect(ws.last.end, 20000);
      for (final w in ws) {
        expect(w.start % grid.stride, 0);
        if (w != ws.last) expect(w.length, 780 + 4 * 585);
        if (w != ws.last) expect(w.length, greaterThan(grid.segment));
      }
      expect(ws.last.length, greaterThan(grid.segment));
      for (var t = 0; t < 20000; t++) {
        var sum = 0.0;
        for (final w in ws) {
          if (t >= w.start && t < w.end) sum += w.weight(t);
        }
        expect(sum, closeTo(1, 1e-12), reason: 'frame $t');
      }
    });
  });

  test('mixtureConsistentInPlace == mixtureConsistent, and sums to the mix',
      () {
    const n = 2000;
    final mixL = _noise(n, 4), mixR = _noise(n, 5);
    List<SeparatedStem> stems() => [
          for (var k = 0; k < 4; k++)
            SeparatedStem('s$k', _noise(n, 10 + k), _noise(n, 20 + k), 44100),
        ];
    final copied = mixtureConsistent(stems(), mixL, mixR);
    final inPlace = stems();
    mixtureConsistentInPlace(inPlace, mixL, mixR);
    for (var t = 0; t < n; t++) {
      var sum = 0.0;
      for (var k = 0; k < 4; k++) {
        expect(inPlace[k].left[t], closeTo(copied[k].left[t], 1e-6));
        expect(inPlace[k].right[t], closeTo(copied[k].right[t], 1e-6));
        sum += inPlace[k].left[t];
      }
      expect(sum, closeTo(mixL[t], 1e-5));
    }
  });

  test('resampleLinear32 matches resampleLinear', () {
    final x = _noise(4801, 6);
    for (final (from, to) in [(48000, 44100), (22050, 44100), (44100, 22050)]) {
      final want = resampleLinear(Float64List.fromList(x), from / to);
      final got = resampleLinear32(x, from, to);
      expect(got.length, want.length);
      for (var i = 0; i < got.length; i++) {
        expect(got[i], closeTo(want[i], 1e-6));
      }
    }
    expect(identical(resampleLinear32(x, 44100, 44100), x), isTrue);
  });

  test('monoAtRate = (l + r) / 2, then resampled', () {
    final l = _noise(4410, 7), r = _noise(4410, 8);
    final mono = Float64List.fromList([
      for (var i = 0; i < l.length; i++) (l[i] + r[i]) / 2,
    ]);
    final want = resampleLinear(mono, 44100 / 22050);
    final got = monoAtRate(l, r, 44100, 22050);
    expect(got.length, want.length);
    for (var i = 0; i < got.length; i++) {
      expect(got[i], closeTo(want[i], 1e-6));
    }
  });

  group('StemRegion', () {
    // Two stems with low and high content, so the stretch has work to do.
    List<SeparatedStem> stems() {
      const n = 22050;
      SeparatedStem tone(String name, double hz, int seed) {
        final noise = _noise(n, seed);
        final l = Float32List(n), r = Float32List(n);
        for (var i = 0; i < n; i++) {
          final x = math.sin(2 * math.pi * hz * i / 44100);
          l[i] = .5 * x + .05 * noise[i];
          r[i] = .4 * x - .05 * noise[i];
        }
        return SeparatedStem(name, l, r, 44100);
      }

      return [tone('bass', 82, 1), tone('vocals', 440, 2)];
    }

    /// The whole of [src], read in uneven windows the way the player feeds.
    List<Float32List> drain(StemSource src) {
      final out = [
        for (var k = 0; k < src.count; k++) Float32List(src.frames * 2),
      ];
      var at = 0, step = 1000;
      while (at < src.frames) {
        for (var k = 0; k < src.count; k++) {
          final w = src.window(k, at, step);
          out[k].setAll(2 * at, w);
        }
        at += step;
        step = step == 1000 ? 777 : 1000;
      }
      return out;
    }

    void expectSame(List<Float32List> got, List<SeparatedStem> want) {
      for (var k = 0; k < want.length; k++) {
        expect(got[k].length, want[k].frames * 2, reason: 'stem $k length');
        for (var i = 0; i < want[k].frames; i++) {
          expect(got[k][2 * i], closeTo(want[k].left[i], 1e-5));
          expect(got[k][2 * i + 1], closeTo(want[k].right[i], 1e-5));
        }
      }
    }

    test('unslowed: windows == loopRegion', () {
      final s = stems();
      expectSame(
        drain(StemRegion(s, start: 3000, end: 15000, fadeFrames: 220)),
        loopRegion(s, 3000, 15000),
      );
      expectSame(drain(StemRegion(s)), s);
    });

    for (final speed in [.85, .5]) {
      test('slowed to $speed: windows == slowStems(loopRegion)', () {
        final s = stems();
        final want = slowStems(loopRegion(s, 3000, 15000), speed);
        final region = StemRegion(s, start: 3000, end: 15000, fadeFrames: 220);
        // The guide exactly as timeStretchLinked builds it.
        final faded = loopRegion(s, 3000, 15000);
        final guide = Float64List(region.regionFrames);
        for (final st in faded) {
          for (var i = 0; i < guide.length; i++) {
            guide[i] += st.left[i] + st.right[i];
          }
        }
        final plan = planStretch(
          guide,
          1 / speed,
          quality: StretchQuality.deep,
        );
        final slowed = StemRegion(
          s,
          start: 3000,
          end: 15000,
          fadeFrames: 220,
          plan: plan,
        );
        expect(slowed.frames, want.first.frames);
        expectSame(drain(slowed), want);
      });
    }

    test('stretchGuide is the faded channel sum', () async {
      final s = stems();
      final region = StemRegion(s, start: 100, end: 9000, fadeFrames: 220);
      final g = await region.stretchGuide();
      final faded = loopRegion(s, 100, 9000);
      for (var i = 0; i < g.length; i++) {
        var sum = 0.0;
        for (final st in faded) {
          sum += st.left[i] + st.right[i];
        }
        expect(g[i], closeTo(sum, 1e-5));
      }
    });
  });
}
