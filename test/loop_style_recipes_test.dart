// Generative style catalog (loop_style_recipes.dart): every recipe × several
// seeds must render, stay bounded and aligned, be deterministic, and obey the
// guardrails that make ANY seed sound good — plus an acceptance pass where the
// app's own detectors read the roots/kicks the recipe implies, and share-token
// compatibility in both directions.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/beat_capture.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/loop_style_recipes.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/core/audio/wav_io.dart';
import 'package:flutter_test/flutter_test.dart';

const _seeds = [0, 1, 42, 9001, 123456789];

/// Whether generated [rows] are a legal realisation of [t]: `x`/`g` always
/// hit, `o` may, `.` never.
bool _fits(Map<Drum, List<bool>> rows, DrumTemplate t) {
  if (rows.keys.toSet().difference(t.rows.keys.toSet()).isNotEmpty) {
    return false;
  }
  for (final MapEntry(key: drum, value: tpl) in t.rows.entries) {
    final row = rows[drum];
    if (row == null || row.length != tpl.length) return false;
    for (var i = 0; i < tpl.length; i++) {
      final c = tpl[i];
      if ((c == 'x' || c == 'g') && !row[i]) return false;
      if (c == '.' && row[i]) return false;
    }
  }
  return true;
}

double _peak(Uint8List wav) {
  final d = readWavPcm16(wav);
  var p = 0;
  for (final s in d.samples) {
    if (s.abs() > p) p = s.abs();
  }
  return p / 32768.0;
}

