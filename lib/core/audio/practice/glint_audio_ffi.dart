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

/// Where glint's symbols are: null = in this process (the app's plugin),
/// otherwise a library path or name to open. Resolution order: [explicit];
/// `COMET_GLINT_LIB`; the process; the platform's bundled library names.
/// Null when none of them provides `glint_decode_audio`.
({String? path})? resolveGlint({String? explicit}) {
  bool has(DynamicLibrary l) => l.providesSymbol('glint_decode_audio');
  final env = Platform.environment['COMET_GLINT_LIB'];
  for (final p in [explicit, if (env != null && env.isNotEmpty) env]) {
    if (p == null) continue;
    try {
      if (has(DynamicLibrary.open(p))) return (path: p);
    } catch (_) {}
  }
  try {
    if (has(DynamicLibrary.process())) return (path: null);
  } catch (_) {}
  final names = Platform.isMacOS
      ? const ['libglint.dylib', 'glint.framework/glint']
      : Platform.isIOS
          ? const ['glint.framework/glint']
          : Platform.isWindows
              ? const ['glint.dll']
              : const ['libglint.so'];
  for (final n in names) {
    try {
      if (has(DynamicLibrary.open(n))) return (path: n);
    } catch (_) {}
  }
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
