// bin/transcribe.dart
//
// The UNIFIED headless transcription CLI: one entry point over every backend +
// model the decision framework can run from `dart run` (i.e. all but onnxFfi —
// the native-ORT plugin transitively needs the Flutter engine, so it's GUI-only
// and deliberately absent here). A WAV goes in; notes (mono F0 → note chain),
// polyphonic notes, or chords come out.
//
//   dart run bin/transcribe.dart audio.wav [options]
//
//   --task notes|poly|chords|tab|stems  what to produce (default notes)
//                              tab = guitar tablature from audio (TabCNN, prefers
//                              the GuitarProFX weights; auto-downloads / or set
//                              COMET_TABCNN_DIR)
//   --backend auto|dart|onnx|crispasr
//                              which runtime (default auto: crispasr → onnx →
//                              pure-Dart for F0). poly/chords are onnx-only;
//                              stems = onnx Open-Unmix or crispasr CLI.
//   --f0 pyin|dio|crepe|rmvpe      the F0 model for `notes` (default: per backend —
//                              dart→pyin, onnx→crepe, crispasr→crepe)
//   --f0-viterbi               path-smooth the neural F0 decode (crepe/rmvpe/
//                              fcpe) over the pitch lattice instead of per-frame
//                              argmax — kills octave flips/spikes; no-op for pyin
//   --sep-bin / --sep-model    crispasr binary + demucs GGUF for `--task stems`
//                              --backend crispasr (or env CRISPASR_BIN /
//                              CRISPASR_SEP_MODEL)
//   --a4 440                   reference pitch
//   --out tab.gp                (tab task) also write the frettings as a real
//                              GuitarPro file — so a rendered `.mp3`/`.wav`
//                              round-trips gp→audio→gp in two commands
//   --bpm 120                  (tab --out) tempo the tab is quantised against
//   --f0-dump                  print the raw pitch track instead of notes
//   --json                     machine-readable output
//
// Input is WAV (PCM16) or MP3 (pure-Dart decoder) — a `rendersong … out.mp3`
// render feeds straight back in.
//
// Each neural model auto-downloads on first use through its own *_model_store
// (MIT weights on the onnx_runtime_dart models-v1 release; crepe GGUF via
// CrispASR's registry). Convert to mono WAV first, e.g.
//   ffmpeg -i in.ogg -ac 1 -ar 44100 -c:a pcm_s16le out.wav
//
// Per-model CLIs still exist (transcribe_crepe/_basicpitch/_chords/_crispasr);
// this one is the single dispatcher over all of them.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mp3/mp3_decoder.dart' show mp3Decode;
import 'package:comet_beat/core/audio/synth.dart' show wavBytes;
import 'package:comet_beat/core/audio/transcription/basic_pitch_model_store.dart';
import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/crepe_model_store.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_pitch.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_pitch.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_separate.dart';
import 'package:comet_beat/core/audio/transcription/dio.dart' show dioEstimator;
import 'package:comet_beat/core/audio/transcription/f0_decode_options.dart';
import 'package:comet_beat/core/audio/transcription/harmony.dart';
import 'package:comet_beat/core/audio/transcription/harmony_model_store.dart';
import 'package:comet_beat/core/audio/transcription/pyin.dart' show pyinF0;
import 'package:comet_beat/core/audio/transcription/rmvpe_model_store.dart';
import 'package:comet_beat/core/audio/transcription/route.dart';
import 'package:comet_beat/core/audio/transcription/separate_umx_model_store.dart';
import 'package:comet_beat/core/audio/transcription/stems.dart';
import 'package:comet_beat/core/audio/wav_io.dart';
import 'package:comet_beat/features/games/composition/tab_emission_decoder.dart'
    show collapseTabFrames, kTabStrings;
import 'package:comet_beat/features/games/composition/tabcnn_emitter.dart'
    show audioToTab;
import 'package:crisp_notation_core/crisp_notation_core.dart';

const _names = [
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B', //
];
String _noteName(int midi) => '${_names[midi % 12]}${midi ~/ 12 - 1}';

double _optD(List<String> a, String f, double d) {
  final i = a.indexOf(f);
  return i >= 0 && i + 1 < a.length ? double.parse(a[i + 1]) : d;
}

String _optS(List<String> a, String f, String d) {
  final i = a.indexOf(f);
  return i >= 0 && i + 1 < a.length ? a[i + 1] : d;
}

