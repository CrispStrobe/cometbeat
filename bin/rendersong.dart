// bin/rendersong.dart
//
// Render a whole SONG to audio through a SoundFont (or a built-in voice) — the
// missing "play this piece" CLI. Parses any notation format crisp_notation_core
// reads (ABC / Guitar Pro / MIDI / MusicXML / MuseScore / MEI / Humdrum), voices
// every note through a chosen SoundFont preset via the same
// loadSoundFont → soundFontInstrument → renderScoreWithInstrument pipeline the
// app uses, and writes a WAV or MP3. Flutter-free, so it runs under plain
// `dart run` like bin/listen.dart / bin/sfont.dart.
//
//   # a General-MIDI SoundFont voice (piano = preset 0) → MP3
//   dart run bin/rendersong.dart tune.abc out.mp3 --sf2 FluidR3Mono_GM.sf3
//
//   # pick a preset + tempo + bitrate; render a Guitar Pro tab to WAV
//   dart run bin/rendersong.dart song.gp3 out.wav --sf2 gm.sf2 --preset 24 --bpm 96
//
//   # no SoundFont → a built-in additive piano
//   dart run bin/rendersong.dart score.musicxml out.mp3
//
// A multi-track MIDI + a SoundFont voices EACH part with its own General-MIDI
// instrument (piano, bass, strings…) and the channel-10 track with a drum kit —
// this is the default for MIDI + --sf2. Pass --preset N or --single for one
// voice across the whole song. Other formats render through one voice.
//
// Inputs (by extension, or --from): abc · mid/midi · musicxml/xml · mxl ·
//   mscx · mscz · mei · krn/kern · gp3 · gp4 · gp5 · gp/gpx · gpif.
// Outputs (by extension): .wav · .mp3 (mono).
//
// A `.sf3` (Ogg-Vorbis) SoundFont needs the native glint decoder — point
// GLINT_LIB at libglint.dylib/.so/glint.dll (uncompressed `.sf2` needs nothing).

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/gm_song_render.dart';
import 'package:comet_beat/core/audio/mp3/mp3_encoder.dart';
import 'package:comet_beat/core/audio/score_instrument_render.dart';
import 'package:comet_beat/core/audio/sf2/sf2.dart' show VorbisDecode;
import 'package:comet_beat/core/audio/sf2/soundfont_loader.dart';
import 'package:comet_beat/core/audio/sf2/vorbis_glint_ffi.dart';
import 'package:comet_beat/core/audio/synth.dart'
    show Instrument, kSampleRate, wavBytes;
import 'package:comet_beat/core/audio/tracker_engine.dart';
// The Flutter-free notation core (a dependency_override, re-exported via
// crisp_notation) — import it directly to stay Flutter-free.
// ignore: depend_on_referenced_packages
import 'package:crisp_notation_core/crisp_notation_core.dart';

