// A TAB can be dropped on the Audio Editor's timeline.
//
// It could not, until now, and the reason is worth keeping: `acceptsDirectly`
// listed the kinds the timeline holds AS-IS (score/tracker/loop), so a tab fell
// through to `convert(tab → audio)` — correctly unsupported, since a bounce is
// one-way — and the refusal even quoted the bounce message. The one mode that
// could put nothing on the timeline was the one most likely to want to: a riff
// you tabbed, under a groove.
//
// ⚠️ Fixing the protocol immediately exposed the wrinkle @loop-d1d4 documented
// for their target: `payload.kind` does NOT determine the document's type. A
// converted tab arrives as a MultiPartScore, so the Audio Editor's
// kind-keyed switch matched nothing and the drop vanished silently. These tests
// are mostly about that join, because the protocol's own suite cannot see it.

import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/interop/drag_payload.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/features/games/composition/daw_screen.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/game_test_support.dart';

DawTester _daw(WidgetTester tester) =>
    tester.state<State<DawScreen>>(find.byType(DawScreen)) as DawTester;

Future<DawTester> _open(WidgetTester tester) async {
  await pumpGame(
    tester,
    ChangeNotifierProvider(
      create: (_) => DawService(),
      child: const DawScreen(),
    ),
  );
  return _daw(tester);
}

TabDocument _tab() =>
    TabDocument.blank(Tuning.standardGuitar, initialColumns: 4)
      ..setFret(0, 0, 3)
      ..setFret(1, 1, 5)
      ..setFret(2, 2, 7);

void main() {
  testWidgets('a dragged tab lands on a lane', (tester) async {
    final daw = await _open(tester);
    final before = daw.clipCount;

    final landed = await daw.debugDropOnLane(
      MusicDragPayload(kind: AppMode.tab, document: _tab()),
      0,
    );
    await tester.pump();

    expect(landed, isTrue);
    expect(daw.clipCount, before + 1);
  });

  testWidgets('the other kinds still land, unconverted', (tester) async {
    // The change must not disturb what already worked: a score is held as-is,
    // with no conversion at all.
    final daw = await _open(tester);
    final score = MultiPartScore([
      Score.simple(timeSignature: TimeSignature.fourFour, notes: 'c4:q d4'),
    ]);
    final decision = dropDecisionFor(
      MusicDragPayload(kind: AppMode.score, document: score),
      AppMode.audio,
      acceptsDirectly: const {AppMode.score, AppMode.tracker, AppMode.loop},
    );
    expect(decision.outcome, DropOutcome.exact);
    expect(identical(decision.document, score), isTrue);

    expect(
      await daw.debugDropOnLane(
        MusicDragPayload(kind: AppMode.score, document: score),
        0,
      ),
      isTrue,
    );
  });

  testWidgets('the dropped tab is playable, not an empty clip', (tester) async {
    // "It landed" is not enough: a clip that renders silence would satisfy a
    // count and nothing else.
    final daw = await _open(tester);
    await daw.debugDropOnLane(
      MusicDragPayload(kind: AppMode.tab, document: _tab()),
      0,
    );
    await tester.pump();

    expect(daw.clipCount, 1);
    expect(
      daw.clipDurationMs(0, 0),
      greaterThan(0),
      reason: 'it has real length, so it has real notes',
    );
  });
}
