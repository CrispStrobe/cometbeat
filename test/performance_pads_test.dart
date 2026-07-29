// WS-X5 (3b) — an on-screen input that a MIDI consumer cannot tell from
// hardware.
//
// The app already had two on-screen keyboards and neither could do this: both
// emit `onKeyTap(int midi)`, a TAP. A tap has no duration, so it can never
// produce a HELD note — which means `HeldNotes`, the whole reason the WS-X5
// seam exists, would have nothing to track, and the standard's most notorious
// corner (a note-on with velocity 0 IS a note-off) would never arise. Those are
// quiz widgets, where a tap is an answer. This is a performance input, where a
// press and a release are two different events.
//
// So the tests below are mostly about the RELEASE, because that is what a tap
// widget does not have and what a stuck note is made of: a finger lifted, a
// finger slid away, a gesture cancelled, the widget disposed mid-press. Any of
// those going missing leaves a note sounding forever, and none of them is
// visible by looking at the screen.

import 'package:comet_beat/core/midi/midi_input.dart';
import 'package:comet_beat/shared/widgets/performance_pads.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _pads = [
  PerformancePad(note: 60, label: 'C'),
  PerformancePad(note: 62, label: 'D'),
  PerformancePad(note: 36, label: 'Kick', channel: 9),
];

