// WS-X5 step 1 — the MIDI-in seam.
//
// No platform binding yet, deliberately: that is a dependency across five
// targets and a maintainer call. What IS here is the part every record path
// will need and the part where MIDI bugs actually live — parsing, and knowing
// which notes are down.
//
// The single most common MIDI bug in any application is treating note-on as
// "start sounding" without checking the velocity, because **a note-on with
// velocity 0 is a note-off** and a great many controllers send exactly that.
// Get it wrong and notes stick on forever. Most of this file is about that and
// its neighbours.

import 'package:comet_beat/core/midi/midi_input.dart';
import 'package:flutter_test/flutter_test.dart';

/// Raw bytes, the way a device sends them.
const _noteOnC4 = [0x90, 60, 100];
const _noteOffC4 = [0x80, 60, 0];
const _noteOnC4Vel0 = [0x90, 60, 0];

void main() {
  group('parsing', () {
    test('a note-on carries its note and velocity', () {
      final message = MidiMessage.fromBytes(_noteOnC4)!;
      expect(message.kind, MidiMessageKind.noteOn);
      expect(message.note, 60);
      expect(message.velocity, 100);
      expect(message.isNoteOn, isTrue);
      expect(message.isNoteOff, isFalse);
    });

    test('⚠️ a note-on with velocity 0 IS a note-off', () {
      // The bug this whole file exists to prevent. It is in the standard, and
      // controllers rely on it so they can use running status.
      final message = MidiMessage.fromBytes(_noteOnC4Vel0)!;
      expect(message.kind, MidiMessageKind.noteOn, reason: 'it IS a note-on');
      expect(message.isNoteOff, isTrue, reason: 'but it MEANS note-off');
      expect(message.isNoteOn, isFalse);
    });

    test('the channel is kept', () {
      // A controller often sends drums on channel 10; merging channels would
      // merge two players into one.
      final message = MidiMessage.fromBytes([0x95, 60, 100])!;
      expect(message.channel, 5);
    });

    test('pitch bend reads as −1…+1 with centre 0', () {
      // 8192 is centre; the LSB comes first on the wire, which is easy to
      // swap and produces a bend that jumps at random.
      expect(MidiMessage.fromBytes([0xE0, 0, 64])!.bend, closeTo(0, 1e-9));
      expect(MidiMessage.fromBytes([0xE0, 0, 0])!.bend, -1);
      expect(
        MidiMessage.fromBytes([0xE0, 127, 127])!.bend,
        closeTo(1, 0.001),
      );
    });

    test('a control change keeps its number and value', () {
      final message = MidiMessage.fromBytes([0xB0, 7, 64])!;
      expect(message.kind, MidiMessageKind.controlChange);
      expect(message.data1, 7);
      expect(message.data2, 64);
    });

    test('unusable input is null, not a guess', () {
      // A caller should skip these. Inventing a message from a truncated or
      // unsupported one would put notes in a recording that nobody played.
      expect(MidiMessage.fromBytes(const []), isNull);
      expect(
        MidiMessage.fromBytes(const [60, 100]),
        isNull,
        reason: 'a data byte with no status (running status)',
      );
      expect(
        MidiMessage.fromBytes(const [0xF0, 1, 2]),
        isNull,
        reason: 'sysex — real, but nothing here could act on it',
      );
    });

    test('a truncated message does not read past the end', () {
      final message = MidiMessage.fromBytes(const [0x90, 60])!;
      expect(message.note, 60);
      expect(message.velocity, 0);
      // …and by the rule above, that means note-off, which is the safe
      // interpretation of a half-arrived note.
      expect(message.isNoteOff, isTrue);
    });
  });

  group('held notes', () {
    test('a note goes down and comes back up', () {
      final held = HeldNotes();
      expect(held.apply(MidiMessage.fromBytes(_noteOnC4)!), isTrue);
      expect(held.notesOn(), [60]);
      expect(held.velocityOf(60), 100);

      expect(held.apply(MidiMessage.fromBytes(_noteOffC4)!), isTrue);
      expect(held.notesOn(), isEmpty);
      expect(held.velocityOf(60), isNull);
    });

    test('velocity-0 note-on releases it — not a second press', () {
      // The failure mode: the note stays down forever and the next recording
      // has one endless note in it.
      final held = HeldNotes()
        ..apply(MidiMessage.fromBytes(_noteOnC4)!)
        ..apply(MidiMessage.fromBytes(_noteOnC4Vel0)!);
      expect(held.notesOn(), isEmpty);
    });

    test('a chord is reported lowest-first, stably', () {
      // A caller reading a chord out of this must not see it shuffle between
      // frames — that would make an arpeggiator or a chord readout flicker.
      final held = HeldNotes();
      for (final note in [67, 60, 64]) {
        held.apply(
          MidiMessage(kind: MidiMessageKind.noteOn, data1: note, data2: 90),
        );
      }
      expect(held.notesOn(), [60, 64, 67]);
      expect(held.notesOn(), [60, 64, 67], reason: 'same order every read');
    });

    test('the same pitch on two channels is two notes', () {
      const middleC = MidiMessage(
        kind: MidiMessageKind.noteOn,
        data1: 60,
        data2: 90,
      );
      const middleCOnDrums = MidiMessage(
        kind: MidiMessageKind.noteOn,
        channel: 9,
        data1: 60,
        data2: 90,
      );
      final held = HeldNotes()
        ..apply(middleC)
        ..apply(middleCOnDrums);
      expect(held.length, 2);
      expect(held.notesOn(channel: 0), [60]);
      expect(held.notesOn(channel: 9), [60]);
    });

    test('a repeat at the same velocity is not a change', () {
      // So a caller can skip redrawing. A stuck key repeating is common.
      final held = HeldNotes();
      final on = MidiMessage.fromBytes(_noteOnC4)!;
      expect(held.apply(on), isTrue);
      expect(held.apply(on), isFalse, reason: 'nothing changed');
      expect(held.length, 1, reason: 'and it is not held twice');
    });

    test('a repeat at a DIFFERENT velocity is a change', () {
      final held = HeldNotes()..apply(MidiMessage.fromBytes(_noteOnC4)!);
      expect(
        held.apply(MidiMessage.fromBytes(const [0x90, 60, 40])!),
        isTrue,
      );
      expect(held.velocityOf(60), 40);
    });

    test('a note-off for something not held is not a change', () {
      final held = HeldNotes();
      expect(held.apply(MidiMessage.fromBytes(_noteOffC4)!), isFalse);
    });

    test('a control change never touches the held set', () {
      final held = HeldNotes()..apply(MidiMessage.fromBytes(_noteOnC4)!);
      expect(
        held.apply(MidiMessage.fromBytes(const [0xB0, 7, 64])!),
        isFalse,
      );
      expect(held.notesOn(), [60]);
    });

    test('clear forgets everything — what a disconnect needs', () {
      // The note-offs for anything held will never arrive, so without this the
      // notes are stuck for the rest of the session.
      final held = HeldNotes()..apply(MidiMessage.fromBytes(_noteOnC4)!);
      held.clear();
      expect(held.isEmpty, isTrue);
    });
  });

  group('the inputs', () {
    test('the null input is quiet and says it is unavailable', () {
      // Not a placeholder: web and any machine without a controller will
      // always need this, and a consumer that only works with hardware present
      // is a consumer that breaks on most machines.
      final input = NullMidiInput();
      expect(input.isAvailable, isFalse);
      expect(input.devices, isEmpty);
      expect(input.messages, emitsDone);
    });

    test('the manual input delivers what is pushed into it', () async {
      final input = ManualMidiInput();
      final seen = <MidiMessage>[];
      final subscription = input.messages.listen(seen.add);

      input.sendBytes(_noteOnC4);
      input.send(const MidiMessage(kind: MidiMessageKind.noteOff, data1: 60));
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(2));
      expect(seen.first.note, 60);
      await subscription.cancel();
      await input.dispose();
    });

    test('it is a BROADCAST stream — two surfaces can listen', () async {
      // One listener cancelling must not silence the other; a single-
      // subscription stream would throw on the second listen.
      final input = ManualMidiInput();
      final a = <MidiMessage>[];
      final b = <MidiMessage>[];
      final subA = input.messages.listen(a.add);
      final subB = input.messages.listen(b.add);

      input.sendBytes(_noteOnC4);
      await Future<void>.delayed(Duration.zero);
      await subA.cancel();
      input.sendBytes(_noteOnC4);
      await Future<void>.delayed(Duration.zero);

      expect(a, hasLength(1));
      expect(b, hasLength(2), reason: 'B kept receiving after A left');
      await subB.cancel();
      await input.dispose();
    });

    test('unparseable bytes are dropped rather than sent on', () async {
      final input = ManualMidiInput();
      final seen = <MidiMessage>[];
      final subscription = input.messages.listen(seen.add);
      input.sendBytes(const [0xF0, 1, 2]);
      await Future<void>.delayed(Duration.zero);
      expect(seen, isEmpty);
      await subscription.cancel();
      await input.dispose();
    });

    test('sending after dispose does not throw', () async {
      // A surface disposing while a device is still delivering is ordinary.
      final input = ManualMidiInput();
      await input.dispose();
      expect(() => input.sendBytes(_noteOnC4), returnsNormally);
    });
  });
}