void main(List<String> args) {
  final pos = <String>[];
  String? sf2;
  String? from;
  var preset = 0;
  var presetSet = false;
  var single = false;
  var bpm = 120;
  var bitrate = 192;
  var gain = 1.0;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '--sf2':
        sf2 = _next(args, ++i, a);
      case '--single':
        single = true;
      case '--preset':
        preset = int.parse(_next(args, ++i, a));
        presetSet = true;
      case '--bpm':
        bpm = int.parse(_next(args, ++i, a));
      case '--bitrate':
        bitrate = int.parse(_next(args, ++i, a));
      case '--gain':
        gain = double.parse(_next(args, ++i, a));
      case '--from':
        from = _next(args, ++i, a);
      case '-h':
      case '--help':
        _usage(exitCode: 0);
      default:
        if (a.startsWith('-')) _fail('unknown option: $a');
        pos.add(a);
    }
  }
  if (pos.length < 2) _usage(exitCode: 2);
  final inPath = pos[0];
  final outPath = pos[1];
  if (bpm < 1) _fail('--bpm must be positive');

  final quarterMs = (60000 / bpm).round();
  final fmt = from ?? _formatOf(inPath);

  // General-MIDI per-part voicing: a multi-track MIDI + a SoundFont, each part
  // voiced by its OWN GM program (drums → the bank-128 kit). This is the default
  // for MIDI + --sf2; --preset N or --single forces one voice for the whole song.
  final gmMode = fmt == 'midi' && sf2 != null && !presetSet && !single;

  final Float64List pcm;
  if (gmMode) {
    pcm = _renderGm(inPath, sf2, quarterMs);
  } else {
    // Parse to a Score / MultiPartScore and render it through one voice.
    final loaded = _load(inPath, from);
    final TrackerInstrument voice;
    if (sf2 != null) {
      voice = _soundFontVoice(sf2, preset);
    } else {
      voice = const AdditiveInstrument('piano', Instrument.piano);
      stderr.writeln('no --sf2 given → built-in additive piano');
    }
    pcm = loaded is MultiPartScore
        ? renderMultiPartWithInstrument(loaded, voice, quarterMs: quarterMs)
        : renderScoreWithInstrument(
            loaded as Score,
            voice,
            quarterMs: quarterMs,
          );
  }
  if (pcm.isEmpty) _fail('the score produced no notes to render');

  // 4) Headroom-normalize (peak → 0.9 · gain), then write WAV or MP3.
  _normalize(pcm, 0.9 * gain);
  final lower = outPath.toLowerCase();
  final Uint8List bytes;
  if (lower.endsWith('.mp3')) {
    bytes = mp3EncodeMono(pcm, bitrate: bitrate);
  } else if (lower.endsWith('.wav')) {
    bytes = wavBytes(_toInt16(pcm));
  } else {
    _fail('output must end in .wav or .mp3');
  }
  File(outPath).writeAsBytesSync(bytes);

  final secs = (pcm.length / kSampleRate).toStringAsFixed(1);
  stderr
      .writeln('wrote $outPath  (${bytes.length} bytes, ${secs}s @ $bpm BPM)');
}

// ── Input routing (mirrors crisp_notation_cli's _loadScore) ──────────────────

/// Parse [path] to a [MultiPartScore] (preferred, all parts) or a [Score]
/// (MIDI / Guitar Pro, which flatten to one score).
Object _load(String path, String? from) {
  final file = File(path);
  if (!file.existsSync()) _fail('no such file: $path');
  final fmt = from ?? _formatOf(path);
  Uint8List bytes() => file.readAsBytesSync();
  String text() => _readText(file);
  switch (fmt) {
    case 'abc':
      return multiPartScoreFromAbc(text());
    case 'musicxml':
      return multiPartScoreFromMusicXml(text());
    case 'mxl':
      return multiPartScoreFromMusicXml(readMusicXmlFromMxl(bytes()));
    case 'mscx':
      return multiPartScoreFromMscx(text());
    case 'mscz':
      return multiPartScoreFromMscx(readMscxFromMscz(bytes()));
    case 'mei':
      return multiPartScoreFromMei(text());
    case 'kern':
      return multiPartScoreFromKern(text());
    case 'midi':
      return scoreFromMidi(bytes());
    case 'gpif':
      return scoreFromGpif(text());
    case 'gp':
      return scoreFromGpif(readGpifFromGp(bytes()));
    case 'gpx':
      return scoreFromGpif(readGpifFromGpx(bytes()));
    case 'gp5':
      return gp5ToScore(bytes());
    case 'gp4':
      return gp4ToScore(bytes());
    case 'gp3':
      return gp3ToScore(bytes());
    default:
      _fail('unknown input format for $path (use --from)');
  }
}

String _formatOf(String path) {
  final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'xml':
    case 'musicxml':
      return 'musicxml';
    case 'mid':
    case 'midi':
      return 'midi';
    case 'krn':
    case 'kern':
      return 'kern';
    default:
      return ext; // abc, mxl, mscx, mscz, mei, gp3/4/5, gp, gpx, gpif
  }
}

/// Read a text score, honouring a UTF-16/UTF-8 BOM (MusicXML is often UTF-16 LE
/// with a BOM, which `readAsStringSync` can't decode). Mirrors the crisp CLI.
String _readText(File file) {
  final b = file.readAsBytesSync();
  if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) {
    final u = <int>[];
    for (var i = 2; i + 1 < b.length; i += 2) {
      u.add(b[i] | (b[i + 1] << 8));
    }
    return String.fromCharCodes(u);
  }
  if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
    final u = <int>[];
    for (var i = 2; i + 1 < b.length; i += 2) {
      u.add((b[i] << 8) | b[i + 1]);
    }
    return String.fromCharCodes(u);
  }
  return file.readAsStringSync(); // UTF-8 (BOM tolerated by the readers)
}

