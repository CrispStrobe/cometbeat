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

import 'package:comet_beat/core/audio/crisp_dsp/modulated_delay.dart'
    show chorusFx;
import 'package:comet_beat/core/audio/crisp_dsp/reverb.dart' show reverbFx;
import 'package:comet_beat/core/audio/gm_song_render.dart';
import 'package:comet_beat/core/audio/midi_render.dart' show renderMidiFile;
import 'package:comet_beat/core/audio/mp3/mp3_encoder.dart';
import 'package:comet_beat/core/audio/score_instrument_render.dart';
import 'package:comet_beat/core/audio/sf2/sf2.dart' show VorbisDecode;
import 'package:comet_beat/core/audio/sf2/sfz.dart' show loadSfz;
import 'package:comet_beat/core/audio/sf2/soundfont_loader.dart';
import 'package:comet_beat/core/audio/sf2/vorbis_glint_ffi.dart';
import 'package:comet_beat/core/audio/synth.dart' show Instrument, kSampleRate;
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
  var notation = false; // force the quantized notation path for MIDI
  var bpm = 120;
  var bitrate = 192;
  var gain = 1.0;
  var reverb = 0.22; // a present stereo room by default; --reverb 0 for dry
  var chorus = 0.0; // off by default
  var bits = 16; // WAV bit depth (16 or 24)
  var play = false; // play the result through the system audio

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '--sf2':
        sf2 = _next(args, ++i, a);
      case '--play':
        play = true;
      case '--single':
        single = true;
      case '--notation':
        notation = true;
      case '--preset':
        preset = int.parse(_next(args, ++i, a));
        presetSet = true;
      case '--bpm':
        bpm = int.parse(_next(args, ++i, a));
      case '--bitrate':
        bitrate = int.parse(_next(args, ++i, a));
      case '--gain':
        gain = double.parse(_next(args, ++i, a));
      case '--reverb':
        reverb = double.parse(_next(args, ++i, a)).clamp(0.0, 1.0);
      case '--chorus':
        chorus = double.parse(_next(args, ++i, a)).clamp(0.0, 1.0);
      case '--bits':
        bits = int.parse(_next(args, ++i, a));
        if (bits != 16 && bits != 24) _fail('--bits must be 16 or 24');
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
  // With --play, the output file is optional — synthesize to a temp WAV, play
  // it, and remove it. Otherwise <in> <out> are both required.
  if (pos.isEmpty || (pos.length < 2 && !play)) _usage(exitCode: 2);
  final inPath = pos[0];
  final playTemp = play && pos.length < 2;
  final outPath = playTemp
      ? '${Directory.systemTemp.path}/rendersong_${pid}_play.wav'
      : pos[1];
  if (bpm < 1) _fail('--bpm must be positive');
  final fmt = from ?? _formatOf(inPath);
  final lower = outPath.toLowerCase();
  final isMp3 = lower.endsWith('.mp3');
  final isFlac = lower.endsWith('.flac');
  if (!isMp3 && !isFlac && !lower.endsWith('.wav')) {
    _fail('output must end in .wav, .mp3 or .flac');
  }

  // General-MIDI per-part voicing: with a SoundFont, voice each part by its OWN
  // GM program (drums → the bank-128 kit) — from a multi-track MIDI's program
  // changes, or a MultiPart format's per-part <midi-program> metadata. The
  // default when --sf2 is given; --preset N or --single forces one voice.
  final gmEligible = sf2 != null && !presetSet && !single;
  const multiPartFormats = {
    'abc', 'musicxml', 'mxl', 'mscx', 'mscz', 'mei', 'kern', //
  };

  // Render to a stereo pair (event-accurate MIDI synth), per-part mono buffers
  // (notation GM → panned stereo), or one mono buffer.
  // Tempo: --bpm wins, else the score's / MIDI's own tempo, else 120.
  (Float64List, Float64List)? stereoPair;
  List<Float64List>? gmParts;
  Float64List? mono;
  int effBpm;

  if (gmEligible && fmt == 'midi' && !notation) {
    // Event-accurate synth: exact timing, tempo map, CC7/10/11, sustain pedal,
    // per-channel program — the faithful MIDI path (--notation forces the old
    // quantized route). The file's tempo map is used, so --bpm is ignored here.
    final bytes = File(inPath).readAsBytesSync();
    effBpm = midiTempoBpm(bytes) ?? 120;
    // The synth applies per-channel reverb/chorus sends (CC91/CC93) scaled by
    // these, so the CLI must NOT double them on the master below.
    stereoPair = renderMidiFile(
      bytes,
      _loadFont(sf2),
      reverbMix: reverb,
      chorusMix: chorus,
    );
    stderr.writeln('  event-accurate MIDI synth '
        '(exact timing · tempo map · CC · sustain pedal · CC91/93 sends)');
  } else if (gmEligible && fmt == 'midi') {
    final bytes = File(inPath).readAsBytesSync();
    effBpm = bpmExplicit(args) ? bpm : (midiTempoBpm(bytes) ?? 120);
    gmParts = _renderGmParts(
      gmPartsFromMidi(bytes),
      _loadFont(sf2),
      _quarterMs(effBpm),
    );
  } else if (gmEligible && multiPartFormats.contains(fmt)) {
    final mp = _load(inPath, from) as MultiPartScore;
    effBpm = bpmExplicit(args) ? bpm : _tempoOfParts(mp.parts);
    gmParts = _renderGmParts(
      gmPartsFromMultiPart(mp),
      _loadFont(sf2),
      _quarterMs(effBpm),
    );
  } else {
    final loaded = _load(inPath, from);
    final parts = loaded is MultiPartScore ? loaded.parts : [loaded as Score];
    effBpm = bpmExplicit(args) ? bpm : _tempoOfParts(parts);
    final qms = _quarterMs(effBpm);
    final TrackerInstrument voice;
    if (sf2 != null) {
      voice = _soundFontVoice(sf2, preset);
    } else {
      voice = const AdditiveInstrument('piano', Instrument.piano);
      stderr.writeln('no --sf2 given → built-in additive piano');
    }
    mono = loaded is MultiPartScore
        ? renderMultiPartWithInstrument(loaded, voice, quarterMs: qms)
        : renderScoreWithInstrument(loaded as Score, voice, quarterMs: qms);
  }

  // Mix down → soft-knee master → write. Stereo (panned) for a GM band of ≥2
  // parts, mono otherwise.
  final target = 0.9 * gain;
  final Uint8List bytes;
  final int frames;
  final isStereo =
      stereoPair != null || (gmParts != null && gmParts.length > 1);
  // WAV/FLAC share the PCM path; FLAC writes a WAV then converts.
  final wantWavPcm = !isMp3;
  if (isStereo) {
    var (left, right) = stereoPair ?? panPartsToStereo(gmParts!);
    if (left.isEmpty) _fail('the score produced no notes to render');
    // The event-accurate synth already applied per-channel reverb/chorus sends;
    // only the notation-GM stereo path gets the master FX here.
    if (stereoPair == null) {
      if (chorus > 0) {
        left = chorusFx(left, mix: chorus);
        right = chorusFx(right, mix: chorus);
      }
      if (reverb > 0) {
        left = reverbFx(left, mix: reverb);
        right = reverbFx(right, mix: reverb);
      }
    }
    _masterStereo(left, right, target);
    frames = left.length;
    bytes = wantWavPcm
        ? _wavStereo(left, right, bits)
        : mp3EncodeStereo(left, right, bitrate: bitrate);
  } else {
    var m = (gmParts != null && gmParts.isNotEmpty) ? gmParts.first : mono!;
    if (m.isEmpty) _fail('the score produced no notes to render');
    if (chorus > 0) m = chorusFx(m, mix: chorus);
    if (reverb > 0) m = reverbFx(m, mix: reverb);
    _master(m, target);
    frames = m.length;
    bytes = wantWavPcm ? _wavMono(m, bits) : mp3EncodeMono(m, bitrate: bitrate);
  }

  if (isFlac) {
    _writeFlac(outPath, bytes); // WAV bytes → .flac via an external encoder
  } else {
    File(outPath).writeAsBytesSync(bytes);
  }

  final secs = (frames / kSampleRate).toStringAsFixed(1);
  final chans = isStereo ? 'stereo' : 'mono';
  if (!playTemp) {
    stderr.writeln(
      'wrote $outPath  (${bytes.length} bytes, ${secs}s @ $effBpm BPM, $chans)',
    );
  }

  if (play) {
    stderr.writeln('playing (${secs}s, $chans) …');
    final ok = _playFile(outPath);
    if (playTemp) {
      try {
        File(outPath).deleteSync();
      } catch (_) {}
    }
    if (!ok) {
      _fail('no audio player found (tried afplay/ffplay/play/mpv/aplay/cvlc)');
    }
  }
}

