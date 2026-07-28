// WS-A7 — clips that follow the project tempo.
//
// A warped clip is a claim that its audio is N BEATS of material rather than N
// seconds, so the tests are about that claim holding: the clip lands on the
// project's grid, its PITCH is untouched (warp is a timing feature — a
// resampler would have been half the code and the wrong answer), and a clip
// that never said what tempo it is in is left alone rather than stretched by a
// guessed factor.
//
// The load-bearing one is the last group: the two render paths are pinned
// byte-identical elsewhere, and a warp implemented in one and not the other
// breaks that pin only for warped clips — which is exactly the kind of bug that
// ships.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/time_stretch.dart';
import 'package:comet_beat/core/audio/daw_project.dart';
import 'package:comet_beat/core/audio/daw_sources.dart';
import 'package:comet_beat/core/audio/daw_tempo_map.dart';
import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/features/games/composition/daw_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

/// A tone of exactly [ms] at [hz], so both the duration and the pitch of the
/// result are measurable.
Float64List _tone(double hz, double ms) {
  final n = (ms * kDawSampleRate / 1000).round();
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = 0.5 * math.sin(2 * math.pi * hz * i / kDawSampleRate);
  }
  return out;
}

/// Dominant frequency by zero-crossing rate — crude, but immune to the
/// amplitude modulation WSOLA introduces, which an FFT peak search is not.
double _dominantHz(Float64List pcm) {
  if (pcm.length < 2) return 0;
  var crossings = 0;
  for (var i = 1; i < pcm.length; i++) {
    if ((pcm[i - 1] < 0) != (pcm[i] < 0)) crossings++;
  }
  return crossings * kDawSampleRate / (2 * pcm.length);
}

