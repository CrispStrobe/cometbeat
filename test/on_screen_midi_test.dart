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

  /// Waits until [done], or gives up after [maxMs].
  ///
  /// ⚠️ Use this, NOT `settle()`, whenever the test is waiting for a MESSAGE
  /// to arrive. Sleeping a fixed interval and hoping is a race: the auto-release
  /// timer is 50ms and `settle()` slept 80ms, a 30ms margin that a stalled
  /// event loop eats. Measured in the act — 137ms of wall clock elapsed and the
  /// note-off still had not been delivered — it failed about one run in three,
  /// which is the worst kind of red because it says nothing about the code.
  ///
  /// Polling is fast when things work (it returns on the first check) and
  /// robust when they do not.
  Future<void> until(bool Function() done, {int maxMs = 2000}) async {
    final clock = Stopwatch()..start();
    while (!done() && clock.elapsedMilliseconds < maxMs) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  /// Waits for [count] messages to have arrived.
  Future<void> untilSeen(int count) => until(() => seen.length >= count);

  group('a tap becomes a note that ENDS', () {
    test('note-on immediately, note-off after the length', () async {
      keys.tap(60);
      await untilSeen(1);
      expect(seen, hasLength(1));
      expect(seen.single.isNoteOn, isTrue);
      expect(seen.single.note, 60);

      await untilSeen(2);
      expect(seen, hasLength(2), reason: 'the note-off must arrive on its own');
      expect(seen.last.isNoteOff, isTrue);
      expect(seen.last.note, 60);
    });

    test('⚠️ without this the note would ring forever', () async {
      // Stated as its own test because it is the whole point of the class. A
      // naive `onKeyTap` -> note-on bridge passes every other test in this file
      // and fails this one.
      keys.tap(64);
      await untilSeen(2);
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
      await untilSeen(6); // three on, three off
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
      // ⚠️ NO SLEEPS AND NO SHARED `keys`. The property is "a second tap
      // arriving WHILE the first is still ringing", and with the 50ms note the
      // rest of the file uses, that precondition is itself a race — any pause
      // between the taps and the first note has already released, making the
      // second an unrelated fresh note. Two earlier attempts failed exactly
      // there, one of them mine.
      //
      // A note long enough to outlive the test removes time from the question
      // altogether: both taps land inside it by construction, and the counts
      // then say everything. If the timers STACKED there would be two
      // note-offs; if the second tap were swallowed there would be one
      // note-on.
      final long = OnScreenMidi(noteLength: const Duration(seconds: 30));
      final heard = <MidiMessage>[];
      long.input.messages.listen(heard.add);
      addTearDown(long.dispose);

      long.tap(60);
      long.tap(60);
      expect(long.isRinging(60), isTrue, reason: 'still inside the 30s note');

      long.releaseAll();
      await until(() => heard.length >= 3);

      expect(
        heard.where((m) => m.isNoteOn).length,
        2,
        reason: 'both taps must sound',
      );
      expect(
        heard.where((m) => m.isNoteOff).length,
        1,
        reason: "the first tap's timer must have been CANCELLED, not stacked",
      );
      final held = HeldNotes();
      for (final message in heard) {
        held.apply(message);
      }
      expect(held.isEmpty, isTrue, reason: 'nothing left sounding');
    });
  });

  group('a real press and release', () {
    test('it holds until released, however long that is', () async {
      keys.press(60);
      // A REAL sleep, deliberately: this proves a note-off does NOT arrive,
      // and you cannot poll for a non-event. A stall only makes it more
      // conclusive, so it is safe where a wait-for-arrival is not.
      await settle(120);
      expect(
        seen.where((m) => m.isNoteOff),
        isEmpty,
        reason: 'a held key must not auto-release',
      );

      keys.release(60);
      await until(() => seen.any((m) => m.isNoteOff));
      expect(seen.last.isNoteOff, isTrue);
    });

    test('pressing a note that was tapped cancels the auto-release', () async {
      // Otherwise a stale timer releases a key the user is still holding.
      keys.tap(60);
      await untilSeen(1);
      keys.press(60);
      await settle(120); // a real wait: proving the auto-release does NOT fire
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
      await untilSeen(1);
      expect(seen.single.velocity, 30);
    });

    test('it is clamped rather than trusted', () async {
      // A velocity from a gesture is computed (pressure, a slider), so a
      // screen must not be able to break the input by being off by one — and
      // 0 in particular would mean note-OFF, silently swallowing the note.
      keys.tap(60, velocity: 0);
      await untilSeen(1);
      expect(seen.single.velocity, greaterThan(0));
      expect(
        seen.single.isNoteOn,
        isTrue,
        reason: 'velocity 0 would be a note-off',
      );

      seen.clear();
      keys.tap(62, velocity: 999);
      await untilSeen(1);
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
