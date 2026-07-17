// lib/shared/widgets/piano_keyboard.dart
//
// A tappable piano keyboard, drawn with plain widgets: a row of white keys
// with the black keys overlaid. Reusable across the keyboard games — the
// games decide what a tap means and what sound it makes.

import 'package:comet_beat/features/games/note_reading/note_names.dart';
import 'package:crisp_notation/crisp_notation.dart' show Step;
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;

class PianoKeyboard extends StatelessWidget {
  /// MIDI number of the leftmost key; must be a C (e.g. 60 = C4).
  final int startMidi;

  /// Number of white keys (12 = an octave and a fifth).
  final int whiteKeyCount;

  final void Function(int midi)? onKeyTap;

  /// Per-key highlight fills, by MIDI number.
  final Map<int, Color> keyColors;

  /// Letter labels on the white keys (localized; German B = H).
  final bool showLabels;

  /// Append the octave number to each label (e.g. C4), as a small superscript,
  /// so keys across several octaves are unambiguous.
  final bool showOctaveNumbers;

  const PianoKeyboard({
    super.key,
    this.startMidi = 60,
    this.whiteKeyCount = 12,
    this.onKeyTap,
    this.keyColors = const {},
    this.showLabels = false,
    this.showOctaveNumbers = false,
  }) : assert(startMidi % 12 == 0, 'startMidi must be a C');

  static const _whiteOffsets = [0, 2, 4, 5, 7, 9, 11];
  static const _whiteSteps = [
    Step.c,
    Step.d,
    Step.e,
    Step.f,
    Step.g,
    Step.a,
    Step.b,
  ];

  /// MIDI number of the i-th white key.
  int whiteMidi(int i) => startMidi + 12 * (i ~/ 7) + _whiteOffsets[i % 7];

  /// Whether a black key sits between white keys [i] and i+1.
  bool hasBlackAfter(int i) => const {0, 1, 3, 4, 5}.contains(i % 7);

  /// The label on white key [i]: its note name, plus a small octave superscript
  /// when [showOctaveNumbers] is set.
  Widget _label(BuildContext context, int i) {
    final base = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: Colors.black54,
        );
    final name = noteNameFor(context, _whiteSteps[i % 7]);
    if (!showOctaveNumbers) return Text(name, style: base);
    final octave = whiteMidi(i) ~/ 12 - 1;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: name, style: base),
          TextSpan(
            text: '$octave',
            style: base?.copyWith(
              fontSize: (base.fontSize ?? 16) * 0.6,
              fontFeatures: const [FontFeature.superscripts()],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final keyWidth = constraints.maxWidth / whiteKeyCount;
        final blackWidth = keyWidth * 0.62;
        final height = constraints.maxHeight;

        return Stack(
          children: [
            Row(
              children: [
                for (var i = 0; i < whiteKeyCount; i++)
                  Expanded(
                    child: GestureDetector(
                      onTap: onKeyTap == null
                          ? null
                          : () => onKeyTap!(whiteMidi(i)),
                      child: Container(
                        decoration: BoxDecoration(
                          color: keyColors[whiteMidi(i)] ?? Colors.white,
                          border: Border.all(color: Colors.black87),
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(6),
                          ),
                        ),
                        alignment: Alignment.bottomCenter,
                        padding: const EdgeInsets.only(bottom: 8),
                        child: showLabels ? _label(context, i) : null,
                      ),
                    ),
                  ),
              ],
            ),
            for (var i = 0; i < whiteKeyCount - 1; i++)
              if (hasBlackAfter(i))
                Positioned(
                  left: (i + 1) * keyWidth - blackWidth / 2,
                  top: 0,
                  width: blackWidth,
                  height: height * 0.58,
                  child: GestureDetector(
                    onTap: onKeyTap == null
                        ? null
                        : () => onKeyTap!(whiteMidi(i) + 1),
                    child: Container(
                      decoration: BoxDecoration(
                        color: keyColors[whiteMidi(i) + 1] ?? Colors.black87,
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}
