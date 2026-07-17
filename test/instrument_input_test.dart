import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/features/games/composition/my_melody_screen.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/midi_pitch.dart';
import 'package:comet_beat/shared/widgets/cello_fingerboard.dart';
import 'package:comet_beat/shared/widgets/guitar_fretboard.dart';
import 'package:comet_beat/shared/widgets/piano_keyboard.dart';
import 'package:crisp_notation/crisp_notation.dart' show Step;
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrapBare(Widget child) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('de')],
      home: ChangeNotifierProvider<SettingsService>(
        create: (_) => SettingsService(),
        child: Scaffold(body: child),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('pitchFromMidi', () {
    test('spells naturals and sharps', () {
      expect(pitchFromMidi(60).step, Step.c);
      expect(pitchFromMidi(60).octave, 4);
      expect(pitchFromMidi(61).step, Step.c);
      expect(pitchFromMidi(61).alter, 1); // C#
      expect(pitchFromMidi(67).step, Step.g);
      expect(pitchFromMidi(57).step, Step.a);
      expect(pitchFromMidi(57).octave, 3);
      expect(pitchFromMidi(43).step, Step.g); // low cello G2
    });

    test('round-trips through midiNumber', () {
      for (final midi in [36, 43, 50, 57, 60, 64, 72]) {
        expect(pitchFromMidi(midi).midiNumber, midi);
      }
    });
  });

  testWidgets('guitar fretboard: top-left cell plays the open high-E (64)',
      (tester) async {
    int? tapped;
    await tester.pumpWidget(
      _wrapBare(GuitarFretboard(onTap: (m) => tapped = m)),
    );
    await tester.tap(find.byType(GestureDetector).first);
    expect(tapped, 64); // string 1 (E4), fret 0
  });

  testWidgets('cello fingerboard: first cell plays the open A string (57)',
      (tester) async {
    int? tapped;
    await tester.pumpWidget(
      _wrapBare(CelloFingerboard(onTap: (m) => tapped = m)),
    );
    await tester.tap(find.byType(GestureDetector).first);
    expect(tapped, 57); // A3 open
  });

  testWidgets('My Melody: entering a note via the piano enables playback',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AudioService>(create: (_) => AudioService()),
          ChangeNotifierProvider(create: (_) => UserSongsService()),
          ChangeNotifierProvider(create: (_) => SettingsService()),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('en'), Locale('de')],
          home: MyMelodyScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to the piano input surface.
    await tester.tap(find.text('Piano'));
    await tester.pumpAndSettle();
    expect(find.byType(PianoKeyboard), findsOneWidget);

    // Play button starts disabled (no notes yet).
    FilledButton playBtn() => tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('Play'),
            matching: find.byType(FilledButton),
          ),
        );
    expect(playBtn().onPressed, isNull);

    // Tap a piano key — a note is entered, so playback enables.
    await tester.tap(
      find
          .descendant(
            of: find.byType(PianoKeyboard),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(playBtn().onPressed, isNotNull);
  });
}
