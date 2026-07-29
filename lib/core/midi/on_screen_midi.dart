// WS-X5 step 2 — an on-screen keyboard that speaks MIDI.
//
// The seam (`midi_input.dart`) has no hardware behind it and, until a platform
// binding is chosen, will not have any. That does not make it useless: a
// keyboard on the glass is a real input, it is the ONLY input on web, and it is
// what most people testing a record path will actually use. Feeding it through
// the same `MidiInput` contract means a surface written against MIDI works
// today and does not change when hardware arrives.
//
// ⚠️ The interesting problem here is the NOTE-OFF, and it is the same bug the
// seam exists to prevent, reintroduced one layer up. A tap is a discrete event
// with no release: bridge `onKeyTap` straight to a note-on and every key you
// touch sounds forever. So a tap has to become a note-on AND a note-off, and
// the gap between them is a decision, not an accident.

import 'dart:async';

import 'package:comet_beat/core/midi/midi_input.dart';

/// How long a tapped note is held before its note-off.
///
/// A tap carries no duration, so one has to be invented. Short enough that
/// repeated taps do not pile up into a held chord; long enough that a synth
/// with an attack actually speaks. This is a stated guess, not a measured
/// value — if it ever needs tuning, tune it here rather than at each caller.
const Duration kTappedNoteLength = Duration(milliseconds: 220);

/// Turns taps and presses on a UI into MIDI, through the shared seam.
///
/// Two shapes of gesture are supported because two exist in this app:
///   * [tap] — a discrete hit (the shared `ScrollablePiano`'s `onKeyTap`, a
///     drum pad). Auto-releases after [noteLength].
///   * [press] / [release] — a real hold, where the UI knows both ends.
///
/// Anything holding one of these must [dispose] it: a pending auto-release is
/// a live timer, and a screen torn down mid-note would otherwise fire into a
/// closed stream.
class OnScreenMidi {
  OnScreenMidi({
    ManualMidiInput? input,
    this.channel = 0,
    this.velocity = 100,
    this.noteLength = kTappedNoteLength,
  }) : input = input ?? ManualMidiInput(devices: const ['On-screen keyboard']);

  /// The input a surface listens to. Owned here unless one was passed in, so
  /// several UIs (a keyboard and a pad row) can share one stream.
  final ManualMidiInput input;

  final int channel;
  final int velocity;
  final Duration noteLength;

  /// Every note currently sounding → its auto-release timer, or null when it
  /// is held for real.
  ///
  /// ⚠️ One map, not two. A first version tracked only the TAPPED notes, so a
  /// pressed key was sounding and untracked — and `releaseAll` could not
  /// release what it did not know about, which is the stuck-note bug this whole
  /// class exists to prevent, for exactly the gesture most likely to be
  /// interrupted.
  final Map<int, Timer?> _sounding = {};
  bool _disposed = false;

  /// A discrete hit: note-on now, note-off after [noteLength].
  void tap(int note, {int? velocity}) {
    if (_disposed) return;
    // Re-tapping a note that is still ringing restarts it rather than stacking
    // a second timer — otherwise the first timer's note-off cuts the second
    // tap short, which sounds like a dropped note.
    _sounding.remove(note)?.cancel();
    _sendOn(note, velocity ?? this.velocity);
    _sounding[note] = Timer(noteLength, () {
      _sounding.remove(note);
      _sendOff(note);
    });
  }

  /// A held press — the UI will tell us when it ends.
  void press(int note, {int? velocity}) {
    if (_disposed) return;
    // Cancel any auto-release: this note is now held for real, and letting a
    // stale timer fire would release a key the user is still holding.
    _sounding.remove(note)?.cancel();
    _sendOn(note, velocity ?? this.velocity);
    // Tracked with a null timer, so releaseAll can still find it.
    _sounding[note] = null;
  }

  /// The end of a [press]. Harmless if nothing was held — a UI that sends an
  /// extra release on cancel should not have to check.
  void release(int note) {
    if (_disposed) return;
    _sounding.remove(note)?.cancel();
    _sendOff(note);
  }

  /// Release everything immediately.
  ///
  /// What a screen calls when it loses focus or is backgrounded: the pointer-up
  /// for anything held will never arrive, so without this those notes are held
  /// forever — the same reason `HeldNotes.clear()` exists on the other side.
  void releaseAll() {
    for (final entry in _sounding.entries.toList()) {
      entry.value?.cancel();
      _sendOff(entry.key);
    }
    _sounding.clear();
  }

  void _sendOn(int note, int velocity) => input.send(
        MidiMessage(
          kind: MidiMessageKind.noteOn,
          channel: channel,
          data1: note,
          // Clamped rather than asserted: a velocity from a UI gesture is
          // computed (from pressure, or a slider), and a screen should not be
          // able to crash the input by being off by one.
          data2: velocity.clamp(1, 127),
        ),
      );

  void _sendOff(int note) => input.send(
        MidiMessage(
          kind: MidiMessageKind.noteOff,
          channel: channel,
          data1: note,
        ),
      );

  /// True while [note] is sounding — whether from a tap that has not expired
  /// or a press that has not been released.
  bool isRinging(int note) => _sounding.containsKey(note);

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // Release before closing, so nothing is left hanging on a surface that is
    // still listening — then drop the timers.
    releaseAll();
    await input.dispose();
  }
}
