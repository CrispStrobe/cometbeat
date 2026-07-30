// The connector's content-source abstraction. A `ContentSource` browses an
// external open-music library and fetches an item's bytes; the app never talks
// to a specific site directly. Adding a source = one adapter implementing this
// interface + a `SourceRegistry` entry. All I/O goes through an injectable
// [HttpGet] so the sources are unit-testable without a live network.

import 'dart:typed_data';

/// Minimal HTTP GET seam — returns the raw bytes at [url] or throws. Injected
/// so tests feed fixtures and production uses `package:http` (see
/// `source_registry.dart`).
typedef HttpGet = Future<Uint8List> Function(Uri url);

/// What a work actually SOUNDS like, precomputed by the catalog so browsing
/// does not have to download and parse every candidate.
///
/// The catalog is otherwise musically opaque — a row tells you who wrote a
/// piece and under what licence, but not whether a class could sing it. These
/// are the three questions worth answering before importing: what key, what
/// metre, and does it fit the range.
class MusicInfo {
  /// Inferred key, e.g. "D major" — not just the signature, so it separates
  /// D major from B minor.
  final String? key;

  /// Time signature as printed, e.g. "6/8". Null for unmetered music
  /// (Renaissance polyphony and chant legitimately have none).
  final String? meter;

  final int? bars;

  /// Lowest and highest sounding MIDI note over all parts.
  final int? lowestMidi;
  final int? highestMidi;

  /// Opening melody as MIDI note numbers.
  final List<int> incipit;

  const MusicInfo({
    this.key,
    this.meter,
    this.bars,
    this.lowestMidi,
    this.highestMidi,
    this.incipit = const [],
  });

  /// Range in semitones, or null when the pitches are unknown.
  int? get ambitusSemitones => (lowestMidi == null || highestMidi == null)
      ? null
      : highestMidi! - lowestMidi!;

  static const _names = [
    'C', 'C♯', 'D', 'E♭', 'E', 'F', 'F♯', 'G', 'A♭', 'A', 'B♭', 'B', //
  ];

  static String _noteName(int midi) => '${_names[midi % 12]}${midi ~/ 12 - 1}';

  /// Range as a readable span, e.g. "D4–D5". Null when unknown.
  String? get ambitusLabel => (lowestMidi == null || highestMidi == null)
      ? null
      : '${_noteName(lowestMidi!)}–${_noteName(highestMidi!)}';

  /// True when everything sounds within one octave — the usual bar for a
  /// piece a young group can sing together.
  bool get fitsOneOctave {
    final a = ambitusSemitones;
    return a != null && a <= 12;
  }

  bool get isEmpty =>
      key == null && meter == null && bars == null && lowestMidi == null;

  /// Reads the `music` object the catalog emits, or null when absent.
  static MusicInfo? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final ambitus = raw['ambitus'];
    final lo = (ambitus is List && ambitus.isNotEmpty) ? ambitus[0] : null;
    final hi = (ambitus is List && ambitus.length > 1) ? ambitus[1] : null;
    final info = MusicInfo(
      key: raw['key'] as String?,
      meter: raw['meter'] as String?,
      bars: raw['bars'] as int?,
      lowestMidi: lo is int ? lo : null,
      highestMidi: hi is int ? hi : null,
      incipit: (raw['incipit'] as List?)?.whereType<int>().toList() ?? const [],
    );
    return info.isEmpty ? null : info;
  }
}

/// One browsable/importable work from a [ContentSource]. Carries everything the
/// license gate + provenance need, so nothing has to be re-fetched to attribute
/// it. Pure data.
class LibraryItem {
  /// Id of the owning [ContentSource].
  final String sourceId;

  /// Human name of the owning source (e.g. "OpenScore Lieder").
  final String sourceName;

  /// Stable id within the source (e.g. the OpenScore `lc…` id).
  final String id;

  final String title;
  final String composer;

  /// A grouping within the source (opus/set), or empty.
  final String collection;

  /// The declared license as the source states it (free text — classified by
  /// `LicensePolicy`, never trusted blindly). E.g. "CC0", "CC BY-SA 4.0".
  final String declaredLicense;

  /// Canonical URL for the license deed, or null.
  final String? licenseUrl;

  /// Human page for the work (for a "view source" link), or null.
  final String? sourceUrl;

  /// Direct download URL for [format]'s bytes.
  final Uri downloadUrl;

  /// Download format: `mxl`, `musicxml`, `midi`, or `abc`.
  final String format;

  /// Precomputed musical description, when the catalog supplies one.
  final MusicInfo? music;

  const LibraryItem({
    required this.sourceId,
    required this.sourceName,
    required this.id,
    required this.title,
    required this.composer,
    this.collection = '',
    required this.declaredLicense,
    this.licenseUrl,
    this.sourceUrl,
    required this.downloadUrl,
    required this.format,
    this.music,
  });
}

/// A browsable external open-music library. Implementations are thin adapters
/// over one site's API/bulk mirror; they must only ever surface items the
/// source publishes under a permissive license (the `LicensePolicy` gate is the
/// backstop, not the first line of defence).
abstract class ContentSource {
  /// Stable source id (matches `LibraryItem.sourceId`).
  String get id;

  /// Display name.
  String get name;

  /// The site's home page.
  String get homepage;

  /// One-line license summary shown in the UI (e.g. "CC0 — public domain").
  String get licenseSummary;

  /// Browses the source, optionally filtered by a free-text [query] (matched
  /// against title/composer). Returns up to [limit] items.
  Future<List<LibraryItem>> browse({String query = '', int limit = 60});

  /// Downloads [item]'s bytes in its [LibraryItem.format].
  Future<Uint8List> fetch(LibraryItem item);
}
