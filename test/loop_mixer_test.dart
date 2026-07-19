// Loop Mixer — the loop-layering sandbox. Drives toggles via the
// LoopMixerTester seam (audio is a no-op in the headless test binding — the
// assertions are on the enabled set, the play state and the render).

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/aec_engine.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/features/games/composition/groove_play_along.dart';
import 'package:comet_beat/features/games/composition/loop_creatures.dart';
import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:comet_beat/features/games/composition/loop_secrets.dart';
import 'package:comet_beat/features/games/composition/smear_pad.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:crisp_notation/crisp_notation.dart' show StaffView;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

LoopMixerTester _game(WidgetTester tester) =>
    tester.state<State<LoopMixerScreen>>(find.byType(LoopMixerScreen))
        as LoopMixerTester;

/// A stand-in for the native Tier-3b engine: records the reference PCM the
/// screen pushes and lets the test emit synthetic cleaned near-end frames. No
/// device, no `dart:ffi` — the graded-jam path runs entirely headless.
class FakeAecEngine implements AecEngine {
  final _cleaned = StreamController<Uint8List>.broadcast();
  final List<Uint8List> references = [];
  bool started = false;
  bool stopped = false;

  @override
  Future<void> start({int sampleRate = 44100, int frame = 256}) async =>
      started = true;

  @override
  void reference(Uint8List pcm16) => references.add(pcm16);

  @override
  Stream<Uint8List> get cleaned => _cleaned.stream;

  @override
  Future<void> stop() async => stopped = true;

  /// Push a cleaned near-end frame as if the mic (minus echo) produced it.
  void emitCleaned(Uint8List pcm16) => _cleaned.add(pcm16);
}

