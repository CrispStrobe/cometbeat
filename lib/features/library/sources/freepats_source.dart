// Freepats (freepats.zenvoid.org) — a long-running collection of free
// instrument sample packs, distributed as .7z archives.
//
// Two things make this source different from the others:
//
//  1. **No API.** Freepats is a static site, so the catalogue here is a
//     curated list of its instrument PAGES (stable URLs). The licence and the
//     current download link are resolved from each page at browse time —
//     the archive filenames carry release dates and would rot if hard-coded.
//
//  2. **Licences vary PER INSTRUMENT, and one page can host downloads under
//     DIFFERENT licences** (the acoustic grand piano page declares both
//     CC BY 3.0 and CC0). A page-level licence would therefore mislabel a
//     CC BY file as CC0. So: if a page declares exactly one licence we use
//     it; if it declares several we refuse to guess and report the page as
//     ambiguous, which the [LicensePolicy] gate then blocks. Skipping a pack
//     is always better than mis-attributing one.
//
// Only the plain "SFZ" archive is offered: the "SFZ+FLAC" variant needs a FLAC
// decoder we don't have, and the SF2 variant is a soundfont, not loose WAVs.
// Note the packaging is NOT uniform — most instruments ship .7z but some (the
// kalimba) ship .tar.xz, so every container our extractor supports is matched.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/features/library/content_source.dart';
import 'package:comet_beat/features/library/license_policy.dart';

const _kBase = 'https://freepats.zenvoid.org/';

/// The curated instrument pages (relative to [_kBase]).
const kFreepatsPages = <String>[
  'ChromaticPercussion/glass.html',
  'ChromaticPercussion/hang.html',
  'ChromaticPercussion/tubular-bells.html',
  'ChromaticPercussion/xylophone.html',
  'ElectricGuitar/clean-electric-bass.html',
  'ElectricGuitar/clean-electric-guitar.html',
  'ElectricGuitar/distorted-electric-guitar.html',
  'ElectricPiano/synthesized-piano.html',
  'Ethnic/bagpipe.html',
  'Ethnic/jaw-harp.html',
  'Ethnic/kalimba.html',
  'Guitar/acoustic-guitar.html',
  'Guitar/steel-acoustic-guitar.html',
  'OrchestralStrings/harp.html',
  'Organ/accordion.html',
  'Organ/electric-organ.html',
  'Organ/pipe-organ.html',
  'Percussion/acoustic-drum-kit.html',
  'Percussion/electric-percussion.html',
  'Percussion/orchestral-percussion.html',
  'Percussion/world-and-rare-percussion.html',
  'Piano/acoustic-grand-piano.html',
  'Piano/honky-tonk-piano.html',
  'Reed/clarinet.html',
  'Reed/saxophone.html',
  'Synthesizer/synth-bass.html',
  'Synthesizer/synth-brass.html',
  'Synthesizer/synth-effects.html',
  'Synthesizer/synth-lead.html',
  'Synthesizer/synth-pad.html',
  'Synthesizer/synth-strings.html',
  'Wind/ocarina.html',
  'Wind/recorder.html',
];

/// Marker used when a page declares more than one licence — deliberately not
/// a real licence name, so [LicensePolicy.classify] reads it as unknown and
/// the gate blocks it.
const kFreepatsAmbiguous = 'ambiguous: page declares multiple licenses';

/// The licence a Freepats page declares, or a value that will fail the gate
/// when the page is ambiguous / silent.
///
/// [policy] is used only to canonicalise the mentions found, so that e.g.
/// "CC0 1.0" and "Creative Commons CC0 1.0" count as ONE licence.
String freepatsLicenseFrom(String html, {LicensePolicy? policy}) {
  final p = policy ?? const LicensePolicy();
  final mentions = RegExp(
    r'(CC0[^.<,]{0,12}|Creative Commons[^.<]{0,48}|public domain[^.<]{0,24}'
    r'|GNU [A-Za-z ]{0,24})',
    caseSensitive: false,
  ).allMatches(html).map((m) => m.group(0)!.trim()).toList();

  if (mentions.isEmpty) return ''; // unknown → blocked
  // Group by PERMISSION CLASS, not exact wording: a page saying both
  // "CC0 1.0" and "public domain dedication" is describing one licence, but a
  // page saying "CC BY 3.0" and "CC0" is describing two different ones.
  final byClass = <int, String>{};
  for (final m in mentions) {
    final kind = p.classify(m);
    if (kind == LicenseKind.unknown) continue;
    byClass.putIfAbsent(_permissionClass(kind), () => m);
  }
  if (byClass.isEmpty) return '';
  if (byClass.length > 1) return kFreepatsAmbiguous;
  return byClass.values.first;
}

