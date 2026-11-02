// Native whole-file decode through glint's `glint_decode_audio` (MIT) — MP3,
// ADTS AAC, Ogg-Opus, Ogg-Vorbis and FLAC, auto-detected from the header,
// returned as interleaved float at the file's own rate with its channels
// intact. The `glint_vorbis` FFI plugin already compiles this decoder into
// the app (for .sf3), so in-app it costs nothing extra.
//
// MP3 is GAPLESS from glint fix/mp3-gapless (vendored with it): the
// Xing/Info frame is skipped and the LAME delay/padding trimmed, sample-exact
// with ffmpeg. An older glint plays an MP3 ~25 ms late — so re-vendor
// native/glint (sync_glint.sh) whenever glint moves.
//
// dart:io/dart:ffi only — reach it through song_audio_file.dart.

import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/practice/song_audio.dart';
import 'package:ffi/ffi.dart';

typedef _DecodeNative = Pointer<Float> Function(
  Pointer<Uint8>,
  Int32,
  Pointer<Int32>,
  Pointer<Int32>,
  Pointer<Int32>,
);
typedef _Decode = Pointer<Float> Function(
  Pointer<Uint8>,
  int,
  Pointer<Int32>,
  Pointer<Int32>,
  Pointer<Int32>,
);
typedef _FreeNative = Void Function(Pointer<Void>);
typedef _Free = void Function(Pointer<Void>);

/// The oldest glint whose MP3 decode is gapless (glint_version, 0.8.1).
const int kGlintGaplessVersion = (0 << 16) | (8 << 8) | 1;

typedef _VersionNative = Int32 Function();
typedef _Version = int Function();

/// Where a USABLE glint is: null path = this process (the app's plugin),
/// otherwise a library path to open. Order: [explicit]; `COMET_GLINT_LIB`;
/// the process. Null when none provides `glint_decode_audio` at
/// [kGlintGaplessVersion] or later.
///
/// Deliberately NO lookup by bare library name: the system loader then
/// searches /usr/local/lib and friends, and found a months-old
/// libglint.dylib there that decodes every MP3 ~25 ms late. In the app the
/// glint_vorbis plugin links glint into the process, so the process is the
/// only place it needs to look; the version check refuses a stale library
/// handed in explicitly, too.
({String? path})? resolveGlint({String? explicit}) {
  bool usable(DynamicLibrary l) {
    if (!l.providesSymbol('glint_decode_audio') ||
        !l.providesSymbol('glint_version')) {
      return false;
    }
    final v = l.lookupFunction<_VersionNative, _Version>('glint_version')();
    return v >= kGlintGaplessVersion;
  }

  final env = Platform.environment['COMET_GLINT_LIB'];
  for (final p in [explicit, if (env != null && env.isNotEmpty) env]) {
    if (p == null) continue;
    try {
      if (usable(DynamicLibrary.open(p))) return (path: p);
    } catch (_) {}
  }
  try {
    if (usable(DynamicLibrary.process())) return (path: null);
  } catch (_) {}
  return null;
}

/// Decode [bytes] with glint, off the calling isolate. Null when glint is not
/// available here or does not recognise the format.
Future<SongAudio?> glintDecodeSong(Uint8List bytes, {String? libraryPath}) {
  final where = resolveGlint(explicit: libraryPath);
  if (where == null || bytes.isEmpty) return Future.value();
  return Isolate.run(() => _decode(bytes, where.path));
}

SongAudio? _decode(Uint8List bytes, String? path) {
  final lib =
      path == null ? DynamicLibrary.process() : DynamicLibrary.open(path);
  final decode = lib.lookupFunction<_DecodeNative, _Decode>(
    'glint_decode_audio',
  );
  final free = lib.lookupFunction<_FreeNative, _Free>('glint_free');
  final input = malloc<Uint8>(bytes.length);
  final sr = malloc<Int32>(), ch = malloc<Int32>(), fr = malloc<Int32>();
  try {
    input.asTypedList(bytes.length).setAll(0, bytes);
    final out = decode(input, bytes.length, sr, ch, fr);
    if (out == nullptr) return null;
    try {
      final channels = ch.value, frames = fr.value;
      if (channels < 1 || frames <= 0 || sr.value <= 0) return null;
      final pcm = out.asTypedList(frames * channels);
      final l = Float32List(frames), r = Float32List(frames);
      final right = channels > 1 ? 1 : 0;
      for (var i = 0; i < frames; i++) {
        l[i] = pcm[i * channels];
        r[i] = pcm[i * channels + right];
      }
      return SongAudio(l, r, sr.value);
    } finally {
      free(out.cast());
    }
  } finally {
    malloc
      ..free(input)
      ..free(sr)
      ..free(ch)
      ..free(fr);
  }
}
