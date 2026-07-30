// lib/core/services/tray_store.dart
//
// WS-X6 slice 3b — the clipboard survives the app closing.
//
// A thing called a clipboard that forgets everything when you close the app is
// a surprise, not a feature: the maintainer's word for it was things "we keep".
//
// WHAT PERSISTS, AND WHAT HONESTLY CANNOT.
//
//   * DOCUMENTS — a groove, a riff, tab columns — go through the same
//     `project_codec` registry that saves a project. No new serialisation, and a
//     kind that gains a codec later starts persisting for free.
//   * INSTRUMENTS FROM THE LIBRARY persist as their NAME. This is where the
//     by-reference argument finally earns its keep: an instrument's samples are
//     already stored once by `InstrumentLibraryStore`, and writing the PCM again
//     here would store a second copy of the same audio under a different key,
//     which then goes stale the moment the library entry is edited.
//   * ⚠️ AN INSTRUMENT WITH NO LIBRARY ENTRY CANNOT PERSIST, and that is not a
//     bug to paper over. A voice lifted off a track, or a sample taken from an
//     Audio Editor clip, exists only in memory; the only honest ways to keep it
//     would be to write its PCM here (a hidden second library) or to save it to
//     the real library behind the player's back. Both are worse than losing a
//     clipboard entry, so it is dropped on save and [unsavedCount] says how
//     many — a caller can then offer "save these to My Instruments first",
//     which is the one action that actually fixes it.
//
// LOADING IS BEST-EFFORT. One unreadable row costs that row, never the
// clipboard: a stored item whose codec is gone, or whose library entry has been
// deleted, is skipped and the rest still come back.

import 'dart:async';
import 'dart:convert';

import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/project/project_codec.dart';
import 'package:comet_beat/core/tray/tray.dart';
import 'package:comet_beat/features/sound_lab/instrument_library_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads and writes the clipboard.
class TrayStore {
  TrayStore(this._prefs, {InstrumentLibraryStore? library})
      : _library = library ?? InstrumentLibraryStore();

  final SharedPreferences _prefs;
  final InstrumentLibraryStore _library;

  static const _key = 'tray_v1';

  /// How many items the last [save] could not keep. See the header: an
  /// instrument with no library entry has nowhere honest to be written.
  int unsavedCount = 0;

  /// Loads the clipboard now, then keeps it saved.
  ///
  /// The listener is attached only AFTER the load finishes, or restoring would
  /// notify its way through a save per restored item — and the first of those
  /// would write a half-loaded clipboard over the full one.
  Future<int> attach(TrayService tray) async {
    final lost = await load(tray);
    tray.addListener(() => unawaited(save(tray)));
    return lost;
  }

  /// Writes what can be written, newest first, and reports the rest.
  Future<void> save(TrayService tray) async {
    var dropped = 0;
    final rows = <Map<String, dynamic>>[];
    for (final item in tray.items) {
      final row = _rowFor(item);
      if (row == null) {
        dropped++;
        continue;
      }
      rows.add(row);
    }
    unsavedCount = dropped;
    await _prefs.setString(_key, jsonEncode(rows));
  }

  Map<String, dynamic>? _rowFor(TrayItem item) {
    if (item.isInstrument) {
      final name = item.libraryName;
      // No library entry → nothing to point at. Dropped, and counted.
      if (name == null || name.isEmpty) return null;
      return {
        'kind': item.kind.name,
        'label': item.label,
        'instrument': name,
        'at': item.addedAtMs,
      };
    }
    final document = item.document;
    if (document == null) return null;
    final codec = projectDocumentCodecFor(item.kind);
    final json = codec?.encode(document);
    // A kind with no codec, or a document this codec cannot express, is not an
    // error — it simply does not survive a restart.
    if (json == null) return null;
    return {
      'kind': item.kind.name,
      'label': item.label,
      'doc': json,
      'at': item.addedAtMs,
    };
  }

  /// Fills [tray] from storage. Existing contents are replaced.
  ///
  /// Returns how many stored rows could not be read back, so a caller can tell
  /// "the clipboard was empty" from "three things could not be restored".
  Future<int> load(TrayService tray) async {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return 0;
    List<dynamic> rows;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return 0;
      rows = decoded;
    } catch (_) {
      // A corrupt store reads as empty, which a player can recover from by
      // putting things on it again; a throw at start-up they cannot.
      return 0;
    }

    // Saved newest-first, and `add` inserts at the front, so replay backwards to
    // come back in the same order.
    var lost = 0;
    final library = await _library.load();
    tray.clear();
    for (final row in rows.reversed) {
      if (row is! Map) {
        lost++;
        continue;
      }
      if (!_restore(tray, row.cast<String, dynamic>(), library)) lost++;
    }
    return lost;
  }

  bool _restore(
    TrayService tray,
    Map<String, dynamic> row,
    List<SavedInstrument> library,
  ) {
    final kind = _kindByName(row['kind']);
    final label = row['label'];
    if (kind == null || label is! String) return false;
    final at = row['at'];
    final addedAtMs = at is num ? at.toInt() : 0;

    final instrumentName = row['instrument'];
    if (instrumentName is String) {
      for (final saved in library) {
        if (saved.name != instrumentName) continue;
        final voice = saved.instrument;
        if (voice == null) return false;
        tray.addInstrument(
          label: label,
          instrument: voice,
          kind: kind,
          libraryName: instrumentName,
          nowMs: addedAtMs,
        );
        return true;
      }
      // The library entry has been deleted since. That row is gone, and the
      // rest of the clipboard is not.
      return false;
    }

    final doc = row['doc'];
    if (doc is! Map) return false;
    final decoded =
        projectDocumentCodecFor(kind)?.decode(doc.cast<String, dynamic>());
    if (decoded == null) return false;
    tray.add(kind: kind, label: label, document: decoded, nowMs: addedAtMs);
    return true;
  }

  AppMode? _kindByName(Object? raw) {
    if (raw is! String) return null;
    for (final mode in AppMode.values) {
      if (mode.name == raw) return mode;
    }
    return null;
  }
}
