// lib/shared/widgets/performance_pads.dart
//
// WS-X5 (3b) — playing notes with your fingers, on a screen.
//
// WHY THIS IS NOT ONE OF THE TWO KEYBOARDS WE ALREADY HAVE.
// `piano_keyboard.dart` and `scrollable_piano.dart` both emit
// `onKeyTap(int midi)` — a TAP. That is exactly right for what they do: in a
// quiz, a tap is an ANSWER, and an answer has no duration. A performance input
// is a different thing: a press and a release are two separate events, and the
// gap between them is the note. A tap-only widget can never produce a HELD
// note, which means `HeldNotes` — the whole reason the WS-X5 seam exists —
// would have nothing to track, and the standard's most notorious corner (a
// note-on with velocity 0 IS a note-off) would never even arise.
//
// So this sends REAL MIDI into a `ManualMidiInput`, and anything written
// against `MidiInput` cannot tell it from hardware. That is the point of the
// seam: when the platform binding (3a) lands, nothing downstream changes.
//
// VELOCITY FROM POSITION. A screen has no idea how hard you pressed, so the
// convention every pad controller uses is borrowed instead: lower on the pad is
// harder. It is learnable in seconds, it is reversible by the caller, and it
// beats sending a constant 100 and pretending the instrument is dynamic.
//
// EVERY PRESS IS RELEASED. `onPointerUp` is not enough on its own: a finger
// that slides off the widget, or a gesture the framework cancels, sends
// `onPointerCancel` instead — and a note whose release never arrives is a note
// that sounds forever. Both are handled, and `releaseAll` exists for the case
// where the widget itself goes away mid-press.

import 'package:comet_beat/core/midi/midi_input.dart';
import 'package:flutter/material.dart';

/// One playable cell: what it sends, and what it says.
class PerformancePad {
  const PerformancePad({
    required this.note,
    this.label = '',
    this.channel = 0,
    this.accent = false,
  });

  /// MIDI note number.
  final int note;

  /// What is drawn on it. Empty draws nothing — a drum board often wants icons
  /// or nothing at all rather than a number.
  final String label;

  /// 0–15. Drums conventionally sit on channel 10 (index 9), and keeping the
  /// channel per PAD rather than per BOARD is what lets one board mix a kit
  /// with a bass line without two widgets.
  final int channel;

  /// Drawn stronger — the black keys of a keyboard, the accent pads of a kit.
  final bool accent;
}

/// A grid of pads that sends note-on / note-off into [input].
///
/// Deliberately dumb about music: it is given [pads] and sends what they say.
/// Laying out a scale, a kit or a chromatic octave is the caller's job, because
/// each of those is a different product decision and none of them belongs in a
/// widget that only knows how to be pressed.
class PerformancePads extends StatefulWidget {
  const PerformancePads({
    required this.pads,
    required this.input,
    super.key,
    this.columns = 4,
    this.minVelocity = 40,
    this.maxVelocity = 127,
    this.velocityFromPosition = true,
  });

  final List<PerformancePad> pads;

  /// Where the notes go. A `ManualMidiInput` so that consumers read it through
  /// the same `MidiInput` interface hardware will use.
  final ManualMidiInput input;

  final int columns;

  /// The softest and hardest a press can be. Equal values make every note the
  /// same velocity, which is what a caller wanting a plain trigger pad passes.
  final int minVelocity;
  final int maxVelocity;

  /// When false, every press sends [maxVelocity]. Position-based velocity is a
  /// convention, not a law, and a caller aiming at very young players may not
  /// want a note's loudness to depend on exactly where a finger landed.
  final bool velocityFromPosition;

  @override
  State<PerformancePads> createState() => PerformancePadsState();
}

class PerformancePadsState extends State<PerformancePads> {
  /// Which pointer is holding which pad, so a second finger does not release
  /// the first one's note. Keyed by pointer id, because two fingers on two pads
  /// is the ordinary case for this widget, not an edge case.
  final Map<int, int> _heldBy = {};

  @override
  void dispose() {
    // The widget is going away mid-press: send the note-offs now, or whatever
    // is playing them keeps playing them.
    releaseAll();
    super.dispose();
  }

