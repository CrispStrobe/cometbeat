// The "Load SoundFont" browser sheet: file-pick seam → preset list → pick →
// returns a TrackerInstrument. Uses the shared in-test SF2 fixture writer and an
// injected picker, so it needs no real file dialog, AudioService, or asset.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/sf2_remote.dart' show SoundFontSource;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/features/library/soundfont_download.dart'
    show kGmSoundFonts;
import 'package:comet_beat/features/library/soundfont_sheet.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sf2_fixture.dart';

void main() {
  // Pumps a host with an "open" button that shows the sheet with an injected
  // [pick]; the returned instrument is written into [sink].
  Future<void> pumpHost(
    WidgetTester tester, {
    required SoundFontPicker pick,
    required void Function(TrackerInstrument?) sink,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async =>
                  sink(await showSoundFontSheet(context, pick: pick)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('loads a .sf2, lists presets, returns the picked instrument',
      (tester) async {
    final bytes = velSplitSf2(sineI16(2000, 8), sineI16(2000, 64));
    TrackerInstrument? result;
    var done = false;
    await pumpHost(
      tester,
      pick: () async => (bytes: bytes, name: 'Test.sf2'),
      sink: (r) {
        result = r;
        done = true;
      },
    );

    // Empty state → choose a file.
    expect(find.text('Choose SoundFont file…'), findsOneWidget);
    await tester.tap(find.text('Choose SoundFont file…'));
    await tester.pumpAndSettle();

    // Loaded → the count chip + preset list appear.
    expect(find.textContaining('sounds'), findsOneWidget);
    expect(find.byType(ListTile), findsWidgets);

    // "Use this sound" is disabled until a preset is picked.
    FilledButton useBtn() => tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('Use this sound'),
            matching: find.byType(FilledButton),
          ),
        );
    expect(useBtn().onPressed, isNull);

    // Pick a preset → confirm → the sheet returns a TrackerInstrument.
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(useBtn().onPressed, isNotNull);
    await tester.tap(find.text('Use this sound'));
    await tester.pumpAndSettle();

    expect(done, isTrue);
    expect(result, isA<TrackerInstrument>());
  });

  testWidgets('cancel returns null', (tester) async {
    final bytes = velSplitSf2(sineI16(1000, 4), sineI16(1000, 20));
    TrackerInstrument? result;
    var done = false;
    await pumpHost(
      tester,
      pick: () async => (bytes: bytes, name: 'Test.sf2'),
      sink: (r) {
        result = r;
        done = true;
      },
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(result, isNull);
  });

  testWidgets('a .sf3 with no decoder shows a friendly error', (tester) async {
    final ogg = Uint8List.fromList([...'OggS'.codeUnits, 0, 1, 2]);
    final bytes = compressedSf3(oggStream: ogg);
    await pumpHost(
      tester,
      pick: () async => (bytes: bytes, name: 'Bad.sf3'),
      sink: (_) {},
    );
    await tester.tap(find.text('Choose SoundFont file…'));
    await tester.pumpAndSettle();
    // The friendly loader error surfaces; no preset list.
    expect(find.textContaining('Vorbis decoder'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('Download General MIDI fetches a font and lists its presets',
      (tester) async {
    final fontBytes = velSplitSf2(sineI16(2000, 8), sineI16(2000, 64));
    SoundFontSource? requested;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => showSoundFontSheet(
                context,
                pick: () async => null,
                download: (source) async {
                  requested = source;
                  return fontBytes; // stand in for the real HTTP download
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The download entry point is offered in the empty state.
    await tester.tap(find.text('Download General MIDI…'));
    await tester.pumpAndSettle();

    // The catalog dialog lists the curated fonts; pick the first (compact one).
    expect(find.text(kGmSoundFonts.first.name), findsOneWidget);
    await tester.tap(find.text(kGmSoundFonts.first.name));
    await tester.pumpAndSettle();

    // The downloaded font loads → the count chip + preset list appear.
    expect(requested, kGmSoundFonts.first);
    expect(find.textContaining('sounds'), findsOneWidget);
    expect(find.byType(ListTile), findsWidgets);
  });
}
