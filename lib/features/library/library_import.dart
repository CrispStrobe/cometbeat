// The import pipeline: LibraryItem → license gate → fetch → decode to MusicXML
// → ImportedSong (with provenance). Kept free of Flutter/network specifics
// (the source + http are injected) so the whole path is unit-testable with a
// fake source.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/core/notation/multi_part_export.dart'
    show multiTrackMidiToMultiPart;
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/library/content_source.dart';
import 'package:comet_beat/features/library/license_policy.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show
        MultiPartScore,
        StaffSystem,
        multiPartScoreFromMscx,
        multiPartToMusicXml,
        readMusicXmlFromMxl,
        scoreFromGabc,
        scoreFromMusicXml;

/// Decodes fetched [bytes] of the given [format] into a MusicXML string. Throws
/// [FormatException] for a format this pipeline can't turn into MusicXML.
///
/// MuseScore (multi-`<Staff>`) and MIDI (multi-track) decode via the multi-part
/// readers so an orchestral `.mscx` (e.g. an OpenScore string quartet) or a
/// multi-track MIDI keeps EVERY part, not just the first.
String bytesToMusicXml(String format, Uint8List bytes) => switch (format) {
      'mxl' => readMusicXmlFromMxl(bytes),
      'musicxml' || 'xml' => utf8.decode(bytes),
      'mscx' => multiPartToMusicXml(multiPartScoreFromMscx(utf8.decode(bytes))),
      'midi' || 'mid' => multiPartToMusicXml(multiTrackMidiToMultiPart(bytes)),
      // GABC (Gregorio chant, e.g. the CC0 GregoBase corpus): single staff.
      'gabc' => multiPartToMusicXml(
          MultiPartScore.fromStaffSystem(
            StaffSystem([scoreFromGabc(utf8.decode(bytes))]),
          ),
        ),
      _ => throw FormatException('Cannot import format: $format'),
    };

/// Runs one [item] through the pipeline and returns an [ImportedSong] ready for
/// `UserSongsService.addSong`. Throws [LicenseBlocked] if the item isn't
/// permissively licensed (before any download), or a [FormatException] if the
/// bytes don't decode/parse.
///
/// [idSuffix] disambiguates the stored id (e.g. a timestamp) — passed in so the
/// function stays pure/deterministic for tests.
Future<ImportedSong> importLibraryItem(
  LibraryItem item,
  ContentSource source, {
  LicensePolicy policy = const LicensePolicy(),
  String idSuffix = '',
}) async {
  policy.gate(item); // throws before we fetch anything non-permissive
  final bytes = await source.fetch(item);
  final xml = bytesToMusicXml(item.format, bytes);
  scoreFromMusicXml(xml); // validate it parses before we store it
  return ImportedSong(
    id: 'lib_${item.sourceId}_${item.id}$idSuffix',
    title: item.title,
    musicXml: xml,
    attribution: policy.attributionFor(item),
    sourceUrl: item.sourceUrl,
  );
}
