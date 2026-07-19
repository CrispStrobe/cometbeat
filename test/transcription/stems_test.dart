// Stem-assembly glue: distinct synthetic stems (a melody, a bass line, a triad,
// a drum hit) assemble into a multi-part score with the right parts, clefs and
// content, and an injected separator drives the whole-song entry — proving W-SEP
// only has to provide the separation.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show Drum, renderDrum;
import 'package:comet_beat/core/audio/transcription/stems.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter_test/flutter_test.dart';

const _sr = 44100;
double _hz(int midi) => 440 * pow(2, (midi - 69) / 12).toDouble();

// A one-note-per-beat line at 120 BPM (sines), as mono float.
Float64List _line(List<int> midis) {
  const beat = 0.5;
  final noteN = (beat * 0.85 * _sr).round();
  final restN = (beat * 0.15 * _sr).round();
  final out = Float64List(midis.length * (noteN + restN));
  var off = 0;
  for (final m in midis) {
    final f = _hz(m);
    for (var i = 0; i < noteN; i++) {
      final env = min(1.0, min(i, noteN - i) / (0.01 * _sr));
      out[off + i] = 0.5 * env * sin(2 * pi * f * i / _sr);
    }
    off += noteN + restN;
  }
  return out;
}

List<int> _partMidis(Score s) => [
      for (final m in s.measures)
        for (final e in m.elements)
          if (e is NoteElement)
            for (final p in e.pitches) p.midiNumber,
    ];

void main() {
  test('distinct stems assemble into named, correctly-clefed parts', () async {
    final Stems stems = (
      vocals: _line(const [72, 74, 76, 77, 79]), // high melody
      bass: _line(const [36, 40, 43, 48]), // low bass line
      drums: null,
      other: null,
    );
    final r = await transcribeStems(stems);

    expect(r.score, isNotNull);
    expect(r.partNames, ['Vocals', 'Bass']);
    expect(r.score!.parts, hasLength(2));
    // Vocals part sits in treble, bass part in bass clef.
    expect(r.score!.parts[0].clef, Clef.treble);
    expect(r.score!.parts[1].clef, Clef.bass);
    // The bass part actually holds the low notes.
    expect(_partMidis(r.score!.parts[1]).every((m) => m < 60), isTrue);
  });

  test('a drums stem becomes hits, not a pitched part', () async {
    final kickBuf = Float64List(_sr ~/ 2);
    final kick = renderDrum(Drum.kick);
    for (var i = 0; i < kick.length && i < kickBuf.length; i++) {
      kickBuf[i] = kick[i];
    }
    final Stems stems = (
      vocals: _line(const [67, 69, 71]),
      bass: null,
      drums: kickBuf,
      other: null,
    );
    final r = await transcribeStems(stems);
    expect(r.partNames, ['Vocals']); // drums are NOT a pitched part
    expect(r.drums, isNotEmpty);
    expect(r.drums.first.drum, Drum.kick);
  });

  test('no pitched stems → null score, still safe', () async {
    final r = await transcribeStems(
      (vocals: null, bass: null, drums: null, other: null),
    );
    expect(r.score, isNull);
    expect(r.partNames, isEmpty);
  });

  test('transcribeSong with an injected separator drives the whole flow',
      () async {
    // The separator splits the (ignored) mix into a melody + a bass stem.
    Future<Stems> fakeSeparator(Float64List mono, int sr) async => (
          vocals: _line(const [72, 74, 76]),
          bass: _line(const [36, 38, 40]),
          drums: null,
          other: null,
        );

    final r = await transcribeSong(
      Float64List(_sr), // the mix (unused by the fake separator)
      separator: fakeSeparator,
    );
    expect(r.partNames, ['Vocals', 'Bass']);
    expect(r.score!.parts, hasLength(2));
  });

  test('transcribeSong without a separator makes a single part', () async {
    final r = await transcribeSong(_line(const [60, 62, 64, 65]));
    expect(r.score!.parts, hasLength(1));
    expect(r.partNames, ['Accompaniment']);
  });
}
