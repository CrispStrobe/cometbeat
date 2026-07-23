// loadSfz — the SFZ (text sample-instrument) importer maps `<global>`/`<group>`/
// `<region>` opcodes onto the SF2 zone model, so the existing resampling voice
// plays an SFZ with no new playback path. WAV samples are injected in-memory via
// the reader seam (no disk).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/midi_render.dart';
import 'package:comet_beat/core/audio/sf2/sfz.dart';
import 'package:comet_beat/core/audio/sf2/soundfont_loader.dart';
import 'package:comet_beat/core/audio/synth.dart' show wavBytes;
import 'package:comet_beat/shared/music_io/audio_export.dart'
    show pcmFloatToMp3;
import 'package:flutter_test/flutter_test.dart';

/// A little 44.1 kHz mono sine WAV to stand in for a real sample.
Uint8List _sineWav(double hz, int frames, {int rate = 44100}) {
  final s = Int16List(frames);
  for (var i = 0; i < frames; i++) {
    s[i] = (16000 * math.sin(2 * math.pi * hz * i / rate)).round();
  }
  return wavBytes(s, sampleRate: rate);
}

Float64List _sinePcm(double hz, int frames, {int rate = 44100}) {
  final s = Float64List(frames);
  for (var i = 0; i < frames; i++) {
    s[i] = 0.5 * math.sin(2 * math.pi * hz * i / rate);
  }
  return s;
}

