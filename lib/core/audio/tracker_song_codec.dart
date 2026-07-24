// TrackerSong (de)serialization — a LOSSLESS native save/load/share format for a
// whole Advanced-Tracker song. Unlike module export (8-bit, effect gaps) or the
// MusicXML-via-Score path (no effects / per-cell instruments), this preserves the
// EXACT document: every pattern cell (note/volume/effect/fxCmd/fxParam/per-cell
// instrument), each channel (instrument, gain, pan, mute, volume/pan envelopes,
// insert effects), the order list, timing, and the shared instrument pool.
//
// Three layers:
//   • JSON       — [trackerSongToJson] / [trackerSongFromJson] (a Map).
//   • String     — [trackerSongToJsonString] / [trackerSongFromJsonString].
//   • Share token — [trackerSongToToken] / [trackerSongFromToken]: the JSON
//     zlib-compressed + url-safe base64, prefixed `CBS1.` (small, paste-able).
//     [tryTrackerSongFromToken] never throws (for UI paste handling), mirroring
//     the Loop Mixer's `KU1.` groove token.
//
// Robust by design: every decode path validates the format tag + version (with a
// [ _migrate] hook for future upgrades) and raises a clear, catchable
// [TrackerSongCodecException] instead of a raw cast error. Instruments serialize
// via tracker_instrument_codec, so a song using a loaded SoundFont voice
// (Sf2/MultiSample — not embeddable) reports which channel and points at the
// reference store. Correctness is guaranteed by a render-roundtrip test (a song
// and its decoded twin render byte-identically). Pure Dart, no Flutter.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart'
    show Inflate, OutputMemoryStream, ZLibEncoder;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_instrument_codec.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';

/// The on-disk format tag + version (bump on a breaking layout change; add a
/// migration step in [_migrate]).
const String kTrackerSongFormat = 'cometbeat.trackersong';
const int kTrackerSongVersion = 1;

/// Share-token prefix — `CBS1.` = CometBeat Song v1 (mirrors the Loop Mixer's
/// `KU1.` groove token). The remainder is url-safe base64 of the zlib-compressed
/// JSON.
const String kTrackerSongTokenPrefix = 'CBS1.';

/// A clear, catchable error for any malformed song data / token (never a raw
/// cast/format exception leaking to the UI).
class TrackerSongCodecException implements Exception {
  TrackerSongCodecException(this.message);
  final String message;
  @override
  String toString() => 'TrackerSongCodecException: $message';
}

// ── JSON ─────────────────────────────────────────────────────────────────────

/// Serialize a whole [song] to a JSON-safe map. An optional [title] is stored
/// for library display (the song model itself has no title).
Map<String, dynamic> trackerSongToJson(TrackerSong song, {String? title}) {
  song.syncCurrent(); // fold any live edit into the current pattern first
  return {
    'format': kTrackerSongFormat,
    'version': kTrackerSongVersion,
    if (title != null && title.isNotEmpty) 'title': title,
    'timing': _timingToJson(song.timing),
    'order': List<int>.of(song.order),
    'instruments': [
      for (var i = 0; i < song.instruments.length; i++)
        _instrumentToJson(song.instruments[i], 'pool instrument ${i + 1}'),
    ],
    'channels': [for (final c in song.channels) _channelToJson(c)],
    'patterns': [for (final p in song.patterns) _patternToJson(p)],
  };
}

/// Rebuild a [TrackerSong] from [json] (as produced by [trackerSongToJson]).
/// Throws [TrackerSongCodecException] on anything malformed.
TrackerSong trackerSongFromJson(Map<String, dynamic> json) {
  try {
    // Inside the try so any migration/cast failure maps to the typed exception.
    final data = _migrate(json);
    final timing = _timingFromJson(_map(data, 'timing'));
    final patterns = [
      for (final p in _list(data, 'patterns'))
        _patternFromJson(_asMap(p, 'pattern')),
    ];
    // The engine's channels start on pattern 0; size them to it.
    final rows0 = patterns.isNotEmpty && patterns.first.cells.isNotEmpty
        ? patterns.first.cells.first.length
        : timing.rows;
    final channels = [
      for (final c in _list(data, 'channels'))
        _channelFromJson(_asMap(c, 'channel'), rows0),
    ];
    final instruments = [
      for (final i in _list(data, 'instruments'))
        instrumentFromJson(_asMap(i, 'instrument')),
    ];
    return TrackerSong.fromParts(
      channels: channels,
      timing: timing,
      patterns: patterns,
      order: [for (final o in _list(data, 'order')) _asInt(o, 'order entry')],
      instruments: instruments,
    );
  } on TrackerSongCodecException {
    rethrow;
  } on InstrumentCodecException catch (e) {
    throw TrackerSongCodecException('instrument decode failed — ${e.message}');
  } catch (e) {
    throw TrackerSongCodecException('malformed song data ($e)');
  }
}

