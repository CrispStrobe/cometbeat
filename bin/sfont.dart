// bin/sfont.dart
//
// Inspect and render SoundFont (.sf2 / .sf3) instruments from the command line —
// the same pipeline the Advanced Tracker uses in-app (loadSoundFont ->
// soundFontInstrument -> renderChannel), just headless. Flutter-free, so it runs
// under plain `dart run`.
//
//   dart run bin/sfont.dart info <font.sf2>
//       list every preset: index, bank:program, zone count, name.
//
//   dart run bin/sfont.dart render <font.sf2> <out.wav> [options]
//       extract a preset as a playable instrument and render it to a WAV.
//       --preset N   preset index (default 0)
//       --note M     MIDI note to sustain (default 60 = middle C)
//       --scale      play an ascending major scale from --note instead of one note
//       --bpm B      tempo (default 120)
//
// .sf2 needs nothing. .sf3 (Ogg-Vorbis-compressed samples) needs the native
// glint Vorbis library — point GLINT_LIB at libglint.dylib/.so/glint.dll.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/sf2.dart' show VorbisDecode;
import 'package:comet_beat/core/audio/sf2/soundfont_loader.dart';
import 'package:comet_beat/core/audio/sf2/vorbis_glint_ffi.dart';
import 'package:comet_beat/core/audio/synth.dart' show wavBytes;
import 'package:comet_beat/core/audio/tracker_engine.dart';

/// A native Vorbis decoder for `.sf3`, if `GLINT_LIB` points at the glint shared
/// library; otherwise null (fine for `.sf2`).
VorbisDecode? _tryVorbis() {
  final lib = Platform.environment['GLINT_LIB'];
  if (lib == null || lib.isEmpty) return null;
  try {
    final g = GlintVorbis.open(lib);
    return g.decode;
  } catch (_) {
    return null;
  }
}

/// Human-readable preset table (pure, so it is unit-testable).
String sfontInfoReport(LoadedSoundFont loaded) {
  final presets = loaded.font.presets;
  final b = StringBuffer('${presets.length} preset(s)\n')
    ..writeln('  #    bank:prog  zones  name');
  for (var i = 0; i < presets.length; i++) {
    final p = presets[i];
    b.writeln('  ${i.toString().padLeft(3)}  '
        '${'${p.bank}:${p.program}'.padRight(9)}  '
        '${p.zones.length.toString().padLeft(4)}   ${p.name}');
  }
  return b.toString();
}

/// A C-major scale (semitone steps 0 2 4 5 7 9 11 12) from [root].
List<int> majorScale(int root) {
  const steps = [0, 2, 4, 5, 7, 9, 11, 12];
  return [for (final s in steps) root + s];
}

/// Render preset [presetIndex] of [loaded] playing [notes] to a mono WAV (pure,
/// unit-testable). One note per row, plus a couple of trailing rows so the last
/// note rings out.
Uint8List sfontRenderWav(
  LoadedSoundFont loaded,
  int presetIndex,
  List<int> notes, {
  int bpm = 120,
}) {
  final preset = loaded.font.presets[presetIndex];
  final inst = soundFontInstrument(loaded, preset);
  final rows = notes.length + 2;
  final cells = [
    for (final n in notes) TrackerCell(midi: n),
    ...List<TrackerCell>.filled(rows - notes.length, TrackerCell.empty),
  ];
  final timing = TrackerTiming(tempoBpm: bpm, rows: rows, stepsPerBeat: 2);
  final pcm = inst.renderChannel(cells, timing);
  final i16 = Int16List(pcm.length);
  for (var i = 0; i < pcm.length; i++) {
    i16[i] = (pcm[i].clamp(-1.0, 1.0) * 32767).round();
  }
  return wavBytes(i16);
}

void _usage() {
  stderr.writeln('usage:\n'
      '  dart run bin/sfont.dart info <font.sf2|sf3>\n'
      '  dart run bin/sfont.dart render <font> <out.wav> '
      '[--preset N] [--note M] [--scale] [--bpm B]');
}

void main(List<String> args) {
  if (args.isEmpty) {
    _usage();
    exit(2);
  }
  final cmd = args[0];
  final rest = args.sublist(1);

  // Parse flags / positionals.
  final pos = <String>[];
  var preset = 0, note = 60, bpm = 120;
  var scale = false;
  for (var i = 0; i < rest.length; i++) {
    switch (rest[i]) {
      case '--preset':
        preset = int.parse(rest[++i]);
      case '--note':
        note = int.parse(rest[++i]);
      case '--bpm':
        bpm = int.parse(rest[++i]);
      case '--scale':
        scale = true;
      default:
        pos.add(rest[i]);
    }
  }

  if (cmd == 'info' || cmd == 'render') {
    if (pos.isEmpty) {
      _usage();
      exit(2);
    }
    final file = File(pos[0]);
    if (!file.existsSync()) {
      stderr.writeln('no such file: ${pos[0]}');
      exit(1);
    }
    final LoadedSoundFont loaded;
    try {
      loaded = loadSoundFont(file.readAsBytesSync(), vorbis: _tryVorbis());
    } catch (e) {
      stderr.writeln('could not read soundfont: $e');
      if ('$e'.contains('sf3') || '$e'.contains('Vorbis')) {
        stderr.writeln('(this looks like an .sf3 — set GLINT_LIB to the glint '
            'shared library for compressed samples)');
      }
      exit(1);
    }

    if (cmd == 'info') {
      stdout.write(sfontInfoReport(loaded));
      return;
    }

    // render
    if (pos.length < 2) {
      stderr
          .writeln('render needs an output path: ... render <font> <out.wav>');
      exit(2);
    }
    if (preset < 0 || preset >= loaded.font.presets.length) {
      stderr.writeln('preset $preset out of range '
          '(0..${loaded.font.presets.length - 1})');
      exit(1);
    }
    final notes = scale ? majorScale(note) : [note];
    final wav = sfontRenderWav(loaded, preset, notes, bpm: bpm);
    File(pos[1]).writeAsBytesSync(wav);
    final p = loaded.font.presets[preset];
    stdout.writeln('rendered preset $preset (${p.name}) '
        '${scale ? 'scale from' : 'note'} $note -> ${pos[1]} '
        '(${wav.length} bytes)');
    return;
  }

  stderr.writeln('unknown command: $cmd');
  _usage();
  exit(2);
}