/// Buckets licences by the obligations they impose, so equivalent spellings
/// collapse together.
int _permissionClass(LicenseKind kind) {
  if (kind.isUnconditional) return 0; // CC0 / public domain
  if (kind.isPermissiveNotice) return 1; // MIT / Apache / BSD
  if (kind == LicenseKind.ccBy) return 2; // attribution
  if (kind == LicenseKind.ccBySa) return 3; // attribution + share-alike
  return 4; // NC / ND / all rights reserved
}

/// Containers our extractor can open. Freepats is NOT uniformly .7z — the
/// kalimba ships .tar.xz, for instance — so match every one we support.
final _kArchiveHref = RegExp(
  r'href="([^"]+\.(?:7z|zip|tgz|tar|tar\.(?:xz|gz|bz2)))"',
  caseSensitive: false,
);

/// The preferred sample-pack download on a page: the plain SFZ (WAV) archive.
/// Returns null when the page only offers FLAC / SF2 variants.
String? freepatsDownloadFrom(String html) {
  final hrefs = _kArchiveHref.allMatches(html).map((m) => m.group(1)!).toList();
  if (hrefs.isEmpty) return null;
  // FLAC needs a decoder we don't have; SF2 is a soundfont, not loose WAVs.
  bool unusable(String h) =>
      h.toLowerCase().contains('flac') || h.toLowerCase().contains('sf2');

  for (final h in hrefs) {
    if (!unusable(h) && h.toLowerCase().contains('sfz')) return h;
  }
  for (final h in hrefs) {
    if (!unusable(h)) return h;
  }
  return null;
}

/// The archive extension of [href], e.g. `7z` or `tar.xz`.
String freepatsFormatOf(String href) {
  final lower = href.toLowerCase();
  for (final ext in const ['tar.xz', 'tar.gz', 'tar.bz2', '7z', 'zip', 'tgz']) {
    if (lower.endsWith('.$ext')) return ext;
  }
  return 'archive';
}