/// song → compact JSON string.
String trackerSongToJsonString(TrackerSong song, {String? title}) =>
    jsonEncode(trackerSongToJson(song, title: title));

/// JSON string → song (throws [TrackerSongCodecException] on bad input).
TrackerSong trackerSongFromJsonString(String s) {
  final Object? decoded;
  try {
    decoded = jsonDecode(s);
  } catch (_) {
    throw TrackerSongCodecException('invalid JSON');
  }
  if (decoded is! Map<String, dynamic>) {
    throw TrackerSongCodecException('expected a JSON object');
  }
  return trackerSongFromJson(decoded);
}

// ── Share token (compressed) ─────────────────────────────────────────────────

/// A compact, paste-able share token: the song's JSON zlib-compressed + url-safe
/// base64, prefixed [kTrackerSongTokenPrefix]. Far smaller than raw JSON for a
/// real song (many patterns/cells compress well).
String trackerSongToToken(TrackerSong song, {String? title}) {
  final jsonBytes = utf8.encode(trackerSongToJsonString(song, title: title));
  final compressed = const ZLibEncoder().encodeBytes(jsonBytes);
  return '$kTrackerSongTokenPrefix${base64UrlEncode(compressed)}';
}

/// Decode a [token] from [trackerSongToToken]. Throws [TrackerSongCodecException]
/// with a specific reason (bad prefix / base64 / decompression / JSON) so the UI
/// can tell the user what went wrong.
TrackerSong trackerSongFromToken(String token) {
  final body = _tokenBody(token);
  final Uint8List jsonBytes;
  try {
    jsonBytes = _inflateBounded(base64Url.decode(body), kMaxTokenJsonBytes);
  } on TrackerSongCodecException {
    rethrow;
  } catch (_) {
    throw TrackerSongCodecException('corrupt song token (bad data)');
  }
  final String jsonStr;
  try {
    jsonStr = utf8.decode(jsonBytes);
  } catch (_) {
    throw TrackerSongCodecException('corrupt song token (bad text)');
  }
  return trackerSongFromJsonString(jsonStr);
}

/// Hard cap on a token's DECOMPRESSED JSON — far above any real song (a few
/// seconds of embedded 16-bit sample PCM is ~a few MB), but a firm bound so a
/// crafted token can't decompress to gigabytes (a zip bomb) and OOM the app.
const int kMaxTokenJsonBytes = 64 << 20; // 64 MiB

/// Thrown internally when the decompressed output exceeds the cap.
class _TokenBomb implements Exception {
  const _TokenBomb();
}

/// An [OutputMemoryStream] that aborts once it has written more than [maxBytes],
/// so a decompression bomb stops near the cap instead of exhausting memory.
class _CappedOutputStream extends OutputMemoryStream {
  _CappedOutputStream(this.maxBytes);
  final int maxBytes;

  @override
  void writeByte(int value) {
    super.writeByte(value);
    if (length > maxBytes) throw const _TokenBomb();
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    super.writeBytes(bytes, length: length);
    if (this.length > maxBytes) throw const _TokenBomb();
  }
}

