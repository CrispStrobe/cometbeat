// D5 — take lanes and comping.
//
// Recording a part three times and keeping the best is the oldest workflow in
// the building, and the thing that makes it usable is that the alternatives
// stay ALIVE: reachable, switchable, and still there tomorrow. So these tests
// are not about a takeIndex field holding a number. They assert that selecting
// a take changes what the renderer produces, that the take you already had is
// never lost by recording another, and that the alternatives survive a save —
// the point at which a takes feature most commonly betrays someone, because the
// project reopens looking fine with everything but the chosen take gone.
//
// Comping is deliberately NOT a fourth concept. Splitting a clip at a phrase
// boundary and choosing a take per segment IS a comp, and the timeline already
// splits. The test below proves the composition works rather than pinning a
// dedicated API that would only duplicate two verbs that already exist.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_project.dart';
import 'package:comet_beat/core/audio/daw_sources.dart';
import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/features/games/composition/daw_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

/// A one-second take at a distinctive level, so the RENDER says which take is
/// playing without anyone having to trust a field.
SampleSource _take(double level) {
  final pcm = Float64List(kDawSampleRate);
  pcm.fillRange(0, pcm.length, level);
  return SampleSource(pcm);
}

double _peak(Float64List pcm) {
  var peak = 0.0;
  for (final v in pcm) {
    peak = math.max(peak, v.abs());
  }
  return peak;
}

/// What the timeline actually sounds like, which is the only evidence that a
/// take selection did anything.
double _renderedPeak(DawService daw) =>
    _peak(renderTimeline(daw.timeline, limit: false));

