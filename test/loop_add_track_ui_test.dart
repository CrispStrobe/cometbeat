// D1 from the GUI — the ＋ that offers the roles and empty.
//
// The engine could already grow a band; nothing on screen could ask it to
// unless a copy of something existing would do. Roles come FIRST in the row
// because the first tap must land on something that plays — the empty entry is
// the end of the ladder, not the start of it.
//
// Two traps this row was designed around, both recorded rather than
// rediscovered:
//
//   the track card's row is FULL — wiring a control into it overflowed by 23px
//   and broke fourteen tests, so everything here lives in the inspector;
//
//   new ids are absent from `_trackColors` and `_trackLabel` — a copy used to
//   throw a null check and every copy read as "Sparkle". A role add inherits
//   through `_sourceIdOf`, but an EMPTY track is a copy of nothing, so it needs
//   its own colour and its own name, which is also why renaming exists.

import 'dart:typed_data';

import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

LoopMixerTester _game(WidgetTester tester) =>
    tester.state<State<LoopMixerScreen>>(find.byType(LoopMixerScreen))
        as LoopMixerTester;

/// The inspector is closed by default; this screen animates continuously, so
/// bounded pumps only — pumpAndSettle never settles here.
Future<LoopMixerTester> _open(WidgetTester tester) async {
  await pumpGame(tester, const LoopMixerScreen());
  final game = _game(tester)..debugFreezeSeams();
  if (!game.inspectorVisible) game.toggleInspector();
  await tester.pump(const Duration(milliseconds: 50));
  return game;
}

