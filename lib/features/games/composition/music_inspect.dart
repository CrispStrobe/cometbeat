// lib/features/games/composition/music_inspect.dart
//
// The "Looking Glass" inspector: given a score element (a note or chord) it
// works out what it is — the note name(s), its scale degree in the key, and, if
// it belongs to a chord, the chord name + roman numeral + harmonic function
// (tonic/subdominant/dominant) + whether it's a non-chord tone. Reuses the
// crisp_notation analysis engine (analyze()). A surface computes the analysis
// once, then calls inspectElement() on tap/hover and shows the info card.

import 'package:comet_beat/features/games/composition/score_analysis_view.dart'
    show harmonicFunctionColor;
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart' hide Key;
import 'package:flutter/material.dart' hide Step;

/// What the inspector found about one element.
class InspectInfo {
  const InspectInfo({
    required this.noteNames,
    this.degree,
    this.chordSymbol,
    this.roman,
    this.function,
    this.isNonChordTone = false,
  });

  /// The sounding note name(s), e.g. `E5` or `C4 E4 G4`.
  final String noteNames;

  /// Scale-degree phrase in the key, e.g. `the 3rd (mediant) of C major`.
  final String? degree;

  /// Chord symbol, e.g. `C` / `Am7`, or null if the note is not in a chord.
  final String? chordSymbol;

  /// Roman numeral, e.g. `I` / `V7`.
  final String? roman;

  /// The chord's harmonic function.
  final HarmonicFunction? function;

  /// Whether this note is a non-chord tone of its chord.
  final bool isNonChordTone;
}

String _pitchName(Pitch p) {
  final acc = p.alter > 0 ? '♯' * p.alter : (p.alter < 0 ? '♭' * -p.alter : '');
  return '${p.step.name.toUpperCase()}$acc${p.octave}';
}

const _degreeNames = [
  'tonic',
  'supertonic',
  'mediant',
  'subdominant',
  'dominant',
  'submediant',
  'leading tone',
];

const _ordinals = ['1st', '2nd', '3rd', '4th', '5th', '6th', '7th'];

/// Find the note element [elementId] in [score] and describe it, using [analysis]
/// (from `analyze(score)`) for the harmonic context. Returns null if not found.
InspectInfo? inspectElement(
  Score score,
  String elementId,
  ScoreAnalysis analysis,
) {
  NoteElement? el;
  for (final m in score.measures) {
    for (final voice in [m.elements, m.voice2, m.voice3, m.voice4]) {
      for (final e in voice) {
        if (e is NoteElement && e.id == elementId) el = e;
      }
    }
  }
  if (el == null || el.pitches.isEmpty) return null;

  final names = el.pitches.map(_pitchName).join(' ');

  // Scale degree of the (lowest) pitch in the key.
  final tonicStep = analysis.key.tonic.step.index;
  final low = el.pitches.reduce((a, b) => a.midiNumber <= b.midiNumber ? a : b);
  final deg = ((low.step.index - tonicStep) % 7 + 7) % 7; // 0-based
  final keyName = '${analysis.key.tonic.step.name.toUpperCase()} '
      '${analysis.key.isMajor ? 'major' : 'minor'}';
  final degree = 'the ${_ordinals[deg]} (${_degreeNames[deg]}) of $keyName';

  // The chord segment this element belongs to.
  final seg = analysis.segments
      .where((s) => s.hasChord && s.elementIds.contains(elementId))
      .firstOrNull;
  final nct = seg != null &&
      seg.nonChordTones.any((p) => p.midiNumber % 12 == low.midiNumber % 12);

  return InspectInfo(
    noteNames: names,
    degree: degree,
    chordSymbol: seg?.chord?.symbol,
    roman: seg?.roman?.symbol,
    function: seg?.function,
    isNonChordTone: nct,
  );
}

String _functionText(AppLocalizations l, HarmonicFunction f) => switch (f) {
      HarmonicFunction.tonic => l.funcTonic,
      HarmonicFunction.subdominant => l.funcSubdominant,
      HarmonicFunction.dominant => l.funcDominant,
    };

/// Show [info] as a small bottom sheet.
Future<void> showInspect(BuildContext context, InspectInfo info) {
  final l10n = AppLocalizations.of(context)!;
  final theme = Theme.of(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.search, size: 20),
                const SizedBox(width: 8),
                Text(
                  info.noteNames,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (info.degree != null)
              Text(info.degree!, style: theme.textTheme.bodyMedium),
            if (info.function != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: harmonicFunctionColor(info.function!),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${info.chordSymbol ?? ''}'
                      '${info.roman != null ? ' · ${info.roman}' : ''}'
                      ' · ${_functionText(l10n, info.function!)}',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
            if (info.isNonChordTone) ...[
              const SizedBox(height: 6),
              Text(
                l10n.analysisNonChordTones,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
