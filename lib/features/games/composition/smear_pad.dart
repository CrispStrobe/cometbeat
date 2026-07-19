// lib/features/games/composition/smear_pad.dart
//
// Loop Mixer §F-1: a scale-locked "smear" solo pad. Dragging a finger left↔right
// plays only in-key pentatonic notes over the running groove, so a child can
// improvise a lead and never hit a wrong note. The pitch mapping is a pure
// function (unit-tested); the widget just turns drag positions into notes.

import 'package:flutter/material.dart';

/// C major-pentatonic scale degrees (semitones above the root).
const _pentatonic = [0, 2, 4, 7, 9];

/// Maps a horizontal position [x] (0 = left … 1 = right) to a pentatonic MIDI
/// note spanning [octaves] octaves from [baseMidi], transposed into the current
/// key/scale ([key] 0–11; [minor] borrows the relative-major set, +3). The
/// mapping is monotonic non-decreasing and only ever returns in-scale notes, so
/// dragging sweeps up/down the scale without a wrong note.
int smearMidi(
  double x, {
  int key = 0,
  bool minor = false,
  int octaves = 2,
  int baseMidi = 60,
}) {
  final steps = _pentatonic.length * octaves;
  final idx = (x.clamp(0.0, 1.0) * (steps - 1)).round();
  final octave = idx ~/ _pentatonic.length;
  final degree = _pentatonic[idx % _pentatonic.length];
  final transpose = key + (minor ? 3 : 0);
  return baseMidi + octave * 12 + degree + transpose;
}

/// A touch surface that fires [onNote] with an in-key MIDI note as a finger
/// slides across it (a new note only when the mapped pitch actually changes, so
/// a slow drag doesn't spam repeats). [keyRoot]/[minor] set the scale.
class SmearPad extends StatefulWidget {
  const SmearPad({
    required this.onNote,
    this.keyRoot = 0,
    this.minor = false,
    super.key,
  });

  final ValueChanged<int> onNote;
  final int keyRoot;
  final bool minor;

  @override
  State<SmearPad> createState() => _SmearPadState();
}

class _SmearPadState extends State<SmearPad> {
  int? _last;

  void _emit(Offset local, Size size) {
    if (size.width <= 0) return;
    final midi = smearMidi(
      local.dx / size.width,
      key: widget.keyRoot,
      minor: widget.minor,
    );
    if (midi != _last) {
      _last = midi;
      widget.onNote(midi);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onPanStart: (d) => _emit(d.localPosition, size),
          onPanUpdate: (d) => _emit(d.localPosition, size),
          onPanEnd: (_) => _last = null,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  scheme.primaryContainer,
                  scheme.tertiaryContainer,
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.gesture,
              color: scheme.onPrimaryContainer.withValues(alpha: 0.5),
            ),
          ),
        );
      },
    );
  }
}
