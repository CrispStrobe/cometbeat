// lib/shared/widgets/guitar_fretboard.dart
//
// A tappable guitar fretboard: six string rows (string 1 / high E on top) and
// frets 0..maxFret. Each cell reports the MIDI note it plays; the caller
// decides what a tap means and what it sounds like — the same contract as
// PianoKeyboard.

import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart' show Tuning;
import 'package:flutter/material.dart';

class GuitarFretboard extends StatelessWidget {
  final Tuning? tuning;
  final int maxFret;
  final void Function(int midi)? onTap;

  /// Optional per-cell highlight, keyed by MIDI number.
  final Map<int, Color> highlights;

  const GuitarFretboard({
    super.key,
    this.tuning,
    this.maxFret = 5,
    this.onTap,
    this.highlights = const {},
  });

  // Position-marker frets (single dot) in first position.
  static const _dotFrets = {3, 5};

  @override
  Widget build(BuildContext context) {
    final tuning = this.tuning ?? Tuning.standardGuitar;
    final scheme = Theme.of(context).colorScheme;
    const woodLight = Color(0xFF8D6E63);
    const woodOpen = Color(0xFF6D4C41);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var s = 0; s < tuning.stringCount; s++)
          Row(
            children: [
              for (var fret = 0; fret <= maxFret; fret++)
                Expanded(
                  // Announced by POSITION, never by note name: in the fretboard
                  // quizzes the name is the answer.
                  child: Semantics(
                    button: true,
                    enabled: onTap != null,
                    selected: highlights.containsKey(
                      tuning.strings[s].midiNumber + fret,
                    ),
                    label: AppLocalizations.of(context)
                            ?.a11yFretCell(s + 1, fret) ??
                        '',
                    child: GestureDetector(
                      onTap: onTap == null
                          ? null
                          : () => onTap!(tuning.strings[s].midiNumber + fret),
                      child: Container(
                        height: 30,
                        margin: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color:
                              highlights[tuning.strings[s].midiNumber + fret] ??
                                  (fret == 0 ? woodOpen : woodLight),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.black26),
                        ),
                        alignment: Alignment.center,
                        child: fret != 0 &&
                                _dotFrets.contains(fret) &&
                                s == tuning.stringCount ~/ 2
                            ? const Icon(
                                Icons.circle,
                                size: 8,
                                color: Colors.white70,
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 2),
        // Fret-number strip (each cell already announces its fret).
        ExcludeSemantics(
          child: Row(
            children: [
              for (var fret = 0; fret <= maxFret; fret++)
                Expanded(
                  child: Text(
                    '$fret',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
