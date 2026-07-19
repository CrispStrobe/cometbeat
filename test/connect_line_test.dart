// Connect the Notes — the connect-a-line matching drill. Drives real drag
// gestures on the board: linking a note to its matching name locks it, a wrong
// drop does not connect, and clearing all pairs advances the round.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/connect_line_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app({ConnectMode mode = ConnectMode.notes}) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProvider(
          create: (_) => SriService(getNow: () => DateTime(2026, 7, 11)),
        ),
        Provider<AudioService>(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => ProgressService()),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('de')],
        home: ConnectLineScreen(mode: mode),
      ),
    );

ConnectLineTester _game(WidgetTester tester) =>
    tester.state<State<ConnectLineScreen>>(find.byType(ConnectLineScreen))
        as ConnectLineTester;

/// Drag from left row [i] to right row [j] on the board.
Future<void> _drag(WidgetTester tester, int i, int j) async {
  final rect = tester.getRect(find.byKey(ConnectLineScreen.boardKey));
  final rowH = rect.height / ConnectLineScreen.pairs;
  final from = Offset(rect.left + 26, rect.top + rowH * i + rowH / 2);
  final to = Offset(rect.right - 26, rect.top + rowH * j + rowH / 2);
  final gesture = await tester.startGesture(from);
  await gesture.moveBy(const Offset(24, 0)); // clear the pan slop
  await gesture.moveTo(to);
  await gesture.up();
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a wrong drop does not connect', (tester) async {
    await tester.pumpWidget(_app());
    final game = _game(tester);

    final right = game.matchingRight(0);
    final wrong = (right + 1) % ConnectLineScreen.pairs;
    await _drag(tester, 0, wrong);

    expect(game.matchedCount, 0);
  });

  testWidgets('linking every note to its name clears and advances the round',
      (tester) async {
    await tester.pumpWidget(_app());
    final game = _game(tester);
    expect(game.round, 0);

    for (var i = 0; i < ConnectLineScreen.pairs; i++) {
      await _drag(tester, i, game.matchingRight(i));
    }
    expect(game.matchedCount, ConnectLineScreen.pairs);

    // Clearing the board auto-advances (700ms in QuizRoundMixin).
    await tester.pump(const Duration(milliseconds: 800));
    expect(game.round, 1);
    expect(game.score, greaterThan(0));
  });

  testWidgets('symbols mode: matching each glyph to its name clears the round',
      (tester) async {
    await tester.pumpWidget(_app(mode: ConnectMode.symbols));
    final game = _game(tester);

    for (var i = 0; i < ConnectLineScreen.pairs; i++) {
      await _drag(tester, i, game.matchingRight(i));
    }
    expect(game.matchedCount, ConnectLineScreen.pairs);

    await tester.pump(const Duration(milliseconds: 800));
    expect(game.round, 1);
    expect(game.score, greaterThan(0));
  });

  testWidgets('intervals mode: matching each interval to its number clears it',
      (tester) async {
    await tester.pumpWidget(_app(mode: ConnectMode.intervals));
    final game = _game(tester);

    for (var i = 0; i < ConnectLineScreen.pairs; i++) {
      await _drag(tester, i, game.matchingRight(i));
    }
    expect(game.matchedCount, ConnectLineScreen.pairs);

    await tester.pump(const Duration(milliseconds: 800));
    expect(game.round, 1);
    expect(game.score, greaterThan(0));
  });

  testWidgets('degrees mode: matching each number to its name clears the round',
      (tester) async {
    await tester.pumpWidget(_app(mode: ConnectMode.degrees));
    final game = _game(tester);

    for (var i = 0; i < ConnectLineScreen.pairs; i++) {
      await _drag(tester, i, game.matchingRight(i));
    }
    expect(game.matchedCount, ConnectLineScreen.pairs);

    await tester.pump(const Duration(milliseconds: 800));
    expect(game.round, 1);
    expect(game.score, greaterThan(0));
  });

  testWidgets(
      'dynamics mode: matching each mark to its meaning clears the round'
      ' and records under reading.dynamics', (tester) async {
    await tester.pumpWidget(_app(mode: ConnectMode.dynamics));
    final game = _game(tester);
    // The SriService lives in the provider tree; read it off the element.
    final sri = Provider.of<SriService>(
      tester.element(find.byType(ConnectLineScreen)),
      listen: false,
    );

    for (var i = 0; i < ConnectLineScreen.pairs; i++) {
      await _drag(tester, i, game.matchingRight(i));
    }
    expect(game.matchedCount, ConnectLineScreen.pairs);
    expect(sri.getDetailedBreakdown()['reading']!.keys, ['dynamics']);

    await tester.pump(const Duration(milliseconds: 800));
    expect(game.round, 1);
    expect(game.score, greaterThan(0));
  });

  testWidgets(
      'rests mode: matching each rest to its note clears the round'
      ' and records under note_values.rest', (tester) async {
    await tester.pumpWidget(_app(mode: ConnectMode.rests));
    final game = _game(tester);
    final sri = Provider.of<SriService>(
      tester.element(find.byType(ConnectLineScreen)),
      listen: false,
    );

    for (var i = 0; i < ConnectLineScreen.pairs; i++) {
      await _drag(tester, i, game.matchingRight(i));
    }
    expect(game.matchedCount, ConnectLineScreen.pairs);
    expect(sri.getDetailedBreakdown()['note_values']!.keys, ['rest']);

    await tester.pump(const Duration(milliseconds: 800));
    expect(game.round, 1);
    expect(game.score, greaterThan(0));
  });

  testWidgets(
      'tempo mode: matching each word to its meaning clears the round'
      ' and records under reading.tempo', (tester) async {
    await tester.pumpWidget(_app(mode: ConnectMode.tempo));
    final game = _game(tester);
    final sri = Provider.of<SriService>(
      tester.element(find.byType(ConnectLineScreen)),
      listen: false,
    );

    for (var i = 0; i < ConnectLineScreen.pairs; i++) {
      await _drag(tester, i, game.matchingRight(i));
    }
    expect(game.matchedCount, ConnectLineScreen.pairs);
    expect(sri.getDetailedBreakdown()['reading']!.keys, ['tempo']);

    await tester.pump(const Duration(milliseconds: 800));
    expect(game.round, 1);
    expect(game.score, greaterThan(0));
  });

  testWidgets(
      'beats mode: matching each note to its beat count clears the round'
      ' and records under note_values.beats', (tester) async {
    await tester.pumpWidget(_app(mode: ConnectMode.beats));
    final game = _game(tester);
    final sri = Provider.of<SriService>(
      tester.element(find.byType(ConnectLineScreen)),
      listen: false,
    );

    for (var i = 0; i < ConnectLineScreen.pairs; i++) {
      await _drag(tester, i, game.matchingRight(i));
    }
    expect(game.matchedCount, ConnectLineScreen.pairs);
    expect(sri.getDetailedBreakdown()['note_values']!.keys, ['beats']);

    await tester.pump(const Duration(milliseconds: 800));
    expect(game.round, 1);
    expect(game.score, greaterThan(0));
  });
}
