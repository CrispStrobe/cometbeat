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
    name: 'Christmas ChordPro — Cardinote Inc.',
    description: 'Twenty-one public-domain Christmas carols and hymns as '
        'ChordPro sources, with chords and guitar fingerings. The '
        'transcriptions are MIT-licensed, © 2020 Cardinote Inc.; the carols '
        'themselves are long out of copyright.',
    url: 'https://github.com/cardinote/christmas-chords-lyrics',
  ),
  MusicSourceCredit(
    name: 'Kinder wollen singen — Musikpiraten e.V.',
    description:
        "Children's-song scores (LilyPond & MuseScore). The settings are "
        'public domain (gemeinfrei); the German "Auld Lang Syne" translation '
        'is CC BY-SA 4.0 by Ulrich Wolf.',
    url: 'https://www.kinder-wollen-singen.de',
  ),
  MusicSourceCredit(
    name: "Simon Wascher's TradArchiv",
    description: 'Dance melodies from three historical manuscripts, '
        'transcribed to ABC by Simon Wascher, Richmud Rollenbeck, '
        'Jørgen Lang, Jan Kristof Schliep and Thomas Behr: the '
        '"Tanzsammlung Dahlhoff" (Staatsbibliothek zu Berlin, Mus. ms. 40182); '
        'the 1720 "Dantz Büchlein" of Johann Friedrich Dreyßer (Bayerische '
        'Staatsbibliothek, Mus. ms. 1578); and the lost "Handschrift aus '
        'Arendsee" from Mecklenburg, as copied by Richard Wossidlo in 1900. '
        'The transcribers assert no copyright but require the source '
        'to be named.',
    url: 'http://simonwascher.info/TradArchiv/',
  ),
];
