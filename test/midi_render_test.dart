// renderMidiFile — the event-accurate MIDI synth: schedules events on a sample
// clock and voices them through a SoundFont. Uses the shared in-test SF2 fixture
// so no real font/network is needed.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/midi_render.dart';
import 'package:comet_beat/core/audio/sf2/soundfont_loader.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sf2_fixture.dart';

List<int> _v(int n) => n < 128 ? [n] : [((n >> 7) & 0x7f) | 0x80, n & 0x7f];
List<int> _cc(int c, int cc, int val) => [0, 0xB0 | c, cc, val];
List<int> _note(int c, int k, int dur) =>
    [0, 0x90 | c, k, 0x64, ..._v(dur), 0x80 | c, k, 0];
List<int> _mtrk(List<int> body) {
  final b = [...body, 0x00, 0xFF, 0x2F, 0x00];
  return [
    ...'MTrk'.codeUnits,
    (b.length >> 24) & 0xff,
    (b.length >> 16) & 0xff,
    (b.length >> 8) & 0xff,
    b.length & 0xff,
    ...b,
  ];
}

Uint8List _midi(List<int> trackBody) => Uint8List.fromList([
      ...'MThd'.codeUnits, 0, 0, 0, 6, 0, 0, 0, 1, 1, 0xE0, //
      ..._mtrk(trackBody),
    ]);

double _peak(Float64List x) {
  var p = 0.0;
  for (final s in x) {
    if (s.abs() > p) p = s.abs();
  }
  return p;
}

void main() {
  final font = loadSoundFont(velSplitSf2(sineI16(2000, 8), sineI16(2000, 64)));

  test('renders a MIDI to non-silent stereo', () {
    final smf = _midi([
      for (final k in [60, 64, 67]) ..._note(0, k, 240),
    ]);
    final (left, right) = renderMidiFile(smf, font);
    expect(left, isNotEmpty);
    expect(right.length, left.length);
    expect(_peak(left) + _peak(right), greaterThan(0.0));
  });

  test('CC10 pan places a note in the stereo field', () {
    // Hard left (CC10 = 0) → louder on the left; hard right (127) → the reverse.
    final leftSmf = _midi([..._cc(0, 10, 0), ..._note(0, 60, 480)]);
    final rightSmf = _midi([..._cc(0, 10, 127), ..._note(0, 60, 480)]);
    final (l0, r0) = renderMidiFile(leftSmf, font);
    final (l1, r1) = renderMidiFile(rightSmf, font);
    expect(_peak(l0), greaterThan(_peak(r0)));
    expect(_peak(r1), greaterThan(_peak(l1)));
  });

  test('empty / non-MIDI input yields empty output', () {
    final (l, r) = renderMidiFile(Uint8List.fromList([1, 2, 3]), font);
    expect(l, isEmpty);
    expect(r, isEmpty);
  });
}
