// FreeSingScreen (free singing → scrolling pitch trace) — previously untested.
// The mic only starts on the record toggle, so the idle screen builds without
// capture; a smoke test covers that build + idle UI. The `debugReadings` seam
// feeds synthetic pitch readings so the capture→display path is covered
// headlessly, without constructing the microphone plugin.
import 'dart:async';

import 'package:comet_beat/core/audio/pitch_analysis.dart';
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

  testWidgets('shows the sung note name from the reading stream',
      (tester) async {
    final controller = StreamController<PitchReading>();
    addTearDown(controller.close);

    await pumpGame(
      tester,
      FreeSingScreen(debugReadings: controller.stream),
      extraProviders: [
        ChangeNotifierProvider(create: (_) => UserSongsService()),
      ],
    );
    await tester.pump();

    // A voiced reading at 440 Hz → A4 (default note naming, with octave).
    controller.add(const PitchReading(frequency: 440, clarity: 0.95, a4: 440));
    await tester.pump(); // deliver the stream event → setState
    await tester.pump(); // rebuild the frame

    expect(tester.takeException(), isNull);
    expect(find.text('A4'), findsOneWidget);
  });
}
