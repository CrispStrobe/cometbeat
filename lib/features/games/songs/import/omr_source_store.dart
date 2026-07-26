// Retains the sheet-music photo an OMR-imported song was recognised from, so
// the recognition can be re-run later on a bad scan.
//
// Facade over a native filesystem implementation (`_io`) and a web stub
// (`_stub`, no persistence — web has no OMR either). Mirrors `omr_import.dart`:
// the bytes live in the same `~/.cache/crisp_notation` tree the model cache
// uses, so no new dependency (path_provider) is pulled in.
export 'omr_source_store_stub.dart'
    if (dart.library.io) 'omr_source_store_io.dart';
