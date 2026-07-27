// FreeSingScreen (free singing → scrolling pitch trace) — previously untested.
// The mic only starts on the record toggle, so the idle screen builds without
// capture; a smoke test covers that build + idle UI.
import 'package:comet_beat/features/games/composition/free_sing_screen.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('renders the idle free-sing screen without throwing',
      (tester) async {
    await pumpGame(
      tester,
      const FreeSingScreen(),
      extraProviders: [
        ChangeNotifierProvider(create: (_) => UserSongsService()),
      ],
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.byType(FreeSingScreen), findsOneWidget);
  });
}
