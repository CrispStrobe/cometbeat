// The Looking-Glass inspector: describes a score element (note name + scale
// degree + chord/roman/function) using the analysis engine, and renders that
// description as a card (inspectBody).
import 'package:comet_beat/features/games/composition/music_inspect.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart' as cn;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

cn.Pitch note(String s) {
  final m = RegExp(r'^([a-g])([#b]*)(-?\d+)$').firstMatch(s)!;
  final step = cn.Step.values.firstWhere((st) => st.name == m[1]);
  final acc = m[2]!;
  final alter =
      acc.isEmpty ? 0 : (acc.startsWith('#') ? acc.length : -acc.length);
  return cn.Pitch(step, alter: alter, octave: int.parse(m[3]!));
}

cn.Score _chord(List<String> notes, String id) => cn.Score(
      clef: cn.Clef.treble,
      measures: [
        cn.Measure([
          cn.NoteElement(
            pitches: [for (final n in notes) note(n)],
            duration: const cn.NoteDuration(cn.DurationBase.whole),
            id: id,
          ),
        ]),
      ],
    );

void main() {
  test('describes a chord tone: note names + roman numeral + function', () {
    final score = _chord(['c4', 'e4', 'g4'], 'x');
    final analysis = cn.analyze(score);
    final info = inspectElement(score, 'x', analysis);

    expect(info, isNotNull);
    expect(info!.noteNames, 'C4 E4 G4');
    expect(info.chordSymbol, 'C');
    expect(info.roman, 'I');
    expect(info.function, cn.HarmonicFunction.tonic);
    expect(info.degree, contains('tonic')); // C is the tonic of C major
  });

  test('returns null for an id that is not in the score', () {
    final score = _chord(['c4', 'e4', 'g4'], 'x');
    expect(inspectElement(score, 'nope', cn.analyze(score)), isNull);
  });

  group('inspectBody (the card)', () {
    Future<void> pumpBody(WidgetTester tester, InspectInfo info) {
      return tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('de')],
          home: Scaffold(
            body: Builder(builder: (context) => inspectBody(context, info)),
          ),
        ),
      );
    }

    testWidgets('renders the full card: chord row, function, detail, NCT',
        (tester) async {
      await pumpBody(
        tester,
        const InspectInfo(
          noteNames: 'C4 E4 G4',
          degree: 'the 1st (tonic) of C major',
          chordSymbol: 'C',
          roman: 'I',
          function: cn.HarmonicFunction.tonic,
          isNonChordTone: true,
          detail: 'Instrument 1 · A04',
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('C4 E4 G4'), findsOneWidget);
      expect(find.text('the 1st (tonic) of C major'), findsOneWidget);
      // chord · roman · function, joined.
      expect(find.text('C · I · Home (tonic)'), findsOneWidget);
      expect(find.text('Instrument 1 · A04'), findsOneWidget); // detail line
      expect(find.text('Non-chord tones'), findsOneWidget); // NCT line
    });

    testWidgets('renders each harmonic-function label', (tester) async {
      for (final (fn, label) in const [
        (cn.HarmonicFunction.subdominant, 'Away (subdominant)'),
        (cn.HarmonicFunction.dominant, 'Tension (dominant)'),
      ]) {
        await pumpBody(
          tester,
          InspectInfo(noteNames: 'G4', chordSymbol: 'G', function: fn),
        );
        expect(find.textContaining(label), findsOneWidget);
      }
    });

    testWidgets('a bare note (no chord/degree/detail) renders just the name',
        (tester) async {
      await pumpBody(tester, const InspectInfo(noteNames: 'F♯5'));
      expect(tester.takeException(), isNull);
      expect(find.text('F♯5'), findsOneWidget);
      // No chord row / NCT line for a bare note.
      expect(find.text('Non-chord tones'), findsNothing);
    });

    testWidgets('showInspect opens a bottom sheet with the card',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('de')],
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showInspect(
                  context,
                  const InspectInfo(noteNames: 'D5', chordSymbol: 'D'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('D5'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
    });
  });
}
