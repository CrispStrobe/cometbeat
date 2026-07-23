// SFZ import — the text-based sample-instrument format (sfzformat.org), mapped
// onto the SAME Sf2SoundFont / Sf2Zone / Sf2Sample model the resampling voice in
// `midi_render.dart` already plays. An `.sfz` file is a little text document of
// `<global>` / `<group>` / `<region>` headers, each carrying `opcode=value`
// pairs (inherited global → group → region), plus a `<control>` `default_path`.
// Every `<region>` names a `sample=` and a key/velocity window; we load each
// referenced audio file once (via the [SfzSampleReader] seam so this file stays
// Flutter-free and unit-testable), translate its opcodes to SF2 generators
// (key/vel range, root key, tune, volume, pan, DAHDSR, low-pass, loop mode), and
// hand back a browsable [LoadedSoundFont] — so the CLI and synth need no new
// playback path. Unknown opcodes are ignored; a region whose sample can't be
// read is skipped (reported via [onWarn]) rather than failing the whole load.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mp3/mp3_decoder.dart';
import 'package:comet_beat/core/audio/sf2/sf2.dart';
import 'package:comet_beat/core/audio/sf2/soundfont_loader.dart';
import 'package:comet_beat/core/audio/wav_io.dart';

/// Fetches the bytes of a sample referenced by an SFZ region, given its path
/// *relative to the `.sfz` file* (already joined with any `default_path`).
/// Returns null if the file can't be found — the region is then skipped. Kept as
/// a seam so the loader has no `dart:io` dependency (the CLI supplies a
/// filesystem-backed reader; tests supply an in-memory map).
typedef SfzSampleReader = Uint8List? Function(String samplePath);

double _log2(double x) => log(x) / ln2;

/// Parse SFZ [text] into a [LoadedSoundFont]. [readSample] resolves each region's
/// `sample=` (with `default_path` already prepended) to audio bytes. [name]
/// labels the single preset produced. [onWarn] receives a line for each skipped
/// region.
/// Throws [SoundFontLoadException] if no region yields a playable sample.
LoadedSoundFont loadSfz(
  String text, {
  required SfzSampleReader readSample,
  String name = 'SFZ',
  void Function(String message)? onWarn,
}) {
  final regions = _parseSfz(text);
  if (regions.isEmpty) {
    throw SoundFontLoadException('No <region> blocks found in this .sfz file.');
  }

  // Decode each distinct audio file once; a zone references its sample by shdr.
  final samples = <Sf2Sample?>[];
  final byKey = <String, int>{}; // "path|loopStart|loopEnd" → shdr index
  final pcmCache = <String, (Float64List, int)>{}; // path → (mono pcm, rate)
  final zones = <Sf2Zone>[];

  for (final r in regions) {
    final rawSample = r['sample'];
    if (rawSample == null || rawSample.isEmpty) continue;
    final path = _joinPath(r['default_path'], rawSample);

    // Decode the WAV (cached across regions that share a file).
    (Float64List, int)? decoded = pcmCache[path];
    if (decoded == null) {
      final bytes = readSample(path);
      if (bytes == null) {
        onWarn?.call('skipped region: sample not found: $path');
        continue;
      }
      try {
        final decodedSample = _decodeSampleAudio(bytes);
        if (decodedSample == null) {
          onWarn?.call('skipped region: unsupported audio sample: $path');
          continue;
        }
        decoded = (decodedSample.$1, decodedSample.$2);
      } on FormatException catch (e) {
        onWarn?.call('skipped region: bad audio $path (${e.message})');
        continue;
      }
      pcmCache[path] = decoded;
    }
    final pcm = decoded.$1;
    final rate = decoded.$2;

    // Loop region (offsets into the sample). Default to the whole sample when a
    // looping mode is set but no explicit points are given.
    final loopMode = r['loop_mode'] ?? r['loopmode'];
    final loops = loopMode == 'loop_continuous' || loopMode == 'loop_sustain';
    final loopStart = _int(r['loop_start'] ?? r['loopstart']) ?? 0;
    final loopEnd =
        _int(r['loop_end'] ?? r['loopend']) ?? (loops ? pcm.length - 1 : 0);
    final sampleModes = !loops ? 0 : (loopMode == 'loop_sustain' ? 3 : 1);

    final key = '$path|$loopStart|$loopEnd';
    var shdr = byKey[key];
    if (shdr == null) {
      shdr = samples.length;
      byKey[key] = shdr;
      samples.add(
        Sf2Sample(
          name: rawSample,
          pcm: pcm,
          sampleRate: rate,
          originalPitch: 60, // the zone's rootKey carries the real key centre
          pitchCorrection: 0,
          loopStart: loopStart.clamp(0, pcm.length),
          loopEnd: loopEnd.clamp(0, pcm.length),
        ),
      );
    }

    zones.add(_zoneFor(r, shdr, sampleModes));
  }

  final playable = zones.where((z) => z.sampleIndex >= 0).toList();
  if (playable.isEmpty) {
    throw SoundFontLoadException(
      'No playable regions in this .sfz (samples missing or unreadable).',
    );
  }

  final preset = Sf2Preset(name: name, bank: 0, program: 0, zones: playable);
  final font = Sf2SoundFont(samples, [preset]);
  return LoadedSoundFont(font, compressed: false);
}

