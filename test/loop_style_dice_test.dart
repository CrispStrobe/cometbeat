// Style catalog phase 2: per-track dice, lock pins, gallery auditions.
// A lock must make a track survive EVERY dice (whole-groove and per-track),
// a per-track roll must touch nothing else, and both must survive the share
// token and undo (which restores a spec snapshot).

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/loop_style_recipes.dart';
import 'package:comet_beat/core/audio/wav_io.dart';
import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:comet_beat/features/games/composition/loop_style_gallery.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

/// Everything a track can play, as text (all three variants).
String _content(LoopEngine e, String id) {
  final track = e.tracks.firstWhere((t) => t.id == id);
  return [
    for (final v in track.variants)
      switch (v) {
        MelodicPattern(:final instrument, :final cells) =>
          '${instrument.name}:${[
            for (final c in cells) '${c.midis}/${c.steps}',
          ].join(' ')}',
        DrumRowsPattern(:final rows) => [
            for (final MapEntry(:key, :value) in rows.entries)
              '${key.name}=${rowToString(value)}',
          ].join(' '),
        _ => '?',
      },
  ].join(' | ');
}

Map<String, String> _all(LoopEngine e) =>
    {for (final id in kRecipeTrackIds) id: _content(e, id)};

void main() {
  group('per-track dice', () {
    test('re-rolls only that track, within the current style', () {
      final e = LoopEngine()..setRecipe('pop', 10);
      final before = _all(e);
      expect(e.rollTrack('melody', 999), isTrue);
      final after = _all(e);
      expect(after['melody'], isNot(before['melody']));
      for (final id in kRecipeTrackIds.where((id) => id != 'melody')) {
        expect(after[id], before[id], reason: id);
      }
      expect(e.recipeId, 'pop');
      expect(e.trackPins['melody'], const RecipePin('pop', 999));
    });

    test('a locked track refuses; nothing changes', () {
      final e = LoopEngine()..setRecipe('funk', 3);
      final before = _all(e);
      e.lockedTracks.add('bass');
      expect(e.rollTrack('bass', 12345), isFalse);
      expect(_all(e), before);
    });

    test('no-op on a hand-authored band', () {
      final e = LoopEngine();
      expect(e.rollTrack('bass', 1), isFalse);
    });
  });

  group('whole-groove dice keeps locked tracks', () {
    test('locked parts survive a style + seed change exactly', () {
      final e = LoopEngine()
        ..setRecipe('reggae', 5)
        ..variants['bass'] = 2;
      final bass = _content(e, 'bass');
      final drums = _content(e, 'drums');
      e.lockedTracks.addAll({'bass', 'drums'});
      e.rollGroove('house', 77);
      expect(e.recipeId, 'house');
      expect(_content(e, 'bass'), bass);
      expect(_content(e, 'drums'), drums);
      expect(e.variants['bass'], 2, reason: 'a lock keeps the variant too');
      expect(
        _content(e, 'melody'),
        isNot(_all(LoopEngine()..setRecipe('reggae', 5))['melody']),
      );
      expect(e.trackPins.keys.toSet(), {'bass', 'drums'});
    });

    test('a per-track roll is kept by a later lock + groove roll', () {
      final e = LoopEngine()..setRecipe('pop', 1);
      e.rollTrack('chords', 4242);
      final chords = _content(e, 'chords');
      e.lockedTracks.add('chords');
      e.rollGroove('bossa', 2);
      expect(_content(e, 'chords'), chords);
      expect(e.trackPins['chords'], const RecipePin('pop', 4242));
    });

    test('unlocked rolls drop stale pins (a fresh groove)', () {
      final e = LoopEngine()..setRecipe('pop', 1);
      e.rollTrack('chords', 4242);
      e.rollGroove('pop', 2);
      expect(e.trackPins, isEmpty);
    });

    test('pins travel in the token and undo (spec snapshots) restores them',
        () {
      final e = LoopEngine()
        ..setRecipe('swing', 8)
        ..enabled.addAll({'drums', 'bass'});
      final snapshot = e.spec;
      final contentBefore = _all(e);
      e.rollTrack('bass', 31337);
      final rolled = _all(e);
      final token = encodeGrooveToken(e.spec);

      // Undo = apply the earlier snapshot.
      e.applySpec(snapshot);
      expect(_all(e), contentBefore);

      // Redo / share = the token restores the rolled bass.
      final f = LoopEngine()..applySpec(decodeGrooveToken(token)!);
      expect(_all(f), rolled);
    });
  });

  group('gallery audition', () {
    test('the preview render is a full loop of the style', () {
      final wav = renderStylePreviewSync('lofi');
      final data = readWavPcm16(wav);
      final e = LoopEngine()..setRecipe('lofi', kStylePreviewSeed);
      expect(data.samples.length ~/ data.channels, e.timing.totalSamples);
      expect(data.samples.any((s) => s.abs() > 300), isTrue);
    });

    testWidgets('play toggles an audition, pauses the host, stops on leave',
        (tester) async {
      final rendered = <String>[];
      var paused = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: LoopStyleGallery(
              currentRecipeId: null,
              onPick: (_) {},
              onRoll: () {},
              onPreviewStart: () => paused++,
              previewRender: (id) async {
                rendered.add(id);
                return renderStylePreviewSync(id);
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('loop-style-preview-pop')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(rendered, ['pop']);
      expect(paused, 1);
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);

      // Tap again → stop.
      await tester.tap(find.byKey(const Key('loop-style-preview-pop')));
      await tester.pump();
      expect(find.byIcon(Icons.stop_circle_outlined), findsNothing);

      // Leaving the gallery disposes the player without throwing.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });
  });

  group('track cards', () {
    testWidgets('dice + lock appear with a generated style and work',
        (tester) async {
      await pumpGame(tester, const LoopMixerScreen());
      final game = tester.state<State<LoopMixerScreen>>(
        find.byType(LoopMixerScreen),
      ) as LoopMixerTester;
      expect(find.byKey(const Key('loop-track-dice-Bass')), findsNothing);

      game.pickStyleRecipe('pop', seed: 1);
      await tester.pump();
      expect(find.byKey(const Key('loop-track-dice-Bass')), findsOneWidget);

      await tester.tap(find.byKey(const Key('loop-track-lock-Bass')));
      await tester.pump();
      expect(game.isTrackLocked('bass'), isTrue);
      // The 🎲 is disabled while locked.
      final dice = tester.widget<IconButton>(
        find.byKey(const Key('loop-track-dice-Bass')),
      );
      expect(dice.onPressed, isNull);

      // The whole-groove 🎲 leaves the locked bass alone.
      game.rollStyleGroove();
      await tester.pump();
      expect(game.recipeId, isNot('pop'));
      expect(game.isTrackLocked('bass'), isTrue);

      await tester.tap(find.byKey(const Key('loop-track-lock-Bass')));
      await tester.pump();
      expect(game.isTrackLocked('bass'), isFalse);
      // Unlocked, the per-track 🎲 rolls it (one undoable edit).
      await tester.tap(find.byKey(const Key('loop-track-dice-Bass')));
      await tester.pump();
      expect(game.canUndo, isTrue);
    });
  });
}
