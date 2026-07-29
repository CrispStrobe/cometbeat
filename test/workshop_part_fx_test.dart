// WS-X3 in the Score screen — the last mode without an effect surface.
//
// `score_fx_test.dart` proves the model half: a chain stored on a part survives
// MusicXML and changes the sound. What is left to prove here is the join —
// that a chain set in the Workshop reaches the DOCUMENT and therefore the
// screen's own exports, which is where Score differs from every other mode
// (its save IS the export).
//
// Deliberately not a test of the rack widget: `fx_rack_test.dart` covers that,
// and pumping a bottom sheet to prove a shared widget still works would test
// the wrong thing.

import 'package:comet_beat/core/audio/fx/fx_chain_codec.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:comet_beat/core/audio/score_fx.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/core/services/project_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/workshop/screens/composition_workshop_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show scoreFromMusicXml;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app() => MultiProvider(
      providers: [
        Provider<AudioService>(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => ProjectService()),
        ChangeNotifierProvider(create: (_) => UserSongsService()),
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProvider(create: (_) => DawService()),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('en'), Locale('de')],
        home: CompositionWorkshopScreen(),
      ),
    );

CompositionWorkshopTester _editor(WidgetTester tester) =>
    tester.state<State<CompositionWorkshopScreen>>(
      find.byType(CompositionWorkshopScreen),
    ) as CompositionWorkshopTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a chain set on a part reaches the MusicXML export', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    final editor = _editor(tester);

    editor.setPartFxChain(0, parseFxChain('lowpass freq=400').chain);
    await tester.pumpAndSettle();

    final (_, xml) = await editor.debugGenerateExport('musicxml');
    expect(xml, isNotNull);
    // Through the real reader, not a string match: what matters is that the
    // chain comes BACK, which is what reopening the score does.
    final chain = scoreFxChain(scoreFromMusicXml(xml!).metadata);
    expect(chain.map((f) => f.type), [FxType.lowpass]);
  });

  testWidgets('clearing it leaves no trace in the export', (tester) async {
    // A rack someone opened and emptied must export like one that never
    // existed — otherwise every glanced-at score carries a metadata block
    // forever, and diffs of "unchanged" files stop being empty.
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    final editor = _editor(tester);

    final (_, before) = await editor.debugGenerateExport('musicxml');
    editor.setPartFxChain(0, parseFxChain('lowpass freq=400').chain);
    await tester.pumpAndSettle();
    editor.setPartFxChain(0, const []);
    await tester.pumpAndSettle();
    final (_, after) = await editor.debugGenerateExport('musicxml');

    expect(after, before);
    expect(after, isNot(contains('miscellaneous')));
  });

  testWidgets('a score with no chain exports exactly as it did', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    final (_, xml) = await _editor(tester).debugGenerateExport('musicxml');
    expect(xml, isNot(contains(kScoreFxKey)));
  });
}