int _quarterMs(int bpm) => (60000 / bpm).round();

/// Whether `--bpm` was passed explicitly (so it overrides the score's tempo).
bool bpmExplicit(List<String> args) => args.contains('--bpm');

/// The tempo (quarter-note BPM) of the first part that declares one, else 120.
int _tempoOfParts(List<Score> parts) {
  for (final p in parts) {
    final t = p.tempo?.quarterBpm;
    if (t != null) return t.round();
  }
  return 120;
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
  // A `.sfz` is a text instrument: parse it and load its WAV samples relative
  // to the .sfz's own directory (the same model, so playback is unchanged).
  if (sf2Path.toLowerCase().endsWith('.sfz')) {
    final dir = File(sf2Path).parent.path;
    try {
      return loadSfz(
        f.readAsStringSync(),
        readSample: (rel) {
          final s = File('$dir/$rel');
          return s.existsSync() ? s.readAsBytesSync() : null;
        },
        name: sf2Path.split(Platform.pathSeparator).last,
        onWarn: (m) => stderr.writeln('  $m'),
      );
    } on SoundFontLoadException catch (e) {
      _fail('SFZ: ${e.message}');
    }
  }
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

/// Voice each [parts] entry with its own GM preset from [font] (drums → the
/// bank-128 kit) and render each to its OWN mono buffer (for stereo panning).
/// Falls back to bank 0 for the same program, then the font's first preset, so
/// a sparse SoundFont still plays something.
List<Float64List> _renderGmParts(
  List<GmPart> parts,
  LoadedSoundFont font,
  int quarterMs,
) {
  if (parts.isEmpty) _fail('no playable parts to render');
  final voiced = <(Score, TrackerInstrument)>[];
  for (final p in parts) {
    final preset = findPreset(font, p.isDrum ? 128 : 0, p.program) ??
        findPreset(font, 0, p.program) ??
        font.presets.first;
    voiced.add((p.score, soundFontInstrument(font, preset)));
    final label = p.name.isEmpty ? 'track' : p.name;
    stderr.writeln('  part "$label" → ${soundFontPresetLabel(preset)}');
  }
  return renderPartsSeparate(voiced, quarterMs: quarterMs);
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

/// Master a mono buffer: peak-normalize to [target] (< 1.0), pure gain only.
///
/// No soft-clip / waveshaping: because the whole buffer is scaled by one gain,
/// this can never distort — the mix keeps its exact shape and [target]'s
/// headroom (0.9 → −1 dB) covers reconstruction overshoot. An earlier version
/// soft-clipped the top of the normalized signal, which audibly buzzed a nearly
/// pure low tone (a kick drum): its wide near-peak crest got flattened into
/// harmonics. Gain staging already lives in the SF2 voice + this normalize, so
/// no clipper is needed. (Loudness for playback is handled downstream.)
void _master(Float64List x, double target) => _scaleToPeak(x, target);

/// Master a stereo pair together, using ONE shared gain so the stereo image
/// isn't skewed by per-channel scaling. Pure gain, as [_master].
void _masterStereo(Float64List left, Float64List right, double target) =>
    _scaleToPeak2(left, right, target);

/// Scale [x] so its peak magnitude becomes [target] (no-op on silence).
void _scaleToPeak(Float64List x, double target) {
  var peak = 0.0;
  for (final s in x) {
    final a = s.abs();
    if (a > peak) peak = a;
  }
  if (peak <= 0) return;
  final g = target / peak;
  for (var i = 0; i < x.length; i++) {
    x[i] *= g;
  }
}

/// Scale a stereo pair by ONE shared gain so their combined peak becomes
/// [target] (keeps the L/R balance intact).
void _scaleToPeak2(Float64List left, Float64List right, double target) {
  var peak = 0.0;
  for (final s in left) {
    final a = s.abs();
    if (a > peak) peak = a;
  }
  for (final s in right) {
    final a = s.abs();
    if (a > peak) peak = a;
  }
  if (peak <= 0) return;
  final g = target / peak;
  for (var i = 0; i < left.length; i++) {
    left[i] *= g;
  }
  for (var i = 0; i < right.length; i++) {
    right[i] *= g;
  }
}

Uint8List _wavMono(Float64List x, int bits) => _wav([x], bits);
Uint8List _wavStereo(Float64List l, Float64List r, int bits) =>
    _wav([l, r], bits);

/// Encode [chans] (mono or stereo) as a PCM WAV at [bits] (16 or 24) bit depth.
Uint8List _wav(List<Float64List> chans, int bits) {
  final numCh = chans.length;
  var n = 0;
  for (final c in chans) {
    if (c.length > n) n = c.length;
  }
  final bytesPer = bits ~/ 8;
  final blockAlign = numCh * bytesPer;
  final dataLen = n * blockAlign;
  final b = BytesBuilder();
  void u32(int v) =>
      b.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
  void u16(int v) => b.add([v & 0xff, (v >> 8) & 0xff]);
  b.add('RIFF'.codeUnits);
  u32(36 + dataLen);
  b.add('WAVE'.codeUnits);
  b.add('fmt '.codeUnits);
  u32(16);
  u16(1); // PCM
  u16(numCh);
  u32(kSampleRate);
  u32(kSampleRate * blockAlign);
  u16(blockAlign);
  u16(bits);
  b.add('data'.codeUnits);
  u32(dataLen);
  final maxv = (1 << (bits - 1)) - 1;
  for (var i = 0; i < n; i++) {
    for (final c in chans) {
      final s = i < c.length ? c[i] : 0.0;
      final v = (s.clamp(-1.0, 1.0) * maxv).round();
      if (bits == 16) {
        b.add([v & 0xff, (v >> 8) & 0xff]);
      } else {
        // 24-bit little-endian signed.
        b.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff]);
      }
    }
  }
  return b.toBytes();
}