/// A steady sine at [freq] as mono PCM16 — a synthetic "instrument" line the
/// AEC would hand back on the cleaned stream.
Uint8List _tonePcm16(
  double freq, {
  int sampleRate = 44100,
  double seconds = 0.6,
  double amp = 0.3,
}) {
  final n = (sampleRate * seconds).round();
  final out = Int16List(n);
  for (var i = 0; i < n; i++) {
    out[i] = (amp * 32767 * sin(2 * pi * freq * i / sampleRate)).round();
  }
  return out.buffer.asUint8List();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('To Multitrack sends the groove as a DAW clip', (tester) async {
    final daw = DawService();
    await pumpGame(
      tester,
      const LoopMixerScreen(),
      extraProviders: [ChangeNotifierProvider<DawService>.value(value: daw)],
    );
    final game = _game(tester);

    // Nothing enabled → nothing sent.
    game.sendToDaw();
    expect(daw.clipCount, 0);

    game.toggleTrack('drums');
    await tester.pump();
    game.sendToDaw();
    expect(daw.clipCount, 1);
    expect(daw.bake(), isNotEmpty); // the groove renders to real audio
  });

  testWidgets('toggling cards layers tracks and starts/stops the groove',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);

    expect(game.enabledTracks, isEmpty);
    expect(game.isPlaying, isFalse);

    game.toggleTrack('drums');
    await tester.pump();
    expect(game.enabledTracks, {'drums'});
    expect(game.isPlaying, isTrue);

    game.toggleTrack('bass');
    await tester.pump();
    expect(game.enabledTracks, {'drums', 'bass'});
    expect(game.isPlaying, isTrue);

    // Untoggling the last card stops the groove.
    game.toggleTrack('drums');
    game.toggleTrack('bass');
    await tester.pump();
    expect(game.enabledTracks, isEmpty);
    expect(game.isPlaying, isFalse);
  });

  testWidgets('cards are tappable and Stop clears the whole band',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);

    await tester.tap(find.text('Drums'));
    await tester.tap(find.text('Melody'));
    await tester.pump();
    expect(game.enabledTracks, {'drums', 'melody'});

    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(game.enabledTracks, isEmpty);
    expect(game.isPlaying, isFalse);
  });

  testWidgets('tempo chips retune the groove', (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);
    expect(game.tempoBpm, 100);

    game.toggleTrack('chords');
    await tester.pump();

    await tester.tap(find.text('Fast'));
    await tester.pump();
    expect(game.tempoBpm, 120);
    expect(game.isPlaying, isTrue, reason: 'groove restarts at the new tempo');
  });

  testWidgets('variant badge, level slider and swing drive the engine',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);

    game.toggleTrack('drums');
    await tester.pump();
    expect(game.variantOf('drums'), 0);

    // The A badge on the drums card cycles the pattern variant. (Scope to the
    // CircleAvatar badge so the key-chip note letters can't be mistaken for it.)
    await tester.tap(
      find
          .descendant(
            of: find.byType(CircleAvatar),
            matching: find.text('A'),
          )
          .first,
    );
    await tester.pump();
    expect(game.variantOf('drums'), 1);
    expect(
      find.descendant(
        of: find.byType(CircleAvatar),
        matching: find.text('B'),
      ),
      findsOneWidget,
    );

    game.setTrackLevel('drums', 0.4);
    game.setSwing(0.3);
    await tester.pump();
    expect(game.levelOf('drums'), closeTo(0.4, 1e-9));
    expect(game.swing, closeTo(0.3, 1e-9));
    expect(game.isPlaying, isTrue);
  });

  testWidgets('harmony chips switch between the vamp and a progression',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);
    expect(game.progressionId, isNull);

    game.toggleTrack('bass');
    await tester.pump();

    await tester.tap(find.text('I–V–vi–IV'));
    await tester.pump();
    expect(game.progressionId, 'axis');
    expect(game.isPlaying, isTrue, reason: 'groove restarts on the song loop');

    await tester.tap(find.text('Free'));
    await tester.pump();
    expect(game.progressionId, isNull);
  });

  testWidgets('the score panel engraves EVERY enabled track (incl. drums)',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);
    expect(game.scoreVisible, isFalse);

    // Toggling Score with nothing enabled still shows something — a hint, so
    // the button never silently no-ops — but no staves yet.
    game.toggleScorePanel();
    await tester.pump();
    expect(game.scoreVisible, isTrue);
    expect(find.byType(StaffView), findsNothing);
    expect(
      find.text('Turn on a layer to see it written as notes.'),
      findsOneWidget,
    );

    // A full band engraves one staff PER enabled track — the drum rhythm
    // reduction + bass + melody, not just the single leading pitched track.
    game.toggleTrack('drums');
    game.toggleTrack('bass');
    game.toggleTrack('melody');
    await tester.pump();
    expect(find.byType(StaffView), findsNWidgets(3));

    // All off → back to the hint, no staves.
    game.toggleTrack('drums');
    game.toggleTrack('bass');
    game.toggleTrack('melody');
    await tester.pump();
    expect(find.byType(StaffView), findsNothing);
  });

  testWidgets('key & scale chips transpose the pitched stems', (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);
    expect(game.key, 0);
    expect(game.scale, GrooveScale.majorPentatonic);

    // Tapping the 'F' key chip sets the root to 5 (C=0 … F=5).
    await tester.tap(find.widgetWithText(ChoiceChip, 'F'));
    await tester.pump();
    expect(game.key, 5);

    // Tapping 'Minor' switches the scale (relative-minor pentatonic set).
    await tester.tap(find.widgetWithText(ChoiceChip, 'Minor'));
    await tester.pump();
    expect(game.scale, GrooveScale.minorPentatonic);

    // The engraving reflects the transposition: with melody on, a staff shows
    // and the transposed cells are what's engraved (no crash on re-render).
    game.toggleTrack('melody');
    await tester.pump();
    game.toggleScorePanel();
    await tester.pump();
    expect(find.byType(StaffView), findsWidgets);
    expect(tester.takeException(), isNull);

    // Seams round-trip through the engine too.
    game.setKey(7);
    game.setScale(GrooveScale.majorPentatonic);
    await tester.pump();
    expect(game.key, 7);
    expect(game.scale, GrooveScale.majorPentatonic);
  });

  testWidgets('the dice rolls a fresh, always-full groove', (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);
    expect(game.enabledTracks, isEmpty);
    const melodic = {'melody', 'chords', 'sparkle', 'voice'};
    // Every roll anchors drums + at least one melodic voice and is never empty
    // (all content is one pentatonic, so any combination is consonant). Roll
    // many times to cover the randomness.
    for (var i = 0; i < 12; i++) {
      await tester.tap(find.byIcon(Icons.casino));
      await tester.pump();
      final on = game.enabledTracks;
      expect(on, isNotEmpty, reason: 'roll $i');
      expect(on, contains('drums'), reason: 'roll $i anchors drums');
      expect(
        on.any(melodic.contains),
        isTrue,
        reason: 'roll $i has a melodic voice',
      );
    }
  });

  testWidgets('long-pressing the variant badge rolls a random variant',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);
    game.toggleTrack('drums');
    await tester.pump();
    expect(game.variantOf('drums'), 0);

    // Long-press the drums variant badge → it rolls to a different variant.
    await tester.longPress(
      find
          .descendant(
            of: find.byType(CircleAvatar),
            matching: find.text('A'),
          )
          .first,
    );
    await tester.pump();
    expect(game.variantOf('drums'), isNot(0));
    expect(game.isPlaying, isTrue);

    // The seam rolls too (always lands in range).
    for (var i = 0; i < 10; i++) {
      game.rollTrackVariant('drums');
      expect(game.variantOf('drums'), inInclusiveRange(0, 3));
    }
  });

  testWidgets('style chips swap the whole-band flavour + bias', (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);
    expect(game.styleId, 'default');
    expect(game.tempoBpm, 100);

    game.toggleTrack('drums');
    game.toggleTrack('bass');
    await tester.pump();

    // Picking "Lounge" re-points the band and biases tempo/kit.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Lounge'));
    await tester.pump();
    expect(game.styleId, 'chill');
    expect(game.tempoBpm, 75);
    expect(game.kitId, 'lofi');
    // State carried across: the same layers stay enabled.
    expect(game.enabledTracks, {'drums', 'bass'});
    expect(game.isPlaying, isTrue);
    expect(tester.takeException(), isNull);

    // Back to Classic via the seam.
    game.setStyle('default');
    await tester.pump();
    expect(game.styleId, 'default');
  });

  testWidgets('kit chips swap the drum timbre', (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);
    expect(game.kitId, 'clean');

    game.toggleTrack('drums');
    await tester.pump();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Deep'));
    await tester.pump();
    expect(game.kitId, 'deep');
    expect(game.isPlaying, isTrue);
    expect(tester.takeException(), isNull);

    // Seam round-trips + an unknown id falls back to clean.
    game.setKit('lofi');
    await tester.pump();
    expect(game.kitId, 'lofi');
    game.setKit('nonsense');
    await tester.pump();
    expect(game.kitId, 'clean');
  });

  testWidgets('every track card shows a shape-creature', (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    // The five built-in layers each render their creature.
    expect(find.byType(LoopCreature), findsNWidgets(5));
  });

  testWidgets('a secret combo unlocks a reveal + a found counter',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);
    // Exactly drums + bass matches the "Rhythm Section" combo.
    game.toggleTrack('drums');
    await tester.pump();
    game.toggleTrack('bass');
    await tester.pump();
    expect(find.textContaining('Rhythm Section'), findsOneWidget);
    expect(find.text('1/${kLoopCombos.length}'), findsOneWidget);

    // Breaking the set hides the reveal; the counter persists at 1/N.
    game.toggleTrack('chords');
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('1/${kLoopCombos.length}'), findsOneWidget);
  });

  testWidgets('a groove saves to a slot and loads back', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);
    game.toggleTrack('drums');
    game.toggleTrack('bass');
    await tester.pump();
    await tester.runAsync(() => game.debugSaveGroove('MyJam'));
    expect(
      await tester.runAsync(game.debugSlotNames),
      contains('MyJam'),
    );

    // Clear the band, then load the saved slot back.
    game.toggleTrack('drums');
    game.toggleTrack('bass');
    await tester.pump();
    expect(game.enabledTracks, isEmpty);
    final ok = await tester.runAsync(() => game.debugLoadGroove('MyJam'));
    expect(ok, isTrue);
    await tester.pump();
    expect(game.enabledTracks, containsAll(['drums', 'bass']));
  });

  testWidgets('Save to Song Book is offered only when a pitched track plays',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);
    expect(game.hasPitchedTrack, isFalse);

    // Drums are unpitched — still nothing to engrave.
    game.toggleTrack('drums');
    await tester.pump();
    expect(game.hasPitchedTrack, isFalse);

    game.toggleTrack('melody');
    await tester.pump();
    expect(game.hasPitchedTrack, isTrue);

    // The share sheet exposes the two export entries. (The groove Ticker runs
    // forever, so settle with a timed pump rather than pumpAndSettle.)
    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Save to Song Book'), findsOneWidget);
    expect(find.text('Export sheet music (MusicXML)'), findsOneWidget);
  });

  testWidgets('saving a groove writes a multi-part score to the Song Book',
      (tester) async {
    final songs = UserSongsService();
    await pumpGame(
      tester,
      const LoopMixerScreen(),
      extraProviders: [
        ChangeNotifierProvider<UserSongsService>.value(value: songs),
      ],
    );
    final game = _game(tester);

    // Nothing pitched → nothing saved.
    expect(game.debugSaveToSongBook(songs), isNull);
    expect(songs.songs, isEmpty);

    game.toggleTrack('melody');
    game.toggleTrack('chords');
    await tester.pump();

    final xml = game.debugSaveToSongBook(songs);
    expect(xml, isNotNull);
    expect(songs.songs.length, 1);
    // Both enabled pitched tracks became named parts…
    expect(xml, contains('Melody'));
    expect(xml, contains('Chords'));
    // …and the stored song re-reads as an engravable score.
    expect(songs.songs.single.score.measures, isNotEmpty);
  });

  testWidgets('a captured voice layer joins the band as a real card',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);
    expect(game.hasVoiceTrack, isFalse);
    expect(find.text('Sing a track!'), findsOneWidget);

    game.debugCaptureCells(const [
      (midis: [64], steps: 8),
      (midis: [67], steps: 8),
    ]);
    await tester.pump();

    expect(game.hasVoiceTrack, isTrue);
    expect(game.enabledTracks, contains('voice'));
    expect(find.text('My voice'), findsOneWidget);
    expect(game.isPlaying, isTrue);

    // The voice card toggles like any other.
    await tester.tap(find.text('My voice'));
    await tester.pump();
    expect(game.enabledTracks, isNot(contains('voice')));
  });

  testWidgets('a captured beat joins the band; jam mode degrades gracefully',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);
    expect(game.hasBeatTrack, isFalse);
    expect(find.text('Beatbox a beat!'), findsOneWidget);

    game.debugCaptureBeat(
      DrumRowsPattern({Drum.kick: stepRow('x.......x.......')}),
    );
    await tester.pump();
    expect(game.hasBeatTrack, isTrue);
    expect(game.enabledTracks, contains('beat'));
    expect(find.text('My beat'), findsOneWidget);

    // Jam mode: no mic in the headless binding → the toggle must not throw
    // and must not report an active jam.
    game.toggleJam();
    await tester.pump();
    expect(game.isJamming, isFalse);
  });

  testWidgets(
      'AEC jam feeds the loop as reference and grades the cleaned '
      'near-end', (tester) async {
    final fake = FakeAecEngine();
    await pumpGame(tester, LoopMixerScreen(aecFactory: () => fake));
    final game = _game(tester);

    // Jam needs a groove to play/grade against.
    game.toggleTrack('melody');
    await tester.pump();

    game.toggleJam();
    await tester.pump(); // _startAecJam completes (fake start is instant)
    await tester
        .pump(const Duration(milliseconds: 120)); // reference pump ticks

    expect(game.isJamming, isTrue);
    expect(game.usesAecJam, isTrue, reason: 'picked the Tier-3b path');
    expect(fake.started, isTrue);
    // The loop PCM is pushed as the AEC reference (prime window + pump ticks).
    expect(fake.references, isNotEmpty);
    expect(fake.references.first, isNotEmpty);

    // The engine hands back a cleaned A4 (mic minus echo) → the jam grades it.
    final tone = _tonePcm16(440); // A4 = midi 69
    for (var i = 0; i < tone.length; i += 8192) {
      fake.emitCleaned(
        Uint8List.sublistView(tone, i, min(i + 8192, tone.length)),
      );
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(game.jamReading?.hasPitch, isTrue);
    expect(
      game.jamReading!.nearestMidi,
      69,
      reason: 'the cleaned near-end grades as A4',
    );

    // Stopping jam flips the visible state synchronously and tears the engine
    // down in the background.
    game.toggleJam();
    await tester.pump();
    expect(game.isJamming, isFalse);
    expect(game.usesAecJam, isFalse);
    // The async teardown (stop/dispose) needs the real event loop to settle.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(fake.stopped, isTrue);
  });

  testWidgets('follow-the-melody grades the player against the leading track',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);

    game.toggleTrack('melody');
    await tester.pump();
    expect(game.isFollowing, isFalse);

    // Turn follow on: it builds a chart over the leading track (melody).
    game.toggleFollow();
    await tester.pump();
    expect(game.isFollowing, isTrue);
    expect(game.followAccuracy, 0);

    // Play the target line perfectly: for each melody note, feed its own pitch
    // during its window (elapsedMs injected — the live grade reads a real
    // Stopwatch the test can't advance).
    final chart = grooveChart(
      LoopEngine().cellsFor('melody')!,
      bpm: game.tempoBpm,
      name: 'melody',
    );
    // Feed in order; each note is finalized (hit/miss) when the next arrives.
    // We stay within one loop pass — going past the end would wrap and re-arm.
    for (final n in chart.notes) {
      final midMs = (n.startBeat + n.beats / 2) * chart.beatMs;
      game.debugFeedFollow(
        PitchReading(
          frequency: 440.0 * pow(2.0, (n.midi - 69) / 12.0),
          clarity: 1,
          a4: kDefaultA4,
        ),
        midMs,
      );
    }
    await tester.pump();

    expect(
      game.followAccuracy,
      greaterThan(0),
      reason: 'playing the melody scores hits',
    );

    // Toggling follow off clears the grade.
    game.toggleFollow();
    await tester.pump();
    expect(game.isFollowing, isFalse);
    expect(game.followAccuracy, 0);
  });

  testWidgets('a groove code captures and restores the whole state',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);

    game.toggleTrack('drums');
    game.toggleTrack('melody');
    game.setSwing(0.2);
    game.setProgression('ballad');
    await tester.pump();
    final token = game.grooveToken;

    // Wipe everything, then load the code back.
    game.stopAll();
    game.setSwing(0);
    game.setProgression(null);
    await tester.pump();
    expect(game.enabledTracks, isEmpty);

    expect(game.loadGrooveToken(token), isTrue);
    await tester.pump();
    expect(game.enabledTracks, {'drums', 'melody'});
    expect(game.swing, closeTo(0.2, 1e-9));
    expect(game.progressionId, 'ballad');
    expect(game.isPlaying, isTrue, reason: 'a loaded groove starts playing');

    expect(game.loadGrooveToken('garbage'), isFalse);
  });

  testWidgets('every 4th loop schedules the drum fill at the seam',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);

    game.toggleTrack('drums');
    await tester.pump();
    expect(game.loopIteration, 0);

    // Wraps 1–2 keep the groove; the wrap into iteration 3 (the 4th loop)
    // swaps in the fill, the next wrap swaps back — none may throw with the
    // headless audio stub.
    for (var wrap = 1; wrap <= 5; wrap++) {
      game.debugLoopWrap();
      await tester.pump();
      expect(game.loopIteration, wrap);
    }

    // Infinite mode re-renders a variation at every seam without throwing.
    expect(game.isInfinite, isFalse);
    game.toggleInfinite();
    await tester.pump();
    expect(game.isInfinite, isTrue);
    game.debugLoopWrap();
    await tester.pump();
    expect(game.loopIteration, 6);
  });

  testWidgets('the smear pad toggles and plays in-key notes', (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);
    expect(game.smearPadVisible, isFalse);

    game.toggleSmearPad();
    await tester.pump();
    expect(game.smearPadVisible, isTrue);
    expect(find.byType(SmearPad), findsOneWidget);

    // Playing across the pad yields a rising run of C-pentatonic notes.
    for (final x in [0.0, 0.5, 1.0]) {
      game.debugSmearAt(x);
    }
    await tester.pump();
    expect(game.debugSmearNotes, isNotEmpty);
    expect(
      game.debugSmearNotes.every((m) => const {0, 2, 4, 7, 9}.contains(m % 12)),
      isTrue,
    );
    expect(game.debugSmearNotes.last, greaterThan(game.debugSmearNotes.first));
  });

  testWidgets('section scenes capture, relaunch, and chain at the seam',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);
    expect(game.sceneIsEmpty(0), isTrue);

    // Capture scene A = {drums, bass}.
    game.toggleTrack('drums');
    game.toggleTrack('bass');
    await tester.pump();
    game.captureScene(0);
    await tester.pump();
    expect(game.sceneIsEmpty(0), isFalse);

    // Capture scene B = {melody} only.
    game.toggleTrack('drums');
    game.toggleTrack('bass');
    game.toggleTrack('melody');
    await tester.pump();
    game.captureScene(1);

    // Relaunch A → the drums+bass layer set comes back.
    game.launchScene(0);
    await tester.pump();
    expect(game.enabledTracks, {'drums', 'bass'});

    // Chain auto-advances to the next captured scene (B) at the seam.
    game.toggleChain();
    await tester.pump();
    expect(game.isChaining, isTrue);
    game.debugLoopWrap();
    await tester.pump();
    expect(game.enabledTracks, {'melody'});

    // Launching an empty slot is a no-op.
    game.launchScene(3);
    await tester.pump();
    expect(game.enabledTracks, {'melody'});
  });

  testWidgets('quantized launch arms a card and fires it at the seam',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);

    // Start a groove so there's a running loop to quantize against.
    game.toggleTrack('drums');
    await tester.pump();
    expect(game.isPlaying, isTrue);

    game.toggleQuantize();
    await tester.pump();
    expect(game.quantizeLaunch, isTrue);

    // Toggling bass now ARMS it — it doesn't sound yet.
    game.toggleTrack('bass');
    await tester.pump();
    expect(game.pendingLaunches, contains('bass'));
    expect(game.enabledTracks, {'drums'}); // not yet live

    // The next loop seam applies the armed change.
    game.debugLoopWrap();
    await tester.pump();
    expect(game.pendingLaunches, isEmpty);
    expect(game.enabledTracks, {'drums', 'bass'});

    // Turning quantize off drops any armed (but not-yet-fired) changes.
    game.toggleTrack('drums'); // arm removal of drums
    await tester.pump();
    expect(game.pendingLaunches, contains('drums'));
    game.toggleQuantize();
    await tester.pump();
    expect(game.pendingLaunches, isEmpty);
    expect(game.enabledTracks, {'drums', 'bass'}); // drums stayed on
  });

  testWidgets('a band challenge is met by exploring and can be skipped',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);
    final firstId = game.currentChallengeId;
    expect(game.currentChallengeMet, isFalse);

    // Skipping moves to a different (still-unmet) prompt.
    game.nextChallenge();
    await tester.pump();
    expect(game.currentChallengeId, isNot(firstId));

    // Land on the "layers" challenge and satisfy it by stacking three.
    while (game.currentChallengeId != 'layers') {
      game.nextChallenge();
    }
    expect(game.currentChallengeMet, isFalse);
    game.toggleTrack('drums');
    game.toggleTrack('bass');
    game.toggleTrack('melody');
    await tester.pump();
    expect(game.currentChallengeMet, isTrue);
    // The banner celebrates when met.
    expect(find.text('Nice! Tap for another idea →'), findsOneWidget);
  });

  testWidgets('the master filter knob drives the engine', (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);
    game.toggleTrack('drums');
    await tester.pump();
    expect(game.masterFilter, 0);

    game.setMasterFilter(-0.8); // pull toward low-pass
    await tester.pump();
    expect(game.masterFilter, closeTo(-0.8, 1e-9));
    expect(game.isPlaying, isTrue);

    game.setMasterFilter(0);
    await tester.pump();
    expect(game.masterFilter, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the master send effect can be set and cleared', (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);
    expect(game.send, LoopSend.none);
    game.setSend(LoopSend.reverb);
    await tester.pump();
    expect(game.send, LoopSend.reverb);
    game.setSend(LoopSend.none);
    await tester.pump();
    expect(game.send, LoopSend.none);
    expect(tester.takeException(), isNull);
  });
}
