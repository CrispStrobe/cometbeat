// Covers GameAppBar: it shows the title and the app-wide sound toggle, and its
// optional "?" opens the given primer (hidden when no primer is passed).

import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/shared/tutorial/primers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

void main() {
  testWidgets('shows title + sound toggle, and "?" opens the primer',
      (tester) async {
    await pumpGame(
      tester,
      const Scaffold(
        appBar: GameAppBar(title: 'Play along', tutorial: readingPrimer),
        body: SizedBox.shrink(),
      ),
    );

    expect(find.text('Play along'), findsOneWidget);
    // The sound toggle (starts on → volume_up).
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);

    // The "?" opens the primer.
    expect(find.text('Reading notes'), findsNothing);
    await tester.tap(find.byIcon(Icons.help_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Reading notes'), findsOneWidget);
  });

  testWidgets('no "?" when the bar has no primer', (tester) async {
    await pumpGame(
      tester,
      const Scaffold(
        appBar: GameAppBar(title: 'Tuner'),
        body: SizedBox.shrink(),
      ),
    );

    expect(find.text('Tuner'), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    expect(find.byIcon(Icons.help_outline_rounded), findsNothing);
  });
}