(Float64List, int)? _decodeSampleAudio(Uint8List bytes) {
  if (_isWav(bytes)) {
    final wav = readWavPcm16(bytes);
    return (wavToMonoFloat(wav), wav.sampleRate > 0 ? wav.sampleRate : 44100);
  }
  if (_isMp3(bytes)) {
    final decoded = mp3Decode(bytes);
    return (
      _deinterleaveMono(decoded.samples, decoded.channels),
      decoded.sampleRate > 0 ? decoded.sampleRate : 44100,
    );
  }
  return null;
}

bool _isWav(Uint8List b) =>
    b.length >= 12 &&
    b[0] == 0x52 &&
    b[1] == 0x49 &&
    b[2] == 0x46 &&
    b[3] == 0x46 &&
    b[8] == 0x57 &&
    b[9] == 0x41 &&
    b[10] == 0x56 &&
    b[11] == 0x45;

bool _isMp3(Uint8List b) {
  if (b.length < 3) return false;
  if (b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33) return true;
  final end = b.length - 1 < 4096 ? b.length - 1 : 4096;
  for (var i = 0; i < end; i++) {
    if (b[i] == 0xFF && (b[i + 1] & 0xE0) == 0xE0) return true;
  }
  return false;
}

Float64List _deinterleaveMono(Float64List samples, int channels) {
  if (channels <= 1) return samples;
  final frames = samples.length ~/ channels;
  final out = Float64List(frames);
  for (var f = 0; f < frames; f++) {
    var sum = 0.0;
    for (var c = 0; c < channels; c++) {
      sum += samples[f * channels + c];
    }
    out[f] = sum / channels;
  }
  return out;
}

/// Translate one region's opcode map to an [Sf2Zone] over sample [shdr].
Sf2Zone _zoneFor(Map<String, String> r, int shdr, int sampleModes) {
  // Key window: `key=` sets lokey=hikey=pitch_keycenter at once.
  final key = _note(r['key']);
  final keyLo = _note(r['lokey']) ?? key ?? 0;
  final keyHi = _note(r['hikey']) ?? key ?? 127;
  final rootKey = _note(r['pitch_keycenter']) ?? key ?? 60;
  final velLo = _int(r['lovel']) ?? 0;
  final velHi = _int(r['hivel']) ?? 127;

  // Tune: `tune`/`pitch` are cents, `transpose` semitones.
  final fineTune = _int(r['tune'] ?? r['pitch']) ?? 0;
  final coarseTune = _int(r['transpose']) ?? 0;

  // Level + pan.
  final volumeDb = _double(r['volume']) ?? 0.0;
  final attenuationCb = (-10.0 * volumeDb).round();
  final panTenthPct = ((_double(r['pan']) ?? 0.0) * 5).round().clamp(-500, 500);

  // DAHDSR (SFZ ampeg_* are seconds / sustain %). SF2 stores times as timecents
  // (2^(tc/1200) s); an unset stage keeps the SF2 default (−12000 ≈ instant).
  int tc(String? v) {
    final s = _double(v);
    if (s == null) return -12000;
    if (s <= 0) return -12000;
    return (1200 * _log2(s)).round();
  }

  final sustainPct = _double(r['ampeg_sustain']);
  final sustainVolCb = sustainPct == null
      ? 0
      : (-200 * log(max(sustainPct, 0.05) / 100) / ln10).round().clamp(0, 1440);

  // Low-pass: `cutoff` Hz → absolute cents; `resonance` dB → centibels.
  final cutoff = _double(r['cutoff']);
  final filterFcCents =
      cutoff == null ? 13500 : (1200 * _log2(cutoff / 8.176)).round();
  final filterQCb = ((_double(r['resonance']) ?? 0.0) * 10).round();

  return Sf2Zone(
    keyLo: keyLo,
    keyHi: keyHi,
    sampleIndex: shdr,
    rootKey: rootKey,
    velLo: velLo,
    velHi: velHi,
    attenuationCb: attenuationCb,
    coarseTune: coarseTune,
    fineTune: fineTune,
    delayVolTc: tc(r['ampeg_delay']),
    attackVolTc: tc(r['ampeg_attack']),
    holdVolTc: tc(r['ampeg_hold']),
    decayVolTc: tc(r['ampeg_decay']),
    sustainVolCb: sustainVolCb,
    releaseVolTc: tc(r['ampeg_release']),
    filterFcCents: filterFcCents,
    filterQCb: filterQCb,
    panTenthPct: panTenthPct,
    sampleModes: sampleModes,
  );
}

