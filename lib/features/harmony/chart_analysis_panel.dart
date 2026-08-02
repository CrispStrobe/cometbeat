// lib/features/harmony/chart_analysis_panel.dart
//
// BB-X6b — showing what `chart_analysis.dart` worked out.
//
// ⚠️ It does NOT reuse `ScoreAnalysisView`, and the card's "reuse it" note
// deserves an answer rather than a silent departure. That view analyses NOTES:
// it runs `analyze(score)` over a melody. A chart has chords and no notes, and
// `chartToScore` gives it a monotone line of slashes — so feeding one in would
// analyse a single repeated pitch and say nothing true. It is the same
// structural mismatch the card's own decision 7 identified for `ChordSymbol`.
//
// What IS reused is everything that matters for consistency: the same
// `AnalysisDepth` dial, and `harmonicFunctionColor` — the shared tonic/
// subdominant/dominant colours already used by the analysis view, the Workshop
// and the Loop Mixer. A second colour scheme would be the real duplication.
library;

import 'package:comet_beat/core/harmony/chart_analysis.dart';
import 'package:comet_beat/features/games/composition/score_analysis_view.dart'
    show AnalysisDepth, harmonicFunctionColor;
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// A chart's harmony, explained at [depth].
class ChartAnalysisPanel extends StatelessWidget {
  const ChartAnalysisPanel({
    super.key,
    required this.analysis,
    this.depth = AnalysisDepth.learner,
  });

  final ChartAnalysis analysis;
  final AnalysisDepth depth;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    if (analysis.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          l10n.chartAnalysisEmpty,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.chartAnalysisKey(_keyName()),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          _chordRows(context),
          if (depth != AnalysisDepth.colours &&
              analysis.phrases.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              l10n.chartAnalysisPhrases,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            for (final phrase in analysis.phrases)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  phrase.fromBar == phrase.toBar
                      ? '${l10n.chartAnalysisBar(phrase.fromBar)} — '
                          '${phrase.label}'
                      : '${l10n.chartAnalysisBars(phrase.fromBar, phrase.toBar)}'
                          ' — ${phrase.label}',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _chordRows(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final chord in analysis.chords)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                // The function colour is the one thing every depth shows —
                // at `colours` it is the ONLY thing, which is the point of
                // that setting.
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: chord.function == null
                        ? theme.colorScheme.outlineVariant
                        : harmonicFunctionColor(chord.function!),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 84,
                  child: Text(
                    chord.symbol,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (depth != AnalysisDepth.colours)
                  SizedBox(
                    width: 72,
                    child: Text(
                      chord.numeral.symbol,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                // The soloing advice is the expert layer: useful to a player,
                // noise to a child learning what a dominant is.
                if (depth == AnalysisDepth.expert)
                  Expanded(
                    child: Text(
                      chord.scale,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _keyName() {
    final tonic = analysis.key.tonic;
    final letter = tonic.step.name.toUpperCase();
    final accidental = tonic.alter > 0
        ? '♯' * tonic.alter
        : (tonic.alter < 0 ? '♭' * -tonic.alter : '');
    return '$letter$accidental${analysis.key.isMajor ? '' : 'm'}';
  }
}