Future<void> main(List<String> args) async {
  // Positionals = args that aren't a `--flag` nor the value consumed by a
  // value-taking flag — so `--task tab file.wav` doesn't mistake `tab` for the
  // file. Boolean flags (`--json`, `--f0-viterbi`, `--f0-dump`) take no value.
  const valueFlags = {
    '--task',
    '--backend',
    '--f0',
    '--sep-bin',
    '--sep-model',
    '--a4',
    '--out',
    '--bpm',
  };
  final positional = <String>[];
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a.startsWith('--')) {
      if (valueFlags.contains(a)) i++; // skip its value
      continue;
    }
    positional.add(a);
  }
  if (positional.isEmpty) {
    stderr.writeln(
      'usage: dart run bin/transcribe.dart audio.wav '
      '[--task notes|poly|chords|tab|stems] [--backend auto|dart|onnx|crispasr] '
      '[--f0 pyin|dio|crepe|rmvpe] [--f0-viterbi] [--sep-bin B] [--sep-model M] '
      '[--a4 440] [--out tab.gp] [--bpm 120] [--f0-dump] [--json]',
    );
    exit(64);
  }
  final path = positional.first;
  if (!File(path).existsSync()) {
    stderr.writeln('no such file: $path');
    exit(66);
  }
  final task = _optS(args, '--task', 'notes');
  final backend = _optS(args, '--backend', 'auto');
  final json = args.contains('--json');
  final a4 = _optD(args, '--a4', 440);

  // Force Viterbi path-smoothing on the neural F0 decoders (crepe/rmvpe/fcpe),
  // overriding the per-model COMET_*_VITERBI env gates. No effect on pyin/dio.
  if (args.contains('--f0-viterbi')) F0DecodeOptions.viterbi = true;

  // Accept WAV (PCM16) or MP3 (pure-Dart decoder) — so a `rendersong … .mp3`
  // render round-trips straight back through transcribe without a separate
  // decode step.
  final bytes = File(path).readAsBytesSync();
  final Float64List mono;
  final int sampleRate;
  final int channels;
  if (path.toLowerCase().endsWith('.mp3')) {
    final pcm = mp3Decode(bytes);
    sampleRate = pcm.sampleRate;
    channels = pcm.channels < 1 ? 1 : pcm.channels;
    final frames = pcm.samples.length ~/ channels;
    mono = Float64List(frames);
    for (var i = 0; i < frames; i++) {
      var sum = 0.0;
      for (var c = 0; c < channels; c++) {
        sum += pcm.samples[i * channels + c];
      }
      mono[i] = sum / channels;
    }
  } else {
    final wav = readWavPcm16(bytes);
    sampleRate = wav.sampleRate;
    channels = wav.channels;
    mono = wavToMonoFloat(wav);
  }
  stderr.writeln(
    'loaded $path — $sampleRate Hz, ${channels}ch, '
    '${(mono.length / sampleRate).toStringAsFixed(2)} s',
  );
  final sw = Stopwatch()..start();

  switch (task) {
    case 'poly':
      // Pooled by default (same path the app's neural provider takes);
      // COMET_BASICPITCH_WORKERS=0 falls back to the synchronous run.
      final transcribe = await BasicPitchModelStore().transcriber();
      final notes = await transcribe(mono, sampleRate);
      sw.stop();
      _printNotes(notes, sw, json);
    case 'chords':
      final bundle = await HarmonyModelStore().load();
      final chords = estimateChords(
        mono,
        model: bundle.model,
        cqt: bundle.cqt,
        sampleRate: sampleRate,
      );
      sw.stop();
      _printChords(chords, sw, json);
    case 'stems':
      final sep = await _resolveSeparator(backend, args);
      if (sep == null) {
        stderr.writeln(
          'no separator available — --backend onnx needs the Open-Unmix model '
          '(auto-downloads, needs network); --backend crispasr needs --sep-bin '
          '<crispasr> --sep-model <demucs.gguf> (or CRISPASR_BIN / '
          'CRISPASR_SEP_MODEL).',
        );
        exit(69);
      }
      final stems = await sep(mono, sampleRate);
      sw.stop();
      final written = _writeStems(path, stems, sampleRate);
      if (json) {
        stdout.writeln(jsonEncode(written));
      } else {
        stdout.writeln(
          '${written.length} stems  (${sw.elapsedMilliseconds} ms):',
        );
        for (final f in written) {
          stdout.writeln('  $f');
        }
      }
    case 'notes':
      final f0 = await _resolveF0(backend, _optS(args, '--f0', ''));
      if (args.contains('--f0-dump')) {
        final track = f0 == null
            ? pyinF0(mono, sampleRate: sampleRate)
            : await f0(mono, sampleRate);
        sw.stop();
        _printTrack(track, sw, json);
        return;
      }
      final notes = await transcribeMonophonic(
        mono,
        sampleRate: sampleRate,
        a4: a4,
        f0: f0,
      );
      sw.stop();
      _printNotes(notes, sw, json);
    case 'tab':
      // Audio → guitar tab via the TabCNN emitter (prefers gpfx) + the
      // per-string Viterbi decoder. Needs the model (auto-downloads, or point
      // COMET_TABCNN_DIR at a prebuilt tabcnn-gpfx.onnx + tabcnn-cqt.bin).
      final perFrame = await audioToTab(mono, sampleRate);
      sw.stop();
      if (perFrame == null) {
        stderr.writeln(
          'no TabCNN model available — needs network to fetch it from HF '
          '(cstr/tabcnn-onnx), or set COMET_TABCNN_DIR to a dir holding '
          'tabcnn-gpfx.onnx + tabcnn-cqt.bin.',
        );
        exit(69);
      }
      final tabOut = _optS(args, '--out', '');
      if (tabOut.isNotEmpty) {
        final bpm = _optD(args, '--bpm', 120).round();
        File(tabOut).writeAsBytesSync(_framesToGp(perFrame, bpm: bpm));
        stderr.writeln('wrote $tabOut (GuitarPro, bpm $bpm)');
      }
      _printTab(perFrame, sw, json);
    default:
      stderr.writeln('unknown --task "$task" (notes|poly|chords|tab|stems)');
      exit(64);
  }
}

