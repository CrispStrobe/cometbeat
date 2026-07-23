// Live (widget-driven) tests for the music library ↔ editors flow: the music
// picker, the score router (openScoreInWorkshop / openScoreInTab /
// showScoreDestinations), the editors' in-place round-trip (onReturnToDaw), and
// the full loop DAW clip → editor → send back → same clip updated.

import 'dart:convert';

import 'package:comet_beat/core/audio/daw_sources.dart' show ScoreSource;
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/features/games/composition/advanced_tracker_screen.dart';
import 'package:comet_beat/features/games/composition/tab_workshop_screen.dart';
import 'package:comet_beat/features/games/songs/song_book.dart' show kSongs;
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/workshop/screens/composition_workshop_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/music/music_picker.dart';
import 'package:comet_beat/shared/music/score_router.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show MultiPartScore;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

/// A small multi-part score built via the (tested) ABC reader — avoids the
/// `Step` symbol clash with Material and keeps the parts real.
MultiPartScore _score([int parts = 2]) {
  final one = decodeMusicFile('t.abc', utf8.encode('X:1\nK:C\nL:1/4\nCDEF|'));
  return MultiPartScore([for (var i = 0; i < parts; i++) one.parts.first]);
}

ChangeNotifierProvider<UserSongsService> _songsP() =>
    ChangeNotifierProvider(create: (_) => UserSongsService());
ChangeNotifierProvider<DawService> _dawP() =>
    ChangeNotifierProvider(create: (_) => DawService());

/// Pump a host with a button; [onTap] runs against the button's context.
Future<void> _host(
  WidgetTester tester,
  void Function(BuildContext) onTap, {
  List<SingleChildWidget> extraProviders = const [],
}) async {
  await pumpGame(
    tester,
    Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => onTap(ctx),
            child: const Text('go'),
          ),
        ),
      ),
    ),
    extraProviders: extraProviders,
  );
}

TabWorkshopTester _tab(WidgetTester t) =>
    t.state<State<TabWorkshopScreen>>(find.byType(TabWorkshopScreen))
        as TabWorkshopTester;

CompositionWorkshopTester _ws(WidgetTester t) =>
    t.state<State<CompositionWorkshopScreen>>(
      find.byType(CompositionWorkshopScreen),
    ) as CompositionWorkshopTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('showMusicPicker returns a Song Book song as a MultiPartScore',
      (tester) async {
    MultiPartScore? picked;
    await _host(
      tester,
      (ctx) async => picked = await showMusicPicker(ctx),
      extraProviders: [
        _songsP(),
      ],
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    // The picker offers import, catalog, and the built-in Song Book songs.
    expect(find.text(kSongs.first.title), findsOneWidget);
    await tester.tap(find.text(kSongs.first.title));
    await tester.pumpAndSettle();
    expect(picked, isNotNull);
    expect(picked!.parts, isNotEmpty);
  });

  testWidgets('openScoreInTab opens one tab track per part (multi-instrument)',
      (tester) async {
    await _host(tester, (ctx) => openScoreInTab(ctx, _score(3)));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(TabWorkshopScreen), findsOneWidget);
    expect(_tab(tester).trackCount, 3);
  });

  testWidgets('openScoreInWorkshop opens every part in the Score Workshop',
      (tester) async {
    await _host(
      tester,
      (ctx) => openScoreInWorkshop(ctx, _score()),
      extraProviders: [
        _songsP(),
        _dawP(),
      ],
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(CompositionWorkshopScreen), findsOneWidget);
    expect(_ws(tester).partCount, 2);
  });

  testWidgets(
      'showScoreDestinations offers Score + Tab + Tracker; Tracker opens editor',
      (tester) async {
    await _host(tester, (ctx) => showScoreDestinations(ctx, _score()));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    // Both destinations are offered.
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.workshopModeScore), findsOneWidget);
    expect(find.text(l10n.workshopModeTab), findsOneWidget);
    expect(find.text(l10n.trackerAdvancedTitle), findsOneWidget);
    await tester.tap(find.text(l10n.trackerAdvancedTitle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AdvancedTrackerScreen), findsOneWidget);
  });

  testWidgets('Tab onReturnToDaw sends the edit back and pops (in place)',
      (tester) async {
    MultiPartScore? returned;
    await _host(
      tester,
      (ctx) => Navigator.of(ctx).push(
        MaterialPageRoute<void>(
          builder: (_) => TabWorkshopScreen(
            initialParts: _score(1),
            onReturnToDaw: (mp) => returned = mp,
          ),
        ),
      ),
      extraProviders: [
        _dawP(),
      ],
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    _tab(tester).sendToDaw();
    await tester.pumpAndSettle();
    expect(returned, isNotNull); // the callback fired with the band score
    expect(find.byType(TabWorkshopScreen), findsNothing); // popped back
  });

  testWidgets('Workshop onReturnToDaw sends the edit back and pops (in place)',
      (tester) async {
    MultiPartScore? returned;
    await _host(
      tester,
      (ctx) => Navigator.of(ctx).push(
        MaterialPageRoute<void>(
          builder: (_) => CompositionWorkshopScreen(
            initialScore: _score(1),
            onReturnToDaw: (mp) => returned = mp,
          ),
        ),
      ),
      extraProviders: [
        _songsP(),
        _dawP(),
      ],
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    _ws(tester).sendToDaw();
    await tester.pumpAndSettle();
    expect(returned, isNotNull);
    expect(find.byType(CompositionWorkshopScreen), findsNothing);
  });

  testWidgets(
      'full round-trip: DAW clip → editor → send back updates THAT clip',
      (tester) async {
    final daw = DawService()..addClip(ScoreSource(_score(1)));
    final originalScore = daw.clipScore(0, 0);
    expect(originalScore, isNotNull);
    final source = daw.clipSourceAt(0, 0);

    await _host(
      tester,
      (ctx) => openScoreInTab(
        ctx,
        daw.clipScore(0, 0)!,
        onReturn: (edited) => daw.replaceScoreClipSource(source, edited),
      ),
      extraProviders: [
        ChangeNotifierProvider<DawService>.value(value: daw),
      ],
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    // "Send to Audio Editor" in the tab editor routes back in place.
    _tab(tester).sendToDaw();
    await tester.pumpAndSettle();

    // Still one clip on the same track, now carrying the editor's (re-built)
    // score — not a duplicate.
    expect(daw.timeline.tracks[0].clips.length, 1);
    expect(daw.clipScore(0, 0), isNotNull);
    expect(identical(daw.clipScore(0, 0), originalScore), isFalse);
  });
}
