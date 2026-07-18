// .sf3 end-to-end harness — validates the whole CometBeat `.sf3` pipeline with a
// REAL Ogg-Vorbis decoder, and is the acceptance gate for glint's Vorbis
// decoder (docs/GLINT_VORBIS_HANDOVER.md).
//
// It plugs a decoder into `Sf2SoundFont.parse`'s `VorbisDecode` seam, decodes a
// real `.sf3` (e.g. FluidR3Mono_GM.sf3), builds Sf2Instruments for melodic GM
// presets, and reports each one's PITCH ACCURACY (the app's own MPM detector) —
// so a decoded organ/flute must play in tune, exactly as the uncompressed-.sf2
// path already does (Reed Organ ~2.6c).
//
//   dart run bin/sf3_oracle.dart <file.sf3> [--limit N] [--ffmpeg <path>]
//
// Decoder backend: **ffmpeg** (a stand-in reference Vorbis decoder) — a DEV
// tool, not a committed CI dependency. When glint ships `glint_vorbis_decode`,
// swap the backend (or add `--decoder glint`) and RE-RUN this harness: the pitch
// numbers must match, and each stream's glint-vs-ffmpeg PCM should agree at high
// SNR. Same shape as bin/oracle_ab.dart (openmpt for modules).
import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/pitch_analysis.dart' show PitchDetector;
import 'package:comet_beat/core/audio/sf2/sf2.dart';
import 'package:comet_beat/core/audio/sf2/vorbis_glint_ffi.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';

void main(List<String> args) {
  if (args.isEmpty || args.first.startsWith('-')) {
    stderr.writeln('usage: dart run bin/sf3_oracle.dart <file.sf3> '
        '[--limit N] [--ffmpeg <path>] [--glint <libglint.dylib>]');
    exit(2);
  }
  final path = args.first;
  final ffmpeg = _value(args, '--ffmpeg') ?? 'ffmpeg';
  final glintLib = _value(args, '--glint');
  final limit = int.tryParse(_value(args, '--limit') ?? '') ?? (1 << 30);

  final bytes = File(path).readAsBytesSync();
  if (!sf2IsCompressed(bytes)) {
    stderr.writeln('$path is not a compressed .sf3 (smpl is not OggS)');
    exit(1);
  }

  // Decoder backend: glint (native FFI — the app's real decoder) if --glint is
  // given, else ffmpeg (the reference stand-in).
  final glint = glintLib == null ? null : GlintVorbis.open(glintLib);
  final tmp = File('${Directory.systemTemp.path}/sf3_oracle_stream.ogg');
  var idx = 0, decoded = 0, failed = 0;
  Float64List? vorbis(Uint8List ogg) {
    if (idx++ >= limit) return null; // --limit: skip beyond N (fast smoke)
    final pcm =
        glint != null ? glint.decode(ogg) : _ffmpegDecode(ffmpeg, tmp, ogg);
    if (pcm == null || pcm.isEmpty) {
      failed++;
      return null;
    }
    decoded++;
    return pcm;
  }

  final sf = Sf2SoundFont.parse(bytes, vorbis: vorbis);
  if (tmp.existsSync()) tmp.deleteSync();
  stdout.writeln('decoder: ${glint != null ? 'glint ($glintLib)' : 'ffmpeg'}');
  stdout.writeln(path);
  stdout.writeln('  decoded $decoded streams (failed $failed) · '
      '${sf.presets.length} presets');

  // Pitch-check a few sustained melodic voices whose zones are all decoded.
  final det = PitchDetector();
  const timing = TrackerTiming(rows: 8, stepsPerBeat: 2);
  var checked = 0;
  for (final want in ['Organ', 'Flute', 'Pipe', 'Reed', 'String', 'Sax']) {
    final cands = sf.presets.where((p) {
      if (p.bank != 0 || !p.name.contains(want) || p.zones.length < 2) {
        return false;
      }
      return p.zones
          .every((z) => sf.sampleAt(z.sampleIndex)?.pcm.isNotEmpty ?? false);
    }).toList();
    if (cands.isEmpty) continue;
    final p = cands.first;
    final inst = sf2InstrumentFromPreset(sf, p, id: 'x');
    var tot = 0.0, n = 0;
    for (final note in [55, 60, 64, 67, 72]) {
      final cells = [
        TrackerCell(midi: note),
        ...List<TrackerCell>.filled(timing.rows - 1, TrackerCell.empty),
      ];
      final buf = inst.renderChannel(cells, timing);
      final w = det.windowSize;
      if (buf.length < 6000 + w) continue;
      final r = det.analyze(Float64List.sublistView(buf, 6000, 6000 + w));
      if (!r.hasPitch) continue;
      tot += ((r.nearestMidi - note) * 100 + r.cents).abs();
      n++;
    }
    if (n > 0) {
      checked++;
      stdout.writeln('  ${p.name.padRight(18)} mean pitch error '
          '${(tot / n).toStringAsFixed(1)}c over $n notes '
          '(${p.zones.length} zones)');
    }
  }
  if (checked == 0) {
    stdout.writeln('  (no fully-decoded melodic preset to pitch-check — '
        'raise --limit or drop it)');
  }
}

/// Decode ONE Ogg-Vorbis stream via ffmpeg → mono float32 PCM. The reference
/// Vorbis decoder for the harness (glint's decoder plugs in here later).
Float64List? _ffmpegDecode(String ffmpeg, File tmp, Uint8List ogg) {
  tmp.writeAsBytesSync(ogg);
  final res = Process.runSync(
    ffmpeg,
    ['-loglevel', 'error', '-i', tmp.path, '-f', 'f32le', '-ac', '1', '-'],
    stdoutEncoding: null, // raw bytes, not a decoded string
  );
  if (res.exitCode != 0) return null;
  final out = res.stdout as List<int>;
  final bd = ByteData.sublistView(Uint8List.fromList(out));
  final n = bd.lengthInBytes ~/ 4;
  final pcm = Float64List(n);
  for (var i = 0; i < n; i++) {
    pcm[i] = bd.getFloat32(i * 4, Endian.little);
  }
  return pcm;
}

String? _value(List<String> args, String key) {
  final i = args.indexOf(key);
  return (i >= 0 && i + 1 < args.length) ? args[i + 1] : null;
}
