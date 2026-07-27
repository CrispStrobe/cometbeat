// tts_asset_cache_web.dart — web (IndexedDB) byte cache for TTS assets, via
// `package:web` + `dart:js_interop`. The browser has no filesystem, so
// downloaded models/voices/narration persist in IndexedDB across reloads.
//
// Two object stores in the `comet_beat_tts` DB: `assets` (key → bytes) and
// `sizes` (key → byte length), so `totalBytes`/`keys` don't have to deserialize
// megabytes of model bytes just to report a size. Every op degrades safely to a
// no-op / absent result if IndexedDB is unavailable (private mode, quota) — the
// manager then just re-fetches instead of caching.

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tts/tts_asset_cache_base.dart';
import 'package:web/web.dart' as web;

/// Web factory — see the tts_asset_cache.dart facade. [dirOverride] names the
/// IndexedDB database (defaults to `comet_beat_tts`); tests/isolation can vary it.
TtsAssetCache createTtsAssetCache({String? dirOverride}) =>
    IdbAssetCache(dbName: dirOverride ?? 'comet_beat_tts');

const _assets = 'assets';
const _sizes = 'sizes';

class IdbAssetCache implements TtsAssetCache {
  IdbAssetCache({required this.dbName});

  final String dbName;
  web.IDBDatabase? _db;

  Future<web.IDBDatabase?> _open() async {
    if (_db != null) return _db;
    try {
      final req = web.window.indexedDB.open(dbName, 1);
      final c = Completer<web.IDBDatabase>();
      req.onupgradeneeded = ((web.Event _) {
        final db = req.result as web.IDBDatabase;
        final names = db.objectStoreNames;
        if (!names.contains(_assets)) db.createObjectStore(_assets);
        if (!names.contains(_sizes)) db.createObjectStore(_sizes);
      }).toJS;
      req.onsuccess =
          ((web.Event _) => c.complete(req.result as web.IDBDatabase)).toJS;
      req.onerror =
          ((web.Event _) => c.completeError(StateError('idb open'))).toJS;
      return _db = await c.future;
    } catch (_) {
      return null;
    }
  }

  /// Bridge an IDBRequest's success/error events to a Future of its result.
  Future<JSAny?> _await(web.IDBRequest req) {
    final c = Completer<JSAny?>();
    req.onsuccess = ((web.Event _) => c.complete(req.result)).toJS;
    req.onerror =
        ((web.Event _) => c.completeError(StateError('idb req'))).toJS;
    return c.future;
  }

  web.IDBObjectStore? _store(web.IDBDatabase db, String name, String mode) {
    try {
      return db.transaction(name.toJS, mode).objectStore(name);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> has(String key) async {
    final db = await _open();
    if (db == null) return false;
    final store = _store(db, _sizes, 'readonly');
    if (store == null) return false;
    try {
      final r = await _await(store.get(key.toJS));
      return !r.isUndefinedOrNull && (r! as JSNumber).toDartInt > 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Uint8List?> read(String key) async {
    final db = await _open();
    if (db == null) return null;
    final store = _store(db, _assets, 'readonly');
    if (store == null) return null;
    try {
      final r = await _await(store.get(key.toJS));
      if (r.isUndefinedOrNull) return null;
      return (r! as JSUint8Array).toDart;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    final db = await _open();
    if (db == null) return;
    try {
      final tx = db.transaction(
        <JSString>[_assets.toJS, _sizes.toJS].toJS,
        'readwrite',
      );
      tx.objectStore(_assets).put(bytes.toJS, key.toJS);
      tx.objectStore(_sizes).put(bytes.length.toJS, key.toJS);
      final c = Completer<void>();
      tx.oncomplete = ((web.Event _) => c.complete()).toJS;
      tx.onerror =
          ((web.Event _) => c.completeError(StateError('idb tx'))).toJS;
      await c.future;
    } catch (_) {
      // quota / unavailable → skip caching; the manager re-fetches next time.
    }
  }

  @override
  Future<void> delete(String key) async {
    final db = await _open();
    if (db == null) return;
    try {
      final tx = db.transaction(
        <JSString>[_assets.toJS, _sizes.toJS].toJS,
        'readwrite',
      );
      tx.objectStore(_assets).delete(key.toJS);
      tx.objectStore(_sizes).delete(key.toJS);
      final c = Completer<void>();
      tx.oncomplete = ((web.Event _) => c.complete()).toJS;
      tx.onerror =
          ((web.Event _) => c.completeError(StateError('idb tx'))).toJS;
      await c.future;
    } catch (_) {}
  }

  @override
  Future<List<String>> keys() async {
    final db = await _open();
    if (db == null) return const [];
    final store = _store(db, _sizes, 'readonly');
    if (store == null) return const [];
    try {
      final r = await _await(store.getAllKeys());
      if (r.isUndefinedOrNull) return const [];
      return (r! as JSArray)
          .toDart
          .map((k) => (k! as JSString).toDart)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<int> totalBytes() async {
    final db = await _open();
    if (db == null) return 0;
    final store = _store(db, _sizes, 'readonly');
    if (store == null) return 0;
    try {
      final r = await _await(store.getAll());
      if (r.isUndefinedOrNull) return 0;
      var total = 0;
      for (final n in (r! as JSArray).toDart) {
        total += (n! as JSNumber).toDartInt;
      }
      return total;
    } catch (_) {
      return 0;
    }
  }
}
