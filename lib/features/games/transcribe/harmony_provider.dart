// Neural chord-recogniser (BTC) provider, behind a conditional import so the
// screen compiles on web. The IO impl loads the BTC ONNX + CQT filterbank
// (pulls dart:io) and wraps estimateChords as a ChordEstimator; the stub returns
// null (web / no model), so the transcription simply carries no neural chords.

export 'harmony_provider_stub.dart'
    if (dart.library.io) 'harmony_provider_io.dart';
