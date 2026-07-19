// gmPartsFromMidi: split a multi-track GM MIDI into parts that carry each
// track's GM program + percussion flag + name — the metadata per-part SoundFont
// voicing needs. Builds a real 3-track format-1 SMF (piano/ch0 prog0 ·
// bass/ch1 prog32 · drums/ch9) in-test, so nothing is mocked.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/gm_song_render.dart';
import 'package:comet_beat/core/audio/score_instrument_render.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _v(int n) => n < 128 ? [n] : [((n >> 7) & 0x7f) | 0x80, n & 0x7f];
List<int> _name(String s) => [0x00, 0xFF, 0x03, s.length, ...s.codeUnits];
List<int> _prog(int ch, int p) => [0x00, 0xC0 | ch, p];
List<int> _note(int ch, int key, int dur) =>
    [0x00, 0x90 | ch, key, 0x64, ..._v(dur), 0x80 | ch, key, 0x00];
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

/// A 3-track GM MIDI: Piano (ch0, program 0) · Bass (ch1, program 32) ·
/// Drums (ch9, percussion).
Uint8List _bandMidi() {
  final t1 = _mtrk([
    ..._name('Piano'),
    ..._prog(0, 0),
    for (final k in [60, 62, 64, 67]) ..._note(0, k, 480),
  ]);
  final t2 = _mtrk([
    ..._name('Bass'),
    ..._prog(1, 32),
    for (final k in [36, 43, 36, 43]) ..._note(1, k, 480),
  ]);
  final t3 = _mtrk([
    ..._name('Drums'),
    for (final k in [36, 38, 36, 38]) ..._note(9, k, 480),
  ]);
  final hdr = [
    ...'MThd'.codeUnits,
    0, 0, 0, 6, // length
    0, 1, // format 1
    0, 3, // 3 tracks
    (480 >> 8) & 0xff, 480 & 0xff, // division
  ];
  return Uint8List.fromList([...hdr, ...t1, ...t2, ...t3]);
}

void main() {
  test('splits a GM MIDI into parts carrying program + drum flag + name', () {
    final parts = gmPartsFromMidi(_bandMidi());
    expect(parts.length, 3);

    expect(parts[0].name, 'Piano');
    expect(parts[0].program, 0);
    expect(parts[0].isDrum, isFalse);

    expect(parts[1].name, 'Bass');
    expect(parts[1].program, 32);
    expect(parts[1].isDrum, isFalse);

    expect(parts[2].name, 'Drums');
    expect(parts[2].isDrum, isTrue, reason: 'channel 10 → percussion');

    // Every part carries real notes.
    for (final p in parts) {
      expect(
        p.score.measures.any((m) => m.elements.any((e) => e is NoteElement)),
        isTrue,
      );
    }
  });

  test('a single-track MIDI yields one part (program 0, not drums)', () {
    final single = Uint8List.fromList([
      ...'MThd'.codeUnits,
      0,
      0,
      0,
      6,
      0,
      0,
      0,
      1,
      1,
      0xE0,
      ..._mtrk([
        for (final k in [60, 64, 67]) ..._note(0, k, 480),
      ]),
    ]);
    final parts = gmPartsFromMidi(single);
    expect(parts.length, 1);
    expect(parts.first.program, 0);
    expect(parts.first.isDrum, isFalse);
  });

  test('gmPartsFromMultiPart reads program + percussion from part metadata',
      () {
    // A 2-part MusicXML: Bass (program 33 → 32) + Drums (channel 10).
    const xml = '''
<?xml version="1.0"?>
<score-partwise version="4.0">
  <part-list>
    <score-part id="P1"><part-name>Bass</part-name>
      <midi-instrument id="P1-I1"><midi-channel>1</midi-channel>
        <midi-program>33</midi-program></midi-instrument></score-part>
    <score-part id="P2"><part-name>Drums</part-name>
      <midi-instrument id="P2-I1"><midi-channel>10</midi-channel>
        <midi-program>1</midi-program></midi-instrument></score-part>
  </part-list>
  <part id="P1"><measure number="1">
    <attributes><divisions>1</divisions>
      <time><beats>4</beats><beat-type>4</beat-type></time>
      <clef><sign>G</sign><line>2</line></clef></attributes>
    <note><pitch><step>C</step><octave>3</octave></pitch>
      <duration>4</duration><type>whole</type></note></measure></part>
  <part id="P2"><measure number="1">
    <attributes><divisions>1</divisions>
      <time><beats>4</beats><beat-type>4</beat-type></time>
      <clef><sign>percussion</sign></clef></attributes>
    <note><pitch><step>C</step><octave>4</octave></pitch>
      <duration>4</duration><type>whole</type></note></measure></part>
</score-partwise>''';
    final parts = gmPartsFromMultiPart(multiPartScoreFromMusicXml(xml));
    expect(parts.length, 2);
    expect(parts[0].program, 32, reason: 'MusicXML 33 (1-based) → 32');
    expect(parts[0].isDrum, isFalse);
    expect(parts[1].isDrum, isTrue, reason: 'channel 10 → percussion');
  });

  test('midiTempoBpm reads the SMF tempo meta (else null)', () {
    // A tempo meta for 100 BPM: 600000 µs/quarter = 0x0927C0.
    const us = 600000;
    final tempoTrack = _mtrk([
      0x00, 0xFF, 0x51, 0x03, //
      (us >> 16) & 0xff, (us >> 8) & 0xff, us & 0xff,
      ..._note(0, 60, 480),
    ]);
    final smf = Uint8List.fromList([
      ...'MThd'.codeUnits,
      0,
      0,
      0,
      6,
      0,
      0,
      0,
      1,
      1,
      0xE0,
      ...tempoTrack,
    ]);
    expect(midiTempoBpm(smf), 100);

    // No tempo meta → null (caller falls back to 120).
    final noTempo = Uint8List.fromList([
      ...'MThd'.codeUnits,
      0,
      0,
      0,
      6,
      0,
      0,
      0,
      1,
      1,
      0xE0,
      ..._mtrk(_note(0, 60, 480)),
    ]);
    expect(midiTempoBpm(noTempo), isNull);
  });

  test('renderPartsWithVoices sums each part through its own voice', () {
    final parts = gmPartsFromMidi(_bandMidi());
    final voice = SampleInstrument('v', Float64List(512)..fillRange(0, 8, 0.3));
    final pcm = renderPartsWithVoices(
      [for (final p in parts) (p.score, voice)],
    );
    var peak = 0.0;
    for (final s in pcm) {
      if (s.abs() > peak) peak = s.abs();
    }
    expect(pcm, isNotEmpty);
    expect(peak, greaterThan(0.0));
  });
}