// ── SoundFont voice ──────────────────────────────────────────────────────────

LoadedSoundFont _loadFont(String sf2Path) {
  final f = File(sf2Path);
  if (!f.existsSync()) _fail('no such SoundFont: $sf2Path');
  return loadSoundFont(f.readAsBytesSync(), vorbis: _tryVorbis());
}

TrackerInstrument _soundFontVoice(String sf2Path, int preset) {
  final loaded = _loadFont(sf2Path);
  if (preset < 0 || preset >= loaded.presets.length) {
    _fail('--preset $preset out of range (font has ${loaded.presets.length})');
  }
  final p = loaded.presets[preset];
  stderr.writeln('voice: ${soundFontPresetLabel(p)}'
      '${loaded.compressed ? ' (.sf3)' : ''}');
  return soundFontInstrument(loaded, p);
}

/// General-MIDI per-part render: split [inPath] into GM parts, voice each with
/// its own program from [sf2Path] (drums → the bank-128 kit), and mix.
Float64List _renderGm(String inPath, String sf2Path, int quarterMs) {
  final font = _loadFont(sf2Path);
  final parts = gmPartsFromMidi(File(inPath).readAsBytesSync());
  if (parts.isEmpty) _fail('no playable tracks in $inPath');
  final voiced = <(Score, TrackerInstrument)>[];
  for (final p in parts) {
    // Drums live in bank 128; melodic voices in bank 0. Fall back to bank 0 for
    // the same program, then to the font's first preset, so a sparse SoundFont
    // still plays something.
    final preset = findPreset(font, p.isDrum ? 128 : 0, p.program) ??
        findPreset(font, 0, p.program) ??
        font.presets.first;
    voiced.add((p.score, soundFontInstrument(font, preset)));
    final label = p.name.isEmpty ? 'track' : p.name;
    stderr.writeln('  part "$label" → ${soundFontPresetLabel(preset)}');
  }
  return renderPartsWithVoices(voiced, quarterMs: quarterMs);
}

/// A native Vorbis decoder for `.sf3`, if `GLINT_LIB` points at the glint
/// shared library; otherwise null (fine for uncompressed `.sf2`).
VorbisDecode? _tryVorbis() {
  final lib = Platform.environment['GLINT_LIB'];
  if (lib == null || lib.isEmpty) return null;
  try {
    return GlintVorbis.open(lib).decode;
  } catch (_) {
    stderr.writeln('warning: GLINT_LIB set but could not load: $lib');
    return null;
  }
}

// ── PCM helpers ──────────────────────────────────────────────────────────────

void _normalize(Float64List pcm, double target) {
  var peak = 0.0;
  for (final s in pcm) {
    final a = s.abs();
    if (a > peak) peak = a;
  }
  if (peak <= 0) return;
  final k = target / peak;
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] *= k;
  }
}

Int16List _toInt16(Float64List pcm) {
  final out = Int16List(pcm.length);
  for (var i = 0; i < pcm.length; i++) {
    final v = (pcm[i] * 32767).round();
    out[i] = v < -32768 ? -32768 : (v > 32767 ? 32767 : v);
  }
  return out;
}

// ── arg plumbing ─────────────────────────────────────────────────────────────

String _next(List<String> args, int i, String flag) {
  if (i >= args.length) _fail('$flag needs a value');
  return args[i];
}

Never _fail(String msg) {
  stderr.writeln('error: $msg');
  exit(2);
}

Never _usage({required int exitCode}) {
  // ignore: close_sinks
  final w = exitCode == 0 ? stdout : stderr;
  w.writeln('''
Render a song through a SoundFont to WAV/MP3.

  dart run bin/rendersong.dart <in> <out.wav|.mp3> [options]

Options:
  --sf2 <file>     SoundFont (.sf2 / .sf3) to voice the song with
  --preset <N>     force ONE preset (index) for the whole song
  --single         force a single voice (preset 0) — disables GM per-part
  --bpm <B>        tempo (default 120)
  --bitrate <K>    MP3 bitrate kbps (default 192)
  --gain <G>       output gain multiplier (default 1.0)
  --from <fmt>     force input format (abc/midi/musicxml/mxl/mscx/mscz/mei/
                   kern/gp3/gp4/gp5/gp/gpx/gpif)

A .sf3 SoundFont needs GLINT_LIB pointing at the glint shared library.''');
  exit(exitCode);
}
