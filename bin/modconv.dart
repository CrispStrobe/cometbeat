// bin/modconv.dart
//
// Headless module converter — reads any tracker module (.mod/.s3m/.xm/.it) and
// writes it in another format, via the SAME pure-Dart neutral-hub converters the
// app uses. Also extracts a module's samples to WAV ("steal an instrument").
//
//   dart run bin/modconv.dart song.s3m song.xm         # convert (out fmt = ext)
//   dart run bin/modconv.dart song.it out.mod
//   dart run bin/modconv.dart song.xm --extract-samples samples/   # → WAVs
//
// Notes, instruments, volume, samples, order, and the effect column all carry
// over; conversion is only lossy where a format can't represent a feature —
// MOD caps at 4 channels and 8-bit samples (its volume/note-off become Cxx/C00
// effects), S3M/IT translate effects to their letter commands (a few Exy have no
// equivalent), and XM/IT keep 16-bit sample precision. See the per-dimension
// contract in test/module_*_roundtrip_test.dart. Flutter-free — runs under
// plain `dart run`.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/synth.dart' show wavBytes;

/// Output file extension → target format. The actual encoding goes through the
/// shared [convertDocTo] dispatcher so a new format is wired in exactly once.
const _extToFormat = <String, ModuleFormat>{
  'mod': ModuleFormat.mod,
  'xm': ModuleFormat.xm,
  's3m': ModuleFormat.s3m,
  'it': ModuleFormat.it,
};

void main(List<String> args) {
  final positional = <String>[];
  String? extractDir;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--extract-samples') {
      if (i + 1 >= args.length) {
        stderr.writeln('modconv: --extract-samples needs a directory');
        exitCode = 2;
        return;
      }
      extractDir = args[++i];
    } else if (a.startsWith('-')) {
      stderr.writeln('modconv: unknown option $a');
      exitCode = 2;
      return;
    } else {
      positional.add(a);
    }
  }

  if (positional.isEmpty || (extractDir == null && positional.length < 2)) {
    stderr.writeln('usage: dart run bin/modconv.dart <in> <out>\n'
        '       dart run bin/modconv.dart <in> --extract-samples <dir>');
    exitCode = 2;
    return;
  }

  final inPath = positional.first;
  final inFile = File(inPath);
  if (!inFile.existsSync()) {
    stderr.writeln('modconv: no such file: $inPath');
    exitCode = 2;
    return;
  }
  final bytes = inFile.readAsBytesSync();
  if (sniffModuleFormat(bytes) == null) {
    stderr.writeln('modconv: $inPath is not a recognized module');
    exitCode = 1;
    return;
  }

  final ModuleDoc doc;
  try {
    doc = parseAnyModule(bytes);
  } catch (e) {
    stderr.writeln('modconv: failed to parse $inPath: $e');
    exitCode = 1;
    return;
  }

  if (extractDir != null) {
    _extractSamples(doc, extractDir);
    return;
  }

  final outPath = positional[1];
  final ext = outPath.split('.').last.toLowerCase();
  final target = _extToFormat[ext];
  if (target == null) {
    stderr.writeln('modconv: unknown output format ".$ext" '
        '(use .mod/.xm/.s3m/.it)');
    exitCode = 2;
    return;
  }
  File(outPath).writeAsBytesSync(convertDocTo(doc, target));
  stdout.writeln('modconv: ${doc.sourceFormat.name} → .$ext  '
      '($inPath → $outPath)');
}

void _extractSamples(ModuleDoc doc, String dir) {
  Directory(dir).createSync(recursive: true);
  var n = 0;
  for (var i = 0; i < doc.samples.length; i++) {
    final s = doc.samples[i];
    if (s.isEmpty) continue;
    final pcm16 = Int16List(s.pcm.length);
    for (var k = 0; k < s.pcm.length; k++) {
      pcm16[k] = (s.pcm[k] * 32767).round().clamp(-32768, 32767);
    }
    final rate = s.c5speed > 0 ? s.c5speed : 8363;
    final name = _sanitize(s.name);
    final base = name.isEmpty ? 'sample' : name;
    final path = '$dir/${_padL('${i + 1}', 2, '0')}_$base.wav';
    File(path).writeAsBytesSync(wavBytes(pcm16, sampleRate: rate));
    stdout.writeln('  → $path  (${s.pcm.length} samples @ ${rate}Hz)');
    n++;
  }
  stdout.writeln('modconv: extracted $n sample(s) to $dir/');
}

String _sanitize(String s) =>
    s.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_').replaceAll(
          RegExp(r'^_+|_+$'),
          '',
        );

String _padL(String s, int w, [String fill = ' ']) =>
    s.length >= w ? s : fill * (w - s.length) + s;
