// A scoreboard for the WHOLE pipeline: synthesize several known children's-song
// melodies, run each through transcribeRecording (the same path the app uses),
// and score the transcription against ground truth with the shared mir_eval
// ruler. This is the regression gate that guards every worker's contribution —
// if an engine swap or a notation change breaks real transcription, a song's
// note-F drops and this goes red. It also checks the derived key and clef.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show wavBytes;
import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/transcription_service.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart' show Clef;
import 'package:flutter_test/flutter_test.dart';

import 'note_metrics.dart';

const _sr = 44100;
double _hz(int midi) => 440 * pow(2, (midi - 69) / 12).toDouble();

// One note per beat at 120 BPM (500 ms), 85% sounded then a rest, as PCM16 WAV.
Uint8List _songWav(List<int> midis) {
  const beat = 0.5;
  final noteN = (beat * 0.85 * _sr).round();
  final restN = (beat * 0.15 * _sr).round();
  final pcm = Int16List(midis.length * (noteN + restN));
  var off = 0;
  for (final m in midis) {
    final f = _hz(m);
    for (var i = 0; i < noteN; i++) {
      final env = min(1.0, min(i, noteN - i) / (0.01 * _sr));
      pcm[off + i] = (0.5 * env * sin(2 * pi * f * i / _sr) * 32767).round();
    }
    off += noteN + restN;
  }
  return wavBytes(pcm);
}

// Ground-truth NoteEvents at the same 500 ms grid.
List<NoteEvent> _truth(List<int> midis) => [
      for (var i = 0; i < midis.length; i++)
        (
          midi: midis[i],
          onMs: i * 500.0,
          offMs: i * 500.0 + 425,
          confidence: 1,
          program: gmProgramUnknown,
        ),
    ];

void main() {
  const songs = <String, List<int>>{
    'C major scale': [60, 62, 64, 65, 67, 69, 71, 72],
    'Twinkle Twinkle': [60, 60, 67, 67, 69, 69, 67],
    'Mary Had a Little Lamb': [64, 62, 60, 62, 64, 64, 64],
    'Ode to Joy': [64, 64, 65, 67, 67, 65, 64, 62, 60, 60, 62, 64, 64, 62, 62],
  };

  for (final entry in songs.entries) {
    test('${entry.key} transcribes with note-F ≥ 0.85', () async {
      final r = await transcribeRecording(_songWav(entry.value));
      final prf = notePrf(
        _truth(entry.value),
        r.notes,
        onsetTolMs: 200,
      );
      // A visible score line even when it passes.
      // ignore: avoid_print
      print('${entry.key}: note-F ${prf.f.toStringAsFixed(2)} '
          '(${r.notes.length}/${entry.value.length} notes, '
          'key ${r.key.fifths}, ${r.score.clef.name}, engine ${r.engine.name})');
      expect(prf.f, greaterThanOrEqualTo(0.85), reason: entry.key);
    });
  }

  test('a C-major song is detected as C major (0 accidentals), treble clef',
      () async {
    final r =
        await transcribeRecording(_songWav(const [60, 62, 64, 65, 67, 72]));
    expect(r.key.fifths, 0);
    expect(r.score.clef, Clef.treble);
  });

  test('a low cello-register line engraves in bass clef', () async {
    // C2 arpeggio.
    final r =
        await transcribeRecording(_songWav(const [36, 40, 43, 48, 43, 40]));
    expect(r.score.clef, Clef.bass);
  });
}
