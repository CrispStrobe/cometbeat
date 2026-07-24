import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:comet_beat/features/games/composition/loop_studio_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

void main() {
  testWidgets('Loop Studio keeps one editor while switching views',
      (tester) async {
    await pumpGame(tester, const LoopStudioScreen());

    expect(find.text('Loop Studio'), findsOneWidget);
    expect(find.text('Simple'), findsOneWidget);
    expect(find.byType(LoopMixerScreen), findsOneWidget);

    await tester.tap(find.text('Advanced'));
    await tester.pump();

    expect(find.text('Advanced'), findsOneWidget);
    expect(find.byType(LoopMixerScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Loop Studio uses a compact view switcher on narrow screens',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpGame(tester, const LoopStudioScreen());

    expect(find.byType(PopupMenuButton<bool>), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
