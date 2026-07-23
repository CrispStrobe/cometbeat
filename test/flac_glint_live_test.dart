// LIVE test of the native glint FLAC decoder (dart:ffi). Unlike a plain unit
// test, this builds the real `native/glint` C++ plugin, loads the shared
// library, and decodes checked-in FLAC fixtures — asserting the output is
// bit-exact against the reference `flac` CLI's decode (the .wav next to each
// .flac, produced by `flac -d`). FLAC is lossless, so an exact match proves the
// decoder is correct end-to-end, not merely "runs".
//
// Fixtures (test/fixtures/flac) cover 16- and 24-bit; mono and stereo (with
// L≠R, exercising stereo decorrelation); 22.05/44.1/48 kHz; a constant subframe
// (silence), a high-residual/verbatim subframe (pink noise), LPC subframes
// (tones), and a small block size.
//
// The test is SKIPPED (not failed) when the native library can't be built or
// loaded (no C++ toolchain / cmake, or an unsupported host) so it degrades
// cleanly in constrained CI. Build it locally with `cmake` — see _ensureLib.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/flac_glint_ffi.dart';
import 'package:comet_beat/features/library/instrument_installer_io.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal WAV reader for the reference fixtures: scans chunks (skipping any
/// LIST/etc.), returns sample rate, channel count, bit depth, and the
/// per-channel integer samples.
({int sr, int ch, int bits, List<Int32List> chans}) _readWav(Uint8List b) {
  final bd = ByteData.sublistView(b);
  var p = 12; // past "RIFF"<size>"WAVE"
  int sr = 0, ch = 0, bits = 0, dataOff = 0, dataLen = 0;
  while (p + 8 <= b.length) {
    final id = String.fromCharCodes(b.sublist(p, p + 4));
    final sz = bd.getUint32(p + 4, Endian.little);
    if (id == 'fmt ') {
      ch = bd.getUint16(p + 10, Endian.little);
      sr = bd.getUint32(p + 12, Endian.little);
      bits = bd.getUint16(p + 22, Endian.little);
    } else if (id == 'data') {
      dataOff = p + 8;
      dataLen = sz;
    }
    p += 8 + sz + (sz & 1); // chunks are word-aligned
  }
  final bytesPer = bits ~/ 8;
  final frames = ch == 0 ? 0 : dataLen ~/ (bytesPer * ch);
  final chans = List.generate(ch, (_) => Int32List(frames));
  for (var i = 0; i < frames; i++) {
    for (var c = 0; c < ch; c++) {
      final o = dataOff + (i * ch + c) * bytesPer;
      int v;
      if (bits == 16) {
        v = bd.getInt16(o, Endian.little);
      } else if (bits == 24) {
        v = b[o] | (b[o + 1] << 8) | (b[o + 2] << 16);
        if (v & 0x800000 != 0) v -= 0x1000000; // sign-extend
      } else {
        v = bd.getInt32(o, Endian.little);
      }
      chans[c][i] = v;
    }
  }
  return (sr: sr, ch: ch, bits: bits, chans: chans);
}

/// Locate the repo root (the test CWD is the package root already) and the
/// native source dir.
String get _repoRoot => Directory.current.path;
String get _nativeSrc => '$_repoRoot/native/glint/src';

/// The platform's shared-library filename for the glint plugin, or null on a
/// platform this live test doesn't build for.
String? _libName() {
  if (Platform.isMacOS) return 'libglint_vorbis.dylib';
  if (Platform.isLinux) return 'libglint_vorbis.so';
  return null; // Windows/others: skip (build wiring differs)
}

/// Build the native glint library once (cached under src/.testbuild) and return
/// its path, or null if the toolchain/host can't produce it (→ skip).
String? _ensureLib() {
  final libName = _libName();
  if (libName == null) return null;
  final buildDir = '$_nativeSrc/.testbuild';
  final libPath = '$buildDir/$libName';
  if (File(libPath).existsSync()) return libPath; // reuse a prior build
  // Needs cmake + a C++ compiler.
  try {
    final cfg = Process.runSync(
      'cmake',
      ['-B', buildDir, '-S', _nativeSrc, '-DCMAKE_BUILD_TYPE=Release'],
    );
    if (cfg.exitCode != 0) return null;
    final build = Process.runSync('cmake', ['--build', buildDir]);
    if (build.exitCode != 0) return null;
  } catch (_) {
    return null; // cmake not installed
  }
  return File(libPath).existsSync() ? libPath : null;
}

