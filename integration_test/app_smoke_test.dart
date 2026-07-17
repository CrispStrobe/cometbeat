// On-device integration smoke test (run with:
//   flutter test integration_test -d macos   # or a connected device
// ). Boots the real app — real fonts, real SMuFL metadata via
// Bravura.load(), real audio path — navigates into a game and answers.

import 'package:comet_beat/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('boots, opens Note Values, answers a Symbol Quiz round',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Home renders all modules (first two unlocked on a fresh profile).
    expect(find.text('CometBeat'), findsOneWidget);

    await tester.tap(find.textContaining('Note Values').first);
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Symbol Quiz').first);
    await tester.pumpAndSettle();

    // One round: tap options until it resolves (max 4).
    for (var attempt = 0; attempt < 4; attempt++) {
      if (find.textContaining('Correct').evaluate().isNotEmpty) break;
      await tester.tap(find.byType(FilledButton).at(attempt));
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.textContaining('Correct'), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
