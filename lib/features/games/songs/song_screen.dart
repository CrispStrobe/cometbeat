// lib/features/games/songs/song_screen.dart
//
// The song player: full notation with lyrics across wrapped systems
// (crisp_notation MultiSystemView), a play button, and a karaoke-style cursor —
// the sounding note highlights in sync (repaint-only per the crisp_notation
// contract). Tapping any note plays it.

import 'dart:async';

import 'package:crisp_notation/crisp_notation.dart'
    show MultiSystemView, NoteElement, Score;
import 'package:flutter/material.dart';
import 'package:klang_universum/core/audio/play_along.dart' show PlayAlongChart;
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/features/games/playalong/play_along_screen.dart';
import 'package:klang_universum/features/games/songs/chord_sheet_screen.dart';
import 'package:klang_universum/features/games/songs/import/chordpro.dart';
import 'package:klang_universum/features/games/songs/import_screen.dart';
import 'package:klang_universum/features/games/songs/song_book.dart';
import 'package:klang_universum/features/games/songs/song_play_along.dart';
import 'package:klang_universum/features/games/songs/songbook_screen.dart';
import 'package:klang_universum/features/games/songs/user_songs_service.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/score_theme.dart';
import 'package:provider/provider.dart';

class SongScreen extends StatefulWidget {
  final String title;
  final Score score;

  SongScreen({super.key, required Song song})
      : title = song.title,
        score = song.score;

  const SongScreen.fromScore({
    super.key,
    required this.title,
    required this.score,
  });

  @override
  State<SongScreen> createState() => _SongScreenState();
}

class _SongScreenState extends State<SongScreen> {
  String? _highlightedId;
  bool _playing = false;
  int _playToken = 0; // invalidates a running play loop

  late final List<(String, int, int)> _playback = playbackOf(widget.score);

  // Targets derived from the song's notation (top pitch = melody). Singing is
  // octave-agnostic (any comfortable range); playing an instrument is not.
  late final _singChart = chartFromScore(widget.score, name: widget.title);
  late final _playChart = chartFromScore(
    widget.score,
    name: widget.title,
    octaveAgnostic: false,
  );

  late final Map<String, int> _midiById = {
    for (final measure in widget.score.measures)
      for (final element in measure.elements)
        if (element is NoteElement && element.id != null)
          element.id!: element.pitches.first.midiNumber,
  };

  Future<void> _play() async {
    final token = ++_playToken;
    final audio = context.read<AudioService>();
    setState(() => _playing = true);

    // One synthesized render of the whole melody, deliberately not awaited...
    unawaited(
      audio.playSequence([
        for (final (_, midi, ms) in _playback) (midi, ms),
      ]),
    );
    // ...while the cursor walks the notation in the same rhythm. Scheduled
    // against an absolute clock, not a cumulative Future.delayed: the per-note
    // rebuild overhead was making the highlight drift behind the audio.
    final clock = Stopwatch()..start();
    var startMs = 0;
    for (final (id, _, ms) in _playback) {
      final wait = startMs - clock.elapsedMilliseconds;
      if (wait > 0) await Future.delayed(Duration(milliseconds: wait));
      if (!mounted || token != _playToken) return;
      setState(() => _highlightedId = id);
      startMs += ms;
    }
    // Hold the last note for its full duration before clearing.
    final tail = startMs - clock.elapsedMilliseconds;
    if (tail > 0) await Future.delayed(Duration(milliseconds: tail));
    if (!mounted || token != _playToken) return;
    setState(() {
      _highlightedId = null;
      _playing = false;
    });
  }

  /// The tap handler that drops [chart] into the moving-score highway, or null
  /// (disabled) while the karaoke preview runs or when the song has no melody.
  /// Stars scale to the song's length — a long song isn't a free 3★.
  VoidCallback? _launcher(
    PlayAlongChart chart, {
    required String gameId,
    required String sriPrefix,
  }) {
    if (_playing || chart.notes.isEmpty) return null;
    return () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PlayAlongScreen(
              chart: chart,
              title: widget.title,
              gameId: gameId,
              sriPrefix: sriPrefix,
              scaleStarsToLength: true,
            ),
          ),
        );
  }

  void _stop() {
    _playToken++;
    context.read<AudioService>().playMidiNote(0, ms: 1); // cuts playback
    setState(() {
      _highlightedId = null;
      _playing = false;
    });
  }

  @override
  void dispose() {
    _playToken++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: Card(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: MultiSystemView(
                      score: widget.score,
                      staffSpace: 11,
                      theme: kidsScoreTheme,
                      highlightedIds: {
                        if (_highlightedId != null) _highlightedId!,
                      },
                      onElementTap: (id) {
                        final midi = _midiById[id];
                        if (midi != null) {
                          context
                              .read<AudioService>()
                              .playMidiNote(midi, ms: 500);
                        }
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Wrap, not Row: three buttons must not overflow a narrow phone.
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _playing ? _stop : _play,
                    icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
                    label: Text(
                      _playing ? l10n.songStop : l10n.myMelodyPlay,
                    ),
                  ),
                  // Sing / play the song against the moving-score highway
                  // (mic-graded). Both are disabled while the karaoke preview
                  // plays, or when the song has no melody (all-rest edge cases).
                  OutlinedButton.icon(
                    onPressed: _launcher(
                      _singChart,
                      gameId: 'sing_along',
                      sriPrefix: 'voice.sing_along',
                    ),
                    icon: const Icon(Icons.mic_external_on),
                    label: Text(l10n.gameSingAlong),
                  ),
                  // The instrument twin: the written octave IS the target.
                  OutlinedButton.icon(
                    onPressed: _launcher(
                      _playChart,
                      gameId: 'keyboard_play_along',
                      sriPrefix: 'keyboard.play_along',
                    ),
                    icon: const Icon(Icons.moving),
                    label: Text(l10n.gamePlayAlong),
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

class SongListScreen extends StatelessWidget {
  const SongListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final userSongs = context.watch<UserSongsService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.gameSongBook),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: l10n.importTitle,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ImportScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final song in kSongs)
            Card(
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                leading: const CircleAvatar(child: Icon(Icons.music_note)),
                title: Text(song.title),
                trailing: const Icon(Icons.play_circle_outline),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SongScreen(song: song),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.songbooksTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: l10n.songbookNew,
                  onPressed: () => createSongbook(context),
                ),
              ],
            ),
          ),
          for (final book in userSongs.collections)
            Card(
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                leading: const CircleAvatar(child: Icon(Icons.library_music)),
                title: Text(book.title),
                subtitle: Text(l10n.songbookSongCount(book.songIds.length)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SongbookScreen(collectionId: book.id),
                  ),
                ),
              ),
            ),
          if (userSongs.songs.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
              child: Text(
                l10n.importedSongs,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final song in userSongs.songs)
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  leading: const CircleAvatar(child: Icon(Icons.file_download)),
                  title: Text(song.title),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        context.read<UserSongsService>().removeSong(song.id),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SongScreen.fromScore(
                        title: song.title,
                        score: song.score,
                      ),
                    ),
                  ),
                ),
              ),
          ],
          if (userSongs.sheets.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
              child: Text(
                l10n.chordSheets,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final sheet in userSongs.sheets)
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  leading: const CircleAvatar(child: Icon(Icons.tag)),
                  title: Text(sheet.title),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        context.read<UserSongsService>().removeSheet(sheet.id),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChordSheetScreen(
                        title: sheet.title,
                        sheet: parseChordPro(sheet.source),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