/// Write [wavBytes] as a `.flac` at [outPath] via an external encoder
/// (flac or ffmpeg). Fails clearly if neither is installed.
void _writeFlac(String outPath, Uint8List wavBytes) {
  final tmp = '${Directory.systemTemp.path}/rendersong_${pid}_flac.wav';
  File(tmp).writeAsBytesSync(wavBytes);
  void cleanup() {
    try {
      File(tmp).deleteSync();
    } catch (_) {}
  }

  final converters = <(String, List<String>)>[
    ('flac', ['-s', '-f', '-o', outPath, tmp]),
    ('ffmpeg', ['-y', '-loglevel', 'quiet', '-i', tmp, outPath]),
  ];
  final finder = Platform.isWindows ? 'where' : 'which';
  for (final (cmd, cmdArgs) in converters) {
    try {
      if (Process.runSync(finder, [cmd]).exitCode != 0) continue;
    } catch (_) {
      continue;
    }
    final ok = Process.runSync(cmd, cmdArgs).exitCode == 0;
    cleanup();
    if (ok) return;
    _fail('FLAC conversion failed via $cmd');
  }
  cleanup();
  _fail('no FLAC encoder found (install flac or ffmpeg)');
}

// ── arg plumbing ─────────────────────────────────────────────────────────────

