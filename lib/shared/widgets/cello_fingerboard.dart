// lib/shared/widgets/cello_fingerboard.dart
//
// A tappable cello fingerboard for note entry: the four strings (A on top, C at
// the bottom) each showing their first-position naturals as labelled cells.
// Reports the MIDI note tapped; the caller decides what it means and sounds
// like — the same contract as PianoKeyboard.

import 'package:comet_beat/features/games/note_reading/note_names.dart';
import 'package:comet_beat/shared/midi_pitch.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;

class CelloFingerboard extends StatelessWidget {
  final void Function(int midi)? onTap;

  /// Optional per-cell highlight, keyed by MIDI number.
  final Map<int, Color> highlights;

  const CelloFingerboard({super.key, this.onTap, this.highlights = const {}});

  // Open-string MIDI + the semitone offsets of the naturals in first position,
  // high string (A) first.
  static const _strings = <(int, List<int>)>[
    (57, [0, 2, 3, 5]), // A3: A B C D
    (50, [0, 2, 3, 5]), // D3: D E F G
    (43, [0, 2, 4, 5]), // G2: G A B C
    (36, [0, 2, 4, 5]), // C2: C D E F
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (openMidi, offsets) in _strings)
          Row(
            children: [
              for (final offset in offsets)
                Expanded(
                  child: GestureDetector(
                    onTap:
                        onTap == null ? null : () => onTap!(openMidi + offset),
                    child: Container(
                      height: 34,
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: highlights[openMidi + offset] ??
                            (offset == 0
                                ? const Color(0xFF6D4C41)
                                : const Color(0xFF8D6E63)),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.black26),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        noteNameFor(
                          context,
                          pitchFromMidi(openMidi + offset).step,
                        ),
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 2),
        Text(
          'C · G · D · A',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}
