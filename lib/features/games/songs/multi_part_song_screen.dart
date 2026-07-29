// lib/features/games/songs/multi_part_song_screen.dart
//
// Displays a multi-part piece — every part on its own staff (stacked) — and
// plays them together via AudioService.playMixedTimedChords. Used for the
// built-in ensemble songs AND for imported/transcribed multi-part songs (which
// the single-voice SongScreen would otherwise flatten to their first part).
// Read-only: SongScreen stays the karaoke/play-along/analysis surface. The one
// thing it launches is the Note Highway, because a multi-part piece is exactly
// what `highwayChartFromParts` is for — a colour per part, all falling at once,
// which no other view here shows.

import 'package:comet_beat/core/games/highway/highway_chart.dart'
    show HighwayChart, highwayChartFromParts;
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/games/highway/note_highway_screen.dart';
import 'package:comet_beat/features/games/songs/song_book.dart'
    show ensembleVoicePlayback;
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show MultiPartScore, MultiSystemView;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class MultiPartSongScreen extends StatefulWidget {
  const MultiPartSongScreen({
    super.key,
    required this.title,
    required this.score,
    this.partNames = const [],
    this.quarterMs = 500,
  });

  final String title;
  final MultiPartScore score;

  /// Optional per-part labels; falls back to the part's instrument name, then
  /// its 1-based index.
  final List<String> partNames;
  final int quarterMs;

  @override
  State<MultiPartSongScreen> createState() => _MultiPartSongScreenState();
}

class _MultiPartSongScreenState extends State<MultiPartSongScreen> {
  bool _playing = false;
  int _token = 0;

  /// Every part as falling blocks, one voice (and so one colour) per part.
  late final HighwayChart _highwayChart = highwayChartFromParts(
    widget.score.parts,
    name: widget.title,
    bpmOverride: 60000 / widget.quarterMs,
  );

  Future<void> _play() async {
    final audio = context.read<AudioService>();
    final token = ++_token;
    setState(() => _playing = true);
    // One part per staff, rest-aware so staggered canon entries line up.
    final parts = [
      for (final part in widget.score.parts)
        ensembleVoicePlayback(part, quarterMs: widget.quarterMs),
    ];
    await audio.playMixedTimedChords(parts);
    if (!mounted || token != _token) return;
    setState(() => _playing = false);
  }

  void _stop() {
    _token++;
    context.read<AudioService>().stop();
    setState(() => _playing = false);
  }

  String _label(int i) {
    if (i < widget.partNames.length && widget.partNames[i].isNotEmpty) {
      return widget.partNames[i];
    }
    return widget.score.parts[i].metadata.instrument ?? '${i + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final parts = widget.score.parts;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.ensembleVoiceCount(parts.length),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _playing ? null : _play,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.myMelodyPlay),
                ),
                if (_playing)
                  OutlinedButton.icon(
                    onPressed: _stop,
                    icon: const Icon(Icons.stop),
                    label: Text(l10n.songStop),
                  ),
                OutlinedButton.icon(
                  onPressed: _playing || _highwayChart.isEmpty
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => NoteHighwayScreen(
                                chart: _highwayChart,
                                title: widget.title,
                                gameId: 'note_highway_piano',
                              ),
                            ),
                          ),
                  icon: const Icon(Icons.piano),
                  label: Text(l10n.gameNoteHighway),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < parts.length; i++) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(
                  _label(i),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: MultiSystemView(
                    score: parts[i],
                    staffSpace: 11,
                    theme: kidsScoreTheme,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
