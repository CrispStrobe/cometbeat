// bin/transcribe_notes_ggml.dart
//
// CLI for the CrispASR ggml NOTE-EVENT path — the one producer that identifies
// an INSTRUMENT per note. A WAV file → `CrispasrSession.pianoNotesWithPrograms`
// (piano-transcription, Basic Pitch or MT3; `--model`) → NoteEvents carrying
// `program` → optionally the S5 engraver, split into one part per instrument.
//
// It exists because `NoteEvent.program` is only worth carrying if something
// downstream uses it, and this is the headless end-to-end proof that something
// does: with MT3 a wind trio comes out of `--musicxml` as three `<part>`s with
// three `<midi-program>`s, not one staff of piled-up chords.
//
//   dart run bin/transcribe_notes_ggml.dart audio.wav [--model mt3]
//       [--download] [--json] [--musicxml out.musicxml]
//
//   --model      auto | piano | basic-pitch | mt3     (default: auto)
//   --download   fetch the GGUF if it is not cached (MT3 is tens of MB)
//   --json       machine-readable notes, program included
//   --musicxml   engrave and write a multi-part MusicXML document
//
// Convert anything to mono WAV first:
//   ffmpeg -i in.flac -ac 1 -ar 16000 -c:a pcm_s16le out.wav
library;

import 'dart:convert';
import 'dart:io';

import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_piano.dart';
import 'package:comet_beat/core/audio/transcription/engine_config.dart'
    show CrispasrNoteModel;
import 'package:comet_beat/core/audio/transcription/gm_programs.dart';
import 'package:comet_beat/core/audio/transcription/rhythm.dart';
import 'package:comet_beat/core/audio/transcription/transcribe.dart';
import 'package:comet_beat/core/audio/wav_io.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show MultiPartScore, multiPartToMusicXml;

const _names = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];
String _noteName(int midi) => '${_names[midi % 12]}${midi ~/ 12 - 1}';

String? _optS(List<String> a, String f) {
  final i = a.indexOf(f);
  return i >= 0 && i + 1 < a.length ? a[i + 1] : null;
}

CrispasrNoteModel _model(String? name) => switch (name) {
      null || '' || 'auto' => CrispasrNoteModel.auto,
      'piano' || 'piano-transcription' => CrispasrNoteModel.pianoTranscription,
      'basic-pitch' || 'basicpitch' => CrispasrNoteModel.basicPitch,
      'mt3' => CrispasrNoteModel.mt3,
      _ => throw ArgumentError('unknown --model "$name" '
          '(auto | piano | basic-pitch | mt3)'),
    };

Future<void> main(List<String> args) async {
  final paths = args.where((a) => !a.startsWith('--')).toList();
  if (paths.isEmpty) {
    stderr.writeln('usage: dart run bin/transcribe_notes_ggml.dart audio.wav '
        '[--model auto|piano|basic-pitch|mt3] [--download] [--json] '
        '[--musicxml out.musicxml]');
    exit(64);
  }
  // The first non-flag argument is the audio; later ones are flag VALUES.
  final path = paths.first;
  final json = args.contains('--json');
  final xmlOut = _optS(args, '--musicxml');

  final wav = readWavPcm16(File(path).readAsBytesSync());
  final mono = wavToMonoFloat(wav);
  stderr.writeln('loaded $path — ${wav.sampleRate} Hz, ${wav.channels}ch, '
      '${(mono.length / wav.sampleRate).toStringAsFixed(2)} s');

  final transcriber = await loadCrispasrPianoFfi(
    download: args.contains('--download'),
    model: _model(_optS(args, '--model')),
  );
  if (transcriber == null) {
    stderr.writeln('no CrispASR ggml note-event backend available — needs '
        'libcrispasr + the model GGUF (pass --download to fetch it).');
    exit(69);
  }

  final sw = Stopwatch()..start();
  final notes = await transcriber(mono, wav.sampleRate);
  sw.stop();

  if (json) {
    stdout.writeln(
      jsonEncode([
        for (final n in notes)
          {
            'midi': n.midi,
            'name': _noteName(n.midi),
            'onMs': n.onMs,
            'offMs': n.offMs,
            'confidence': n.confidence,
            'program': n.program,
            'instrument':
                hasInstrument(n.program) ? gmProgramName(n.program) : null,
          },
      ]),
    );
  } else {
    stdout.writeln('${notes.length} notes  (${sw.elapsedMilliseconds} ms):');
    // The histogram is the point of the whole exercise: one line per
    // instrument the model heard, so "did it identify the trio" is answerable
    // at a glance instead of by eyeballing hundreds of note rows.
    final byProgram = <int, int>{};
    for (final n in notes) {
      byProgram[n.program] = (byProgram[n.program] ?? 0) + 1;
    }
    final programs = byProgram.keys.toList()..sort();
    stdout.writeln('instruments:');
    for (final p in programs) {
      stdout.writeln('  program ${p.toString().padLeft(4)}  '
          '${gmProgramName(p).padRight(24)} ${byProgram[p]} notes');
    }
    stdout.writeln('  #   note   start      end     conf  instrument');
    for (var i = 0; i < notes.length; i++) {
      final n = notes[i];
      stdout.writeln(
        '${(i + 1).toString().padLeft(3)}  '
        '${_noteName(n.midi).padRight(5)} '
        '${(n.onMs / 1000).toStringAsFixed(3).padLeft(7)}s '
        '${(n.offMs / 1000).toStringAsFixed(3).padLeft(7)}s '
        '${n.confidence.toStringAsFixed(2).padLeft(6)}  '
        '${gmProgramName(n.program)}',
      );
    }
  }

  if (xmlOut != null) {
    final grid = detectRhythm(mono, sampleRate: wav.sampleRate);
    final parts = transcribeToParts(notes, grid);
    File(xmlOut).writeAsStringSync(
      multiPartToMusicXml(MultiPartScore([for (final p in parts) p.score])),
    );
    stderr.writeln('wrote $xmlOut — ${parts.length} part(s): '
        '${parts.map((p) => gmProgramName(p.program)).join(', ')}');
  }
}