String _next(List<String> args, int i, String flag) {
  if (i >= args.length) _fail('$flag needs a value');
  return args[i];
}

/// Play [path] through the first available system audio player, blocking until
/// it finishes. Returns false if none is installed.
bool _playFile(String path) {
  // Test/CI seam: skip the actual player (no audio) but report success.
  if (Platform.environment['COMET_RENDERSONG_NOPLAY'] == '1') return true;
  // (command, leading args); the file path is appended. First on PATH wins.
  final players = <(String, List<String>)>[
    ('afplay', <String>[]), // macOS, built-in
    ('ffplay', ['-autoexit', '-nodisp', '-loglevel', 'quiet']),
    ('play', ['-q']), // sox
    ('mpv', ['--really-quiet']),
    ('aplay', ['-q']), // Linux/ALSA (WAV)
    ('cvlc', ['--play-and-exit', '--quiet']),
  ];
  final finder = Platform.isWindows ? 'where' : 'which';
  for (final (cmd, args) in players) {
    try {
      if (Process.runSync(finder, [cmd]).exitCode != 0) continue;
    } catch (_) {
      continue;
    }
    try {
      return Process.runSync(cmd, [...args, path]).exitCode == 0;
    } catch (_) {
      continue;
    }
  }
  return false;
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
  --sf2 <file>     SoundFont (.sf2 / .sf3) or SFZ instrument (.sfz) to voice with
  --preset <N>     force ONE preset (index) for the whole song
  --single         force a single voice (preset 0) — disables GM per-part
  --notation       MIDI: force the quantized notation path (default is the
                   event-accurate synth: exact timing, CC, sustain pedal)
  --bpm <B>        tempo (default 120)
  --bitrate <K>    MP3 bitrate kbps (default 192)
  --gain <G>       output gain multiplier (default 1.0)
  --reverb <0..1>  master reverb mix (default 0.22, stereo; 0 = dry)
  --chorus <0..1>  master chorus mix (default 0 = off)
  --bits <16|24>   WAV/FLAC bit depth (default 16)
  --play           play the result through the system audio (the <out> file is
                   optional with --play — a temp is used and removed)

Output: <out.wav | out.mp3 | out.flac>. FLAC needs an external `flac` or
`ffmpeg` on PATH.
  --from <fmt>     force input format (abc/midi/musicxml/mxl/mscx/mscz/mei/
                   kern/gp3/gp4/gp5/gp/gpx/gpif)

A .sf3 SoundFont needs GLINT_LIB pointing at the glint shared library.''');
  exit(exitCode);
}