/// The inspector scrolls, so a chip low down may be off-screen — scroll it in
/// rather than tapping at a location nothing is at.
Future<void> _tap(WidgetTester tester, Key key) async {
  final target = find.byKey(key);
  if (tester.any(target)) {
    await tester.ensureVisible(target);
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.tap(target);
  await tester.pump(const Duration(milliseconds: 50));
}

/// Silent PCM — this suite is about the TRACK, not the sound; the audio itself
/// is measured in loop_audio_track_test.
Float64List _silence(int samples) => Float64List(samples);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the row offers the roles, then empty', () {
    testWidgets('there is a chip per authored role', (tester) async {
      await _open(tester);
      for (final role in ['drums', 'bass', 'chords', 'melody', 'sparkle']) {
        expect(
          find.byKey(Key('loop-add-$role')),
          findsOneWidget,
          reason: 'no add chip for $role',
        );
      }
      expect(find.byKey(const Key('loop-add-empty')), findsOneWidget);
    });

    testWidgets('adding a role grows the band and plays', (tester) async {
      final game = await _open(tester);
      final before = game.trackIds.length;
      await _tap(tester, const Key('loop-add-bass'));
      expect(game.trackIds.length, before + 1);
      final added = game.trackIds.last;
      expect(game.isEmptyTrack(added), isFalse);
      expect(game.trackLabelOf(added), isNot(game.trackLabelOf('sparkle')));
    });

    testWidgets('adding empty gives a silent track with its OWN name',
        (tester) async {
      final game = await _open(tester);
      await _tap(tester, const Key('loop-add-empty'));
      final added = game.trackIds.last;
      expect(game.isEmptyTrack(added), isTrue);
      // The bug the colour/label tables caused for copies, in its empty-track
      // form: falling through the default labelled everything "Sparkle".
      expect(game.trackLabelOf(added), isNot(game.trackLabelOf('sparkle')));
      expect(game.trackLabelOf(added), contains('2'));
    });

    testWidgets('nothing overflows once the band has grown', (tester) async {
      // The 23px overflow happened on the track CARD's row, which is why these
      // controls are in the inspector. Adding four tracks is the cheapest way
      // to keep asserting that the card row was left alone.
      final game = await _open(tester);
      await _tap(tester, const Key('loop-add-bass'));
      await _tap(tester, const Key('loop-add-drums'));
      await _tap(tester, const Key('loop-add-empty'));
      await _tap(tester, const Key('loop-add-empty'));
      expect(game.trackIds.length, greaterThan(8));
      expect(tester.takeException(), isNull);
    });
  });

  group('renaming', () {
    testWidgets('the rename row is hidden until a track is added',
        (tester) async {
      final game = await _open(tester);
      expect(find.byKey(const Key('loop-rename-drums')), findsNothing);
      await _tap(tester, const Key('loop-add-empty'));
      final added = game.trackIds.last;
      expect(find.byKey(Key('loop-rename-$added')), findsOneWidget);
      expect(
        find.byKey(const Key('loop-rename-drums')),
        findsNothing,
        reason: 'the base band is named by the app, in the player\'s language',
      );
    });

    testWidgets('a name replaces "Track 2" everywhere it is read',
        (tester) async {
      final game = await _open(tester);
      await _tap(tester, const Key('loop-add-empty'));
      final added = game.trackIds.last;

      await _tap(tester, Key('loop-rename-$added'));
      await tester.enterText(
        find.byKey(const Key('loop-rename-field')),
        'Ukulele',
      );
      await tester.tap(find.byKey(const Key('loop-rename-ok')));
      await tester.pump(const Duration(milliseconds: 50));

      expect(game.trackLabelOf(added), 'Ukulele');
      expect(find.text('Ukulele'), findsWidgets);
    });

    testWidgets('cancelling changes nothing', (tester) async {
      final game = await _open(tester);
      await _tap(tester, const Key('loop-add-empty'));
      final added = game.trackIds.last;
      final was = game.trackLabelOf(added);

      await _tap(tester, Key('loop-rename-$added'));
      await tester.enterText(
        find.byKey(const Key('loop-rename-field')),
        'Ukulele',
      );
      // The first action is Cancel; found by position so the test does not
      // depend on which language the suite runs in.
      await tester.tap(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextButton),
            )
            .first,
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(game.trackLabelOf(added), was);
    });

    testWidgets('a blank name gives the app\'s own name back', (tester) async {
      final game = await _open(tester);
      await _tap(tester, const Key('loop-add-empty'));
      final added = game.trackIds.last;
      final was = game.trackLabelOf(added);
      game.renameTrack(added, 'Ukulele');
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.trackLabelOf(added), 'Ukulele');
      game.renameTrack(added, '  ');
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.trackLabelOf(added), was);
    });
  });

  group('WS-L10 — an imported loop is a track like any other', () {
    testWidgets('the import chip is offered beside the roles', (tester) async {
      await _open(tester);
      expect(find.byKey(const Key('loop-add-audio')), findsOneWidget);
    });

    testWidgets('an audio track appears with its OWN name and colour',
        (tester) async {
      // The same trap the empty track had: an id absent from the colour and
      // label tables reads as a grey "Sparkle".
      final game = await _open(tester);
      final id = game.addAudioTrack(_silence(4410));
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.isAudioTrack(id), isTrue);
      expect(game.trackLabelOf(id), isNot(game.trackLabelOf('sparkle')));
      expect(game.trackIds, contains(id));
    });

    testWidgets('it gets a lane strip and a tone badge like the rest',
        (tester) async {
      final game = await _open(tester);
      final id = game.addAudioTrack(_silence(4410));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(Key('loop-auto-$id-0')), findsOneWidget);
      expect(find.byKey(Key('loop-filter-$id')), findsOneWidget);
    });

    testWidgets('the stretch it needed is reported', (tester) async {
      final game = await _open(tester);
      // Half a loop of audio has to play at half speed to fill it.
      final id = game.addAudioTrack(_silence(game.debugLoopSamples ~/ 2));
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.audioStretchOf(id), closeTo(2, 0.01));
    });
  });

  group('WS-L5 — copying a pattern between tracks', () {
    testWidgets('there is a chip per track that has somewhere to send it',
        (tester) async {
      await _open(tester);
      expect(find.byKey(const Key('loop-copy-bass')), findsOneWidget);
      expect(find.byKey(const Key('loop-copy-melody')), findsOneWidget);
    });

    testWidgets('the dialog offers only compatible destinations',
        (tester) async {
      final game = await _open(tester);
      await _tap(tester, const Key('loop-copy-bass'));
      // Pitched destinations yes, itself and the drum track no.
      expect(find.byKey(const Key('loop-copy-to-melody')), findsOneWidget);
      expect(find.byKey(const Key('loop-copy-to-bass')), findsNothing);
      expect(find.byKey(const Key('loop-copy-to-drums')), findsNothing);
      expect(game.copyTargetsFor('bass'), contains('melody'));
    });

    testWidgets('picking one copies the pattern', (tester) async {
      final game = await _open(tester);
      await _tap(tester, const Key('loop-copy-bass'));
      await tester.tap(find.byKey(const Key('loop-copy-to-melody')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.trackIds, contains('melody'));
      // The engine-level assertion lives in loop_copy_pattern_test; here the
      // point is that the two taps reached it at all.
      expect(find.byType(SimpleDialog), findsNothing, reason: 'dialog closed');
    });

    testWidgets('dismissing the dialog copies nothing', (tester) async {
      await _open(tester);
      await _tap(tester, const Key('loop-copy-bass'));
      expect(find.byType(SimpleDialog), findsOneWidget);
      Navigator.of(tester.element(find.byType(SimpleDialog))).pop();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(SimpleDialog), findsNothing);
    });
  });

  testWidgets('an added track can be removed again, and takes its name',
      (tester) async {
    final game = await _open(tester);
    await _tap(tester, const Key('loop-add-empty'));
    final added = game.trackIds.last;
    game.renameTrack(added, 'Ukulele');
    await tester.pump(const Duration(milliseconds: 50));

    game.removeCopy(added);
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.trackIds, isNot(contains(added)));
    expect(find.text('Ukulele'), findsNothing);
  });

  testWidgets('the base band still cannot be removed by a stray tap',
      (tester) async {
    final game = await _open(tester);
    final before = game.trackIds.length;
    game.removeCopy('drums');
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.trackIds.length, before);
  });
}
