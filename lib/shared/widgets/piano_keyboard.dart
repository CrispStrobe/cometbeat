// lib/shared/widgets/piano_keyboard.dart
//
// A tappable piano keyboard, drawn with plain widgets: a row of white keys
// with the black keys overlaid. Reusable across the keyboard games — the
// games decide what a tap means and what sound it makes.

import 'package:comet_beat/core/note_naming.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/features/games/note_reading/note_names.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart' show Step;
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

class PianoKeyboard extends StatelessWidget {
  /// MIDI number of the leftmost key; must be a C (e.g. 60 = C4).
  final int startMidi;

  /// Number of white keys (12 = an octave and a fifth).
  final int whiteKeyCount;

  final void Function(int midi)? onKeyTap;

  /// Per-key highlight fills, by MIDI number.
  final Map<int, Color> keyColors;

  /// Optional small hint drawn on a key (by MIDI number) — e.g. the computer
  /// keyboard letter that plays it in the Tracker. Empty = none.
  final Map<int, String> keyHints;

  /// Letter labels on the white keys (localized; German B = H).
  final bool showLabels;

  /// Append the octave number to each label (e.g. C4), as a small superscript,
  /// so keys across several octaves are unambiguous.
  final bool showOctaveNumbers;

  /// Whether a screen reader announces each key by its note name ("C4").
  /// Turn it OFF where the name is the answer (a "name this key" quiz): the
  /// keys are then announced by position ("Piano key 3") instead.
  final bool semanticNames;

  const PianoKeyboard({
    super.key,
    this.startMidi = 60,
    this.whiteKeyCount = 12,
    this.onKeyTap,
    this.keyColors = const {},
    this.keyHints = const {},
    this.showLabels = false,
    this.showOctaveNumbers = false,
    this.semanticNames = true,
  }) : assert(startMidi % 12 == 0, 'startMidi must be a C');

  /// A small hint caption (the computer-key letter) drawn on a key.
  static Widget _hintChip(String text, Color color) => Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
          height: 1,
        ),
      );

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

  /// One key, as assistive technology sees it: a button with a name, marked
  /// selected while a game highlights it. Without this the keyboard is a row
  /// of anonymous boxes — a screen reader finds nothing to press.
  Widget _key(BuildContext context, int midi, Widget child) {
    final l10n = AppLocalizations.of(context);
    final String label;
    if (l10n == null) {
      label = '';
    } else if (semanticNames) {
      label = spelledMidiNameWith(
        l10n,
        context.watch<SettingsService?>()?.noteNaming ?? NoteNaming.auto,
        midi,
      );
    } else {
      label = l10n.a11yPianoKey(midi - startMidi + 1);
    }
    return Semantics(
      button: true,
      enabled: onKeyTap != null,
      selected: keyColors.containsKey(midi),
      label: label,
      excludeSemantics: true,
      onTap: onKeyTap == null ? null : () => onKeyTap!(midi),
      child: child,
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
                    child: _key(
                      context,
                      whiteMidi(i),
                      GestureDetector(
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
                          child: Stack(
                            children: [
                              if (keyHints[whiteMidi(i)] != null)
                                Align(
                                  alignment: Alignment.topCenter,
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: _hintChip(
                                      keyHints[whiteMidi(i)]!,
                                      Colors.black54,
                                    ),
                                  ),
                                ),
                              if (showLabels)
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _label(context, i),
                                  ),
                                ),
                            ],
                          ),
                        ),
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
                  child: _key(
                    context,
                    whiteMidi(i) + 1,
                    GestureDetector(
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
                        alignment: Alignment.topCenter,
                        padding: const EdgeInsets.only(top: 3),
                        child: keyHints[whiteMidi(i) + 1] != null
                            ? _hintChip(
                                keyHints[whiteMidi(i) + 1]!,
                                Colors.white70,
                              )
                            : null,
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
