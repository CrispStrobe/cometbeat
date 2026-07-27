// Rendering a module through the INDEPENDENT tracker replayers, so our own
// output has something to be judged against.
//
// This lives apart from any one test because the number that matters is not
// "how close are we to OpenMPT" but "how close are we to OpenMPT, RELATIVE to
// how close OpenMPT and libxmp and micromod are to each other" (PLAN.md §6 X0).
// That needs several players, and more than one test file wants them.
//
// Every player is resolved from PATH and every renderer returns null when its
// binary is missing, so a checkout without them degrades to fewer references
// rather than failing. Install what you have:
//
//   brew install libopenmpt   # openmpt123 — the one the harness requires
//   brew install xmp          # libxmp
//   cc -O2 -o mod2wav mod2wav.c micromod.c   # martincameron/micromod, MOD only
//
// None of these is a dependency of the app; they are development tools for the
// audit, and nothing in `lib/` knows they exist.

import 'dart:io';
import 'dart:typed_data';

/// The sample rate every reference is asked to render at. Comparing two renders
/// at different rates would mean resampling one of them, and any resampler
/// leaves its own fingerprint on the spectrum.
const int kReferenceSampleRate = 44100;

String? _resolve(String binary) {
  final which = Process.runSync('which', [binary]);
  if (which.exitCode != 0) return null;
  final path = (which.stdout as String).trim();
  return path.isNotEmpty && File(path).existsSync() ? path : null;
}

/// openmpt123, resolved from PATH and falling back to the Homebrew prefix.
///
/// It used to be pinned to one Cellar version, so a routine `brew upgrade`
/// silently skipped the whole audit — the tests still passed, they just stopped
/// testing anything.
final String kOpenMptPath =
    _resolve('openmpt123') ?? '/opt/homebrew/bin/openmpt123';

/// libxmp's CLI, or null when it is not installed.
final String? kXmpPath = _resolve('xmp');

/// micromod's `mod2wav`, or null when it is not on PATH. MOD only — micromod
/// does not read XM/S3M/IT.
final String? kMicromodPath = _resolve('mod2wav');

/// Renders through libopenmpt. Throws on failure: this is the one reference the
/// audit cannot run without, so a silent null would hide a broken install.
Future<Uint8List> renderWithOpenMpt(String fixturePath) async {
  final dir = Directory.systemTemp.createTempSync('openmpt_ref_');
  try {
    // openmpt123 writes its output beside the INPUT, so the fixture is copied
    // into the temp dir rather than rendered in place — otherwise the audit
    // would litter test/fixtures with .wav files.
    final name = fixturePath.split('/').last;
    final input = '${dir.path}/$name';
    await File(fixturePath).copy(input);

    final r = await Process.run(
      kOpenMptPath,
      [
        '--render',
        '--samplerate', '$kReferenceSampleRate',
        '--channels', '2',
        '--no-float',
        // Dither is RANDOM and openmpt123 defaults it on for 16-bit output, so
        // the reference differed on every run. Level and envelope shrugged it
        // off, but on thin material it was enough to move the cross-correlation
        // peak — the same A/B reported lags of 21504 and 29696 samples for
        // identical inputs.
        '--dither', '0',
        input,
      ],
      workingDirectory: dir.path,
    );
    if (r.exitCode != 0) {
      throw Exception('openmpt123 failed on $name: ${r.stderr}');
    }
    final out = File('$input.wav');
    if (!out.existsSync()) {
      throw Exception('openmpt123 produced no output for $name');
    }
    return out.readAsBytesSync();
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// Renders through libxmp, or null when `xmp` is not installed.
Future<Uint8List?> renderWithXmp(String fixturePath) async {
  final exe = kXmpPath;
  if (exe == null) return null;
  final dir = Directory.systemTemp.createTempSync('xmp_ref_');
  try {
    final out = '${dir.path}/out.wav';
    final r = await Process.run(
      exe,
      ['-d', 'wav', '-o', out, '-f', '$kReferenceSampleRate', fixturePath],
    );
    if (r.exitCode != 0 || !File(out).existsSync()) return null;
    return File(out).readAsBytesSync();
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// Renders through micromod, or null when `mod2wav` is missing or the fixture
/// is not a MOD.
Future<Uint8List?> renderWithMicromod(String fixturePath) async {
  final exe = kMicromodPath;
  if (exe == null || !fixturePath.toLowerCase().endsWith('.mod')) return null;
  final dir = Directory.systemTemp.createTempSync('micromod_ref_');
  try {
    final out = '${dir.path}/out.wav';
    final r = await Process.run(
      exe,
      [fixturePath, out, '-rate', '$kReferenceSampleRate'],
    );
    if (r.exitCode != 0 || !File(out).existsSync()) return null;
    return File(out).readAsBytesSync();
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// Mono PCM from ANY 16-bit PCM WAV, whatever its channel count.
///
/// This used to be TWO functions — one that downmixed stereo (used for the
/// OpenMPT reference) and one that assumed mono (used for our render). Our
/// renderer has since gained stereo output, so our side was being read as twice
/// as many "samples" of interleaved L/R: every module reported a duration ratio
/// of almost exactly 2.0, and the comparisons after it were matching
/// interleaved L/R against a mono downmix, which is meaningless.
///
/// So there is one reader, and it reads the channel count from the header
/// rather than assuming it. The chunk list is walked rather than trusting a
/// fixed 44-byte header — a WAV carrying a LIST or fact chunk would otherwise
/// shift every sample.
Float64List wavToMonoPcm(Uint8List wavBytes) {
  final data = ByteData.sublistView(wavBytes);
  if (wavBytes.length < 44) return Float64List(0);

  var channels = 1;
  var bitsPerSample = 16;
  var dataOffset = -1;
  var dataBytes = 0;
  var pos = 12; // past "RIFF" + size + "WAVE"
  while (pos + 8 <= wavBytes.length) {
    final id = String.fromCharCodes(wavBytes.sublist(pos, pos + 4));
    final size = data.getUint32(pos + 4, Endian.little);
    final body = pos + 8;
    if (id == 'fmt ' && body + 16 <= wavBytes.length) {
      channels = data.getUint16(body + 2, Endian.little);
      bitsPerSample = data.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      dataOffset = body;
      dataBytes = size;
      break;
    }
    pos = body + size + (size.isOdd ? 1 : 0);
  }
  if (dataOffset < 0 || channels < 1 || bitsPerSample != 16) {
    return Float64List(0);
  }

  final available = wavBytes.length - dataOffset;
  final usable =
      dataBytes > 0 && dataBytes <= available ? dataBytes : available;
  final bytesPerFrame = 2 * channels;
  final frames = usable ~/ bytesPerFrame;
  final pcm = Float64List(frames);
  for (var i = 0; i < frames; i++) {
    var sum = 0.0;
    for (var c = 0; c < channels; c++) {
      sum +=
          data.getInt16(dataOffset + i * bytesPerFrame + c * 2, Endian.little) /
              32768.0;
    }
    pcm[i] = sum / channels;
  }
  return pcm;
}

/// Every reference render of [fixturePath] that this machine can produce,
/// as mono PCM. Empty renders are dropped, so the list length is the number of
/// references that actually said something.
Future<List<Float64List>> renderAllReferences(String fixturePath) async {
  final out = <Float64List>[];
  for (final bytes in [
    await renderWithOpenMpt(fixturePath),
    await renderWithXmp(fixturePath),
    await renderWithMicromod(fixturePath),
  ]) {
    if (bytes == null) continue;
    final pcm = wavToMonoPcm(bytes);
    if (pcm.isNotEmpty) out.add(pcm);
  }
  return out;
}