void main() {
  group('catalog', () {
    test('at least 12 styles, unique ids, valid tempos/kits/progressions', () {
      expect(kStyleRecipes.length, greaterThanOrEqualTo(12));
      expect(
        kStyleRecipes.map((r) => r.id).toSet().length,
        kStyleRecipes.length,
      );
      final kits = kDrumKits.map((k) => k.id).toSet();
      final progs = kProgressions.map((p) => p.id).toSet();
      for (final r in kStyleRecipes) {
        for (final t in r.tempos) {
          expect(isGridTempo(t), isTrue, reason: '${r.id} tempo $t');
          expect(kValidLoopTempos, contains(t));
        }
        expect(r.kits.every(kits.contains), isTrue, reason: r.id);
        expect(r.progressions.every(progs.contains), isTrue, reason: r.id);
        for (final shape in [...r.bassBars, ...r.chordBars, ...r.sparkleBars]) {
          expect(() => parseChordBar(shape), returnsNormally);
        }
        for (final rh in r.melodyRhythms) {
          expect(rh.length, 8, reason: '${r.id} rhythm $rh');
          expect(rh.contains('n'), isTrue);
        }
        for (final t in r.drums) {
          for (final row in t.rows.values) {
            expect(row.length, kPatternSteps, reason: r.id);
          }
        }
      }
    });

    test('valid grid tempos are exactly the integral-ms-and-sample ones', () {
      final valid = [
        for (var b = kMinTempoBpm; b <= kMaxTempoBpm; b++)
          if (isGridTempo(b)) b,
      ];
      expect(valid, [40, 50, 60, 75, 100, 120, 125, 150, 200]);
      for (final b in valid) {
        final t = LoopTiming(tempoBpm: b);
        expect((t.stepMs * kSampleRate) % 1000, 0, reason: '$b');
        expect(t.stepMs * 2 * b, 60000, reason: '$b');
      }
    });
  });

  group('guardrails hold for every recipe × seed', () {
    for (final r in kStyleRecipes) {
      test(r.id, () {
        for (final seed in _seeds) {
          final tracks = generateRecipeTracks(r, seed);
          expect(tracks.map((t) => t.id).toList(), kRecipeTrackIds);
          for (final track in tracks) {
            expect(track.variants.length, 3);
            for (final v in track.variants) {
              if (v is MelodicPattern) {
                expect(
                  v.cells.fold<int>(0, (s, c) => s + c.steps),
                  kPatternSteps,
                );
              }
            }
          }

          // Drums: bounded by a template.
          for (final v in tracks[0].variants) {
            final rows = (v as DrumRowsPattern).rows;
            expect(
              r.drums.any((t) => _fits(rows, t)),
              isTrue,
              reason: '${r.id}/$seed drums escaped the template',
            );
          }

          // Bass: first sounding note is the root; beats 1 and 3 carry only
          // root / fifth / octave.
          for (final bar in tracks[1].chordFollower!.bars) {
            final onsets = chordBarOnsets(bar);
            final first = bar.cells.firstWhere((c) => c.tones != null);
            expect(first.tones, [0], reason: '${r.id}/$seed bass');
            for (var i = 0; i < bar.cells.length; i++) {
              final t = bar.cells[i].tones;
              if (t == null || onsets[i] % 4 != 0) continue;
              expect(
                t.every({0, 2, 3}.contains),
                isTrue,
                reason: '${r.id}/$seed bass strong beat $t',
              );
            }
          }

          // Melody: chord tones on every beat; neighbours only off-beat.
          for (final bar in tracks[3].chordFollower!.bars) {
            final onsets = chordBarOnsets(bar);
            for (var i = 0; i < bar.cells.length; i++) {
              final t = bar.cells[i].tones;
              if (t == null) continue;
              expect(t.every((x) => x >= 0 && x <= 3), isTrue);
              final shift = bar.scaleSteps?[i] ?? 0;
              if (onsets[i].isEven) {
                expect(shift, 0, reason: '${r.id}/$seed melody on a beat');
              }
            }
          }
        }
      });
    }
  });

  group('rendering', () {
    for (final r in kStyleRecipes) {
      test('${r.id}: renders, bounded, aligned, deterministic', () {
        for (final seed in _seeds.take(2)) {
          LoopEngine make() => LoopEngine()
            ..setRecipe(r.id, seed)
            ..enabled.addAll(kRecipeTrackIds);
          final e = make();
          expect(e.recipeId, r.id);
          expect(isGridTempo(e.tempoBpm), isTrue);
          final wav = e.renderLoop();
          final data = readWavPcm16(wav);
          expect(data.samples.length ~/ data.channels, e.timing.totalSamples);
          final peak = _peak(wav);
          expect(peak, greaterThan(0.05), reason: 'audible');
          expect(peak, lessThanOrEqualTo(1.0));
          // Same (recipe, seed) → byte-identical, on a fresh engine.
          expect(make().renderLoop(), equals(wav));

          // Every stem has exactly the loop's length (alignment / seam).
          for (final track in e.tracks) {
            for (final v in track.variants) {
              expect(
                v
                    .render(LoopTiming(tempoBpm: e.tempoBpm, swing: e.swing))
                    .length,
                LoopTiming(tempoBpm: e.tempoBpm).totalSamples,
              );
            }
          }
          // Vamp mode too.
          e.progression = null;
          final vamp = readWavPcm16(e.renderLoop());
          expect(
            vamp.samples.length ~/ vamp.channels,
            LoopTiming(tempoBpm: e.tempoBpm).totalSamples,
          );
        }
      });
    }

    test('different seeds give different bands', () {
      final a = generateRecipeTracks(kStyleRecipes.first, 1);
      final b = generateRecipeTracks(kStyleRecipes.first, 2);
      final ca = (a[3].variants[0] as MelodicPattern).cells;
      final cb = (b[3].variants[0] as MelodicPattern).cells;
      final da = (a[0].variants[0] as DrumRowsPattern).rows;
      final db = (b[0].variants[0] as DrumRowsPattern).rows;
      expect(
        ca.toString() == cb.toString() && da.toString() == db.toString(),
        isFalse,
      );
    });

    test('the RNG is bit-exact (pinned values guard platform drift)', () {
      final rng = SeededRng(7);
      expect(
        [for (var i = 0; i < 5; i++) rng.nextInt(1000)],
        [330, 993, 543, 252, 725],
      );
      expect(fnv32('pop/bass/1'), fnv32('pop/bass/1'));
      expect(fnv32(''), 0x811c9dc5);
      expect(fnv32('a'), 0xe40c292c); // FNV-1a reference value
    });
  });

  group('share token', () {
    test('recipe + seed + pins round-trip and re-render identically', () {
      final e = LoopEngine()
        ..setRecipe('funk', 4242)
        ..enabled.addAll({'drums', 'bass', 'melody'});
      e.rollTrack('bass', 77);
      final token = encodeGrooveToken(e.spec);
      final back = decodeGrooveToken(token)!;
      expect(back.recipeId, 'funk');
      expect(back.recipeSeed, 4242);
      expect(back.trackPins['bass'], const RecipePin('funk', 77));
      final f = LoopEngine()..applySpec(back);
      expect(f.renderLoop(), equals(e.renderLoop()));
      expect(f.spec.cacheKey, e.spec.cacheKey);
    });

    test('a pre-catalog token decodes unchanged (no recipe)', () {
      final old = 'KU1.${base64UrlEncode(
        utf8.encode(
          '{"e":["drums","bass"],"t":75,"s":0.33,"kt":"lofi","st":"chill"}',
        ),
      )}';
      final spec = decodeGrooveToken(old)!;
      expect(spec.recipeId, isNull);
      expect(spec.styleId, 'chill');
      expect(spec.toJson().keys, isNot(contains('rc')));
      // Re-encoding a recipe-less spec emits no recipe keys at all.
      final json = jsonEncode(const GrooveSpec(enabled: {'drums'}).toJson());
      expect(json.contains('"rc"') || json.contains('"rs"'), isFalse);
      final e = LoopEngine()..applySpec(spec);
      expect(e.recipeId, isNull);
      expect(e.styleId, 'chill');
    });

    test('unknown recipe ids and junk pins fall back safely', () {
      final spec = GrooveSpec.fromJson({
        'e': ['drums'],
        'rc': 'polka-from-the-future',
        'rs': -5,
        'rp': {'bass': 'nope:1', 'melody': 'pop:x', 'evil': 'pop:1'},
      });
      expect(spec.recipeId, isNull);
      expect(spec.trackPins, isEmpty);
    });

    test('choosing a hand-authored style clears the recipe', () {
      final e = LoopEngine()..setRecipe('house', 3);
      e.styleId = 'default';
      expect(e.recipeId, isNull);
      expect(e.tracks.first.variants, kLoopMixerTracks.first.variants);
    });
  });

  group('acceptance: the detectors hear what the recipe implies', () {
    test('every bass bar starts on the progression chord root', () {
      final detector = PitchDetector();
      for (final r in kStyleRecipes) {
        final e = LoopEngine()
          ..setRecipe(r.id, 5)
          ..enabled.add('bass');
        final prog = e.progression!;
        final cells = e.cellsFor('bass')!;
        final stepSamples = e.timing.totalSamples ~/ e.timing.totalSteps;
        final stem = readWavPcm16(e.renderLoop());
        final mono = Float64List.fromList([
          for (var i = 0; i < stem.samples.length; i += stem.channels)
            stem.samples[i] / 32768.0,
        ]);
        var step = 0;
        var bar = -1;
        for (final c in cells) {
          final b = step ~/ 8;
          if (b != bar && c.midis != null) {
            bar = b;
            // Skip the attack, read a window inside the note.
            final from = step * stepSamples + 1500;
            final to = from + detector.windowSize;
            if (to <= (step + c.steps) * stepSamples) {
              final reading =
                  detector.analyze(Float64List.sublistView(mono, from, to));
              expect(
                reading.hasPitch,
                isTrue,
                reason: '${r.id} bar $b unvoiced',
              );
              final root = (prog.degrees[b].rootOffset + e.pitchTranspose) % 12;
              expect(
                reading.nearestMidi % 12,
                root,
                reason: '${r.id} bar $b: heard ${reading.nearestMidi}',
              );
            }
          }
          step += c.steps;
        }
      }
    });

    test('four-on-the-floor kicks come back on every beat (house)', () {
      final detector = PitchDetector();
      final tracks = generateRecipeTracks(styleRecipeById('house')!, 11);
      final drums = tracks.first.variants.first as DrumRowsPattern;
      final kickOnly = DrumRowsPattern({Drum.kick: drums.rows[Drum.kick]!});
      const timing = LoopTiming(tempoBpm: 120);
      final audio = kickOnly.render(timing);
      const hop = 1024;
      final w = detector.windowSize;
      final frames = <BeatFrame>[
        for (var s = 0; s + w <= audio.length; s += hop)
          () {
            final r =
                detector.analyze(Float64List.sublistView(audio, s, s + w));
            return (
              ms: s * 1000 / kSampleRate,
              rms: r.rms,
              zcr: r.zcr,
              pitchedLow: r.hasPitch && r.nearestMidi < 60,
            );
          }(),
      ];
      final heard = quantizeToBeat(frames, totalMs: timing.totalMs)!;
      expect(rowToString(heard.rows[Drum.kick]!), 'x.x.x.x.x.x.x.x.');
    });
  });
}
