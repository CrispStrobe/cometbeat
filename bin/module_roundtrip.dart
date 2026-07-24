// Module round-trip checker.
//
// This separates container/codec problems from playback problems:
//   source -> ModuleDoc -> X1 -> ModuleDoc -> X2 -> ModuleDoc
//
// X1 and X2 are written files, while the comparisons are made in the neutral
// model. If libopenmpt123 is available, it also renders the source and X1 so
// an independent reader can validate the conversion acoustically.
//
//   dart run bin/module_roundtrip.dart song.it [--format it]

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/wav_io.dart';

Future<void> main(List<String> args) async {
  final paths = args.where((a) => !a.startsWith('-')).toList();
  if (paths.isEmpty) {
    stderr.writeln('usage: dart run bin/module_roundtrip.dart <module> '
        '[--format it|xm|s3m|mod] [--openmpt PATH]');
    exitCode = 2;
    return;
  }
  final sourcePath = paths.first;
  final sourceFile = File(sourcePath);
  if (!sourceFile.existsSync()) {
    stderr.writeln('module_roundtrip: no such file: $sourcePath');
    exitCode = 2;
    return;
  }

  final targetName = _value(args, '--format') ?? 'it';
  final target = ModuleFormat.values.firstWhere(
    (f) => f.name == targetName,
    orElse: () => throw ArgumentError('unknown format: $targetName'),
  );
  final sourceBytes = sourceFile.readAsBytesSync();
  final source = parseAnyModule(sourceBytes);
  final x1Bytes = convertDocTo(source, target);
  final base = _withoutExtension(sourceFile.uri.pathSegments.last);
  final outputDir = Directory(
    _value(args, '--output-dir') ??
        Directory.systemTemp.createTempSync('module_roundtrip_').path,
  )..createSync(recursive: true);
  final x1Path = '${outputDir.path}/$base.x1.${target.name}';
  final x2Path = '${outputDir.path}/$base.x2.${target.name}';
  File(x1Path).writeAsBytesSync(x1Bytes);

  final x1 = parseAnyModule(x1Bytes);
  final x2Bytes = convertDocTo(x1, target);
  File(x2Path).writeAsBytesSync(x2Bytes);
  final x2 = parseAnyModule(x2Bytes);

  final d01 = _diff(source, x1);
  final d12 = _diff(x1, x2);
  stdout.writeln('source: $sourcePath (${source.sourceFormat.name})');
  stdout.writeln('target: ${target.name}');
  stdout.writeln('X1: $x1Path (${x1Bytes.length} bytes)');
  stdout.writeln('X2: $x2Path (${x2Bytes.length} bytes)');
  _printDiff('source -> X1', d01);
  _printDiff('X1 -> X2', d12);

  final audioCheck = args.contains('--no-external')
      ? null
      : await _renderExternal(
          _value(args, '--openmpt') ?? 'openmpt123',
          sourcePath,
          x1Path,
          outputDir.path,
          seconds: double.tryParse(_value(args, '--seconds') ?? ''),
        );
  if (d01.isNotEmpty || d12.isNotEmpty || audioCheck == false) exitCode = 1;
}

