import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/composition/ending_detective_screen.dart';
import 'package:klang_universum/features/games/composition/my_melody_screen.dart';
import 'package:klang_universum/features/games/composition/question_answer_screen.dart';
import 'package:klang_universum/features/games/songs/user_songs_service.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:partitura/partitura.dart'
    show InteractiveStaff, StaffView, scoreFromMusicXml;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child, SriService sri, {UserSongsService? songs}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SriService>.value(value: sri),
      Provider<AudioService>(create: (_) => AudioService()),
      ChangeNotifierProvider(create: (_) => ProgressService()),
      ChangeNotifierProvider<UserSongsService>.value(
        value: songs ?? UserSongsService(),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('de')],
      home: child,
    ),
  );
}

void main() {
  late SriService sri;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sri = SriService(getNow: () => DateTime(2026, 7, 11));
  });

  testWidgets('ending detective asks finished-or-not and records',
      (tester) async {
    await tester.pumpWidget(_wrap(const EndingDetectiveScreen(), sri));
    await tester.pump();

    expect(find.textContaining('sound finished'), findsOneWidget);
    expect(find.byType(StaffView), findsOneWidget);
    expect(find.text('Finished!'), findsOneWidget);
    expect(find.text('Not yet...'), findsOneWidget);

    await tester.tap(find.text('Finished!'));
    await tester.pump();
    expect(sri.getDetailedBreakdown()['composition']!.keys, ['closure']);
    await tester.pumpAndSettle();
  });

  testWidgets('question & answer shows the question and two answer cards',
      (tester) async {
    await tester.pumpWidget(_wrap(const QuestionAnswerScreen(), sri));
    await tester.pump();

    expect(find.textContaining('asks a question'), findsOneWidget);
    // 1 question staff + 2 answer cards.
    expect(find.byType(StaffView), findsNWidgets(3));

    await tester.tap(find.byType(StaffView).at(1));
    await tester.pump();
    expect(sri.getDetailedBreakdown()['composition']!.keys, ['answer']);
    await tester.pumpAndSettle();
  });

  testWidgets('my melody sandbox: place, play, undo, clear', (tester) async {
    await tester.pumpWidget(_wrap(const MyMelodyScreen(), sri));
    await tester.pump();

    expect(find.textContaining('write your melody'), findsOneWidget);
    expect(find.byType(InteractiveStaff), findsOneWidget);

    // Play/Undo/Clear disabled while empty.
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Play'),
          )
          .onPressed,
      isNull,
    );

    // Tap the middle of the staff to place a note.
    final staff = tester.getRect(find.byType(InteractiveStaff));
    await tester.tapAt(staff.center);
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Play'),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Play'),
          )
          .onPressed,
      isNull,
    );
    // Sandbox records nothing.
    expect(sri.totalTrackedItems, 0);
    await tester.pumpAndSettle();
  });

  testWidgets('my melody saves to the Song Book as valid MusicXML',
      (tester) async {
    final songs = UserSongsService();
    await tester.pumpWidget(_wrap(const MyMelodyScreen(), sri, songs: songs));
    await tester.pump();

    // Place a few notes across the staff.
    final staff = tester.getRect(find.byType(InteractiveStaff));
    for (final dy in [-20.0, 0.0, 20.0, 10.0, -10.0]) {
      await tester.tapAt(staff.center + Offset(0, dy));
      await tester.pump();
    }

    // Open the save dialog and confirm with the default name.
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Name your melody'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Save'),
      ),
    );
    await tester.pumpAndSettle();

    // It landed in the Song Book and round-trips back to a real score.
    expect(songs.songs, hasLength(1));
    final saved = songs.songs.single;
    expect(saved.title, 'My melody');
    final score = scoreFromMusicXml(saved.musicXml);
    expect(score.measures, isNotEmpty);
    expect(find.text('Saved to the Song Book!'), findsOneWidget);
  });
}
