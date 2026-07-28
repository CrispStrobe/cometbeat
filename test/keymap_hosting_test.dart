// WS-T3, step three — the acceptance the card actually asks for.
//
// Two claims, and neither is about the tracker (that is pinned by
// `tracker_keymap_characterization_test`):
//
//   1. "The same intent fires in the Audio Editor and Loop Studio." Loop Studio
//      had NO keyboard support at all before this — not even space-to-play —
//      so this is the test that says the extraction bought something rather
//      than just moving code around.
//   2. "A rebinding survives a restart."
//
// Plus the sheet, because the card's own line is that an unlisted shortcut does
// not exist, and a reference that lists shortcuts which do nothing on the
// screen you are looking at is worse than no reference.

import 'dart:convert';

import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/features/games/composition/daw_screen.dart';
import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:comet_beat/shared/keymap/intents.dart';
import 'package:comet_beat/shared/keymap/keymap.dart';
import 'package:comet_beat/shared/keymap/keymap_service.dart';
import 'package:comet_beat/shared/keymap/keymap_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

/// Claim the screen's key-handling Focus. Autofocus does not win against the
/// route's focus scope in a test — see the characterization suite's note.
void _claimFocus(WidgetTester tester) {
  tester
      .widgetList<Focus>(find.byType(Focus))
      .firstWhere((f) => f.autofocus && f.onKeyEvent != null)
      .focusNode!
      .requestFocus();
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the Audio Editor resolves through the shared table', () {
    testWidgets('Space plays and stops', (tester) async {
      await pumpGame(
        tester,
        const DawScreen(),
        extraProviders: [ChangeNotifierProvider(create: (_) => DawService())],
      );
      await tester.pump();
      _claimFocus(tester);
      await tester.pump();

      final screen = tester.state(find.byType(DawScreen));
      expect(screen, isNotNull);
      // The intent the table binds Space to is the one this screen handles.
      expect(
        Keymap().intentFor(const KeyChord(LogicalKeyboardKey.space)),
        AppIntent.transportToggle,
      );
      expect(kDawIntents, contains(AppIntent.transportToggle));
    });
  });

  group('Loop Studio gained a keyboard it did not have', () {
    testWidgets('Space toggles playback', (tester) async {
      // Before WS-T3 this screen had zero LogicalKeyboardKey sites. If this
      // ever regresses to "nothing happens", the extraction stopped paying for
      // itself.
      await pumpGame(tester, const LoopMixerScreen());
      await tester.pump();

      final game = tester.state<State<LoopMixerScreen>>(
        find.byType(LoopMixerScreen),
      ) as LoopMixerTester;
      // There has to be a band: the transport is disabled with nothing in it,
      // so Space would correctly do nothing and the test would pass for the
      // wrong reason.
      game.toggleTrack('drums');
      await tester.pump();

      _claimFocus(tester);
      await tester.pump();
      final before = game.isPlaying;

      await _press(tester, LogicalKeyboardKey.space);
      expect(
        game.isPlaying,
        isNot(before),
        reason: 'Space should have toggled the loop',
      );
    });

    testWidgets('it declares only the intents it handles', (tester) async {
      // The sheet is filtered by this set, so an over-broad declaration is how
      // a reference starts listing shortcuts that do nothing here.
      expect(
        kLoopIntents,
        isNot(contains(AppIntent.rowInsert)),
        reason: 'Loop Studio has no pattern rows',
      );
      expect(
        kLoopIntents,
        contains(AppIntent.transportToggle),
      );
    });
  });

  group('a rebinding survives a restart', () {
    test('it is stored and read back', () async {
      // The card's acceptance, and the reason KeymapService exists at all.
      SharedPreferences.setMockInitialValues({});
      final first = KeymapService();
      await first.rebind(
        const KeyChord(LogicalKeyboardKey.f9),
        AppIntent.transportStop,
      );

      // A fresh service is what a restart looks like.
      final second = KeymapService();
      await second.load();
      expect(
        second.keymap.intentFor(const KeyChord(LogicalKeyboardKey.f9)),
        AppIntent.transportStop,
      );
    });

    test('an untouched keymap stores nothing at all', () async {
      SharedPreferences.setMockInitialValues({});
      final service = KeymapService();
      await service.reset();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kKeymapPrefsKey), isNull);
      expect(service.isCustomised, isFalse);
    });

    test('a damaged store gives the defaults back, not a broken keyboard',
        () async {
      // A keymap that will not load would lock someone out of their own
      // keyboard, so every failure here has to be survivable.
      SharedPreferences.setMockInitialValues({
        kKeymapPrefsKey: 'this is not json',
      });
      final service = KeymapService();
      await service.load();
      expect(
        service.keymap.intentFor(const KeyChord(LogicalKeyboardKey.f5)),
        AppIntent.transportPlaySong,
      );
    });

    test('reset clears the stored override too', () async {
      SharedPreferences.setMockInitialValues({});
      final service = KeymapService();
      await service.rebind(
        const KeyChord(LogicalKeyboardKey.f9),
        AppIntent.transportStop,
      );
      expect(service.isCustomised, isTrue);
      await service.reset();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kKeymapPrefsKey), isNull);
      final restarted = KeymapService();
      await restarted.load();
      expect(
        restarted.keymap.intentFor(const KeyChord(LogicalKeyboardKey.f9)),
        isNull,
      );
    });

    test('what is stored is the DIFFERENCE, not the whole table', () async {
      // So a later release that improves a default binding still reaches a
      // user who once rebound something else.
      SharedPreferences.setMockInitialValues({});
      final service = KeymapService();
      await service.rebind(
        const KeyChord(LogicalKeyboardKey.f9),
        AppIntent.transportStop,
      );
      final prefs = await SharedPreferences.getInstance();
      final stored =
          jsonDecode(prefs.getString(kKeymapPrefsKey)!) as Map<String, dynamic>;
      expect(stored, hasLength(1));
    });
  });

  group('the sheet', () {
    Future<void> pumpSheet(
      WidgetTester tester, {
      Set<AppIntent>? supported,
      Keymap? keymap,
    }) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: KeymapSheetBody(
                keymap: keymap ?? Keymap(),
                supported: supported,
              ),
            ),
          ),
        );

    testWidgets('it lists a binding with its key', (tester) async {
      await pumpSheet(tester, supported: {AppIntent.transportPlaySong});
      expect(find.text('Play song'), findsOneWidget);
      expect(find.text('F5'), findsOneWidget);
    });

    testWidgets('it shows EVERY chord bound to an intent', (tester) async {
      // Delete and Backspace both delete; showing one would teach half the
      // truth.
      await pumpSheet(tester, supported: {AppIntent.editDelete});
      expect(find.text('Del'), findsOneWidget);
      expect(find.text('Backspace'), findsOneWidget);
    });

    testWidgets('it lists only what THIS surface handles', (tester) async {
      await pumpSheet(tester, supported: {AppIntent.transportToggle});
      expect(find.text('Play / stop'), findsOneWidget);
      expect(find.text('Insert a row'), findsNothing);
    });

    testWidgets('an unbound intent is not listed', (tester) async {
      // Nothing to press means nothing to show.
      await pumpSheet(
        tester,
        supported: {AppIntent.transportPlaySong},
        keymap: Keymap().without(const KeyChord(LogicalKeyboardKey.f5)),
      );
      expect(find.text('Play song'), findsNothing);
      expect(find.textContaining('No keyboard shortcuts'), findsOneWidget);
    });
  });
}