/// Resolve the F0 estimator for the `notes` task from the backend + model
/// choice. Null ⇒ the pure-Dart pYIN default (web-safe, no model).
Future<F0Estimator?> _resolveF0(String backend, String model) async {
  // Pure-Dart F0 models (no download, any backend): `dio` = WORLD DIO+StoneMask
  // (a robust classical DSP tracker, pyworld-parity); `pyin` = the built-in
  // default (null estimator).
  if (model == 'dio') return dioEstimator();
  if (model == 'pyin') return null;

  Future<F0Estimator?> onnx() async {
    final m = model.isEmpty ? 'crepe' : model;
    if (m == 'rmvpe') return RmvpeModelStore().estimator();
    if (m == 'crepe') return crepeF0Estimator();
    return null; // pyin
  }

  Future<F0Estimator?> crispasr() async =>
      await crispasrFfiCrepeF0(download: true) ?? crispasrCliCrepeF0();

  switch (backend) {
    case 'dart':
      return null; // pyin
    case 'onnx':
      return onnx();
    case 'crispasr':
      final f0 = await crispasr();
      if (f0 == null) {
        stderr.writeln('crispasr backend unavailable — falling back to pyin');
      }
      return f0;
    case 'auto':
    default:
      // Fastest-first: crispasr ggml → onnx (crepe/rmvpe) → pyin.
      final ggml = await crispasr();
      if (ggml != null) {
        stderr.writeln('backend: crispasr (ggml CREPE)');
        return ggml;
      }
      final o = await onnx();
      if (o != null) {
        stderr.writeln('backend: onnx (${model.isEmpty ? 'crepe' : model})');
        return o;
      }
      stderr.writeln('backend: pure-Dart (pYIN)');
      return null;
  }
}

/// Resolve a source separator from the backend choice. onnx ⇒ Open-Unmix
/// (auto-downloads); crispasr ⇒ the `--separate` CLI (needs a binary + demucs
/// model). auto tries crispasr first, then onnx. Null ⇒ none available.
Future<Separator?> _resolveSeparator(String backend, List<String> args) async {
  Future<Separator?> onnx() async {
    try {
      return await UmxModelStore().separator(); // loads/downloads the model
    } catch (_) {
      return null;
    }
  }

  Separator? crispasr() {
    final env = Platform.environment;
    final bin = _optS(args, '--sep-bin', env['CRISPASR_BIN'] ?? '');
    final model = _optS(args, '--sep-model', env['CRISPASR_SEP_MODEL'] ?? '');
    if (bin.isEmpty || model.isEmpty) return null;
    return crispasrCliSeparator(binary: bin, model: model);
  }

  switch (backend) {
    case 'crispasr':
      return crispasr();
    case 'onnx':
      return onnx();
    case 'dart':
      return null; // no pure-Dart separator
    case 'auto':
    default:
      return crispasr() ?? await onnx();
  }
}

