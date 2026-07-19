// The Multitrack (DAW) arranger surface: add clips from modules, bake the
// arrangement, mute tracks. Audio is a no-op in the headless binding; assertions
// are on the arrangement + the bake.

import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/features/games/composition/daw_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

DawTester _daw(WidgetTester tester) =>
    tester.state<State<DawScreen>>(find.byType(DawScreen)) as DawTester;

Future<void> _pumpDaw(WidgetTester tester) => pumpGame(
      tester,
      const DawScreen(),
      extraProviders: [ChangeNotifierProvider(create: (_) => DawService())],
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('starts empty with two tracks', (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    expect(daw.trackCount, 2);
    expect(daw.clipCount, 0);
    expect(daw.debugBakeLength(), 0); // nothing to bake
  });

  testWidgets('adding clips from modules bakes real, layered audio',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);

    daw.addDemoBeat(); // a DrumSource on track A
    daw.addDemoTune(); // a ScoreSource on track B, 2 s later
    await tester.pump();
    expect(daw.clipCount, 2);

    // The arrangement bakes to a non-empty buffer that runs at least until the
    // second clip's placement (2 s in).
    final len = daw.debugBakeLength();
    expect(len, greaterThan(2 * 44100));
  });

  testWidgets('muting a track shortens/changes the bake', (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat(); // track A at 0
    await tester.pump();
    final withBeat = daw.debugBakeLength();
    expect(withBeat, greaterThan(0));

    daw.toggleTrackMute(0);
    await tester.pump();
    expect(daw.isTrackMuted(0), isTrue);
    expect(daw.debugBakeLength(), 0); // the only track is muted → silence
  });

  testWidgets('merge all flattens the arrangement into one baked take',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat();
    daw.addDemoTune();
    await tester.pump();
    expect(daw.clipCount, 2);
    final before = daw.debugBakeLength();

    daw.mergeAll();
    await tester.pump();
    expect(daw.clipCount, 1);
    expect(daw.trackCount, 2); // lanes stay; only the clips collapse
    expect(daw.isClipFrozen(0, 0), isTrue);
    // Merging preserves the arrangement, so the bake length is unchanged.
    expect(daw.debugBakeLength(), before);
  });

  testWidgets('freeze converts a live clip to audio; remove drops it',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat(); // a live DrumSource
    await tester.pump();
    expect(daw.isClipFrozen(0, 0), isFalse);

    daw.freezeClip(0, 0);
    await tester.pump();
    expect(daw.isClipFrozen(0, 0), isTrue);
    expect(daw.debugBakeLength(), greaterThan(0));

    daw.removeClip(0, 0);
    await tester.pump();
    expect(daw.clipCount, 0);
  });

  testWidgets('clips draw to scale and can be dragged along the lane',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat(); // track A @ 0 ms
    await tester.pump();

    // A real, non-zero duration (drawn to scale), and it starts at 0.
    expect(daw.clipDurationMs(0, 0), greaterThan(0));
    expect(daw.clipStartMs(0, 0), 0);
    expect(daw.canExport, isTrue);

    // Long-press then drag the clip box to the right → later in time.
    final center = tester.getCenter(find.text('🥁'));
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 600)); // arm the long press
    await gesture.moveBy(const Offset(160, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(daw.clipStartMs(0, 0), greaterThan(0));
  });

  testWidgets('export is gated on having content', (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    expect(daw.canExport, isFalse);
    daw.addDemoBeat();
    await tester.pump();
    expect(daw.canExport, isTrue);
  });

  testWidgets('undo/redo reverse and replay edits', (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    expect(daw.canUndo, isFalse);

    daw.addDemoBeat();
    daw.addDemoTune();
    await tester.pump();
    expect(daw.clipCount, 2);
    expect(daw.canUndo, isTrue);

    daw.undo();
    await tester.pump();
    expect(daw.clipCount, 1);

    daw.redo();
    await tester.pump();
    expect(daw.clipCount, 2);
  });

  testWidgets('clear empties every track', (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat();
    daw.addDemoTune();
    await tester.pump();
    expect(daw.clipCount, 2);

    daw.clear();
    await tester.pump();
    expect(daw.clipCount, 0);
    expect(tester.takeException(), isNull);
  });
}
