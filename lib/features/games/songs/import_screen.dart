// lib/features/games/songs/import_screen.dart
//
// Import: paste MusicXML (from MuseScore & friends) or ChordPro (lyrics
// with [C] chords) into the text field, or pick a simple MIDI file.
// Imported songs live in the Song Book (persisted via UserSongsService).

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/core/notation/multi_part_export.dart'
    show multiTrackMidiToMultiPart;
import 'package:comet_beat/features/games/songs/import/chordpro.dart';
import 'package:comet_beat/features/games/songs/import/jams.dart';
import 'package:comet_beat/features/games/songs/import/omr_import.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/library/library_browser_screen.dart';
import 'package:comet_beat/features/library/license_policy.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show
        MultiPartScore,
        Score,
        StaffSystem,
        multiPartScoreFromAbc,
        multiPartScoreFromKern,
        multiPartScoreFromMei,
        multiPartScoreFromMusicRender,
        multiPartScoreFromMusicXml,
        multiPartToMusicXml,
        readMusicXmlFromMxl,
        scoreFromGabc,
        scoreFromLilyPond,
        scoreFromMusicXml;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _text = TextEditingController();
  final _title = TextEditingController();

  // OMR (scan sheet music) progress.
  bool _omrBusy = false;
  String? _omrStatus;

  String _newId() => DateTime.now().millisecondsSinceEpoch.toString();

  void _fail(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context)!.importFailed(error.toString()),
        ),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  void _done() {
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.importDone)));
    Navigator.of(context).pop();
  }

  /// Title priority: the title field, else the score's embedded work title,
  /// else [fallback].
  String _musicXmlTitle(String xml, {required String fallback}) {
    final typed = _title.text.trim();
    if (typed.isNotEmpty) return typed;
    final embedded = RegExp(r'<(?:work-title|movement-title)>([^<]+)<')
        .firstMatch(xml)
        ?.group(1)
        ?.trim();
    return (embedded != null && embedded.isNotEmpty) ? embedded : fallback;
  }

  void _importMusicXml() {
    try {
      final xml = _text.text.trim();
      scoreFromMusicXml(xml); // validate before storing
      context.read<UserSongsService>().addSong(
            ImportedSong(
              id: _newId(),
              title: _musicXmlTitle(xml, fallback: 'MusicXML'),
              musicXml: xml,
            ),
          );
      _done();
    } catch (e) {
      _fail(e);
    }
  }

  /// One picker for every notation FILE format — MusicXML/.mxl/ABC/MEI/kern/
  /// MIDI — each via its multi-part reader, stored as MusicXML like the rest of
  /// the Song Book. The Song Book's universal front door.
  Future<void> _importMusicFile() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Music',
            extensions: [
              'musicxml',
              'xml',
              'mxl',
              'abc',
              'gabc',
              'mei',
              'krn',
              'mid',
              'midi',
              'json',
              'ly',
              'lilypond',
            ],
          ),
        ],
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final ext = file.name.split('.').last.toLowerCase();
      final mp = switch (ext) {
        'mid' || 'midi' => multiTrackMidiToMultiPart(bytes),
        'abc' => multiPartScoreFromAbc(utf8.decode(bytes)),
        // GABC (Gregorio chant, e.g. the CC0 GregoBase corpus): single staff.
        'gabc' => MultiPartScore.fromStaffSystem(
            StaffSystem([scoreFromGabc(utf8.decode(bytes))]),
          ),
        'mei' => multiPartScoreFromMei(utf8.decode(bytes)),
        'krn' => multiPartScoreFromKern(utf8.decode(bytes)),
        'mxl' => multiPartScoreFromMusicXml(readMusicXmlFromMxl(bytes)),
        'ly' || 'lilypond' => MultiPartScore.fromStaffSystem(
            StaffSystem([scoreFromLilyPond(utf8.decode(bytes))]),
          ),
        // muspy / PDMX "MusicRender" JSON (MuseScore's own JSON export).
        'json' => multiPartScoreFromMusicRender(utf8.decode(bytes)),
        _ => multiPartScoreFromMusicXml(utf8.decode(bytes)),
      };
      final base = file.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      final typed = _title.text.trim();
      context.read<UserSongsService>().addSong(
            ImportedSong(
              id: _newId(),
              title: typed.isNotEmpty ? typed : base,
              musicXml: multiPartToMusicXml(mp),
            ),
          );
      _done();
    } catch (e) {
      if (mounted) _fail(e);
    }
  }

  // Scan/photograph sheet music → recognise → store as a song. The recognition
  // model (~24 MB) downloads on first use, consent-gated.
  Future<void> _importOmr({required bool camera}) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      Uint8List bytes;
      String name;
      if (camera) {
        final x = await ImagePicker().pickImage(source: ImageSource.camera);
        if (x == null || !mounted) return;
        bytes = await x.readAsBytes();
        name = 'Scan';
      } else {
        final f = await openFile(
          acceptedTypeGroups: [
            const XTypeGroup(
              label: 'Image',
              extensions: ['png', 'jpg', 'jpeg'],
            ),
          ],
        );
        if (f == null || !mounted) return;
        bytes = await f.readAsBytes();
        name = f.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      }
      if (!mounted) return;

      // First-use consent for the model download.
      if (await omrModelPath() == null) {
        if (!mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(l10n.importScanModelTitle),
            content: Text(l10n.importScanModelBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(l10n.importScanCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(l10n.importScanModelDownload),
              ),
            ],
          ),
        );
        if (ok != true || !mounted) return;
      }

      setState(() {
        _omrBusy = true;
        _omrStatus = null;
      });
      final score = await recognizeSheetMusic(
        bytes,
        download: true,
        onStatus: (m) {
          if (mounted) setState(() => _omrStatus = m);
        },
      );
      if (!mounted) return;
      setState(() {
        _omrBusy = false;
        _omrStatus = null;
      });
      if (score == null) {
        _fail(l10n.importScanFailed);
        return;
      }
      final typed = _title.text.trim();
      context.read<UserSongsService>().addSong(
            ImportedSong(
              id: _newId(),
              title: typed.isNotEmpty ? typed : name,
              musicXml: multiPartToMusicXml(MultiPartScore(<Score>[score])),
            ),
          );
      _done();
    } catch (e) {
      if (mounted) {
        setState(() {
          _omrBusy = false;
          _omrStatus = null;
        });
        _fail(e);
      }
    }
  }

  String _abcTitle(String abc) {
    final typed = _title.text.trim();
    if (typed.isNotEmpty) return typed;
    final t = RegExp(r'^T:\s*(.+)$', multiLine: true)
        .firstMatch(abc)
        ?.group(1)
        ?.trim();
    return (t != null && t.isNotEmpty) ? t : 'ABC';
  }

  // ABC is a compact text notation used by huge public-domain tune libraries.
  // Parse ALL its voices (V: → separate staves) to a MultiPartScore, then store
  // it as multi-part MusicXML like the file-import path — so a multi-voice ABC
  // tune keeps every voice instead of flattening to the first.
  void _importAbc() {
    try {
      final abc = _text.text.trim();
      final mp = multiPartScoreFromAbc(abc); // parse + validate (all voices)
      final title = _abcTitle(abc);
      context.read<UserSongsService>().addSong(
            ImportedSong(
              id: _newId(),
              title: title,
              musicXml: multiPartToMusicXml(mp),
            ),
          );
      _done();
    } catch (e) {
      _fail(e);
    }
  }

  void _importChordPro() {
    try {
      final source = _text.text;
      final sheet = parseChordPro(source); // validates
      final title =
          _title.text.trim().isNotEmpty ? _title.text.trim() : sheet.title;
      context.read<UserSongsService>().addSheet(
            ImportedChordSheet(id: _newId(), title: title, source: source),
          );
      _done();
    } catch (e) {
      _fail(e);
    }
  }

  /// Picks a `.jams` file (JSON Annotated Music Specification — the MIR chord/
  /// melody/beat/key dataset format). A `note_midi` melody imports as a song
  /// (via the MIDI path — tempo drives the rhythm, beats the meter, key_mode the
  /// title); otherwise a chord annotation imports as a chord sheet.
  Future<void> _importJamsFile() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'JAMS', extensions: ['jams', 'json']),
        ],
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final json = utf8.decode(bytes);
      final base = file.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      final typed = _title.text.trim();

      if (jamsMelodyNotes(json).isNotEmpty) {
        // Melody → a notated song, reusing the MIDI importer.
        final mp = multiTrackMidiToMultiPart(jamsToMidi(json));
        final name = typed.isNotEmpty ? typed : (jamsTitle(json) ?? base);
        final key = jamsKey(json);
        context.read<UserSongsService>().addSong(
              ImportedSong(
                id: _newId(),
                title: key != null ? '$name — $key' : name,
                musicXml: multiPartToMusicXml(mp),
              ),
            );
      } else {
        // Chords → a chord sheet (throws if neither annotation is present).
        final source = jamsToChordPro(json);
        final sheet = parseChordPro(source);
        context.read<UserSongsService>().addSheet(
              ImportedChordSheet(
                id: _newId(),
                title: typed.isNotEmpty
                    ? typed
                    : (sheet.title == 'JAMS chords' ? base : sheet.title),
                source: source,
              ),
            );
      }
      _done();
    } catch (e) {
      if (mounted) _fail(e);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.importTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.public),
            tooltip: l10n.libraryTitle,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                // Allow CC-BY / CC-BY-SA imports: attribution travels with the
                // song (ImportedSong.attribution) and shows in "Sources &
                // credits", so the ~8.8k CC-BY scores (NIFC/PDMX) are usable too.
                builder: (_) => const LibraryBrowserScreen(
                  policy: LicensePolicy(allowAttributionLicenses: true),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _title,
                decoration: InputDecoration(
                  labelText: l10n.importTitleField,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TextField(
                  controller: _text,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                  decoration: InputDecoration(
                    hintText: l10n.importHint,
                    border: const OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _importMusicXml,
                    icon: const Icon(Icons.library_music),
                    label: Text(l10n.importAsMusicXml),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _importAbc,
                    icon: const Icon(Icons.abc),
                    label: Text(l10n.importAsAbc),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _importChordPro,
                    icon: const Icon(Icons.tag),
                    label: Text(l10n.importAsChordPro),
                  ),
                  OutlinedButton.icon(
                    onPressed: _importMusicFile,
                    icon: const Icon(Icons.file_open),
                    label: Text(l10n.importMusicFile),
                  ),
                  OutlinedButton.icon(
                    onPressed: _importJamsFile,
                    icon: const Icon(Icons.data_object),
                    label: Text(l10n.importJamsFile),
                  ),
                  // OMR: photograph/scan sheet music → a song. Native only (the
                  // recogniser needs the ggml engine), so hidden on web / where
                  // the library isn't present.
                  if (omrAvailable()) ...[
                    OutlinedButton.icon(
                      onPressed:
                          _omrBusy ? null : () => _importOmr(camera: true),
                      icon: const Icon(Icons.photo_camera),
                      label: Text(l10n.importScanPhoto),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          _omrBusy ? null : () => _importOmr(camera: false),
                      icon: const Icon(Icons.image_search),
                      label: Text(l10n.importScanImage),
                    ),
                  ],
                ],
              ),
              if (_omrBusy) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
                if (_omrStatus != null) ...[
                  const SizedBox(height: 8),
                  Center(child: Text(_omrStatus!)),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