// ── Parser ───────────────────────────────────────────────────────────────────

/// Flatten SFZ [text] to a list of region opcode maps, each already merged with
/// its enclosing `<global>` / `<master>` / `<group>` opcodes and the
/// `<control>` `default_path`. Later opcodes win (region overrides group
/// overrides global), matching the SFZ inheritance rule.
List<Map<String, String>> _parseSfz(String text) {
  // Strip comments: `//` to end of line, and `/* … */` blocks.
  final clean = text
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ')
      .replaceAll(RegExp(r'//[^\n]*'), ' ');

  final control = <String, String>{};
  var global = <String, String>{};
  var master = <String, String>{};
  var group = <String, String>{};
  Map<String, String>? region;
  final regions = <Map<String, String>>[];

  // The current header a following opcode belongs to.
  Map<String, String>? target = global;

  // A token is either a `<header>` or an `opcode=value`. Values may contain
  // spaces (sample paths), so a whitespace token that is neither a header nor a
  // `key=value` continues the previous value.
  String? lastKey;
  for (final tok in clean.split(RegExp(r'\s+'))) {
    if (tok.isEmpty) continue;
    if (tok.startsWith('<') && tok.endsWith('>')) {
      final h = tok.substring(1, tok.length - 1).toLowerCase();
      lastKey = null;
      switch (h) {
        case 'control':
          target = control;
        case 'global':
          global = <String, String>{};
          master = group = {};
          target = global;
        case 'master':
          master = <String, String>{...global};
          group = {};
          target = master;
        case 'group':
          group = <String, String>{...global, ...master};
          target = group;
        case 'region':
          region = <String, String>{
            ...global,
            ...master,
            ...group,
            if (control['default_path'] != null)
              'default_path': control['default_path']!,
          };
          regions.add(region);
          target = region;
        default:
          // Unknown header (e.g. <curve>, <effect>) — ignore its opcodes.
          target = null;
      }
      continue;
    }
    final eq = tok.indexOf('=');
    if (eq > 0) {
      final k = tok.substring(0, eq).toLowerCase();
      final v = tok.substring(eq + 1);
      target?[k] = v;
      lastKey = k;
    } else if (lastKey != null && target != null) {
      // Continuation of a spaced value (e.g. a sample path with a space).
      target[lastKey] = '${target[lastKey]} $tok';
    }
  }
  return regions;
}

// ── Value parsing ──────────────────────────────────────────────────────────

int? _int(String? s) => s == null ? null : int.tryParse(s.trim());
double? _double(String? s) => s == null ? null : double.tryParse(s.trim());

/// A key value: a MIDI number, or a note name (`c4`, `f#3`, `Db-1`) with the
/// c4 = 60 convention. Returns null if [s] is null/unparseable.
int? _note(String? s) {
  if (s == null) return null;
  final t = s.trim();
  final n = int.tryParse(t);
  if (n != null) return n;
  final m = RegExp(r'^([a-gA-G])([#b]?)(-?\d+)$').firstMatch(t);
  if (m == null) return null;
  const pc = {'c': 0, 'd': 2, 'e': 4, 'f': 5, 'g': 7, 'a': 9, 'b': 11};
  var semi = pc[m.group(1)!.toLowerCase()]!;
  if (m.group(2) == '#') semi += 1;
  if (m.group(2) == 'b') semi -= 1;
  final octave = int.parse(m.group(3)!);
  return (octave + 1) * 12 + semi; // c4 → (4+1)*12 + 0 = 60
}

/// Join a region's `default_path` with its `sample=`, normalising Windows
/// backslashes. An absolute-looking sample path ignores `default_path`.
String _joinPath(String? defaultPath, String sample) {
  final s = sample.replaceAll(r'\', '/').trim();
  final dp = (defaultPath ?? '').replaceAll(r'\', '/').trim();
  if (dp.isEmpty || s.startsWith('/')) return s;
  return dp.endsWith('/') ? '$dp$s' : '$dp/$s';
}