/// Zlib-inflate [compressed] with a hard cap on the DECOMPRESSED size. Uses
/// package:archive's pure-Dart [Inflate] with a size-capped output — portable
/// across native + web (a capping stream on the platform ZLib decoder isn't
/// honoured by the native path, which buffers the whole output first). Skips the
/// 2-byte zlib header; Inflate reads the raw DEFLATE body and ignores the
/// trailing adler32. Throws [TrackerSongCodecException] on a bomb.
Uint8List _inflateBounded(Uint8List compressed, int maxBytes) {
  if (compressed.length < 2) {
    throw TrackerSongCodecException('corrupt song token (truncated)');
  }
  final out = _CappedOutputStream(maxBytes);
  try {
    Inflate(compressed.sublist(2), output: out);
  } on _TokenBomb {
    throw TrackerSongCodecException(
      'song token too large (possible decompression bomb)',
    );
  }
  return out.getBytes();
}

/// Like [trackerSongFromToken] but returns null on ANY foreign/corrupt input
/// (for UI paste handling — never throws). Mirrors the groove `KU1.` decoder.
TrackerSong? tryTrackerSongFromToken(String token) {
  try {
    return trackerSongFromToken(token);
  } catch (_) {
    return null;
  }
}

// ── Metadata peek (library lists) ────────────────────────────────────────────

/// Lightweight song metadata read WITHOUT building the full song — for a library
/// list / preview.
class TrackerSongInfo {
  const TrackerSongInfo({
    required this.title,
    required this.version,
    required this.channelCount,
    required this.patternCount,
    required this.orderLength,
    required this.instrumentCount,
  });

  final String title;
  final int version;
  final int channelCount;
  final int patternCount;
  final int orderLength;
  final int instrumentCount;
}

/// Read [TrackerSongInfo] from a JSON map (validates format/version).
TrackerSongInfo trackerSongInfo(Map<String, dynamic> json) {
  final data = _migrate(json);
  int len(String k) => (data[k] is List) ? (data[k] as List).length : 0;
  // Type-safe reads: an untrusted token's metadata may be any JSON type; a raw
  // cast would throw a TypeError (an Error) instead of degrading to a default.
  final rawTitle = data['title'];
  final rawVer = data['version'];
  return TrackerSongInfo(
    title: rawTitle is String ? rawTitle : '',
    version: rawVer is num ? rawVer.toInt() : kTrackerSongVersion,
    channelCount: len('channels'),
    patternCount: len('patterns'),
    orderLength: len('order'),
    instrumentCount: len('instruments'),
  );
}

/// Read [TrackerSongInfo] from a share token (throws on a bad token).
TrackerSongInfo trackerSongInfoFromToken(String token) {
  final body = _tokenBody(token);
  try {
    final bytes = _inflateBounded(base64Url.decode(body), kMaxTokenJsonBytes);
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map<String, dynamic>) {
      throw TrackerSongCodecException('token is not a song');
    }
    return trackerSongInfo(json);
  } on TrackerSongCodecException {
    rethrow;
  } catch (_) {
    throw TrackerSongCodecException('corrupt song token');
  }
}

// ── version / migration ──────────────────────────────────────────────────────

/// Validate the format tag + version and upgrade older payloads to the current
/// layout. A `null` format is tolerated (hand-built maps / tests); a DIFFERENT
/// non-null format or a FUTURE version is rejected with a clear message.
Map<String, dynamic> _migrate(Map<String, dynamic> json) {
  final fmt = json['format'];
  if (fmt != null && fmt != kTrackerSongFormat) {
    throw TrackerSongCodecException('not a CometBeat song (format "$fmt")');
  }
  // Type-safe read: a hostile token could carry a non-num `version` (bool,
  // string …); a raw `as num?` cast would throw a TypeError (an Error) instead
  // of the decoder's typed exception.
  final rawVer = json['version'];
  final ver = rawVer is num ? rawVer.toInt() : kTrackerSongVersion;
  if (ver > kTrackerSongVersion) {
    throw TrackerSongCodecException(
      'this song is version $ver but the app supports up to '
      '$kTrackerSongVersion — please update the app',
    );
  }
  // v1 is current; future upgrades (v1→v2 …) chain here.
  return json;
}

// ── typed field access (clear errors, not raw casts) ─────────────────────────

String _tokenBody(String token) {
  final t = token.trim();
  if (!t.startsWith(kTrackerSongTokenPrefix)) {
    throw TrackerSongCodecException(
      'not a CometBeat song token (expected a "$kTrackerSongTokenPrefix" prefix)',
    );
  }
  final raw = t.substring(kTrackerSongTokenPrefix.length);
  try {
    return base64Url.normalize(raw);
  } catch (_) {
    throw TrackerSongCodecException('corrupt song token (invalid base64)');
  }
}