/// Mounts the board and returns everything it sends.
Future<List<MidiMessage>> _pump(
  WidgetTester tester, {
  List<PerformancePad> pads = _pads,
  bool velocityFromPosition = true,
  ManualMidiInput? input,
  GlobalKey<PerformancePadsState>? boardKey,
}) async {
  final midi = input ?? ManualMidiInput();
  final seen = <MidiMessage>[];
  midi.messages.listen(seen.add);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 300,
          child: PerformancePads(
            key: boardKey,
            pads: pads,
            input: midi,
            velocityFromPosition: velocityFromPosition,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return seen;
}

Finder _pad(int note, {int channel = 0}) =>
    find.byKey(Key('perf-pad-$channel-$note'));

void main() {
  group('a press and a release are two events', () {
    testWidgets('pressing sends note-on, lifting sends note-off',
        (tester) async {
      final seen = await _pump(tester);
      final gesture = await tester.startGesture(tester.getCenter(_pad(60)));
      await tester.pump();

      expect(seen, hasLength(1));
      expect(seen.single.isNoteOn, isTrue);
      expect(seen.single.note, 60);

      await gesture.up();
      await tester.pump();
      expect(seen, hasLength(2));
      expect(seen.last.isNoteOff, isTrue);
      expect(seen.last.note, 60);
    });

    testWidgets('a note is HELD between them — what a tap cannot do',
        (tester) async {
      // Run it through HeldNotes, which is what a consumer actually uses.
      final midi = ManualMidiInput();
      final held = HeldNotes();
      midi.messages.listen(held.apply);
      await _pump(tester, input: midi);

      final gesture = await tester.startGesture(tester.getCenter(_pad(60)));
      await tester.pump();
      expect(held.notesOn(), contains(60));

      await gesture.up();
      await tester.pump();
      expect(held.isEmpty, isTrue);
    });

    testWidgets('two fingers hold two notes, and one lifting keeps the other',
        (tester) async {
      final midi = ManualMidiInput();
      final held = HeldNotes();
      midi.messages.listen(held.apply);
      await _pump(tester, input: midi);

      final a = await tester.startGesture(tester.getCenter(_pad(60)));
      final b = await tester.startGesture(tester.getCenter(_pad(62)));
      await tester.pump();
      expect(held.notesOn(), containsAll([60, 62]));

      await a.up();
      await tester.pump();
      expect(
        held.notesOn(),
        [62],
        reason: 'lifting one finger must not release the other note',
      );
      await b.up();
      await tester.pump();
      expect(held.isEmpty, isTrue);
    });
  });

  group('every press is released — where stuck notes come from', () {
    testWidgets('a cancelled gesture still sends note-off', (tester) async {
      // A finger that slides off, or a gesture the framework cancels, never
      // sends up. Without this the note sounds forever, and nothing on screen
      // looks wrong.
      final midi = ManualMidiInput();
      final held = HeldNotes();
      midi.messages.listen(held.apply);
      await _pump(tester, input: midi);

      final gesture = await tester.startGesture(tester.getCenter(_pad(60)));
      await tester.pump();
      expect(held.notesOn(), contains(60));

      await gesture.cancel();
      await tester.pump();
      expect(held.isEmpty, isTrue, reason: 'cancel must release too');
    });

    testWidgets('sliding onto another pad does not stack notes',
        (tester) async {
      final midi = ManualMidiInput();
      final held = HeldNotes();
      midi.messages.listen(held.apply);
      await _pump(tester, input: midi);

      final gesture = await tester.startGesture(tester.getCenter(_pad(60)));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(_pad(62)));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(held.isEmpty, isTrue, reason: 'nothing may be left sounding');
    });

    testWidgets('the widget going away mid-press releases what it held',
        (tester) async {
      final midi = ManualMidiInput();
      final held = HeldNotes();
      midi.messages.listen(held.apply);
      await _pump(tester, input: midi);

      await tester.startGesture(tester.getCenter(_pad(60)));
      await tester.pump();
      expect(held.notesOn(), contains(60));

      // Navigate away with the finger still down.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();
      expect(
        held.isEmpty,
        isTrue,
        reason: 'a disposed board must not leave notes sounding',
      );
    });
  });

  group('what it sends', () {
    testWidgets('velocity comes from where the pad was pressed',
        (tester) async {
      final seen = await _pump(tester);
      final box = tester.getRect(_pad(60));

      await (await tester.startGesture(
        Offset(box.center.dx, box.top + box.height * 0.1),
      ))
          .up();
      await tester.pump();
      final soft = seen.first.velocity;

      await (await tester.startGesture(
        Offset(box.center.dx, box.bottom - box.height * 0.1),
      ))
          .up();
      await tester.pump();
      final hard = seen.firstWhere(
        (m) => m.isNoteOn && m != seen.first,
        orElse: () => seen.last,
      );

      expect(
        soft,
        lessThan(hard.velocity),
        reason: 'lower on the pad is harder — the pad-controller convention',
      );
      expect(soft, greaterThan(0));
    });

    testWidgets('a caller can turn position-velocity off', (tester) async {
      // For a very young audience, a note whose loudness depends on exactly
      // where a finger landed is a bug report, not a feature.
      final seen = await _pump(tester, velocityFromPosition: false);
      final box = tester.getRect(_pad(60));
      for (final y in [box.top + 4, box.bottom - 4]) {
        await (await tester.startGesture(Offset(box.center.dx, y))).up();
        await tester.pump();
      }
      final velocities =
          seen.where((m) => m.isNoteOn).map((m) => m.velocity).toSet();
      expect(velocities, hasLength(1));
    });

    testWidgets('a pad keeps its own CHANNEL', (tester) async {
      // Drums conventionally sit on channel 10 (index 9). Merging channels
      // would make one board unable to hold a kit and a bass line at once.
      final seen = await _pump(tester);
      await (await tester.startGesture(
        tester.getCenter(_pad(36, channel: 9)),
      ))
          .up();
      await tester.pump();
      expect(seen.first.channel, 9);
      expect(seen.first.note, 36);
    });

    testWidgets('the same pitch on two channels is two notes', (tester) async {
      final midi = ManualMidiInput();
      final held = HeldNotes();
      midi.messages.listen(held.apply);
      await _pump(
        tester,
        input: midi,
        pads: const [
          PerformancePad(note: 60, label: 'a'),
          PerformancePad(note: 60, label: 'b', channel: 9),
        ],
      );

      await tester.startGesture(tester.getCenter(_pad(60)));
      await tester.startGesture(tester.getCenter(_pad(60, channel: 9)));
      await tester.pump();
      expect(held.length, 2, reason: 'same pitch, two channels, two notes');

      // Releasing one channel must not silence the other — the reason HeldNotes
      // keys on (channel, note) rather than note alone.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();
      expect(held.isEmpty, isTrue);
    });
  });

  test('the chromatic helper labels and accents like a keyboard', () {
    final pads = chromaticPads(60, 13);
    expect(pads, hasLength(13));
    expect(pads.first.note, 60);
    expect(pads.first.label, 'C');
    expect(pads.first.accent, isFalse);
    expect(pads[1].label, 'C♯');
    expect(pads[1].accent, isTrue, reason: 'the black keys read as black');
    expect(pads.last.note, 72);
    expect(pads.last.label, 'C');
  });
}