/// Write each non-null stem next to the input as `<base>_<name>.wav` (mono, at
/// the input sample rate). Returns the paths written.
List<String> _writeStems(String inputPath, Stems stems, int sr) {
  final base =
      inputPath.replaceAll(RegExp(r'\.wav$', caseSensitive: false), '');
  final out = <String>[];
  void write(String name, Float64List? pcm) {
    if (pcm == null) return;
    final i16 = Int16List(pcm.length);
    for (var k = 0; k < pcm.length; k++) {
      i16[k] = (pcm[k].clamp(-1.0, 1.0) * 32767).round();
    }
    final f = File('${base}_$name.wav')
      ..writeAsBytesSync(wavBytes(i16, sampleRate: sr));
    out.add(f.path);
  }

  write('vocals', stems.vocals);
  write('bass', stems.bass);
  write('drums', stems.drums);
  write('other', stems.other);
  return out;
}

void _printNotes(List<NoteEvent> events, Stopwatch sw, bool json) {
  if (json) {
    stdout.writeln(
      jsonEncode([
        for (final n in events)
          {
            'midi': n.midi,
            'name': _noteName(n.midi),
            'onMs': n.onMs,
            'offMs': n.offMs,
            'confidence': n.confidence,
          },
      ]),
    );
    return;
  }
  stdout.writeln('${events.length} notes  (${sw.elapsedMilliseconds} ms):');
  stdout.writeln('  #   note   start      end     conf');
  for (var i = 0; i < events.length; i++) {
    final n = events[i];
    stdout.writeln(
      '${(i + 1).toString().padLeft(3)}  '
      '${_noteName(n.midi).padRight(5)} '
      '${(n.onMs / 1000).toStringAsFixed(3).padLeft(7)}s '
      '${(n.offMs / 1000).toStringAsFixed(3).padLeft(7)}s '
      '${n.confidence.toStringAsFixed(2).padLeft(6)}',
    );
  }
}

/// Renders the per-frame frettings as an ASCII guitar tab: collapse identical
/// runs, drop sub-46 ms flickers, one column per surviving fretted event.
/// Quantise the per-frame frettings into a GuitarPro (.gp) byte blob so an
/// audio recording round-trips back to editable tab: collapse frame runs into
/// columns, snap each run's length to the nearest tab note value at [bpm], place
/// notes on the model's predicted strings, and serialise via GPIF. Standard
/// guitar tuning (string 0 = high e). Flutter-free (crisp_notation_core only),
/// mirroring `TabDocument.toScore` so it can live on the CLI path.
Uint8List _framesToGp(List<Map<int, int>> perFrame, {int bpm = 120}) {
  const hop = 512 / 22050;
  const durTable = <(NoteDuration, int)>[
    (NoteDuration.whole, 8),
    (NoteDuration(DurationBase.half, dots: 1), 6),
    (NoteDuration.half, 4),
    (NoteDuration(DurationBase.quarter, dots: 1), 3),
    (NoteDuration.quarter, 2),
    (NoteDuration.eighth, 1),
  ];
  NoteDuration nearest(int steps) {
    var best = durTable.last.$1;
    var bestDiff = 1 << 30;
    for (final (nd, s) in durTable) {
      final d = (s - steps).abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = nd;
      }
    }
    return best;
  }

  int stepsOf(NoteDuration d) {
    for (final (dur, s) in durTable) {
      if (dur == d) return s;
    }
    return 1;
  }

  final tuning = Tuning.standardGuitar;
  final measures = <Measure>[];
  final voicings = <TabVoicing>[];
  var bar = <MusicElement>[];
  var barSteps = 0;
  var idc = 0;
  for (final (frets, frames) in collapseTabFrames(perFrame)) {
    if (frames < 2) continue; // drop sub-46 ms flicker
    final beats = frames * hop * bpm / 60;
    final eighthSteps = (beats * 2).round().clamp(1, 8);
    final dur = nearest(eighthSteps);
    final steps = stepsOf(dur);
    if (barSteps > 0 && barSteps + steps > 8) {
      measures.add(Measure(bar));
      bar = <MusicElement>[];
      barSteps = 0;
    }
    if (frets.isEmpty) {
      bar.add(RestElement(dur));
    } else {
      final entries = frets.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      final id = 't${idc++}';
      bar.add(
        NoteElement(
          pitches: [
            for (final e in entries)
              Pitch.fromMidi(tuning.strings[e.key].midiNumber + e.value),
          ],
          duration: dur,
          id: id,
        ),
      );
      voicings.add(TabVoicing(id, [for (final e in entries) e.key]));
    }
    barSteps += steps;
  }
  if (bar.isNotEmpty) measures.add(Measure(bar));
  if (measures.isEmpty) {
    measures.add(const Measure([RestElement(NoteDuration.whole)]));
  }
  final score = Score(
    clef: Clef.treble,
    measures: measures,
    tabVoicings: voicings,
  );
  return writeGpFromGpif(scoreToGpif(score, tuning: tuning));
}

