// Loop Mixer §F-1 — the scale-locked smear pad. The pitch mapping is pure and
// only ever returns in-scale notes; the widget turns a drag into those notes.

import 'package:comet_beat/features/games/composition/smear_pad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _majorPent = {0, 2, 4, 7, 9};

void main() {
  group('smearMidi is scale-locked and monotonic', () {
    test('every position maps to a C-pentatonic note (left→right rises)', () {
      var prev = -1;
      for (var i = 0; i <= 100; i++) {
        final midi = smearMidi(i / 100);
        expect(
          _majorPent.contains(midi % 12),
          isTrue,
          reason: 'x=${i / 100} → $midi is off-pentatonic',
        );
        expect(midi, greaterThanOrEqualTo(prev)); // non-decreasing
        prev = midi;
      }
      // The ends span the requested octave range.
      expect(smearMidi(0), lessThan(smearMidi(1)));
    });

    test('key shifts every note by the root; minor uses the +3 set', () {
      // D major (key 2): notes are C-pentatonic + 2.
      for (var i = 0; i <= 20; i++) {
        expect(smearMidi(i / 20, key: 2) % 12, isIn({2, 4, 6, 9, 11}));
      }
      // C minor pentatonic = {0,3,5,7,10}.
      for (var i = 0; i <= 20; i++) {
        expect(smearMidi(i / 20, minor: true) % 12, isIn({0, 3, 5, 7, 10}));
      }
    });

    test('out-of-range x is clamped', () {
      expect(smearMidi(-1), smearMidi(0));
      expect(smearMidi(2), smearMidi(1));
    });
  });

  testWidgets('dragging the pad fires a rising run of in-key notes',
      (tester) async {
    final notes = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 80,
              child: SmearPad(onNote: notes.add),
            ),
          ),
        ),
      ),
    );

    // Drag left → right across the pad.
    await tester.drag(find.byType(SmearPad), const Offset(280, 0));
    await tester.pump();

    expect(notes, isNotEmpty);
    expect(notes.every((m) => _majorPent.contains(m % 12)), isTrue);
    // A left→right smear ends higher than it starts.
    expect(notes.last, greaterThan(notes.first));
  });
}