  /// Sends note-off for everything currently held.
  void releaseAll() {
    for (final index in _heldBy.values.toList()) {
      _sendOff(index);
    }
    _heldBy.clear();
  }

  int _velocityFor(Offset local, Size size) {
    if (!widget.velocityFromPosition || size.height <= 0) {
      return widget.maxVelocity;
    }
    // Lower on the pad is harder — the convention every hardware pad uses.
    final t = (local.dy / size.height).clamp(0.0, 1.0);
    final span = widget.maxVelocity - widget.minVelocity;
    return (widget.minVelocity + span * t).round().clamp(1, 127);
  }

  void _sendOn(int index, int velocity) {
    final pad = widget.pads[index];
    widget.input.send(
      MidiMessage(
        kind: MidiMessageKind.noteOn,
        channel: pad.channel,
        data1: pad.note,
        data2: velocity,
      ),
    );
  }

  void _sendOff(int index) {
    final pad = widget.pads[index];
    // An explicit note-off rather than a note-on at velocity 0. Both are legal
    // and `HeldNotes` accepts either, but the explicit one is what a reader of
    // a log expects to see, and this end has no reason to use running status.
    widget.input.send(
      MidiMessage(
        kind: MidiMessageKind.noteOff,
        channel: pad.channel,
        data1: pad.note,
      ),
    );
  }

  void _press(int pointer, int index, int velocity) {
    // The same finger cannot press two pads; releasing the old one first keeps
    // a slide across the board from stacking notes that never stop.
    if (_heldBy[pointer] case final previous? when previous != index) {
      _sendOff(previous);
    }
    _heldBy[pointer] = index;
    _sendOn(index, velocity);
    setState(() {});
  }

  void _release(int pointer) {
    final index = _heldBy.remove(pointer);
    if (index == null) return;
    _sendOff(index);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final columns = widget.columns < 1 ? 1 : widget.columns;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: widget.pads.length,
      itemBuilder: (context, i) {
        final pad = widget.pads[i];
        final held = _heldBy.containsValue(i);
        // LayoutBuilder rather than `findRenderObject()`: inside a sliver's
        // itemBuilder the context's render object is not a RenderBox, and the
        // cast threw while DISPATCHING the pointer event — which surfaces as a
        // TypeError in the gesture system rather than anywhere near this code.
        // The constraints give the pad's size directly and cannot lie.
        return LayoutBuilder(
          builder: (context, constraints) => Listener(
            key: Key('perf-pad-${pad.channel}-${pad.note}'),
            // Listener rather than GestureDetector: this needs the raw pointer
            // lifecycle. A gesture recognizer can WIN or LOSE an arena and would
            // swallow the down/up pair the note depends on, which is how a
            // performance surface ends up with stuck notes on a scroll.
            onPointerDown: (event) => _press(
              event.pointer,
              i,
              _velocityFor(event.localPosition, constraints.biggest),
            ),
            onPointerUp: (event) => _release(event.pointer),
            // A finger that slides off, or a gesture the framework cancels,
            // never sends up — and a note without a release sounds forever.
            onPointerCancel: (event) => _release(event.pointer),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: held
                    ? scheme.primary
                    : (pad.accent
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  pad.label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: held ? scheme.onPrimary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A chromatic run of [count] pads from [startMidi], labelled with note names.
///
/// A convenience for the ordinary case, kept OUT of the widget so that the
/// widget stays dumb: a kit, a scale and a chromatic octave are three different
/// product decisions, and only one of them belongs in a helper.
List<PerformancePad> chromaticPads(int startMidi, int count) {
  const names = [
    'C',
    'C♯',
    'D',
    'D♯',
    'E',
    'F',
    'F♯',
    'G',
    'G♯',
    'A',
    'A♯',
    'B',
  ];
  return [
    for (var i = 0; i < count; i++)
      PerformancePad(
        note: startMidi + i,
        label: names[(startMidi + i) % 12],
        // The black keys, so a chromatic board still reads as a keyboard.
        accent: const {1, 3, 6, 8, 10}.contains((startMidi + i) % 12),
      ),
  ];
}