void main() {
  final libPath = _ensureLib();
  final skip = libPath == null
      ? 'native glint library not built (needs cmake + a C++ toolchain on '
          'macOS/Linux)'
      : false;

  group('glint FLAC decode — bit-exact vs the reference flac CLI', () {
    late FlacDecode decode;

    setUpAll(() {
      if (libPath != null) decode = loadGlintFlac(libraryPath: libPath)!;
    });

    final fixtures = <String>[
      'mono_44100_16', // LPC tone, mono, 16-bit
      'stereo_48000_16', // L≠R stereo decorrelation, small block size
      'mono_22050_16', // sample-rate variety
      'mono_44100_24', // 24-bit path
      'silence_44100_16', // constant subframe
      'noise_44100_16', // verbatim / high-residual subframe
    ];

    for (final name in fixtures) {
      test('$name decodes to the exact reference samples', () {
        final base = '$_repoRoot/test/fixtures/flac/$name';
        final flac = File('$base.flac').readAsBytesSync();
        final ref = _readWav(File('$base.wav').readAsBytesSync());

        final pcm = decode(flac);
        expect(pcm, isNotNull, reason: '$name failed to decode');

        final gch = pcm!.right == null ? 1 : 2;
        expect(pcm.sampleRate, ref.sr, reason: 'sample rate');
        expect(gch, ref.ch, reason: 'channel count');
        expect(pcm.left.length, ref.chans[0].length, reason: 'frame count');

        // Re-quantize glint's float PCM back to the reference bit depth and
        // require an exact (±0) match on every sample of every channel.
        final scale = (1 << (ref.bits - 1)).toDouble();
        final gchans = [pcm.left, if (pcm.right != null) pcm.right!];
        var maxErr = 0;
        for (var c = 0; c < gch; c++) {
          for (var i = 0; i < pcm.left.length; i++) {
            final q = (gchans[c][i] * scale).round();
            final e = (q - ref.chans[c][i]).abs();
            if (e > maxErr) maxErr = e;
          }
        }
        expect(maxErr, 0, reason: '$name: max sample error in LSBs');
      });
    }

    test('silence really is all-zero', () {
      final pcm = decode(
        File('$_repoRoot/test/fixtures/flac/silence_44100_16.flac')
            .readAsBytesSync(),
      )!;
      expect(pcm.left.every((s) => s == 0.0), isTrue);
    });

    test('a real tone has meaningful energy (not silence)', () {
      final pcm = decode(
        File('$_repoRoot/test/fixtures/flac/mono_44100_16.flac')
            .readAsBytesSync(),
      )!;
      var peak = 0.0;
      for (final s in pcm.left) {
        if (s.abs() > peak) peak = s.abs();
      }
      expect(peak, greaterThan(0.05));
      expect(peak, lessThanOrEqualTo(1.0));
    });
  }, skip: skip);

  group('glint FLAC decode — malformed input is null, never a crash', () {
    late FlacDecode decode;
    setUpAll(() {
      if (libPath != null) decode = loadGlintFlac(libraryPath: libPath)!;
    });

    test('empty input → null', () {
      expect(decode(Uint8List(0)), isNull);
    });
    test('non-FLAC bytes → null', () {
      expect(decode(Uint8List.fromList(List.filled(64, 0x42))), isNull);
    });
    test('a truncated FLAC stream → null (no crash)', () {
      final full = File('$_repoRoot/test/fixtures/flac/mono_44100_16.flac')
          .readAsBytesSync();
      final cut = Uint8List.sublistView(full, 0, full.length ~/ 3);
      // Either null or a short partial decode is acceptable; the point is no
      // crash / no throw.
      expect(() => decode(cut), returnsNormally);
    });
  }, skip: skip);

  group('installer decodes a FLAC-sampled SFZ into a playable voice (live)',
      () {
    test('a FLAC region builds a voice; the .flac is cached', () async {
      if (libPath == null) return; // skipped group would still enter here
      final decode = loadGlintFlac(libraryPath: libPath)!;
      final cache = Directory.systemTemp.createTempSync('flac_inst');
      addTearDown(() {
        if (cache.existsSync()) cache.deleteSync(recursive: true);
      });

      const sfz = '''
<region>
sample=samples/tone.flac
pitch_keycenter=60
lokey=0 hikey=127
''';
      final flacBytes = File('$_repoRoot/test/fixtures/flac/mono_44100_16.flac')
          .readAsBytesSync();
      Future<Uint8List> http(Uri url) async {
        final u = url.toString();
        if (u.endsWith('.sfz')) return Uint8List.fromList(sfz.codeUnits);
        if (u.endsWith('samples/tone.flac')) return flacBytes;
        throw Exception('404 $u');
      }

      final installed = await installSfzInstrument(
        sfzUrl: 'https://h/vcsl/FlacInst.sfz',
        name: 'Flac Inst',
        http: http,
        cacheDirOverride: cache.path,
        flacDecode: decode, // inject the live decoder
      );

      expect(installed, isNotNull,
          reason: 'a decodable FLAC region should yield a voice');
      expect(installed!.instrument, isNotNull);
      // the raw .flac is kept on disk (Downloads manager can free it)
      expect(
        File('${cache.path}/instruments/Flac_Inst/samples/tone.flac')
            .existsSync(),
        isTrue,
      );
    });
  }, skip: skip);
}