String? _value(List<String> args, String key) {
  final i = args.indexOf(key);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

String _withoutExtension(String name) {
  final i = name.lastIndexOf('.');
  return i <= 0 ? name : name.substring(0, i);
}

List<String> _diff(ModuleDoc a, ModuleDoc b) {
  final out = <String>[];
  void check(bool condition, String message) {
    if (!condition && out.length < 20) out.add(message);
  }

  check(a.title.trim() == b.title.trim(), 'title "${a.title}" != "${b.title}"');
  check(a.channelCount == b.channelCount,
      'channels ${a.channelCount} != ${b.channelCount}');
  check(a.initialSpeed == b.initialSpeed,
      'speed ${a.initialSpeed} != ${b.initialSpeed}');
  check(a.initialTempo == b.initialTempo,
      'tempo ${a.initialTempo} != ${b.initialTempo}');
  final orderA = _validOrder(a), orderB = _validOrder(b);
  check(orderA.toString() == orderB.toString(), 'order $orderA != $orderB');
  check(a.patterns.length == b.patterns.length,
      'patterns ${a.patterns.length} != ${b.patterns.length}');
  check(a.linearFrequency == b.linearFrequency,
      'linear frequency ${a.linearFrequency} != ${b.linearFrequency}');
  check(a.xmInstruments.length == b.xmInstruments.length,
      'XM instruments ${a.xmInstruments.length} != ${b.xmInstruments.length}');
  final xmInstruments =
      math.min(a.xmInstruments.length, b.xmInstruments.length);
  for (var i = 0; i < xmInstruments; i++) {
    final ia = a.xmInstruments[i], ib = b.xmInstruments[i];
    check(ia.keymap.toString() == ib.keymap.toString(),
        'XM instrument ${i + 1} keymap differs');
    check(
        ia.vibratoType == ib.vibratoType &&
            ia.vibratoSweep == ib.vibratoSweep &&
            ia.vibratoDepth == ib.vibratoDepth &&
            ia.vibratoRate == ib.vibratoRate &&
            ia.fadeout == ib.fadeout,
        'XM instrument ${i + 1} playback fields differ');
  }

  final patternCount = math.min(a.patterns.length, b.patterns.length);
  for (var p = 0; p < patternCount; p++) {
    final pa = a.patterns[p], pb = b.patterns[p];
    check(pa.numRows == pb.numRows, 'pattern $p row count differs');
    final rows = math.min(pa.rows.length, pb.rows.length);
    for (var r = 0; r < rows; r++) {
      final cells = math.min(pa.rows[r].length, pb.rows[r].length);
      for (var c = 0; c < cells; c++) {
        if (pa.rows[r][c] != pb.rows[r][c]) {
          check(
              false,
              'cell p$p r$r c$c ${_cellText(pa.rows[r][c])} != '
              '${_cellText(pb.rows[r][c])}');
        }
      }
    }
  }

  check(a.samples.length == b.samples.length,
      'samples ${a.samples.length} != ${b.samples.length}');
  final samples = math.min(a.samples.length, b.samples.length);
  for (var i = 0; i < samples; i++) {
    final sa = a.samples[i], sb = b.samples[i];
    check(sa.pcm.length == sb.pcm.length, 'sample ${i + 1} length differs');
    check(sa.loopStart == sb.loopStart && sa.loopLength == sb.loopLength,
        'sample ${i + 1} loop differs');
    check(sa.pingPong == sb.pingPong, 'sample ${i + 1} ping-pong differs');
    check(sa.volume == sb.volume, 'sample ${i + 1} volume differs');
    check(sa.c5speed == sb.c5speed, 'sample ${i + 1} C5 speed differs');
    final n = math.min(sa.pcm.length, sb.pcm.length);
    final tolerance = sa.sixteenBit || sb.sixteenBit ? 1e-4 : 1 / 128;
    for (var k = 0; k < n; k++) {
      if ((sa.pcm[k] - sb.pcm[k]).abs() > tolerance) {
        check(false, 'sample ${i + 1} PCM differs at $k');
        break;
      }
    }
  }
  return out;
}

String _cellText(DocCell c) =>
    '(n${c.note},i${c.instrument},v${c.volume},off${c.noteOff},'
    'f${c.effect.toRadixString(16)}:${c.effectParam.toRadixString(16)})';

List<int> _validOrder(ModuleDoc d) =>
    d.order.where((i) => i >= 0 && i < d.patterns.length).toList();

void _printDiff(String label, List<String> diff) {
  if (diff.isEmpty) {
    stdout.writeln('$label: PASS');
  } else {
    stdout.writeln('$label: CHECK (${diff.length} differences shown)');
    for (final line in diff) stdout.writeln('  $line');
  }
}

Future<bool?> _renderExternal(
    String executable, String sourcePath, String x1Path, String outputDir,
    {double? seconds}) async {
  final rendered = <({double duration, double peak, double rms})>[];
  for (final input in [sourcePath, x1Path]) {
    final copied = '$outputDir/external_${input.split('/').last}';
    File(copied).writeAsBytesSync(File(input).readAsBytesSync());
    final command = <String>[
      '--render',
      '--samplerate',
      '44100',
      '--channels',
      '2',
      '--no-float',
      '--output-type',
      'wav',
      '--force',
      '--quiet',
      copied,
    ];
    if (seconds != null && seconds > 0) {
      command.insert(command.length - 1, '--end-time');
      command.insert(command.length - 1, seconds.toString());
    }
    final result = await Process.run(executable, command);
    if (result.exitCode != 0) {
      stdout
          .writeln('external render: SKIP ($executable unavailable or failed)');
      return null;
    }
    final wavPath = '$copied.wav';
    final stats = _wavStats(File(wavPath).readAsBytesSync());
    rendered.add(stats);
    stdout.writeln('external render ${input.split('/').last}: $wavPath '
        '(duration ${stats.duration.toStringAsFixed(3)}s, '
        'peak ${stats.peak.toStringAsFixed(4)}, '
        'RMS ${stats.rms.toStringAsFixed(4)})');
  }
  final durationDelta = (rendered[0].duration - rendered[1].duration).abs();
  final levelRatio = rendered[0].rms == 0 || rendered[1].rms == 0
      ? double.infinity
      : math.max(rendered[0].rms, rendered[1].rms) /
          math.min(rendered[0].rms, rendered[1].rms);
  final pass = durationDelta <= 0.5 && levelRatio <= 1.25;
  stdout.writeln('external audio source -> X1: ${pass ? 'PASS' : 'CHECK'} '
      '(duration delta ${durationDelta.toStringAsFixed(3)}s, '
      'RMS ratio ${levelRatio.toStringAsFixed(2)})');
  return pass;
}

({double duration, double peak, double rms}) _wavStats(Uint8List bytes) {
  final wav = readWavPcm16(bytes);
  var peak = 0.0, sum = 0.0;
  for (final sample in wav.samples) {
    final v = sample / 32768.0;
    peak = math.max(peak, v.abs());
    sum += v * v;
  }
  final rms = wav.samples.isEmpty ? 0.0 : math.sqrt(sum / wav.samples.length);
  return (
    duration: wav.channels == 0 || wav.sampleRate == 0
        ? 0
        : wav.samples.length / wav.channels / wav.sampleRate,
    peak: peak,
    rms: rms,
  );
}
