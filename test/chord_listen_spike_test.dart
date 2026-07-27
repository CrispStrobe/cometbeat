// ChordListenSpikeScreen (live chord listener) — previously untested. The mic
// only starts on the toggle button, so the idle screen builds without any
// capture; a smoke test covers that build + idle UI. The `debugChords` seam
// feeds synthetic readings so the detection→display path is covered headlessly,
// without constructing the microphone plugin.
import 'dart:async';

import 'package:comet_beat/core/audio/chroma_analysis.dart';
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

  testWidgets('names the detected chord and its runner-up from the stream',
      (tester) async {
    final controller = StreamController<ChordReading>();
    addTearDown(controller.close);

    await pumpGame(
      tester,
      ChordListenSpikeScreen(debugChords: controller.stream),
    );
    await tester.pump();

    // Idle placeholder before any reading arrives.
    expect(find.text('—'), findsOneWidget);

    // A-minor detected best, C major runner-up. rootPc 9 → A, 0 → C (default
    // international note names).
    controller.add(
      ChordReading(
        candidates: const [
          ChordCandidate(rootPc: 9, suffix: 'm', score: 0.9),
          ChordCandidate(rootPc: 0, suffix: '', score: 0.6),
        ],
        chroma: List<double>.filled(12, 0.5),
        energy: 1.0,
      ),
    );
    await tester.pump(); // deliver the stream event → setState
    await tester.pump(); // rebuild the frame

    expect(tester.takeException(), isNull);
    expect(find.text('Am'), findsOneWidget); // best, big display
    // Runner-up chip: name + percentage.
    expect(find.text('C  60%'), findsOneWidget);
  });
}