void _printTab(List<Map<int, int>> perFrame, Stopwatch sw, bool json) {
  const hop = 512 / 22050; // TabCNN frame hop (s)
  const minFrames = 2; // ignore < ~46 ms noise
  final events = <({Map<int, int> frets, int startFrame, int frames})>[];
  var f = 0;
  for (final (frets, n) in collapseTabFrames(perFrame)) {
    if (frets.isNotEmpty && n >= minFrames) {
      events.add((frets: frets, startFrame: f, frames: n));
    }
    f += n;
  }
  if (json) {
    stdout.writeln(
      jsonEncode([
        for (final e in events)
          {
            'frets': {for (final k in e.frets.keys) '$k': e.frets[k]},
            'startS': e.startFrame * hop,
            'durS': e.frames * hop,
          },
      ]),
    );
    return;
  }
  stdout
      .writeln('${events.length} tab events  (${sw.elapsedMilliseconds} ms):');
  if (events.isEmpty) return;
  // 6 string lines (0 = high e … 5 = low E), one 2-wide column per event.
  const labels = ['e', 'B', 'G', 'D', 'A', 'E'];
  final lines = [
    for (var s = 0; s < kTabStrings; s++) StringBuffer('  ${labels[s]}|'),
  ];
  for (final e in events) {
    for (var s = 0; s < kTabStrings; s++) {
      final cell =
          e.frets.containsKey(s) ? e.frets[s].toString().padLeft(2, '-') : '--';
      lines[s].write('-$cell');
    }
  }
  for (final l in lines) {
    stdout.writeln((l..write('-|')).toString());
  }
}

void _printChords(List<ChordEvent> chords, Stopwatch sw, bool json) {
  if (json) {
    stdout.writeln(
      jsonEncode([
        for (final c in chords)
          {
            'label': c.label,
            'rootPc': c.rootPc,
            'quality': c.quality,
            'onMs': c.onMs,
            'offMs': c.offMs,
          },
      ]),
    );
    return;
  }
  stdout.writeln('${chords.length} chords  (${sw.elapsedMilliseconds} ms):');
  stdout.writeln('  #   chord    start      end');
  for (var i = 0; i < chords.length; i++) {
    final c = chords[i];
    stdout.writeln(
      '${(i + 1).toString().padLeft(3)}  '
      '${c.label.padRight(7)} '
      '${(c.onMs / 1000).toStringAsFixed(3).padLeft(7)}s '
      '${(c.offMs / 1000).toStringAsFixed(3).padLeft(7)}s',
    );
  }
}

void _printTrack(PitchTrack track, Stopwatch sw, bool json) {
  if (json) {
    stdout.writeln(
      jsonEncode([
        for (final f in track)
          {'timeMs': f.timeMs, 'f0Hz': f.f0Hz, 'voicedProb': f.voicedProb},
      ]),
    );
    return;
  }
  stderr.writeln('${track.length} frames (${sw.elapsedMilliseconds} ms):');
  stdout.writeln('   time(s)     f0(Hz)   voiced');
  for (final f in track) {
    stdout.writeln(
      '${(f.timeMs / 1000).toStringAsFixed(3).padLeft(9)}  '
      '${f.f0Hz.toStringAsFixed(2).padLeft(9)}  '
      '${f.voicedProb.toStringAsFixed(3).padLeft(7)}',
    );
  }
}
