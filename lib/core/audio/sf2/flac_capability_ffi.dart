import 'package:comet_beat/core/audio/sf2/flac_glint_ffi.dart' as glint;

export 'flac_glint_ffi.dart' show FlacPcm, FlacDecode;

glint.FlacDecode? loadGlintFlac({String? libraryPath}) =>
    glint.loadGlintFlac(libraryPath: libraryPath);
