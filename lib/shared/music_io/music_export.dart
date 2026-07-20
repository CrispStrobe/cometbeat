// lib/shared/music_io/music_export.dart
//
// A reusable "export this music to any format" bottom sheet. Any screen that
// holds a MultiPartScore (Song Book, trackers, Loop Mixer, …) can offer the
// whole library's writers from one place instead of copy-pasting per screen.
//
// Every format here keeps every part — MusicXML/.mxl/ABC/MEI/MuseScore/kern/
// LilyPond/MIDI/module are multi-voice, Braille is written section-by-section
// (each part labelled), and PDF engraves one system per line with all staves.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart'
    show convertToMod;
import 'package:comet_beat/core/audio/mod/module_notation.dart'
    show multiPartToModuleDoc;
import 'package:comet_beat/core/notation/multi_part_export.dart'
    show multiPartToAbc, multiPartToMidi;
import 'package:comet_beat/features/workshop/export/score_pdf.dart'
    show exportMultiPartToPdf;
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

/// One exportable format: a label, a file extension, and a builder that turns
/// the score into the file's bytes (string writers are utf8-encoded here).
class _ExportFormat {
  const _ExportFormat(this.label, this.ext, this.build);
  final String label;
  final String ext;
  final FutureOr<Uint8List> Function(MultiPartScore mp, List<String> names)
      build;
}

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

final List<_ExportFormat> _kFormats = [
  // Multi-part (every voice survives).
  _ExportFormat(
    'MusicXML',
    'musicxml',
    (mp, names) => _utf8(multiPartToMusicXml(mp, partNames: names)),
  ),
  _ExportFormat(
    'MusicXML (.mxl)',
    'mxl',
    (mp, names) =>
        writeMusicXmlToMxl(multiPartToMusicXml(mp, partNames: names)),
  ),
  _ExportFormat(
    'ABC',
    'abc',
    (mp, names) => _utf8(multiPartToAbc(mp, partNames: names)),
  ),
  _ExportFormat('MIDI', 'mid', (mp, names) => multiPartToMidi(mp)),
  _ExportFormat(
    'Module (.mod)',
    'mod',
    (mp, names) => convertToMod(multiPartToModuleDoc(mp, title: 'SONG')),
  ),
  // MEI keeps every part (one <staff> per part); the rest are single-Score.
  _ExportFormat(
    'MEI',
    'mei',
    (mp, names) => _utf8(multiPartToMei(mp, partNames: names)),
  ),
  _ExportFormat(
    'Humdrum **kern',
    'krn',
    (mp, names) => _utf8(multiPartToKern(mp, partNames: names)),
  ),
  _ExportFormat(
    'LilyPond',
    'ly',
    (mp, names) => _utf8(multiPartToLilyPond(mp, partNames: names)),
  ),
  _ExportFormat(
    'Braille',
    'brf',
    (mp, names) => _utf8(multiPartToBraille(mp, partNames: names)),
  ),
  _ExportFormat(
    'MuseScore',
    'mscx',
    (mp, names) => _utf8(multiPartToMscx(mp, partNames: names)),
  ),
  _ExportFormat('PDF', 'pdf', (mp, names) => exportMultiPartToPdf(mp)),
];

/// Shows the export picker; on pick, builds the bytes and prompts for a save
/// location. [baseName] seeds the suggested filename (no extension).
Future<void> showMusicExportSheet(
  BuildContext context, {
  required MultiPartScore multiPart,
  required List<String> partNames,
  required String baseName,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  if (multiPart.parts.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.musicExportEmpty)));
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.musicExportTitle,
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in _kFormats)
                  ActionChip(
                    label: Text(f.label),
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await _exportAs(
                        context,
                        f,
                        multiPart,
                        partNames,
                        baseName,
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _exportAs(
  BuildContext context,
  _ExportFormat fmt,
  MultiPartScore mp,
  List<String> names,
  String baseName,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await fmt.build(mp, names);
    final suggested = '$baseName.${fmt.ext}';
    final location = await getSaveLocation(
      suggestedName: suggested,
      acceptedTypeGroups: [
        XTypeGroup(label: fmt.label, extensions: [fmt.ext]),
      ],
    );
    if (location == null) return;
    await XFile.fromData(bytes, name: suggested).saveTo(location.path);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.workshopSavedTo(location.path))),
    );
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.musicExportFailed)));
  }
}
