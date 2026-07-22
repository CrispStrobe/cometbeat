// Registry of connected open-music libraries + the default (real) HTTP fetch.
// The UI asks the registry for the available sources; each is a thin adapter
// (see content_source.dart). Adding a vetted source = one line here.
//
// Only SAFE / permissively-licensed sources are wired. The connect-first list
// and the verdicts for the rest are in docs/LIBRARIES_AND_TAB_SCOPING.md §1.2.

import 'dart:typed_data';

import 'package:comet_beat/features/library/content_source.dart';
import 'package:comet_beat/features/library/sources/commons_source.dart';
import 'package:comet_beat/features/library/sources/freepats_source.dart';
import 'package:comet_beat/features/library/sources/gregobase_source.dart';
import 'package:comet_beat/features/library/sources/openscore_source.dart';
import 'package:comet_beat/features/library/sources/vcsl_source.dart';
import 'package:http/http.dart' as http;

/// Production [HttpGet]: a plain GET returning the body bytes, or throwing on a
/// non-2xx status. A short, honest User-Agent is sent (GitHub's API wants one).
Future<Uint8List> defaultHttpGet(Uri url) async {
  final res = await http.get(
    url,
    headers: const {
      'User-Agent': 'CometBeat-music-education-app',
      'Accept': 'application/octet-stream, application/json;q=0.9, */*;q=0.8',
    },
  );
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw http.ClientException(
      'HTTP ${res.statusCode} for $url',
      url,
    );
  }
  return res.bodyBytes;
}

/// Builds the list of connected sources, using [http] for all I/O (defaults to
/// the real network; tests pass a fake).
List<ContentSource> buildSources({HttpGet http = defaultHttpGet}) => [
      OpenScoreSource.lieder(http),
      OpenScoreSource.stringQuartets(http),
      CommonsSource(http),
      // A separate "Gregorian Chant" category so the ~18.7k CC0 GregoBase chants
      // don't swamp the main (children's) repertoire.
      GregoBaseSource(http),
    ];

/// Sources that yield **audio samples** (WAV), not notation — kept out of
/// [buildSources] because they don't decode to MusicXML. The Tracker's
/// sample-instrument UI is the intended consumer (see
/// docs/CC0_SAMPLE_SOURCE_HANDOFF.md). CC0/PD-filtered by the default policy.
List<ContentSource> buildSampleSources({HttpGet http = defaultHttpGet}) => [
      // VCSL first: a blanket-CC0 instrument library (thousands of WAVs) is a
      // better default than Commons' mixed bag, which needs per-file filtering.
      VcslSource(http),
      CommonsSource.audio(http),
    ];

/// Sources that yield whole sample PACKS (archives of many WAVs) rather than
/// single files — consumed by the Sample Extractor via `showSamplePackSheet`.
/// Licences vary per instrument here, so the policy gate does real work.
List<ContentSource> buildSamplePackSources({HttpGet http = defaultHttpGet}) => [
      FreepatsSource(http),
    ];