/// "Guitar/steel-acoustic-guitar.html" → "Steel Acoustic Guitar".
String freepatsTitleFrom(String page) {
  final file = page.split('/').last.replaceAll('.html', '');
  return file
      .split('-')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// Why a page didn't produce a browsable pack.
///
/// The first two are **licence decisions** — working as designed, and quiet.
/// The rest are **structural**: the page didn't parse the way we expect, which
/// usually means the site's layout changed (or it's unreachable). Those must
/// be loud, or a re-skinned Freepats would silently look like "no packs".
enum FreepatsSkipReason {
  licenseBlocked,
  ambiguousLicense,
  noLicenseStatement,
  noArchiveLink,
  unreachable;

  bool get isStructural =>
      this != FreepatsSkipReason.licenseBlocked &&
      this != FreepatsSkipReason.ambiguousLicense;
}

/// One page that didn't yield a pack, and why.
class FreepatsSkip {
  const FreepatsSkip(this.page, this.reason);
  final String page;
  final FreepatsSkipReason reason;

  @override
  String toString() => '$page: ${reason.name}';
}

/// Thrown when a browse finds nothing AND every page failed structurally —
/// i.e. this is a site/layout problem, not a licensing one.
class FreepatsUnavailable implements Exception {
  const FreepatsUnavailable(this.message, this.skips);
  final String message;
  final List<FreepatsSkip> skips;

  @override
  String toString() => message;
}

/// The outcome of resolving one instrument page.
class FreepatsResolution {
  const FreepatsResolution(this.item, this.reason);
  final LibraryItem? item;
  final FreepatsSkipReason? reason;
}

/// Browses Freepats instrument packs (.7z), licence-gated per instrument.
class FreepatsSource implements ContentSource {
  FreepatsSource(this._http, {LicensePolicy? policy})
      : _policy = policy ?? const LicensePolicy();

  final HttpGet _http;
  final LicensePolicy _policy;

  /// Resolved pages, so re-browsing doesn't re-hit the site.
  final Map<String, LibraryItem?> _cache = {};
  final Map<String, FreepatsSkipReason?> _reasons = {};
  final List<FreepatsSkip> _skips = [];

  /// Pages the last [browse] left out, and why — licence decisions are
  /// expected; anything [FreepatsSkipReason.isStructural] means the site's
  /// layout probably changed.
  List<FreepatsSkip> get lastSkips => List.unmodifiable(_skips);

  @override
  String get id => 'freepats';

  @override
  String get name => 'Freepats';

  @override
  String get homepage => _kBase;

  @override
  String get licenseSummary => 'Per-instrument (mostly CC0)';

  /// Resolves one instrument page into an item, or null when it has no usable
  /// download or its licence is ambiguous/unrecognised.
  Future<LibraryItem?> resolve(String page) async =>
      (await resolveDetailed(page)).item;

  /// Like [resolve], but says WHY a page produced nothing — so a layout change
  /// can be told apart from a licence decision.
  Future<FreepatsResolution> resolveDetailed(String page) async {
    if (_cache.containsKey(page)) {
      final cached = _cache[page];
      return FreepatsResolution(cached, _reasons[page]);
    }
    LibraryItem? item;
    FreepatsSkipReason? reason;
    try {
      final html = utf8.decode(
        await _http(Uri.parse('$_kBase$page')),
        allowMalformed: true,
      );
      final href = freepatsDownloadFrom(html);
      final license = freepatsLicenseFrom(html, policy: _policy);
      if (href == null) {
        reason = FreepatsSkipReason.noArchiveLink;
      } else if (license.isEmpty) {
        reason = FreepatsSkipReason.noLicenseStatement;
      } else {
        final dir = page.contains('/')
            ? page.substring(0, page.lastIndexOf('/') + 1)
            : '';
        item = LibraryItem(
          sourceId: id,
          sourceName: name,
          id: page,
          title: freepatsTitleFrom(page),
          composer: '',
          collection: page.split('/').first,
          declaredLicense: license,
          sourceUrl: '$_kBase$page',
          downloadUrl: Uri.parse('$_kBase$dir$href'),
          format: freepatsFormatOf(href),
        );
        if (license == kFreepatsAmbiguous) {
          reason = FreepatsSkipReason.ambiguousLicense;
        }
      }
    } catch (_) {
      reason = FreepatsSkipReason.unreachable;
    }
    _cache[page] = item;
    _reasons[page] = reason;
    return FreepatsResolution(item, reason);
  }

  @override
  Future<LibraryPage> browsePage({
    String query = '',
    LibraryFilter filter = const LibraryFilter(),
    int limit = 60,
    int offset = 0,
  }) =>
      browsePageByFiltering(
        this,
        query: query,
        filter: filter,
        limit: limit,
        offset: offset,
      );

  @override
  Future<List<LibraryItem>> browse({String query = '', int limit = 60}) async {
    final q = query.trim().toLowerCase();
    final pages = kFreepatsPages
        .where(
          (p) => q.isEmpty || freepatsTitleFrom(p).toLowerCase().contains(q),
        )
        .toList();

    final out = <LibraryItem>[];
    final skips = <FreepatsSkip>[];
    var attempted = 0;
    var structural = 0;
    // Resolving hits one page each, so stay modest even if `limit` is large.
    final budget = limit < 12 ? limit : 12;
    for (final page in pages) {
      if (out.length >= budget) break;
      attempted++;
      final res = await resolveDetailed(page);
      final item = res.item;
      // The gate is the backstop: ambiguous/unknown/NC never surface.
      if (item != null && _policy.isAllowed(item)) {
        out.add(item);
        continue;
      }
      final reason = res.reason ??
          (item == null
              ? FreepatsSkipReason.unreachable
              : FreepatsSkipReason.licenseBlocked);
      skips.add(FreepatsSkip(page, reason));
      if (reason.isStructural) structural++;
    }
    _skips
      ..clear()
      ..addAll(skips);

    // Loud failure: nothing came back AND every page we tried failed
    // structurally. That is a site/layout problem — surfacing it as an empty
    // list would look like "Freepats has no free packs", which is wrong.
    if (out.isEmpty && attempted > 0 && structural == attempted) {
      final sample = skips.take(3).join('; ');
      throw FreepatsUnavailable(
        'Freepats returned nothing usable for all $attempted page(s) — the '
        'site may be unreachable or its page layout changed ($sample)',
        List.of(skips),
      );
    }
    return out;
  }

  @override
  Future<Uint8List> fetch(LibraryItem item) {
    _policy.gate(item); // never download something the policy blocks
    return _http(item.downloadUrl);
  }
}
