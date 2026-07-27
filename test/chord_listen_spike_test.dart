// ChordListenSpikeScreen (live chord listener) — previously untested. The mic
// only starts on the toggle button, so the idle screen builds without any
// capture; a smoke test covers that build + idle UI.
import 'package:comet_beat/features/games/chords/chord_listen_spike_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('renders the idle chord listener without throwing',
      (tester) async {
    await pumpGame(tester, const ChordListenSpikeScreen());
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.byType(ChordListenSpikeScreen), findsOneWidget);
  });
}
