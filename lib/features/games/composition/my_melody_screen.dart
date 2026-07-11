// lib/features/games/composition/my_melody_screen.dart
//
// "Meine Melodie" — the composing sandbox: tap the staff to write notes,
// hear each one as you place it, then play your melody back. No score, no
// stars, no wrong answers — free creation is the point (and the child is
// reading and writing real notation the whole time).

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/features/games/songs/user_songs_service.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:partitura/partitura.dart'
    show
        Clef,
        DurationBase,
        InteractiveStaff,
        Measure,
        NoteDuration,
        NoteElement,
        PartituraTheme,
        RestElement,
        Score,
        StaffTarget,
        scoreToMusicXml;
import 'package:provider/provider.dart';

class MyMelodyScreen extends StatefulWidget {
  const MyMelodyScreen({super.key});

  static const maxNotes = 12;

  @override
  State<MyMelodyScreen> createState() => _MyMelodyScreenState();
}

class _MyMelodyScreenState extends State<MyMelodyScreen> {
  final List<NoteElement> _notes = [];
  var _nextId = 0;

  Score get _score => Score(
        clef: Clef.treble,
        measures: [
          Measure(List.of(_notes)),
          // Whole-rest measure keeps the tappable staff wide.
          if (_notes.length < 6)
            const Measure([RestElement(NoteDuration(DurationBase.whole))]),
        ],
      );

  void _onStaffTap(StaffTarget target) {
    if (_notes.length >= MyMelodyScreen.maxNotes) return;
    final pitch = target.pitchFor(Clef.treble);
    context.read<AudioService>().playMidiNote(pitch.midiNumber, ms: 400);
    setState(() {
      _notes.add(
        NoteElement.note(
          pitch,
          const NoteDuration(DurationBase.quarter),
          id: 'm${_nextId++}',
        ),
      );
    });
  }

  void _play() {
    if (_notes.isEmpty) return;
    context.read<AudioService>().playSequence([
      for (final note in _notes) (note.pitches.first.midiNumber, 400),
    ]);
  }

  /// A clean 4/4-barred score for export, so it opens tidily in MuseScore &
  /// co. (The on-screen [_score] keeps everything in one wide measure.)
  Score _exportScore() {
    const perMeasure = 4; // quarter notes per 4/4 measure
    final measures = <Measure>[
      for (var i = 0; i < _notes.length; i += perMeasure)
        Measure(_notes.sublist(i, min(i + perMeasure, _notes.length))),
    ];
    return Score(clef: Clef.treble, measures: measures);
  }

  Future<void> _saveToSongBook() async {
    if (_notes.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final songs = context.read<UserSongsService>();

    final controller = TextEditingController(text: l10n.myMelodyDefaultName);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.myMelodySaveTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(l10n.myMelodySave),
          ),
        ],
      ),
    );
    if (title == null) return; // cancelled

    final name = title.trim().isEmpty ? l10n.myMelodyDefaultName : title.trim();
    songs.addSong(
      ImportedSong(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: name,
        musicXml: scoreToMusicXml(_exportScore()),
      ),
    );
    messenger.showSnackBar(SnackBar(content: Text(l10n.myMelodySaved)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final full = _notes.length >= MyMelodyScreen.maxNotes;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gameMyMelody)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(
                full ? l10n.myMelodyFull : l10n.myMelodyPrompt,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Card(
                  child: Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: InteractiveStaff(
                        score: _score,
                        theme: PartituraTheme.kids,
                        staffSpace: 14,
                        onStaffTap: _onStaffTap,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _notes.isEmpty ? null : _play,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(l10n.myMelodyPlay),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _notes.isEmpty ? null : _saveToSongBook,
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: Text(l10n.myMelodySave),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _notes.isEmpty
                        ? null
                        : () => setState(_notes.removeLast),
                    icon: const Icon(Icons.undo),
                    label: Text(l10n.myMelodyUndo),
                  ),
                  TextButton.icon(
                    onPressed:
                        _notes.isEmpty ? null : () => setState(_notes.clear),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l10n.myMelodyClear),
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
