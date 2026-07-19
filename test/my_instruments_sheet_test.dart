// The "My Instruments" browser — lists saved instruments, deletes, and (when
// pickable) resolves to a pick. Uses the real InstrumentLibraryStore seeded via
// the engine codec, so it exercises the whole save→browse path.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_instrument_codec.dart';
import 'package:comet_beat/features/sound_lab/instrument_library_store.dart';
import 'package:comet_beat/features/sound_lab/my_instruments_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

SavedInstrument _saved(String name) {
  final pcm = Float64List(2048);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = 0.4 * math.sin(2 * math.pi * 220 * i / 44100);
  }
  return SavedInstrument(
    name: name,
    json: instrumentToJsonString(SampleInstrument(name, pcm)),
    source: 'Voice Lab',
  );
}

MyInstrumentsTester _sheet(WidgetTester tester) =>
    tester.state<State<MyInstrumentsSheet>>(find.byType(MyInstrumentsSheet))
        as MyInstrumentsTester;

Widget _hosted(Widget child) => Scaffold(body: child);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('lists saved instruments with source + kind', (tester) async {
    final store = InstrumentLibraryStore();
    await store.save(_saved('bell'));
    await store.save(_saved('pluck'));
    await pumpGame(
      tester,
      _hosted(MyInstrumentsSheet(store: InstrumentLibraryStore())),
    );
    await tester.pumpAndSettle();

    expect(_sheet(tester).instruments.map((s) => s.name), ['bell', 'pluck']);
    expect(find.text('bell'), findsOneWidget);
    expect(find.textContaining('Voice Lab'), findsWidgets); // source shown
  });

  testWidgets('deleting removes it from the store', (tester) async {
    final store = InstrumentLibraryStore();
    await store.save(_saved('one'));
    await store.save(_saved('two'));
    await pumpGame(
      tester,
      _hosted(MyInstrumentsSheet(store: InstrumentLibraryStore())),
    );
    await tester.pumpAndSettle();

    await _sheet(tester).deleteAt(0);
    await tester.pumpAndSettle();

    expect(_sheet(tester).instruments.map((s) => s.name), ['two']);
    expect((await InstrumentLibraryStore().load()).map((s) => s.name), ['two']);
  });

  testWidgets('empty library explains how to fill it', (tester) async {
    await pumpGame(
      tester,
      _hosted(MyInstrumentsSheet(store: InstrumentLibraryStore())),
    );
    await tester.pumpAndSettle();
    expect(_sheet(tester).instruments, isEmpty);
    expect(find.textContaining('No saved instruments'), findsOneWidget);
  });

  test('renderInstrumentNote is non-silent across the keyboard octave', () {
    final inst = _saved('x').instrument!;
    for (final midi in kKeyboardMidi) {
      final pcm = renderInstrumentNote(inst, midi);
      var peak = 0.0;
      for (final s in pcm) {
        if (s.abs() > peak) peak = s.abs();
      }
      expect(peak, greaterThan(0.01), reason: 'silent at midi $midi');
    }
    // a higher note is genuinely different audio, not the same buffer
    expect(
      renderInstrumentNote(inst, 72),
      isNot(renderInstrumentNote(inst)),
    );
  });

  testWidgets('the 🎹 button opens a one-octave keyboard', (tester) async {
    final store = InstrumentLibraryStore();
    await store.save(_saved('bell'));
    await pumpGame(
      tester,
      _hosted(MyInstrumentsSheet(store: InstrumentLibraryStore())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.piano));
    await tester.pumpAndSettle();

    // one labelled button per white key (C D E F G A B C)
    for (final label in const ['C', 'D', 'E', 'F', 'G', 'A', 'B']) {
      expect(find.widgetWithText(ElevatedButton, label), findsWidgets);
    }
    expect(find.byType(ElevatedButton), findsNWidgets(kKeyboardMidi.length));
  });
}
