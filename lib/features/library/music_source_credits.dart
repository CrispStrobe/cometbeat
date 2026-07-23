// Standing SOURCE-level credits for the open-music catalogs the app draws from.
//
// Per-imported-work attribution travels on each `ImportedSong.attribution`
// (set by `library_import.dart` via `LicensePolicy.attributionFor`). This list
// is the complement: it credits the SOURCE PROJECTS whose licence obliges
// attribution (CC BY / CC BY-SA), independent of whether any single work has
// been imported yet — so the obligation is met for browse-only users too.
//
// CC0 / public-domain sources create no obligation and are deliberately omitted
// (mirrors the per-work rule in `attribution_screen.dart`). A project appears
// here only if some of its catalogued material is attribution-bearing.

/// One credited upstream music source.
class MusicSourceCredit {
  final String name;

  /// What we use from it + the licence basis + any specific per-work credit the
  /// licence names (e.g. a CC BY-SA translator).
  final String description;

  final String url;

  const MusicSourceCredit({
    required this.name,
    required this.description,
    required this.url,
  });
}

/// The attribution-bearing music sources bundled/served in the catalog.
/// Append new CC-BY / CC-BY-SA sources here as they are ingested.
const List<MusicSourceCredit> kMusicSourceCredits = [
  MusicSourceCredit(
    name: 'Kinder wollen singen — Musikpiraten e.V.',
    description:
        "Children's-song scores (LilyPond & MuseScore). The settings are "
        'public domain (gemeinfrei); the German "Auld Lang Syne" translation '
        'is CC BY-SA 4.0 by Ulrich Wolf.',
    url: 'https://www.kinder-wollen-singen.de',
  ),
];
