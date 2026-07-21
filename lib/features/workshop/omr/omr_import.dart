// Optical Music Recognition (OMR) — the app-side glue that turns a photo or
// scan of sheet music into a [Score].
//
// The recognition itself is done by an injectable [OmrEngine] (native CrispEmbed
// ggml via FFI today — see crispembed_ffi_omr.dart; a pure-Dart ONNX engine can
// drop in behind the same seam later). THIS file is the pure-Dart, testable
// glue around that engine:
//   • decode an encoded image (PNG/JPEG/…) into the grayscale [OmrImage] buffer
//     an engine consumes, and
//   • route the engine's token output through the right crisp_notation parser by
//     sniffing its dialect (SMT `bekern` / TrOMR semantic / Flova lilyNotes).
//
// Keeping this Flutter-free and model-free means the whole image→Score chain is
// unit-testable: feed a known token string and assert on the [Score].

import 'dart:typed_data';

import 'package:crisp_notation/crisp_notation.dart'
    show
        OmrDialect,
        OmrImage,
        Score,
        bekernToScore,
        omrDialectOf,
        scoreFromLilyNotes,
        scoreFromSemantic;
import 'package:image/image.dart' as img;

/// Decodes encoded image [bytes] (PNG/JPEG/BMP/GIF/TIFF…) into a single-channel
/// grayscale [OmrImage] the engine can consume. Returns null when [bytes] aren't
/// a decodable image (the caller then shows "couldn't read that image").
OmrImage? imageBytesToOmr(Uint8List bytes) {
  // decodeImage can *throw* (not just return null) on malformed data as a codec
  // reads past the end — treat any failure as "not a decodable image".
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object {
    return null;
  }
  if (decoded == null) return null;
  final gray = decoded.numChannels == 1 ? decoded : img.grayscale(decoded);
  final w = gray.width;
  final h = gray.height;
  final buf = Uint8List(w * h);
  var i = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      buf[i++] = gray.getPixel(x, y).r.toInt();
    }
  }
  return OmrImage(buf, width: w, height: h); // single channel (the default)
}

/// Routes OMR [tokens] to a [Score] via the parser for their dialect. An engine
/// can emit any of the three (SMT `bekern`, TrOMR semantic, Flova lilyNotes), so
/// we sniff with [omrDialectOf] rather than assume. Throws on unparseable input.
Score omrTokensToScore(String tokens) {
  final t = tokens.trim();
  return switch (omrDialectOf(t)) {
    OmrDialect.semantic => scoreFromSemantic(t),
    OmrDialect.lilyNotes => scoreFromLilyNotes(t),
    OmrDialect.bekern => bekernToScore(t),
  };
}
