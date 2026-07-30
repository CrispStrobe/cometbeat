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

  /// The CORPUS this row came from — "GregoBase", "CPDL", "NIFC Polish Scores".
  ///
  /// Distinct from [sourceName], which is the CONNECTOR ("CometBeat Library")
  /// and is therefore identical for every row of a curated catalog. Filtering by
  /// provenance needs this; filtering by [sourceName] narrows nothing.
  final String? corpusSource;

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
    this.corpusSource,
  });
}

/// A set-membership filter over the facets a library row actually carries.
///
/// Deliberately built from `LibraryItem` fields that already exist — kind
/// (`collection`), `format`, `declaredLicense`, `sourceName` — so no source has
/// to grow a new field. Licence is matched as a case-insensitive SUBSTRING
/// because the strings in the wild are prose ("CC0 1.0", "Public Domain",
/// "CC BY 4.0", "MIT License"): a user picking "CC0" means "anything CC0", not
/// one exact spelling.
class LibraryFilter {
  const LibraryFilter({
    this.kinds = const {},
    this.formats = const {},
    this.licences = const {},
    this.sources = const {},
  });

  final Set<String> kinds;
  final Set<String> formats;
  final Set<String> licences;
  final Set<String> sources;

  bool get isEmpty =>
      kinds.isEmpty && formats.isEmpty && licences.isEmpty && sources.isEmpty;

  bool matches(LibraryItem i) {
    if (kinds.isNotEmpty && !kinds.contains(i.collection)) return false;
    if (formats.isNotEmpty && !formats.contains(i.format)) return false;
    // Prefer the corpus source; fall back to the connector name for sources
    // that do not carry provenance per row.
    if (sources.isNotEmpty &&
        !sources.contains(i.corpusSource ?? i.sourceName)) {
      return false;
    }
    if (licences.isNotEmpty) {
      final lic = i.declaredLicense.toLowerCase();
      if (!licences.any((l) => lic.contains(l.toLowerCase()))) return false;
    }
    return true;
  }

  LibraryFilter toggle(String facet, String value) {
    Set<String> flip(Set<String> s) => s.contains(value)
        ? (s.toSet()..remove(value))
        : (s.toSet()..add(value));
    return LibraryFilter(
      kinds: facet == 'kind' ? flip(kinds) : kinds,
      formats: facet == 'format' ? flip(formats) : formats,
      licences: facet == 'licence' ? flip(licences) : licences,
      sources: facet == 'source' ? flip(sources) : sources,
    );
  }
}

/// One page of results.
///
/// `total` is NULLABLE on purpose. A source that holds its whole catalog in
/// memory can count exactly; a source that pages a remote API cannot, and
/// inventing a number there would be a lie the UI then displays. `hasMore` is
/// always knowable, so paging works either way.
class LibraryPage {
  const LibraryPage({required this.items, this.total, required this.hasMore});

  final List<LibraryItem> items;

  /// Exact number of matches, or null when the source cannot know.
  final int? total;
  final bool hasMore;
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

  /// Filtered, paged browse.
  ///
  /// ⚠️ Declared, not defaulted. Every source uses `implements ContentSource`,
  /// and `implements` does NOT inherit a method body — a concrete default here
  /// compiles but leaves all nine sources missing the member. So each source
  /// delegates to [browsePageByFiltering] in one line, which keeps the logic in
  /// one place while staying explicit about who implements what.
  Future<LibraryPage> browsePage({
    String query,
    LibraryFilter filter,
    int limit,
    int offset,
  });

  /// Downloads [item]'s bytes in its [LibraryItem.format].
  Future<Uint8List> fetch(LibraryItem item);
}

/// The default [ContentSource.browsePage]: ask [ContentSource.browse] for one
/// more item than the page needs, filter what came back, and slice.
///
/// Asking for `offset + limit + 1` is what makes "load more" knowable without
/// pretending to know a total. ⚠️ Filtering applies only to what `browse`
/// returned, so a filter plus a deep offset can under-report on a source that
/// pages a remote API — which is exactly why `total` is left null instead of
/// guessed. A source holding its whole catalog in memory should implement
/// `browsePage` itself and report an exact total.
Future<LibraryPage> browsePageByFiltering(
  ContentSource source, {
  String query = '',
  LibraryFilter filter = const LibraryFilter(),
  int limit = 60,
  int offset = 0,
}) async {
  final fetched = await source.browse(query: query, limit: offset + limit + 1);
  final matched =
      filter.isEmpty ? fetched : fetched.where(filter.matches).toList();
  return LibraryPage(
    items: matched.skip(offset).take(limit).toList(),
    hasMore: matched.length > offset + limit,
  );
}
