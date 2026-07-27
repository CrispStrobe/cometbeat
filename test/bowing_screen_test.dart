// BowingScreen (cello bowing exercise) — a previously-untested screen. It reads
// AudioService + SriService and draws a moving reading-staff; a widget smoke
// test confirms it builds and settles a frame without throwing.
import 'package:comet_beat/features/games/cello/bowing_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('renders the bowing exercise without throwing', (tester) async {
    await pumpGame(tester, const BowingScreen());
    // A game screen may run a Ticker, so advance a frame rather than settle.
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.byType(BowingScreen), findsOneWidget);
  });
}
