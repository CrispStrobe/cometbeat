// Native store for retained OMR source images. Keyed by song id; the bytes are
// written verbatim (PNG/JPEG), so the re-run path can feed them straight back
// to `recognizeSheetMusic`, which sniffs the format.
import 'dart:io';
import 'dart:typed_data';

/// Test seam: overrides the directory retained scans are written to. Set it to
/// a temp dir in a test, then clear it. Null in production.
String Function()? debugOmrSourcesDirOverride;

String _sourcesDir() =>
    debugOmrSourcesDirOverride?.call() ?? _defaultSourcesDir();

String _defaultSourcesDir() {
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.systemTemp.path;
  return '$home/.cache/crisp_notation/omr_sources';
}

// Song ids are a millisecond timestamp today, but sanitise anyway so a future
// id scheme can never escape the store dir or collide with a path separator.
String _fileFor(String songId) {
  final safe = songId.replaceAll(RegExp('[^A-Za-z0-9_-]'), '_');
  return '${_sourcesDir()}/$safe';
}

/// Persists the [bytes] of the photo [songId] was recognised from. Best-effort:
/// a write failure (read-only cache dir, no space) is swallowed and reported as
/// `false` — the song still imports, it just can't be re-scanned.
Future<bool> saveOmrSource(String songId, Uint8List bytes) async {
  try {
    final dir = Directory(_sourcesDir());
    if (!dir.existsSync()) dir.createSync(recursive: true);
    await File(_fileFor(songId)).writeAsBytes(bytes, flush: true);
    return true;
  } catch (_) {
    return false;
  }
}

/// The retained bytes for [songId], or null when none were kept (or the read
/// fails). A zero-length file counts as absent.
Future<Uint8List?> loadOmrSource(String songId) async {
  try {
    final f = File(_fileFor(songId));
    if (!f.existsSync() || f.lengthSync() == 0) return null;
    return await f.readAsBytes();
  } catch (_) {
    return null;
  }
}

/// Drops the retained image for [songId], if any. Called when its song is
/// deleted, so a removed song leaves nothing behind.
Future<void> deleteOmrSource(String songId) async {
  try {
    final f = File(_fileFor(songId));
    if (f.existsSync()) await f.delete();
  } catch (_) {
    // Nothing to clean up, or it is already gone.
  }
}
