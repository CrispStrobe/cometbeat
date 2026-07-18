// The note-name reading scaffold: the persisted SettingsService.showNoteNames
// flag and the ReadingStaffView wrapper that games use to honour it.

import 'package:comet_beat/core/note_naming.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/features/games/widgets/playing_staff.dart';
import 'package:comet_beat/features/games/widgets/reading_staff.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Score _score() => Score(
      clef: Clef.treble,
      measures: [
        Measure([
          NoteElement.note(
            const Pitch(Step.c),
            const NoteDuration(DurationBase.quarter),
            id: 'n',
          ),
        ]),
      ],
    );

bool _staffShowsNames(WidgetTester tester) =>
    tester.widget<StaffView>(find.byType(StaffView)).showNoteNames;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('showNoteNames is off by default and persists across a reload',
      () async {
    final s = SettingsService();
    expect(s.showNoteNames, isFalse);
    await s.setShowNoteNames(true);
    expect(s.showNoteNames, isTrue);

    final reloaded = SettingsService();
    await reloaded.load();
    expect(reloaded.showNoteNames, isTrue);
  });

  testWidgets('ReadingStaffView reflects the setting', (tester) async {
    final settings = SettingsService();
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsService>.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(body: ReadingStaffView(score: _score())),
        ),
      ),
    );
    expect(_staffShowsNames(tester), isFalse, reason: 'off by default');

    await settings.setShowNoteNames(true);
    await tester.pump();
    expect(_staffShowsNames(tester), isTrue, reason: 'reacts to the setting');

    // The spelling follows the app's note-naming setting.
    await settings.setNoteNaming(NoteNaming.germanH);
    await tester.pump();
    expect(
      tester.widget<StaffView>(find.byType(StaffView)).noteNameStyle,
      NoteNameStyle.german,
    );
  });

  testWidgets('with a playback controller the notes light up (and keep names)',
      (tester) async {
    final settings = SettingsService();
    await settings.setShowNoteNames(true);
    final pb = ScorePlayback();
    addTearDown(pb.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsService>.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: ReadingStaffView(score: _score(), playback: pb),
          ),
        ),
      ),
    );
    StaffView staff() => tester.widget<StaffView>(find.byType(StaffView));
    // The reading scaffold still shows through the playing wrapper.
    expect(staff().showNoteNames, isTrue);
    expect(staff().highlightedIds, isEmpty);

    pb.play([
      (ids: {'n'}, ms: 100),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(staff().highlightedIds, {'n'});
    await tester.pump(const Duration(milliseconds: 120)); // finishes → clears
  });
}
