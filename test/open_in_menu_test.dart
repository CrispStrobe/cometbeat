// test/open_in_menu_test.dart
//
// C4 — the shared "Open in…" menu. It is driven entirely by ProjectBridge, so
// the tests are about the two things a screen depends on: it offers exactly the
// routes that exist, and it does not let a lossy conversion happen silently.
//
// The lossless-goes-straight-through rule is deliberate and worth pinning: a
// confirmation that appears every time stops being read, which would defeat the
// warning for the conversions that genuinely need one.

// The fixtures spell out every column's duration, including the ones that match
// the default — these tests are about what a conversion does to note LENGTHS,
// so leaving some implicit would hide the fixture.
// ignore_for_file: avoid_redundant_argument_values

import 'package:comet_beat/core/audio/loop_engine.dart' show PatternCell;
import 'package:comet_beat/core/interop/project_bridge.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:comet_beat/shared/widgets/open_in_menu.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TabDocument _tab() => TabDocument(
      tuning: Tuning.standardGuitar,
      columns: const [
        TabColumn(frets: {5: 3}, duration: NoteDuration.quarter),
        TabColumn(frets: {4: 5}, duration: NoteDuration.quarter),
      ],
    );

Future<List<(AppMode, ConversionResult)>> _pump(
  WidgetTester tester, {
  required AppMode from,
  required Object Function() document,
}) async {
  final converted = <(AppMode, ConversionResult)>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          actions: [
            OpenInMenu(
              from: from,
              documentBuilder: document,
              onConverted: (mode, result) => converted.add((mode, result)),
            ),
          ],
        ),
        body: const SizedBox.shrink(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return converted;
}

void main() {
  testWidgets('it offers exactly the routes the bridge has', (t) async {
    await _pump(t, from: AppMode.tab, document: _tab);
    await t.tap(find.byKey(const ValueKey('open-in')));
    await t.pumpAndSettle();

    for (final target in AppMode.values) {
      final item = find.byKey(ValueKey('open-in-${target.name}'));
      if (target == AppMode.tab) {
        expect(item, findsNothing, reason: 'the current mode is not a target');
      } else {
        expect(
          item,
          findsOneWidget,
          reason: '$target is reachable but not offered',
        );
      }
    }
  });

  testWidgets('each entry shows what the trip costs, before committing',
      (t) async {
    await _pump(t, from: AppMode.tab, document: _tab);
    await t.tap(find.byKey(const ValueKey('open-in')));
    await t.pumpAndSettle();

    expect(
      find.text(ProjectBridge.describeEdge(AppMode.tab, AppMode.tracker)),
      findsOneWidget,
    );
    expect(
      find.text(ProjectBridge.describeEdge(AppMode.tab, AppMode.score)),
      findsOneWidget,
    );
  });

  testWidgets('a lossy conversion asks first and names what it loses',
      (t) async {
    final converted = await _pump(t, from: AppMode.tab, document: _tab);
    await t.tap(find.byKey(const ValueKey('open-in')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('open-in-loop')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('open-in-loss-dialog')), findsOneWidget);
    // Tab -> Loop drops the string/fret choice (a loop track is bare pitches);
    // the user must be told. (Tab -> Score keeps it now, via the tabVoicings
    // side-car — see the C4 lossless test below.)
    expect(find.textContaining('string and fret'), findsOneWidget);
    expect(converted, isEmpty, reason: 'it converted before being confirmed');

    await t.tap(find.byKey(const ValueKey('open-in-confirm')));
    await t.pumpAndSettle();
    expect(converted, hasLength(1));
    expect(converted.single.$1, AppMode.loop);
    expect(converted.single.$2.document, isA<List<PatternCell>>());
  });

  testWidgets('cancelling a lossy conversion does nothing at all', (t) async {
    final converted = await _pump(t, from: AppMode.tab, document: _tab);
    await t.tap(find.byKey(const ValueKey('open-in')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('open-in-loop')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('open-in-cancel')));
    await t.pumpAndSettle();

    expect(converted, isEmpty);
    expect(find.byKey(const ValueKey('open-in-loss-dialog')), findsNothing);
  });

  testWidgets('a lossless conversion goes straight through', (t) async {
    // A dialog that always appears is a dialog nobody reads. Tab -> Tracker
    // keeps string and fret natively, so there is nothing to warn about.
    final converted = await _pump(t, from: AppMode.tab, document: _tab);
    await t.tap(find.byKey(const ValueKey('open-in')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('open-in-tracker')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('open-in-loss-dialog')), findsNothing);
    expect(converted, hasLength(1));
    expect(converted.single.$1, AppMode.tracker);
    expect(converted.single.$2.lossless, isTrue);
  });

  testWidgets(
      'Tab -> Score is lossless now — the fretting rides in the '
      'side-car (C4)', (t) async {
    // The string/fret choice used to be reported dropped on this edge. It is
    // not: TabDocument.toScore records it in Score.tabVoicings, so the score
    // carries the exact fingering and a trip back to Tab reproduces it. A
    // lossless edge must go straight through with no loss dialog.
    final converted = await _pump(t, from: AppMode.tab, document: _tab);
    await t.tap(find.byKey(const ValueKey('open-in')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('open-in-score')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('open-in-loss-dialog')), findsNothing);
    expect(converted, hasLength(1));
    expect(converted.single.$1, AppMode.score);
    expect(converted.single.$2.document, isA<MultiPartScore>());
    expect(converted.single.$2.lossless, isTrue);
  });

  testWidgets('an unsupported target explains itself instead of failing',
      (t) async {
    final converted = await _pump(t, from: AppMode.loop, document: _loopTrack);
    await t.tap(find.byKey(const ValueKey('open-in')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('open-in-audio')));
    await t.pumpAndSettle();

    expect(find.textContaining('Bounce to Audio'), findsOneWidget);
    expect(converted, isEmpty);

    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
  });

  testWidgets('the document is built on selection, not on every rebuild',
      (t) async {
    // A mode should not pay to assemble its document just to draw a menu.
    var builds = 0;
    await _pump(
      t,
      from: AppMode.tab,
      document: () {
        builds++;
        return _tab();
      },
    );
    expect(builds, 0);

    await t.tap(find.byKey(const ValueKey('open-in')));
    await t.pumpAndSettle();
    expect(builds, 0, reason: 'opening the menu should not build it either');

    await t.tap(find.byKey(const ValueKey('open-in-tracker')));
    await t.pumpAndSettle();
    expect(builds, 1);
  });

  testWidgets('every mode can host the menu without throwing', (t) async {
    for (final from in AppMode.values) {
      await t.pumpWidget(
        MaterialApp(
          key: ValueKey('host-$from'),
          home: Scaffold(
            appBar: AppBar(
              actions: [
                OpenInMenu(
                  from: from,
                  documentBuilder: _tab,
                  onConverted: (_, __) {},
                ),
              ],
            ),
            body: const SizedBox.shrink(),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('open-in')));
      await t.pumpAndSettle();
      expect(
        find.byType(PopupMenuItem<AppMode>),
        findsWidgets,
        reason: '$from offered no targets',
      );
      // Close the menu before the next iteration.
      await t.tapAt(const Offset(5, 400));
      await t.pumpAndSettle();
    }
  });
}

List<PatternCell> _loopTrack() => const [
      PatternCell(midis: [60], steps: 2),
      PatternCell(midis: [64], steps: 2),
    ];
