// WS-X5 step 2 — the on-screen keyboard, through the MIDI seam.
//
// The seam exists because a note-on with velocity 0 is a note-off and missing
// that leaves notes stuck on. This layer can reintroduce exactly that bug in a
// different way: **a tap has no release.** Bridge `onKeyTap` straight to a
// note-on and every key you touch rings forever — the same failure, one layer
// up, and invisible until someone plays a chord.
//
// So most of this is about note-offs actually arriving: after a tap, after a
// press, when a note is re-tapped while still ringing, and when a screen goes
// away mid-note.

import 'package:comet_beat/core/midi/midi_input.dart';
import 'package:comet_beat/core/midi/on_screen_midi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late OnScreenMidi keys;
  late List<MidiMessage> seen;

  setUp(() {
    keys = OnScreenMidi(noteLength: const Duration(milliseconds: 50));
    seen = [];
    keys.input.messages.listen(seen.add);
  });

  tearDown(() => keys.dispose());

  Future<void> settle([int ms = 80]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  group('a tap becomes a note that ENDS', () {
    test('note-on immediately, note-off after the length', () async {
      keys.tap(60);
      await settle(10);
      expect(seen, hasLength(1));
      expect(seen.single.isNoteOn, isTrue);
      expect(seen.single.note, 60);

      await settle();
      expect(seen, hasLength(2), reason: 'the note-off must arrive on its own');
      expect(seen.last.isNoteOff, isTrue);
      expect(seen.last.note, 60);
    });

    test('⚠️ without this the note would ring forever', () async {
      // Stated as its own test because it is the whole point of the class. A
      // naive `onKeyTap` -> note-on bridge passes every other test in this file
      // and fails this one.
      keys.tap(64);
      await settle();
      final held = HeldNotes();
      for (final message in seen) {
        held.apply(message);
      }
      expect(held.isEmpty, isTrue, reason: 'nothing left sounding');
    });

    test('a chord of taps all come back down', () async {
      for (final note in [60, 64, 67]) {
        keys.tap(note);
      }
      await settle();
      final held = HeldNotes();
      for (final message in seen) {
        held.apply(message);
      }
      expect(held.notesOn(), isEmpty);
      expect(seen.where((m) => m.isNoteOn).length, 3);
      expect(seen.where((m) => m.isNoteOff).length, 3);
    });
  });

  group('re-tapping while still ringing', () {
    test('it restarts the note rather than stacking timers', () async {
      // The bug this prevents: two timers, the first one's note-off cutting
      // the second tap short, which sounds like a dropped note.
      keys.tap(60);
      await settle(20);
      keys.tap(60);
      await settle(20);
      // The first timer would have fired by now if it were still pending.
      expect(keys.isRinging(60), isTrue, reason: 'the SECOND tap still holds');

      await settle();
      expect(keys.isRinging(60), isFalse);
      final held = HeldNotes();
      for (final message in seen) {
        held.apply(message);
      }
      expect(held.isEmpty, isTrue);
    });
  });

  group('a real press and release', () {
    test('it holds until released, however long that is', () async {
      keys.press(60);
      await settle(120); // well past the tap length
      expect(
        seen.where((m) => m.isNoteOff),
        isEmpty,
        reason: 'a held key must not auto-release',
      );

      keys.release(60);
      await settle(10);
      expect(seen.last.isNoteOff, isTrue);
    });

    test('pressing a note that was tapped cancels the auto-release', () async {
      // Otherwise a stale timer releases a key the user is still holding.
      keys.tap(60);
      await settle(10);
      keys.press(60);
      await settle(120);
      final held = HeldNotes();
      for (final message in seen) {
        held.apply(message);
      }
      expect(held.notesOn(), [60], reason: 'still held');
    });

    test('releasing something never pressed is harmless', () async {
      // A UI that sends an extra release on gesture-cancel should not have to
      // check first.
      expect(() => keys.release(72), returnsNormally);
      await settle(10);
    });
  });

  group('when the screen goes away', () {
    test('releaseAll ends everything still sounding', () async {
      // The pointer-up for a held key never arrives if the screen is
      // backgrounded — the same reason HeldNotes.clear() exists on the other
      // side of the seam.
      keys
        ..press(60)
        ..press(64);
      await settle(10);
      keys.releaseAll();
      await settle(10);

      final held = HeldNotes();
      for (final message in seen) {
        held.apply(message);
      }
      expect(held.isEmpty, isTrue);
    });

    test('dispose releases before closing the stream', () async {
      // Closing first would strand the note-offs in a closed controller and
      // leave a listening surface holding notes forever.
      final local = OnScreenMidi(noteLength: const Duration(seconds: 5));
      final messages = <MidiMessage>[];
      local.input.messages.listen(messages.add);
      local.press(60);
      await settle(10);
      await local.dispose();
      await settle(10);

      final held = HeldNotes();
      for (final message in messages) {
        held.apply(message);
      }
      expect(held.isEmpty, isTrue, reason: 'the note-off got out in time');
    });

    test('sending after dispose is a no-op, not a throw', () async {
      final local = OnScreenMidi();
      await local.dispose();
      expect(() => local.tap(60), returnsNormally);
      expect(() => local.press(60), returnsNormally);
      expect(() => local.release(60), returnsNormally);
    });
  });

  group('velocity', () {
    test('a per-tap velocity overrides the default', () async {
      keys.tap(60, velocity: 30);
      await settle(10);
      expect(seen.single.velocity, 30);
    });

    test('it is clamped rather than trusted', () async {
      // A velocity from a gesture is computed (pressure, a slider), so a
      // screen must not be able to break the input by being off by one — and
      // 0 in particular would mean note-OFF, silently swallowing the note.
      keys.tap(60, velocity: 0);
      await settle(10);
      expect(seen.single.velocity, greaterThan(0));
      expect(
        seen.single.isNoteOn,
        isTrue,
        reason: 'velocity 0 would be a note-off',
      );

      seen.clear();
      keys.tap(62, velocity: 999);
      await settle(10);
      expect(seen.single.velocity, 127);
    });
  });

  group('it is a real MidiInput', () {
    test('the surface sees an available device', () {
      // A consumer written against the seam works with this and does not know
      // the difference — which is the whole point of doing the seam first.
      expect(keys.input.isAvailable, isTrue);
      expect(keys.input.devices, isNotEmpty);
      expect(keys.input, isA<MidiInput>());
    });

    test('two UIs can share one input', () async {
      // A keyboard and a pad row are two widgets, one instrument.
      final shared = ManualMidiInput();
      final pads = OnScreenMidi(input: shared);
      final board = OnScreenMidi(input: shared);
      final messages = <MidiMessage>[];
      shared.messages.listen(messages.add);

      pads.tap(36);
      board.tap(60);
      await settle(10);
      expect(messages.map((m) => m.note), containsAll([36, 60]));
      await pads.dispose();
    });
  });
}
