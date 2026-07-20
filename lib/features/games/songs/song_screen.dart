// lib/features/games/songs/song_screen.dart
//
// The song player: full notation with lyrics across wrapped systems
// (crisp_notation MultiSystemView), a play button, and a karaoke-style cursor —
// the sounding note highlights in sync (repaint-only per the crisp_notation
// contract). Tapping any note plays it.

import 'dart:async';

import 'package:comet_beat/core/audio/daw_sources.dart' show ScoreSource;
import 'package:comet_beat/core/audio/play_along.dart' show PlayAlongChart;
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/games/composition/music_inspect.dart';
import 'package:comet_beat/features/games/composition/score_analysis_view.dart';
import 'package:comet_beat/features/games/playalong/play_along_screen.dart';
import 'package:comet_beat/features/games/songs/chord_sheet_screen.dart';
import 'package:comet_beat/features/games/songs/import/chordpro.dart';
import 'package:comet_beat/features/games/songs/import_screen.dart';
import 'package:comet_beat/features/games/songs/multi_part_song_screen.dart';
import 'package:comet_beat/features/games/songs/song_book.dart';
import 'package:comet_beat/features/games/songs/song_play_along.dart';
import 'package:comet_beat/features/games/songs/songbook_screen.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/daw/send_to_daw.dart';
import 'package:comet_beat/shared/music_io/music_export.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show
        ElementRegionController,
        MultiSystemView,
        NoteElement,
        Score,
        ScoreAnalysis,
        analyze,
        multiPartScoreFromMusicXml;
import 'package:flutter/material.dart';
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
  bool _inspect = false; // 🔍 Looking Glass: tap a note to see what it is
  late final ScoreAnalysis _analysis = analyze(widget.score);
  int _playToken = 0; // invalidates a running play loop

  // 🔍 Desktop hover-inspect: the note under the mouse while Inspect is on (a
  // looking glass you sweep over the score). Null on touch; tap opens the sheet.
  final ElementRegionController _regions = ElementRegionController();
  InspectInfo? _hoverInfo;
  Offset? _hoverAt;
  String? _hoverId;

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

  /// 🔍 Desktop hover in Inspect mode: resolve the note under the cursor and
  /// show a floating card. Re-runs the lookup only when the hovered element
  /// changes (analysis is precomputed once in [_analysis]).
  void _onScoreHover(Offset localPos) {
    if (!_inspect) {
      _clearHoverInspect();
      return;
    }
    final ids = _regions.elementIdsIn(
      Rect.fromCenter(center: localPos, width: 6, height: 6),
    );
    final id = ids.isEmpty ? null : ids.first;
    if (id == _hoverId) {
      if (id != null && _hoverAt != localPos) {
        setState(() => _hoverAt = localPos);
      }
      return;
    }
    if (id == null) {
      _clearHoverInspect();
      return;
    }
    setState(() {
      _hoverId = id;
      _hoverInfo = inspectElement(widget.score, id, _analysis);
      _hoverAt = localPos;
    });
  }

  void _clearHoverInspect() {
    if (_hoverInfo != null || _hoverId != null) {
      setState(() {
        _hoverInfo = null;
        _hoverId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: l10n.inspectMode,
            isSelected: _inspect,
            selectedIcon: const Icon(Icons.search_off),
            onPressed: () => setState(() => _inspect = !_inspect),
          ),
          IconButton(
            icon: const Icon(Icons.insights),
            tooltip: l10n.analyzeAction,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _SongAnalysisScreen(
                  title: widget.title,
                  score: widget.score,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.library_add),
            tooltip: l10n.dawSend,
            onPressed: () =>
                sendToMultitrack(context, ScoreSource.single(widget.score)),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: Card(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: MouseRegion(
                      onHover: (e) => _onScoreHover(e.localPosition),
                      onExit: (_) => _clearHoverInspect(),
                      child: Stack(
                        children: [
                          MultiSystemView(
                            score: widget.score,
                            staffSpace: 11,
                            theme: kidsScoreTheme,
                            controller: _regions,
                            highlightedIds: {
                              if (_highlightedId != null) _highlightedId!,
                            },
                            onElementTap: (id) {
                              if (_inspect) {
                                final info = inspectElement(
                                  widget.score,
                                  id,
                                  _analysis,
                                );
                                if (info != null) showInspect(context, info);
                                return;
                              }
                              final midi = _midiById[id];
                              if (midi != null) {
                                context
                                    .read<AudioService>()
                                    .playMidiNote(midi, ms: 500);
                              }
                            },
                          ),
                          if (_inspect &&
                              _hoverInfo != null &&
                              _hoverAt != null)
                            Positioned(
                              left: _hoverAt!.dx + 14,
                              top: _hoverAt!.dy + 14,
                              child: IgnorePointer(
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 260),
                                  child: Card(
                                    elevation: 4,
                                    margin: EdgeInsets.zero,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      child: inspectBody(context, _hoverInfo!),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
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

/// A filename-safe version of a song title (letters/digits/-/_; spaces → _).
String _safeName(String title) {
  final cleaned = title
      .trim()
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
  return cleaned.isEmpty ? 'song' : cleaned;
}

/// Open an imported song: a multi-part one (a transcription or ensemble) goes
/// to the stacked multi-staff view so every voice shows; a single-part one goes
/// to the karaoke [SongScreen].
void openImportedSong(BuildContext context, ImportedSong song) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => song.isMultiPart
          ? MultiPartSongScreen(title: song.title, score: song.multiPart)
          : SongScreen.fromScore(title: song.title, score: song.score),
    ),
  );
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
            child: Text(
              l10n.songbookEnsembleSongs,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final song in kEnsembleSongs)
            Card(
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                leading: const CircleAvatar(child: Icon(Icons.groups)),
                title: Text(song.title),
                subtitle: Text(l10n.ensembleVoiceCount(song.voices.length)),
                trailing: const Icon(Icons.play_circle_outline),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MultiPartSongScreen(
                      title: song.title,
                      score: song.score,
                      partNames: song.partNames,
                      quarterMs: song.quarterMs,
                    ),
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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.ios_share),
                        tooltip: l10n.musicExportTitle,
                        // The stored MusicXML keeps every voice, so export is
                        // multi-part (not just the flattened single Score).
                        onPressed: () => showMusicExportSheet(
                          context,
                          multiPart: multiPartScoreFromMusicXml(song.musicXml),
                          partNames: const [],
                          baseName: _safeName(song.title),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => context
                            .read<UserSongsService>()
                            .removeSong(song.id),
                      ),
                    ],
                  ),
                  onTap: () => openImportedSong(context, song),
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

/// Harmonic analysis of a song — the computed AnaVis over its real score.
class _SongAnalysisScreen extends StatelessWidget {
  const _SongAnalysisScreen({required this.title, required this.score});

  final String title;
  final Score score;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.analysisHarmonyHeading)),
      body: ListView(
        children: [
          ScoreAnalysisView(title: title, score: score),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