DawTimeline _one(Clip clip) => DawTimeline(
      tracks: [
        DawTrack(clips: [clip]),
      ],
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('a warped clip follows the project tempo', () {
    test('a 120 BPM loop in a 140 BPM project gets SHORTER', () {
      // Two bars at 120 BPM = 4000 ms. The same music at 140 has to fit into
      // 4000 × 120/140 ≈ 3429 ms, or it is no longer two bars of this song.
      final clip = Clip(
        source: SampleSource(_tone(440, 4000)),
        warp: true,
        nativeBpm: 120,
      );
      final warped = renderTimelineStereo(
        _one(clip),
        tempoMap: TempoMap.constant(140),
        limit: false,
      );
      const expected = 4000 * 120 / 140 * kDawSampleRate / 1000;
      expect(warped.left.length, closeTo(expected, kDawSampleRate * 0.02));
    });

    test('and LONGER in a slower project', () {
      final clip = Clip(
        source: SampleSource(_tone(440, 2000)),
        warp: true,
        nativeBpm: 120,
      );
      final warped = renderTimelineStereo(
        _one(clip),
        tempoMap: TempoMap.constant(60),
        limit: false,
      );
      const expected = 2000 * 120 / 60 * kDawSampleRate / 1000;
      expect(warped.left.length, closeTo(expected, kDawSampleRate * 0.05));
    });

    test('the PITCH does not move — this is the whole reason it is WSOLA', () {
      // A resampler would have been half the code and would transpose the loop
      // by a fourth here. That would be a different (and wrong) feature.
      final clip = Clip(
        source: SampleSource(_tone(440, 2000)),
        warp: true,
        nativeBpm: 120,
      );
      final warped = renderTimelineStereo(
        _one(clip),
        tempoMap: TempoMap.constant(160),
        limit: false,
      );
      expect(_dominantHz(warped.left), closeTo(440, 25));
    });

    test('at the SAME tempo nothing happens at all', () {
      // Not "approximately nothing": running WSOLA at a factor of 1 would still
      // smear the audio, and the overwhelmingly common case is a project whose
      // tempo matches its loops.
      final clip = Clip(
        source: SampleSource(_tone(440, 1000)),
        warp: true,
        nativeBpm: 120,
      );
      final plain = renderTimelineStereo(_one(clip), limit: false);
      final mapped = renderTimelineStereo(
        _one(clip),
        tempoMap: TempoMap.constant(120),
        limit: false,
      );
      expect(mapped.left, orderedEquals(plain.left));
    });
  });

  group('warping is refused rather than guessed', () {
    Float64List renderWith(Clip clip) => renderTimelineStereo(
          _one(clip),
          tempoMap: TempoMap.constant(160),
          limit: false,
        ).left;

    final source = SampleSource(_tone(440, 1000));

    test('a clip with warp OFF is byte-identical', () {
      final off = renderWith(Clip(source: source, nativeBpm: 120));
      final none = renderTimelineStereo(
        _one(Clip(source: source)),
        limit: false,
      ).left;
      expect(off, orderedEquals(none));
    });

    test('warp ON with NO native tempo is left alone', () {
      // The honest answer. Stretching by an invented factor would shift the
      // arrangement's timing, and a listener cannot tell that from a mistake
      // they made themselves.
      final guessed = renderWith(Clip(source: source, warp: true));
      final plain = renderTimelineStereo(
        _one(Clip(source: source)),
        limit: false,
      ).left;
      expect(guessed, orderedEquals(plain));
    });

    test('with no tempo map, nothing warps', () {
      // Every caller predating this passes no map, and must be unaffected.
      final noMap = renderTimelineStereo(
        _one(Clip(source: source, warp: true, nativeBpm: 120)),
        limit: false,
      ).left;
      expect(noMap, hasLength(source.render(kDawSampleRate).length));
    });

    test('an absurd factor is refused instead of mangling the audio', () {
      // A 60 BPM loop declared at 240 is a mis-stated tempo, not a request for
      // a 4× stretch; WSOLA at that range produces obvious artefacts and
      // calling it a feature would be dishonest.
      final absurd = renderWith(
        Clip(
          source: source,
          warp: true,
          nativeBpm: 10, // 10 → 160 BPM is 16× faster
        ),
      );
      final plain = renderTimelineStereo(
        _one(Clip(source: source)),
        limit: false,
      ).left;
      expect(absurd, orderedEquals(plain));
    });
  });

  group('across a tempo change', () {
    test('the clip ENDS where the map says, so nothing after it drifts', () {
      // The documented trade: a clip spanning a tempo change gets one factor,
      // so the change is smeared inside the clip — but the clip's end lands
      // exactly, which is the property the rest of the arrangement depends on.
      // 4 beats at 120 BPM (2000 ms of material), starting at 0, in a project
      // that runs 120 for 1 s then 60: beats 0..2 take 1000 ms, beats 2..4 take
      // 2000 ms → the clip should occupy 3000 ms.
      final map = TempoMap([
        const TempoChange(ms: 0, bpm: 120),
        const TempoChange(ms: 1000, bpm: 60),
      ]);
      final clip = Clip(
        source: SampleSource(_tone(440, 2000)),
        warp: true,
        nativeBpm: 120,
      );
      final out = renderTimelineStereo(_one(clip), tempoMap: map, limit: false);
      final ms = out.left.length * 1000 / kDawSampleRate;
      expect(ms, closeTo(3000, 60));
    });

    test('a clip AFTER the change uses the tempo in force there', () {
      final map = TempoMap([
        const TempoChange(ms: 0, bpm: 120),
        const TempoChange(ms: 1000, bpm: 60),
      ]);
      final clip = Clip(
        source: SampleSource(_tone(440, 1000)),
        startMs: 4000, // well inside the 60 BPM section
        warp: true,
        nativeBpm: 120,
      );
      final out = renderTimelineStereo(_one(clip), tempoMap: map, limit: false);
      final clipMs =
          out.left.length * 1000 / kDawSampleRate - 4000; // minus the lead-in
      // 120 → 60 is half speed, so 1000 ms of material occupies 2000.
      expect(clipMs, closeTo(2000, 60));
    });
  });

  group('the two render paths must not disagree', () {
    test('windowed matches full, for a WARPED clip', () {
      // The pin that exists elsewhere breaks only for warped clips if warp is
      // implemented in one path and not the other.
      final timeline = _one(
        Clip(
          source: SampleSource(_tone(440, 1500)),
          startMs: 200,
          warp: true,
          nativeBpm: 120,
        ),
      );
      final tempo = TempoMap.constant(90);
      final full = renderTimelineStereo(
        timeline,
        tempoMap: tempo,
        limit: false,
      );
      const from = 300 * kDawSampleRate ~/ 1000;
      const to = 900 * kDawSampleRate ~/ 1000;
      final windowed = renderTimelineWindowStereo(
        timeline,
        fromSample: from,
        toSample: to,
        tempoMap: tempo,
        limit: false,
      );
      for (var i = 0; i < to - from; i++) {
        expect(
          windowed.left[i],
          closeTo(full.left[from + i], 1e-12),
          reason: 'sample ${from + i}',
        );
      }
    });

    test('the reported LENGTH matches what actually renders', () {
      // A warped clip that grew would be truncated if the length calculation
      // ignored the warp — the render would simply end early.
      final timeline = _one(
        Clip(
          source: SampleSource(_tone(440, 1000)),
          warp: true,
          nativeBpm: 120,
        ),
      );
      final tempo = TempoMap.constant(60);
      final length = dawTimelineLengthSamples(timeline, tempoMap: tempo);
      final rendered =
          renderTimelineStereo(timeline, tempoMap: tempo, limit: false);
      expect(length, rendered.left.length);
    });
  });

  group('the service and the file format', () {
    test('setting warp is undoable', () {
      final daw = DawService()..addClip(SampleSource(_tone(440, 500)));
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      daw.setClipWarp(track, 0, true, nativeBpm: 100);
      expect(daw.clipWarps(track, 0), isTrue);
      daw.undo();
      expect(daw.clipWarps(track, 0), isFalse);
    });

    test('a symbolic clip knows its own tempo without anyone typing one', () {
      // A drum pattern carries its grid; asking the user to restate it would be
      // asking for information the document already holds.
      final daw = DawService();
      daw.addClip(
        DrumSource(
          DrumRowsPattern({
            Drum.kick: [for (var i = 0; i < kPatternSteps; i++) i % 4 == 0],
          }),
          const LoopTiming(tempoBpm: 96),
        ),
      );
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      expect(daw.clipNativeBpm(track, 0), 96);
    });

    test('a recording has no tempo to report', () {
      final daw = DawService()..addClip(SampleSource(_tone(440, 500)));
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      expect(daw.clipNativeBpm(track, 0), isNull);
    });

    test('warp survives save and reload', () {
      final timeline = _one(
        Clip(
          source: SampleSource(_tone(440, 300)),
          warp: true,
          nativeBpm: 132,
        ),
      );
      final back = projectFromJson(projectToJson(timeline));
      expect(back.tracks.single.clips.single.warp, isTrue);
      expect(back.tracks.single.clips.single.nativeBpm, 132);
    });

    test('an unwarped clip writes no warp keys', () {
      final timeline = _one(Clip(source: SampleSource(_tone(440, 100))));
      final json = projectToJson(timeline);
      expect(json.contains('warp'), isFalse);
      expect(json.contains('nativeBpm'), isFalse);
    });
  });

  group('WS-A9 — warp honours the per-clip stretch setting', () {
    // Per-CLIP, not per-project, and this is the test that justifies it: a bass
    // line and a drum loop on adjacent lanes need different windows, and a
    // project-wide setting would force the wrong one on somebody.
    Float64List warpedAt(StretchQuality q) => renderTimelineStereo(
          _one(
            Clip(
              // 55 Hz — below what the default window can hold, which is the
              // whole reason `deep` exists.
              source: SampleSource(_tone(55, 800)),
              warp: true,
              nativeBpm: 120,
              warpQuality: q,
            ),
          ),
          tempoMap: TempoMap.constant(90),
          limit: false,
        ).left;

    double pitchOf(Float64List pcm) {
      var crossings = 0;
      for (var i = 1; i < pcm.length; i++) {
        if ((pcm[i - 1] < 0) != (pcm[i] < 0)) crossings++;
      }
      return crossings * kDawSampleRate / (2 * pcm.length);
    }

    test('DEEP keeps a bass note in tune through a warp; light does not', () {
      expect(pitchOf(warpedAt(StretchQuality.deep)), closeTo(55, 5));
      expect(pitchOf(warpedAt(StretchQuality.light)), lessThan(48));
    });

    test('the setting is undoable and survives save', () {
      final daw = DawService()..addClip(SampleSource(_tone(110, 500)));
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      daw.setClipWarpQuality(track, 0, StretchQuality.deep);
      expect(daw.clipWarpQuality(track, 0), StretchQuality.deep);
      daw.undo();
      expect(daw.clipWarpQuality(track, 0), StretchQuality.balanced);

      final back = projectFromJson(
        projectToJson(
          _one(
            Clip(
              source: SampleSource(_tone(110, 200)),
              warpQuality: StretchQuality.deep,
            ),
          ),
        ),
      );
      expect(back.tracks.single.clips.single.warpQuality, StretchQuality.deep);
    });

    test('the default writes no key, and an unknown one reads as balanced', () {
      // Forward compatibility: a project written by a build with more settings
      // than this one must open, not crash.
      final json = projectToJson(
        _one(Clip(source: SampleSource(_tone(110, 100)))),
      );
      expect(json.contains('warpQuality'), isFalse);

      final odd =
          json.replaceFirst('"warp":', '"warpQuality":"granular","warp":');
      expect(
        projectFromJson(odd).tracks.single.clips.single.warpQuality,
        StretchQuality.balanced,
      );
    });
  });

  group('the door is offered — including for a RECORDING', () {
    // The case warp most exists for is a recording, and a recording cannot know
    // its own tempo. Hiding the feature there (or guessing a number) would make
    // it useless exactly where it is wanted, so it asks.
    Future<DawService> pumpDaw(WidgetTester tester) async {
      await pumpGame(
        tester,
        const DawScreen(),
        extraProviders: [ChangeNotifierProvider(create: (_) => DawService())],
      );
      return Provider.of<DawService>(
        tester.element(find.byType(DawScreen)),
        listen: false,
      );
    }

    testWidgets('a recording asks for its tempo, then follows', (tester) async {
      final daw = await pumpDaw(tester);
      daw.addClip(SampleSource(_tone(440, 1000)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('🎵').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Follow project tempo'));
      await tester.pumpAndSettle();

      expect(find.text('What tempo is this clip in?'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '96');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      expect(daw.clipWarps(track, 0), isTrue);
      expect(daw.clipNativeBpm(track, 0), 96);
    });

    testWidgets('cancelling leaves the clip alone', (tester) async {
      // Not "warp on with a default tempo" — an invisible timing shift is the
      // one outcome worse than nothing happening.
      final daw = await pumpDaw(tester);
      daw.addClip(SampleSource(_tone(440, 1000)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('🎵').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Follow project tempo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      expect(daw.clipWarps(track, 0), isFalse);
    });

    testWidgets('a symbolic clip does not ask — it already knows',
        (tester) async {
      final daw = await pumpDaw(tester);
      daw.addClip(
        DrumSource(
          DrumRowsPattern({
            Drum.kick: [for (var i = 0; i < kPatternSteps; i++) i % 4 == 0],
          }),
          const LoopTiming(tempoBpm: 96),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('🥁').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Follow project tempo'));
      await tester.pumpAndSettle();

      expect(find.text('What tempo is this clip in?'), findsNothing);
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      expect(daw.clipWarps(track, 0), isTrue);
      expect(daw.clipNativeBpm(track, 0), 96);
    });
  });
}