Map<String, dynamic> _map(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v is! Map<String, dynamic>) {
    throw TrackerSongCodecException('missing/invalid "$key" object');
  }
  return v;
}

List<dynamic> _list(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v is! List) {
    throw TrackerSongCodecException('missing/invalid "$key" list');
  }
  return v;
}

Map<String, dynamic> _asMap(Object? v, String what) {
  if (v is! Map<String, dynamic>) {
    throw TrackerSongCodecException('expected a $what object');
  }
  return v;
}

int _asInt(Object? v, String what) {
  if (v is! num) throw TrackerSongCodecException('expected an integer $what');
  return v.toInt();
}

/// Upper bound on a pattern's row count — far above any real song (a channel
/// column is `List.filled(rows, …)`, so an unbounded `rows` from an untrusted
/// share token is an allocation bomb: a tiny token declaring `rows: 2e9` would
/// OOM the app when pasted). 64K rows is ~0.5 MB/channel — a hard safety cap.
const int kMaxTrackerRows = 1 << 16;

/// Reads a bounded integer field from decoded token JSON. Rejects an
/// out-of-range value with a clean [TrackerSongCodecException] BEFORE it can
/// size an allocation — the token decoder's DoS guard.
int _boundedInt(Object? v, int fallback, int min, int max, String what) {
  final n = v is num ? v.toInt() : fallback;
  if (n < min || n > max) {
    throw TrackerSongCodecException('$what out of range ($n)');
  }
  return n;
}

Map<String, dynamic> _instrumentToJson(TrackerInstrument inst, String where) {
  try {
    return instrumentToJson(inst);
  } on InstrumentCodecException catch (e) {
    throw TrackerSongCodecException(
      '$where can\'t be saved (${e.message}). Loaded SoundFont voices are '
      'stored by reference — see the reference store.',
    );
  }
}

// ── timing ───────────────────────────────────────────────────────────────────

Map<String, dynamic> _timingToJson(TrackerTiming t) => {
      'tempoBpm': t.tempoBpm,
      'rows': t.rows,
      'stepsPerBeat': t.stepsPerBeat,
      'swing': t.swing,
    };

