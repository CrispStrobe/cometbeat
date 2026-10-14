// The tracker's keyboard-entry state machine, without a widget: what each
// keystroke turns into, column by column.
import 'package:comet_beat/features/games/composition/tracker_field_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('volume: high nibble, then low, clamped to 0x40', () {
    final e = TrackerFieldEntry();
    expect(e.typeVolume(3), 3); // a first digit stands alone
    expect(e.typeVolume(2), 0x32);
    expect(e.typeVolume(4), 4); // a third digit starts a new pair
    expect(e.typeVolume(0xF), 0x40); // 0x4F clamps to the column maximum
  });

  test('effect: command, then a two-nibble parameter, then a new effect', () {
    final e = TrackerFieldEntry();
    expect(e.typeEffect(0xA), (command: 0xA, param: 0));
    expect(e.typeEffect(0x0), (command: 0xA, param: 0x0));
    expect(e.typeEffect(0xF), (command: 0xA, param: 0x0F));
    expect(e.typeEffect(0x3), (command: 0x3, param: 0));
  });

  test('instrument: two decimal digits, clamped to the pool', () {
    final e = TrackerFieldEntry();
    expect(e.typeInstrument(1, poolSize: 20), 1);
    expect(e.typeInstrument(2, poolSize: 20), 12);
    expect(e.typeInstrument(9, poolSize: 5), 5);
    expect(e.typeInstrument(9, poolSize: 5), 5); // 59 → the last instrument
  });

  test('a cursor move forgets typed digits but keeps an armed note', () {
    final e = TrackerFieldEntry()
      ..typeVolume(3)
      ..typeEffect(0xA)
      ..typeInstrument(1, poolSize: 20)
      ..armNote(5);
    e.resetColumns();
    expect(e.typeVolume(2), 2);
    expect(e.typeEffect(0xB).command, 0xB);
    expect(e.typeInstrument(4, poolSize: 20), 4);
    expect(e.noteArmed, isTrue);
  });

  test('note names: letter, optional sharp, octave', () {
    final e = TrackerFieldEntry();
    expect(e.commitOctave(4), isNull, reason: 'nothing armed');
    e.sharpen(); // ignored with nothing armed
    e.armNote(5); // F
    expect(e.armedPitchClass, 5);
    e.sharpen();
    expect(e.armedPitchClass, 6);
    expect(e.commitOctave(2), 42); // F#2
    expect(e.noteArmed, isFalse);

    e
      ..armNote(11) // B
      ..sharpen()
      ..armNote(0); // a new letter drops the old sharp
    expect(e.commitOctave(4), 60); // C4, not C#4
  });

  test('cancelNote disarms the letter and its sharp', () {
    final e = TrackerFieldEntry()
      ..armNote(9)
      ..sharpen()
      ..cancelNote();
    expect(e.armedPitchClass, isNull);
    e.armNote(9);
    expect(e.armedPitchClass, 9);
  });
}
