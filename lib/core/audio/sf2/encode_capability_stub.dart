// Web / no-dart:ffi stub for the native encoder seam: no encoder here, so the
// export UI offers only the pure-Dart formats (WAV, MP3 via our own encoder).

import 'package:comet_beat/core/audio/sf2/encoded_audio.dart';

export 'package:comet_beat/core/audio/sf2/encoded_audio.dart';

/// No native encoder on this platform → null.
EncodeAudio? loadGlintEncoder({String? libraryPath}) => null;

/// ...and so nothing to decode back either.
OpusFileDecode? loadOpusFileDecoder({String? libraryPath}) => null;

/// No whole-file decoder here either.
AudioFileDecode? loadAudioDecoder({String? libraryPath}) => null;

/// Nothing to load, so readiness is immediate and false.
Future<bool> ensureGlintCodecReady() async => false;