int _trackOf(DawService daw) =>
    daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('takes are alternatives you can actually reach', () {
    test('selecting a take changes what RENDERS', () {
      final daw = DawService()..addClip(_take(0.2));
      final track = _trackOf(daw);
      daw.addTake(track, 0, _take(0.8));

      expect(_renderedPeak(daw), closeTo(0.8, 1e-6));
      daw.selectTake(track, 0, 0);
      expect(_renderedPeak(daw), closeTo(0.2, 1e-6));
    });

    test('adding a take never loses the one already there', () {
      // The commonest way this feature betrays someone: the first "record
      // another" quietly discards the original, because the list was seeded
      // empty instead of with what the clip already held.
      final daw = DawService()..addClip(_take(0.3));
      final track = _trackOf(daw);
      daw.addTake(track, 0, _take(0.9));

      expect(daw.takeCount(track, 0), 2);
      daw.selectTake(track, 0, 0);
      expect(_renderedPeak(daw), closeTo(0.3, 1e-6));
    });

    test('a clip nobody has re-recorded reports exactly one take', () {
      // An empty list means one take, not zero. Every reader would otherwise
      // need to know about the empty case.
      final daw = DawService()..addClip(_take(0.5));
      final track = _trackOf(daw);
      expect(daw.takeCount(track, 0), 1);
      expect(daw.activeTake(track, 0), 0);
      expect(daw.timeline.tracks[track].clips.first.takes, isEmpty);
    });

    test('a new take becomes the audible one', () {
      // You record another take to hear it. Having to then go and select it
      // would make the verb a lie.
      final daw = DawService()..addClip(_take(0.25));
      final track = _trackOf(daw);
      daw.addTake(track, 0, _take(0.75));
      expect(daw.activeTake(track, 0), 1);
      expect(_renderedPeak(daw), closeTo(0.75, 1e-6));
    });

    test('an out-of-range selection does NOTHING rather than clamping', () {
      // Clamping would play a take other than the one asked for, which is
      // worse than refusing: the user hears something and believes it is take
      // 7.
      final daw = DawService()..addClip(_take(0.2));
      final track = _trackOf(daw);
      daw.addTake(track, 0, _take(0.8));

      daw.selectTake(track, 0, 5);
      expect(daw.activeTake(track, 0), 1);
      expect(_renderedPeak(daw), closeTo(0.8, 1e-6));

      daw.selectTake(track, 0, -1);
      expect(daw.activeTake(track, 0), 1);
    });

    test('switching takes is undoable', () {
      final daw = DawService()..addClip(_take(0.2));
      final track = _trackOf(daw);
      daw.addTake(track, 0, _take(0.8));
      daw.selectTake(track, 0, 0);
      expect(_renderedPeak(daw), closeTo(0.2, 1e-6));
      daw.undo();
      expect(_renderedPeak(daw), closeTo(0.8, 1e-6));
    });

    test('re-selecting the take already playing costs no undo step', () {
      // Asserted by what the undo restores: if the no-op had recorded a
      // snapshot, this undo would be spent on it and stop at 0.8.
      final daw = DawService()..addClip(_take(0.2));
      final track = _trackOf(daw);
      daw.addTake(track, 0, _take(0.8));
      daw.selectTake(track, 0, 1);
      daw.undo();
      expect(_renderedPeak(daw), closeTo(0.2, 1e-6));
    });
  });

  group('comping composes from verbs that already exist', () {
    test('split segments carry the takes and choose independently', () {
      // This IS a comp: two phrases, take A on the first and take B on the
      // second. Nothing here is comping-specific machinery — it is split plus
      // per-clip take selection, which is the whole design.
      final daw = DawService()..addClip(_take(0.2));
      final track = _trackOf(daw);
      daw.addTake(track, 0, _take(0.8));

      daw.splitClip(track, 0, 500);
      expect(daw.timeline.tracks[track].clips, hasLength(2));

      // Both halves inherited the full take list…
      expect(daw.takeCount(track, 0), 2);
      expect(daw.takeCount(track, 1), 2);

      // …and choose separately: first phrase from take 0, second from take 1.
      daw.selectTake(track, 0, 0);
      final mix = renderTimeline(daw.timeline, limit: false);
      expect(
        _peak(Float64List.sublistView(mix, 0, kDawSampleRate ~/ 4)),
        closeTo(0.2, 1e-6),
      );
      expect(
        _peak(Float64List.sublistView(mix, kDawSampleRate * 3 ~/ 4)),
        closeTo(0.8, 1e-6),
      );
    });

    test('a comped segment plays the ALIGNED region of the take', () {
      // The property that makes comping work at all. Takes of one part are the
      // same passage played again, so the second phrase must play the second
      // phrase OF THE ALTERNATIVE — not restart it from the top. A take list
      // that ignored the segment's trim would sound like a stutter, and the
      // flat-level takes above cannot tell the two apart.
      final rising = Float64List(kDawSampleRate);
      for (var i = 0; i < rising.length; i++) {
        rising[i] = i / rising.length; // 0 → 1 across the second
      }
      final daw = DawService()..addClip(_take(0.2));
      final track = _trackOf(daw);
      daw.addTake(track, 0, SampleSource(rising));

      daw.splitClip(track, 0, 500);
      // Second half, on the rising take: it must be the LOUD end of the ramp.
      final mix = renderTimeline(daw.timeline, limit: false);
      expect(
        _peak(Float64List.sublistView(mix, kDawSampleRate * 3 ~/ 4)),
        greaterThan(0.9),
        reason: 'restarting the take would put the quiet end here',
      );
    });

    test('a comped segment can still be revisited', () {
      // The value of keeping the alternatives rather than flattening: the
      // choice made for one phrase is not final.
      final daw = DawService()..addClip(_take(0.2));
      final track = _trackOf(daw);
      daw.addTake(track, 0, _take(0.8));
      daw.splitClip(track, 0, 500);
      daw.selectTake(track, 0, 0);
      daw.selectTake(track, 0, 1);
      expect(daw.activeTake(track, 0), 1);
    });
  });

  group('stacking parallel passes into one clip', () {
    // How take lanes actually get made: record the part again on another lane,
    // then fold that clip in. The row of parallel clips becomes one clip you
    // can audition, which is the point.
    DawService twoLanes() {
      final daw = DawService()..addClip(_take(0.2));
      daw.addClip(_take(0.8), track: 1);
      return daw;
    }

    test('the donor clip leaves the timeline and becomes a take', () {
      final daw = twoLanes();
      expect(daw.stackAsTake(0, 0, 1, 0), isTrue);
      expect(daw.timeline.tracks[1].clips, isEmpty);
      expect(daw.takeCount(0, 0), 2);
      expect(_renderedPeak(daw), closeTo(0.8, 1e-6));
      daw.selectTake(0, 0, 0);
      expect(_renderedPeak(daw), closeTo(0.2, 1e-6));
    });

    test('a donor that already had takes brings them ALL', () {
      // Otherwise stacking a clip someone had already comped silently discards
      // the alternatives they kept.
      final daw = twoLanes();
      daw.addTake(1, 0, _take(0.5));
      expect(daw.stackAsTake(0, 0, 1, 0), isTrue);
      expect(daw.takeCount(0, 0), 3);
    });

    test('stacking a clip onto ITSELF is refused, not obeyed', () {
      // Obeying would delete the clip and leave a take list pointing at
      // nothing — a data-loss bug dressed as a no-op.
      final daw = twoLanes();
      expect(daw.stackAsTake(0, 0, 0, 0), isFalse);
      expect(daw.clipCount, 2);
    });

    test('it survives a donor EARLIER on the same lane', () {
      // Removing the donor shifts every later index on that lane. Writing the
      // target back by its old index would edit the wrong clip — and on this
      // arrangement it would edit one that no longer exists.
      final daw = DawService()..addClip(_take(0.2));
      daw.addClip(_take(0.8));
      // Two clips on one lane: donor at 0, target at 1.
      expect(daw.stackAsTake(0, 1, 0, 0), isTrue);
      expect(daw.timeline.tracks[0].clips, hasLength(1));
      expect(daw.takeCount(0, 0), 2);
      daw.selectTake(0, 0, 0);
      expect(_renderedPeak(daw), closeTo(0.8, 1e-6));
    });

    test('it is undoable, donor and all', () {
      final daw = twoLanes();
      daw.stackAsTake(0, 0, 1, 0);
      daw.undo();
      expect(daw.timeline.tracks[1].clips, hasLength(1));
      expect(daw.takeCount(0, 0), 1);
    });
  });

  group('the alternatives survive a save', () {
    test('every take comes back, and the chosen one is still chosen', () {
      final daw = DawService()..addClip(_take(0.2));
      final track = _trackOf(daw);
      daw.addTake(track, 0, _take(0.8));
      daw.addTake(track, 0, _take(0.5));
      daw.selectTake(track, 0, 1);
      final saved = daw.saveProject();

      final reopened = DawService()..loadProject(saved);
      final t = _trackOf(reopened);
      expect(reopened.takeCount(t, 0), 3);
      expect(reopened.activeTake(t, 0), 1);
      expect(_renderedPeak(reopened), closeTo(0.8, 1e-3));

      // And the ones that were NOT chosen are genuinely still there, not
      // placeholders that reopen silent.
      reopened.selectTake(t, 0, 2);
      expect(_renderedPeak(reopened), closeTo(0.5, 1e-3));
      reopened.selectTake(t, 0, 0);
      expect(_renderedPeak(reopened), closeTo(0.2, 1e-3));
    });

    test('a take with a MODEL comes back editable, not merely audible', () {
      // The same guarantee C1 gave the clip's own source has to hold for the
      // alternatives, or switching to one would downgrade it to a bounce.
      final timeline = DawTimeline(
        tracks: [
          DawTrack(
            clips: [
              Clip(
                source: _take(0.4),
                takes: [
                  _take(0.4),
                  DrumSource(
                    DrumRowsPattern({
                      Drum.kick: [
                        for (var i = 0; i < kPatternSteps; i++) i % 4 == 0,
                      ],
                    }),
                    const LoopTiming(tempoBpm: 120),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      final back = projectFromJson(projectToJson(timeline));
      expect(back.tracks.single.clips.single.takes[1], isA<DrumSource>());
    });

    test('a single-take clip writes no takes key at all', () {
      // Nothing to say that the default does not cover, and the file reads
      // identically on a build that predates this.
      final timeline = DawTimeline(
        tracks: [
          DawTrack(clips: [Clip(source: _take(0.5))]),
        ],
      );
      expect(projectToJson(timeline).contains('"takes"'), isFalse);
    });

    test('the active take is not written twice', () {
      // It is already on disk as the clip's own source; a second copy of its
      // audio in every project file is real cost for no information.
      final withTakes = DawTimeline(
        tracks: [
          DawTrack(
            clips: [
              Clip(source: _take(0.4), takes: [_take(0.4), _take(0.6)]),
            ],
          ),
        ],
      );
      final withoutTakes = DawTimeline(
        tracks: [
          DawTrack(clips: [Clip(source: _take(0.4))]),
        ],
      );
      // Two takes, one of which is the active one: the file grows by ONE
      // take's audio, not two.
      final grew =
          projectToJson(withTakes).length - projectToJson(withoutTakes).length;
      final oneTake = projectToJson(withoutTakes).length;
      expect(grew, lessThan(oneTake));
    });

    test('a damaged takes list falls back to a single-take clip', () {
      // If the marker for the active take is lost, a takes list that no longer
      // contains the audible take would drop it on the next selection. Better
      // to arrive as the clip it plainly is.
      final json = projectToJson(
        DawTimeline(
          tracks: [
            DawTrack(
              clips: [
                Clip(source: _take(0.4), takes: [_take(0.4), _take(0.6)]),
              ],
            ),
          ],
        ),
      ).replaceAll('"active":true', '"active":false');

      final back = projectFromJson(json);
      expect(back.tracks.single.clips.single.takes, isEmpty);
      // The audible take is untouched — that is the point of the fallback.
      expect(_peak(renderTimeline(back, limit: false)), closeTo(0.4, 1e-3));
    });
  });

  group('the door is actually offered', () {
    // A service verb no screen calls is not a feature. The sheet also has to
    // SWITCH the take, not merely list them — a picker that shows the
    // alternatives and plays the same one is the failure this catches.
    Future<void> pumpDaw(WidgetTester tester) => pumpGame(
          tester,
          const DawScreen(),
          extraProviders: [ChangeNotifierProvider(create: (_) => DawService())],
        );

    DawService serviceOf(WidgetTester tester) => Provider.of<DawService>(
          tester.element(find.byType(DawScreen)),
          listen: false,
        );

    testWidgets(
        'the clip inspector reaches the takes, and switching '
        'changes what plays', (tester) async {
      await pumpDaw(tester);
      final daw = serviceOf(tester)..addClip(_take(0.2));
      final track = _trackOf(daw);
      daw.addTake(track, 0, _take(0.8));
      await tester.pumpAndSettle();

      // 🎵 is a plain sample clip's badge; tapping it opens the inspector.
      await tester.tap(find.text('🎵').first);
      await tester.pumpAndSettle();
      // The label carries which take is playing — otherwise it is invisible on
      // the timeline.
      expect(find.text('Takes (2/2)'), findsOneWidget);

      await tester.tap(find.text('Takes (2/2)'));
      await tester.pumpAndSettle();
      expect(find.text('Take 1'), findsOneWidget);
      expect(find.text('Take 2'), findsOneWidget);

      await tester.tap(find.text('Take 1'));
      await tester.pumpAndSettle();
      expect(daw.activeTake(track, 0), 0);
      expect(_renderedPeak(daw), closeTo(0.2, 1e-6));
    });

    testWidgets('a single-take clip says so rather than hiding the door',
        (tester) async {
      // Hiding it would leave no way to discover that stacking exists.
      await pumpDaw(tester);
      serviceOf(tester).addClip(_take(0.5));
      await tester.pumpAndSettle();

      await tester.tap(find.text('🎵').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Takes'));
      await tester.pumpAndSettle();
      expect(find.textContaining('One take'), findsOneWidget);
    });
  });
}
