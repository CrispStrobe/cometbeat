// RMVPE F0-estimator provider, behind a conditional import so the screen
// compiles on web. The IO impl loads the RMVPE ONNX + mel asset (pulls dart:io)
// and wraps rmvpeF0 as an F0Estimator; the stub returns null (web / no model),
// so the monophonic chain falls back to CREPE/pYIN. RMVPE is a large (~300 MB),
// vocal-robust model — the accuracy tier above CREPE for singing.

export 'rmvpe_provider_stub.dart' if (dart.library.io) 'rmvpe_provider_io.dart';