TrackerTiming _timingFromJson(Map<String, dynamic> m) => TrackerTiming(
      // Bound every size/rate field so a crafted token can't OOM (rows sizes a
      // per-channel List.filled) or divide-by-zero (tempo/steps are divisors).
      tempoBpm: _boundedInt(m['tempoBpm'], 120, 1, 100000, 'tempoBpm'),
      rows: _boundedInt(m['rows'], 16, 1, kMaxTrackerRows, 'rows'),
      stepsPerBeat: _boundedInt(m['stepsPerBeat'], 4, 1, 1024, 'stepsPerBeat'),
      swing: ((m['swing'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 0.9),
    );

// ── channel ──────────────────────────────────────────────────────────────────

Map<String, dynamic> _channelToJson(TrackerChannel c) => {
      'id': c.id,
      'instrument': _instrumentToJson(c.instrument, 'channel "${c.id}"'),
      'gain': c.gain,
      'pan': c.pan,
      'muted': c.muted,
      if (c.volumeEnvelope != null)
        'volumeEnvelope': _volEnvToJson(c.volumeEnvelope!),
      if (c.panEnvelope != null) 'panEnvelope': _panEnvToJson(c.panEnvelope!),
      'effects': [for (final e in c.effects) e.name],
    };

TrackerChannel _channelFromJson(Map<String, dynamic> m, int rows) {
  final ch = TrackerChannel(
    id: (m['id'] as String?) ?? 'ch',
    instrument: instrumentFromJson(_asMap(m['instrument'], 'instrument')),
    rows: rows,
    gain: (m['gain'] as num?)?.toDouble() ?? 0.6,
    pan: (m['pan'] as num?)?.toDouble() ?? 0.0,
    volumeEnvelope: m['volumeEnvelope'] == null
        ? null
        : _volEnvFromJson(_asMap(m['volumeEnvelope'], 'volumeEnvelope')),
    panEnvelope: m['panEnvelope'] == null
        ? null
        : _panEnvFromJson(_asMap(m['panEnvelope'], 'panEnvelope')),
    effects: [
      for (final e in (m['effects'] as List? ?? const []))
        _channelEffectFromName(e as String),
    ],
  );
  ch.muted = (m['muted'] as bool?) ?? false;
  return ch;
}

/// An unknown insert-effect name degrades to [TrackerChannelEffect.none] rather
/// than throwing (forward-compatible with effects added in a later version).
TrackerChannelEffect _channelEffectFromName(String name) {
  for (final e in TrackerChannelEffect.values) {
    if (e.name == name) return e;
  }
  return TrackerChannelEffect.none;
}

// ── envelopes ────────────────────────────────────────────────────────────────

Map<String, dynamic> _volEnvToJson(VolumeEnvelope e) => {
      'points': [
        for (final p in e.points) {'ms': p.ms, 'level': p.level},
      ],
    };

VolumeEnvelope _volEnvFromJson(Map<String, dynamic> m) => VolumeEnvelope([
      for (final p in (m['points'] as List? ?? const []))
        (
          ms: ((p as Map)['ms'] as num).toInt(),
          level: (p['level'] as num).toDouble(),
        ),
    ]);

Map<String, dynamic> _panEnvToJson(PanEnvelope e) => {
      'points': [
        for (final p in e.points) {'ms': p.ms, 'pan': p.pan},
      ],
    };

PanEnvelope _panEnvFromJson(Map<String, dynamic> m) => PanEnvelope([
      for (final p in (m['points'] as List? ?? const []))
        (
          ms: ((p as Map)['ms'] as num).toInt(),
          pan: (p['pan'] as num).toDouble(),
        ),
    ]);

// ── pattern + cells ──────────────────────────────────────────────────────────

Map<String, dynamic> _patternToJson(TrackerPattern p) => {
      'name': p.name,
      // Channel-major, like the model; an empty cell is null (compact).
      'cells': [
        for (final col in p.cells) [for (final cell in col) _cellToJson(cell)],
      ],
    };

TrackerPattern _patternFromJson(Map<String, dynamic> m) => TrackerPattern(
      name: (m['name'] as String?) ?? '00',
      cells: [
        for (final col in _list(m, 'cells'))
          [
            for (final cell in (col as List))
              _cellFromJson(cell == null ? null : _asMap(cell, 'cell')),
          ],
      ],
    );

/// A cell as a compact map of only its non-default fields, or null when empty.
Map<String, dynamic>? _cellToJson(TrackerCell c) {
  if (c.midi == null &&
      c.volume == null &&
      c.effect == TrackerEffect.none &&
      c.fxCmd == 0 &&
      c.fxParam == 0 &&
      c.instrument == 0 &&
      !c.keyOff) {
    return null;
  }
  return {
    if (c.midi != null) 'n': c.midi,
    if (c.volume != null) 'v': c.volume,
    if (c.effect != TrackerEffect.none) 'e': c.effect.name,
    if (c.fxCmd != 0) 'c': c.fxCmd,
    if (c.fxParam != 0) 'p': c.fxParam,
    if (c.instrument != 0) 'i': c.instrument,
    if (c.keyOff) 'k': true,
  };
}

TrackerCell _cellFromJson(Map<String, dynamic>? m) {
  if (m == null) return TrackerCell.empty;
  return TrackerCell(
    midi: (m['n'] as num?)?.toInt(),
    volume: (m['v'] as num?)?.toDouble(),
    effect: _trackerEffectFromName(m['e'] as String?),
    fxCmd: (m['c'] as num?)?.toInt() ?? 0,
    fxParam: (m['p'] as num?)?.toInt() ?? 0,
    instrument: (m['i'] as num?)?.toInt() ?? 0,
    keyOff: m['k'] == true,
  );
}

/// An unknown cell-effect name degrades to [TrackerEffect.none] (forward-compat).
TrackerEffect _trackerEffectFromName(String? name) {
  if (name == null) return TrackerEffect.none;
  for (final e in TrackerEffect.values) {
    if (e.name == name) return e;
  }
  return TrackerEffect.none;
}