void main() {
  final wav = _sineWav(440, 4000);
  Uint8List? reader(String p) => p == 'samples/note.wav' ? wav : null;

  test('a minimal region → one preset with a covering zone', () {
    const sfz = '''
      <region> sample=samples/note.wav lokey=48 hikey=72 pitch_keycenter=60
    ''';
    final loaded = loadSfz(sfz, readSample: reader);
    expect(loaded.presets, hasLength(1));
    final z = loaded.presets.single.zones.single;
    expect(z.keyLo, 48);
    expect(z.keyHi, 72);
    expect(z.rootKey, 60);
    expect(z.covers(60), isTrue);
    expect(z.covers(40), isFalse);
  });

  test('key= sets lokey, hikey and pitch_keycenter at once', () {
    const sfz = '<region> sample=samples/note.wav key=c4';
    final z = loadSfz(sfz, readSample: reader).presets.single.zones.single;
    expect(z.keyLo, 60); // c4 = 60
    expect(z.keyHi, 60);
    expect(z.rootKey, 60);
  });

  test('note names honour the c4 = 60 convention (incl. accidentals)', () {
    Sf2ZoneRoot z(String key) => _root(
          loadSfz(
            '<region> sample=samples/note.wav key=$key',
            readSample: reader,
          ),
        );
    expect(z('c4').root, 60);
    expect(z('a4').root, 69);
    expect(z('f#3').root, 54);
    expect(z('c-1').root, 0);
  });

  test('opcodes map to SF2 generators (volume/pan/tune/filter)', () {
    const sfz = '''
      <region> sample=samples/note.wav key=60
        volume=-6 pan=100 tune=25 transpose=-12
        cutoff=523.25 resonance=6
    ''';
    final z = loadSfz(sfz, readSample: reader).presets.single.zones.single;
    expect(z.attenuationCb, 60); // −6 dB → +60 cB attenuation
    expect(z.pan, closeTo(1.0, 1e-9)); // pan=100 → hard right
    expect(z.fineTune, 25);
    expect(z.coarseTune, -12);
    expect(z.filterCutoffHz, closeTo(523.25, 1));
    expect(z.filterQ, greaterThan(1.0)); // 6 dB resonance is peaky
  });

  test('ampeg envelope: seconds → timecents, sustain % → gain', () {
    const sfz = '''
      <region> sample=samples/note.wav key=60
        ampeg_attack=1 ampeg_decay=2 ampeg_sustain=50 ampeg_release=0.5
    ''';
    final z = loadSfz(sfz, readSample: reader).presets.single.zones.single;
    expect(z.attackVolSec, closeTo(1.0, 1e-6));
    expect(z.decayVolSec, closeTo(2.0, 1e-6));
    expect(z.releaseVolSec, closeTo(0.5, 1e-6));
    expect(z.sustainGain, closeTo(0.5, 0.02)); // 50 % ≈ 0.5 linear
  });

  test('loop_mode → sampleModes (continuous vs sustain vs none)', () {
    Sf2ZoneRoot loop(String? mode) => _root(
          loadSfz(
            '<region> sample=samples/note.wav key=60'
            '${mode == null ? '' : ' loop_mode=$mode'}',
            readSample: reader,
          ),
        );
    expect(loop(null).zone.sampleModes, 0);
    expect(loop('loop_continuous').zone.sampleModes, 1);
    expect(loop('loop_sustain').zone.sampleModes, 3);
  });

  test('<group> opcodes are inherited; a region overrides them', () {
    const sfz = '''
      <group> volume=-3 cutoff=1000
      <region> sample=samples/note.wav key=60
      <region> sample=samples/note.wav key=62 volume=0
    ''';
    final zs = loadSfz(sfz, readSample: reader).presets.single.zones;
    expect(zs, hasLength(2));
    expect(zs[0].attenuationCb, 30); // inherits −3 dB
    expect(zs[1].attenuationCb, 0); // overrides to 0 dB
    expect(zs[0].filterCutoffHz, closeTo(1000, 2)); // both inherit cutoff
    expect(zs[1].filterCutoffHz, closeTo(1000, 2));
  });

  test('<control> default_path is prepended to sample=', () {
    const sfz = '''
      <control> default_path=samples/
      <region> sample=note.wav key=60
    ''';
    // Reader only answers the joined path — proves the join happened.
    final loaded = loadSfz(sfz, readSample: reader);
    expect(loaded.presets.single.zones, hasLength(1));
  });

  test('a region whose sample is missing is skipped (others still load)', () {
    const sfz = '''
      <region> sample=samples/note.wav key=60
      <region> sample=samples/missing.wav key=62
    ''';
    final warnings = <String>[];
    final loaded = loadSfz(sfz, readSample: reader, onWarn: warnings.add);
    expect(loaded.presets.single.zones, hasLength(1));
    expect(warnings, hasLength(1));
    expect(warnings.single, contains('missing.wav'));
  });

  test('two regions sharing a WAV decode it once (one shdr sample)', () {
    const sfz = '''
      <region> sample=samples/note.wav lokey=60 hikey=60
      <region> sample=samples/note.wav lokey=61 hikey=61
    ''';
    final loaded = loadSfz(sfz, readSample: reader);
    expect(loaded.presets.single.zones, hasLength(2));
    expect(loaded.font.samples, hasLength(1)); // deduped
  });

  test('MP3-backed regions decode through the core audio decoders', () {
    final mp3 = pcmFloatToMp3(_sinePcm(330, 4608));
    Uint8List? mp3Reader(String p) => p == 'samples/note.mp3' ? mp3 : null;

    const sfz = '<region> sample=samples/note.mp3 key=60';
    final loaded = loadSfz(sfz, readSample: mp3Reader);
    final sample = loaded.font.samples.single;

    expect(loaded.presets.single.zones, hasLength(1));
    expect(sample.name, 'samples/note.mp3');
    expect(sample.sampleRate, 44100);
    expect(sample.pcm, isNotEmpty);
  });

  test('unsupported sample codecs warn and skip the region', () {
    Uint8List? badReader(String p) =>
        p == 'samples/note.flac' ? Uint8List.fromList('fLaC'.codeUnits) : null;
    final warnings = <String>[];

    expect(
      () => loadSfz(
        '<region> sample=samples/note.flac key=60',
        readSample: badReader,
        onWarn: warnings.add,
      ),
      throwsA(isA<SoundFontLoadException>()),
    );
    expect(warnings.single, contains('unsupported audio sample'));
    expect(warnings.single, contains('note.flac'));
  });

  test('no regions → a clear load exception', () {
    expect(
      () => loadSfz('<global> volume=0', readSample: reader),
      throwsA(isA<SoundFontLoadException>()),
    );
  });

  test('the loaded SFZ actually renders a MIDI note (end-to-end)', () {
    const sfz = '<region> sample=samples/note.wav lokey=0 hikey=127 '
        'pitch_keycenter=69 loop_mode=loop_continuous';
    final loaded = loadSfz(sfz, readSample: reader);
    // A single middle-C quarter note on channel 0.
    final smf = Uint8List.fromList([
      ...'MThd'.codeUnits, 0, 0, 0, 6, 0, 0, 0, 1, 1, 0xE0,
      ...'MTrk'.codeUnits, 0, 0, 0, 0x0C,
      0x00, 0x90, 60, 0x64, 0x83, 0x60, 0x80, 60, 0x00, //
      0x00, 0xFF, 0x2F, 0x00,
    ]);
    final (left, right) = renderMidiFile(smf, loaded);
    var peak = 0.0;
    for (final v in left) {
      if (v.abs() > peak) peak = v.abs();
    }
    expect(left, isNotEmpty);
    expect(right.length, left.length);
    expect(peak, greaterThan(0.0));
  });
}

// ── Test helpers: peek at the single zone through the public model ────────────

class Sf2ZoneRoot {
  Sf2ZoneRoot(this.zone);
  final dynamic zone;
  int get root => zone.rootKey as int;
}

Sf2ZoneRoot _root(LoadedSoundFont f) =>
    Sf2ZoneRoot(f.presets.single.zones.single);
