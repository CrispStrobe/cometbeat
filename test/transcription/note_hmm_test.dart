// S2 — note-HMM segmentation. The headline: a VIBRATO melody (the "Mary sung"
// case) still transcribes to the right notes, because the note-state Viterbi
// absorbs the wobble instead of splitting it. Scored by the shared mir_eval
// harness. Synthetic sines we control; the real "Mary" recording is a documented
// CLI demo once S5 lands.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/note_hmm.dart';
import 'package:comet_beat/core/audio/transcription/pyin.dart';
import 'package:flutter_test/flutter_test.dart';

import 'note_metrics.dart';

const _sr = 44100;
double _hz(int m) => 440 * pow(2, (m - 69) / 12).toDouble();

Float64List _tone(int midi, double seconds, double vibratoCents) {
  final n = (seconds * _sr).round();
  final out = Float64List(n);
  final centre = _hz(midi);
  var phase = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / _sr;
    final f = vibratoCents <= 0
        ? centre
        : centre * pow(2, vibratoCents / 1200 * sin(2 * pi * 6 * t)).toDouble();
    phase += f / _sr;
    out[i] = 0.5 * sin(2 * pi * phase);
  }
  return out;
}

Float64List _melody(
  List<int> midis, {
  double noteMs = 400,
  double gapMs = 80,
  double vibratoCents = 0,
}) {
  final parts = <Float64List>[];
  for (final m in midis) {
    parts.add(_tone(m, noteMs / 1000, vibratoCents));
    parts.add(Float64List((gapMs / 1000 * _sr).round())); // rest
  }
  final total = parts.fold<int>(0, (s, p) => s + p.length);
  final out = Float64List(total);
  var off = 0;
  for (final p in parts) {
    out.setAll(off, p);
    off += p.length;
  }
  return out;
}

List<NoteEvent> _gt(List<int> midis, {double noteMs = 400, double gapMs = 80}) {
  final out = <NoteEvent>[];
  var t = 0.0;
  for (final m in midis) {
    out.add((midi: m, onMs: t, offMs: t + noteMs, confidence: 1));
    t += noteMs + gapMs;
  }
  return out;
}

void main() {
  const song = [60, 62, 64, 65, 67]; // C D E F G

  test('a plain melody transcribes (note-F ≥ 0.9)', () {
    final notes = segmentNotes(pyinF0(_melody(song)));
    expect(
      notePrf(_gt(song), notes, onsetTolMs: 120).f,
      greaterThanOrEqualTo(0.9),
    );
  });

  test('a VIBRATO melody still transcribes — the "Mary sung" fix', () {
    // ±45 cents at 6 Hz on every note: raw pitch smears across semitones, but
    // the note HMM absorbs it.
    final notes = segmentNotes(pyinF0(_melody(song, vibratoCents: 45)));
    expect(notes.length, song.length, reason: 'vibrato split a note');
    expect(
      notePrf(_gt(song), notes, onsetTolMs: 120).f,
      greaterThanOrEqualTo(0.9),
    );
    expect([for (final n in notes) n.midi], song);
  });

  test('one sustained vibrato note stays ONE note', () {
    final notes = segmentNotes(pyinF0(_tone(69, 0.9, 50))); // A4, heavy vibrato
    expect(notes.length, 1);
    expect(notes.first.midi, 69);
  });

  test('silence and too-short input yield no notes', () {
    expect(segmentNotes(pyinF0(Float64List(_sr))), isEmpty);
    expect(segmentNotes(const []), isEmpty);
  });
}
