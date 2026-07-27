// The realistic visual kit: pieces glow when their Drum sounds — driven
// by the step clock (playback/recording) and by a live pad-tap controller. Pure
// widget test, no audio.

import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/features/games/drums/drum_kit_visual.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DrumKitVisualTester handleOf(WidgetTester t) =>
      t.state<State<DrumKitVisual>>(find.byType(DrumKitVisual))
          as DrumKitVisualTester;

  Future<void> pumpKit(
    WidgetTester tester, {
    required ValueListenable<int> step,
    required bool Function(Drum, int) hitAt,
    DrumKitVisualController? controller,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 200,
            width: 320,
            child: DrumKitVisual(
              step: step,
              hitAt: hitAt,
              controller: controller,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a step hit lights that drum, then it decays', (tester) async {
    final step = ValueNotifier<int>(-1);
    // Only the kick hits on step 0.
    await pumpKit(
      tester,
      step: step,
      hitAt: (drum, s) => drum == Drum.kick && s == 0,
    );
    final kit = handleOf(tester);
    expect(kit.glowOf(Drum.kick), 0.0); // dark at rest

    step.value = 0;
    await tester.pump(); // process the step listener → light the kick
    await tester.pump(const Duration(milliseconds: 1));
    expect(kit.glowOf(Drum.kick), greaterThan(0.5), reason: 'kick struck');
    expect(kit.glowOf(Drum.snare), 0.0, reason: 'snare silent on this step');

    // It fades over time (exponential decay).
    final lit = kit.glowOf(Drum.kick);
    await tester.pump(const Duration(milliseconds: 250));
    expect(kit.glowOf(Drum.kick), lessThan(lit), reason: 'kick decays');

    step.dispose();
  });

  testWidgets('the controller flashes a drum on a live tap', (tester) async {
    final step = ValueNotifier<int>(-1);
    final controller = DrumKitVisualController();
    await pumpKit(
      tester,
      step: step,
      hitAt: (_, __) => false, // nothing from the clock
      controller: controller,
    );
    final kit = handleOf(tester);

    controller.flash(Drum.crash);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(kit.glowOf(Drum.crash), greaterThan(0.5));

    // Tapping the SAME drum again re-flashes it (seq-based, not value-equality).
    await tester.pump(const Duration(milliseconds: 300));
    final faded = kit.glowOf(Drum.crash);
    controller.flash(Drum.crash);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(kit.glowOf(Drum.crash), greaterThan(faded));

    step.dispose();
    controller.dispose();
  });

  testWidgets('tapping a drawn piece fires its drum (playable kit)',
      (tester) async {
    final step = ValueNotifier<int>(-1);
    final hits = <Drum>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: 200,
              width: 320,
              child: DrumKitVisual(
                step: step,
                hitAt: (_, __) => false,
                onHit: hits.add,
              ),
            ),
          ),
        ),
      ),
    );
    // The kick is the big front piece at normalized (0.53, 0.74).
    final box = tester.getRect(find.byType(DrumKitVisual));
    await tester.tapAt(Offset(box.left + 0.53 * 320, box.top + 0.74 * 200));
    await tester.pump();
    expect(hits, [Drum.kick]);

    // A tap in empty space (top-right corner) fires nothing.
    await tester.tapAt(Offset(box.right - 4, box.top + 4));
    await tester.pump();
    expect(hits, [Drum.kick]);
    step.dispose();
  });

  test('pieceAt hit-tests each piece at its own centre', () {
    const size = Size(320, 200);
    final shown = Drum.values.toSet();
    // Every piece resolves to itself when tapped dead-centre.
    for (final probe in [
      (Drum.kick, 0.53, 0.74),
      (Drum.snare, 0.30, 0.62),
      (Drum.crash, 0.21, 0.25),
      (Drum.ride, 0.80, 0.24),
      (Drum.lowTom, 0.86, 0.58),
    ]) {
      final (drum, cx, cy) = probe;
      expect(
        pieceAt(Offset(cx * size.width, cy * size.height), size, shown),
        drum,
      );
    }
    // A drum not in `shown` is never returned.
    expect(
      pieceAt(const Offset(0.53 * 320, 0.76 * 200), size, {Drum.snare}),
      isNot(Drum.kick),
    );
  });

  testWidgets('renders without error and repaints on the step clock',
      (tester) async {
    final step = ValueNotifier<int>(-1);
    await pumpKit(
      tester,
      step: step,
      hitAt: (drum, s) => true, // every piece lights on any step
    );
    expect(find.byType(CustomPaint), findsWidgets);
    for (var s = 0; s < 4; s++) {
      step.value = s;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.takeException(), isNull);
    step.dispose();
  });
}
