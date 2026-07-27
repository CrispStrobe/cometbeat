// The §4 instrument-macro editor in the Sample instrument editor: add a macro
// via the "+" menu, see it listed, and have it travel back out on Done. The
// step/loop/release manipulation itself is pure and unit-tested in
// macro_sequence_test.dart; this drives the real UI wiring end to end.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/envelope.dart';
import 'package:comet_beat/core/audio/macro_sequence.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/features/games/composition/instrument_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

void main() {
  testWidgets('add a Volume macro in the editor; it returns on the instrument',
      (tester) async {
    final inst = SampleInstrument(
      's',
      Float64List(4410)..fillRange(0, 4410, 0.5),
      envelope: Envelope.none,
    );
    TrackerInstrument? result;

    await pumpGame(
      tester,
      Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              result = await showInstrumentEditor(ctx, inst);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The macro section lives at the bottom of the sample editor list.
    await tester.scrollUntilVisible(
      find.text('Instrument Macros'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Instrument Macros'), findsOneWidget);

    // Add a Volume macro via the "+" menu.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Volume').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('macro_volume')), findsOneWidget);

    // Done hands the edited instrument back with the macro attached.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final sample = result! as SampleInstrument;
    expect(sample.macros, hasLength(1));
    expect(sample.macros.single.target, MacroTarget.volume);
    expect(sample.macros.single.values, [64, 64, 64, 64]); // the default
  });

  testWidgets('the macro edit dialog opens and Done keeps the macro',
      (tester) async {
    final inst = SampleInstrument(
      's',
      Float64List(4410)..fillRange(0, 4410, 0.5),
      envelope: Envelope.none,
      macros: const [
        MacroSequence(target: MacroTarget.pitch, values: [0, 12, 7]),
      ],
    );
    TrackerInstrument? result;

    await pumpGame(
      tester,
      Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              result = await showInstrumentEditor(ctx, inst);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('macro_pitch')),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('macro_pitch')),
        matching: find.byIcon(Icons.tune),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pitch macro'), findsOneWidget); // dialog title
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Done'),
      ),
    ); // dialog Done
    await tester.pumpAndSettle();

    await tester.tap(find.text('Done')); // sheet Done (now unique)
    await tester.pumpAndSettle();

    final sample = result! as SampleInstrument;
    expect(sample.macros.single.values, [0, 12, 7]);
  });
}
