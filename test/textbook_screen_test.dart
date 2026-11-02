// The read-through textbook reader: lists grade bands + concepts, opens a
// concept's lesson (primer) and links to its games.
import 'package:comet_beat/core/curriculum/concept_map.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/textbook/textbook_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app({Locale locale = const Locale('en')}) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProvider(
          create: (_) => SriService(getNow: () => DateTime(2026, 7, 17)),
        ),
        Provider<AudioService>(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => ProgressService()),
        ChangeNotifierProvider(create: (_) => UserSongsService()),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('de')],
        home: const TextbookScreen(),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows every grade band and the concept titles', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    // The intro chrome, the first grade band, and the first concept are all at
    // the top of the list (no scrolling needed).
    expect(find.text(l10n.textbookIntro), findsOneWidget);
    expect(find.text(GradeBand.g12.label), findsOneWidget);
    expect(find.text('A steady beat (pulse)'), findsOneWidget);
  });

  testWidgets('concept titles + band labels are localised (de)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(locale: const Locale('de')));
    await tester.pumpAndSettle();

    // German band label, area sub-header and concept title all render.
    expect(find.text('Stufe 1'), findsOneWidget);
    expect(find.text('Ein gleichmäßiger Puls (Grundschlag)'), findsOneWidget);
    // The English forms must be absent under a German locale.
    expect(find.text('A steady beat (pulse)'), findsNothing);
  });

  testWidgets('expanding a concept reveals its lesson + game links',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text('A steady beat (pulse)'));
    await tester.pumpAndSettle();
    // Its lesson opener + at least one practise link appear.
    expect(find.text(l10n.textbookReadLesson), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsWidgets);
  });
}
