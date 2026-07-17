// lib/features/games/songs/import_screen.dart
//
// Import: paste MusicXML (from MuseScore & friends) or ChordPro (lyrics
// with [C] chords) into the text field, or pick a simple MIDI file.
// Imported songs live in the Song Book (persisted via UserSongsService).

import 'package:comet_beat/features/games/songs/import/chordpro.dart';
import 'package:comet_beat/features/games/songs/import/midi_import.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show scoreFromAbc, scoreFromMusicXml, scoreToMusicXml;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _text = TextEditingController();
  final _title = TextEditingController();

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

  Future<void> _importMusicXmlFile() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'MusicXML', extensions: ['musicxml', 'xml']),
        ],
      );
      if (file == null || !mounted) return;
      final xml = await file.readAsString();
      if (!mounted) return;
      scoreFromMusicXml(xml); // validate before storing
      final base = file.name
          .replaceAll(RegExp(r'\.(musicxml|xml)$', caseSensitive: false), '');
      context.read<UserSongsService>().addSong(
            ImportedSong(
              id: _newId(),
              title: _musicXmlTitle(xml, fallback: base),
              musicXml: xml,
            ),
          );
      _done();
    } catch (e) {
      if (mounted) _fail(e);
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
  // Parse it to a Score (crisp_notation), then store it as MusicXML like the rest.
  void _importAbc() {
    try {
      final abc = _text.text.trim();
      final score = scoreFromAbc(abc); // parse + validate
      final title = _abcTitle(abc);
      context.read<UserSongsService>().addSong(
            ImportedSong(
              id: _newId(),
              title: title,
              musicXml: scoreToMusicXml(score, partName: title),
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

  Future<void> _importMidi() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'MIDI', extensions: ['mid', 'midi']),
        ],
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final score = scoreFromMidi(bytes); // validates + quantizes
      final title = _title.text.trim().isNotEmpty
          ? _title.text.trim()
          : file.name.replaceAll(RegExp(r'\.(mid|midi)$'), '');
      // Persist as MusicXML so it reloads without re-parsing MIDI.
      context.read<UserSongsService>().addSong(
            ImportedSong(
              id: _newId(),
              title: title,
              musicXml: scoreToMusicXml(score, partName: title),
            ),
          );
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
      appBar: AppBar(title: Text(l10n.importTitle)),
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
                    onPressed: _importMusicXmlFile,
                    icon: const Icon(Icons.file_open),
                    label: Text(l10n.importMusicXmlFile),
                  ),
                  OutlinedButton.icon(
                    onPressed: _importMidi,
                    icon: const Icon(Icons.piano),
                    label: Text(l10n.importMidiFile),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
