// lib/features/games/composition/tracker_field_entry.dart
//
// The Advanced Tracker's keyboard-entry state machine, out of the widget.
//
// A tracker cell is typed a character at a time, FastTracker 2 style: two hex
// digits for the volume column, a command nibble then two parameter nibbles for
// the effect column, two decimal digits for the instrument column, and — in
// note-name mode — a letter, an optional sharp, then the octave digit. Each
// field remembers the digits typed so far until the cursor moves.
//
// This used to be nine loose fields on the screen's State. It holds no song and
// no widget: it turns keystrokes into column VALUES, and the screen decides
// what to write where (undo, playback sync and the cell itself stay there).

/// Accumulates the digits typed into one tracker cell's columns.
class TrackerFieldEntry {
  int _volAccum = 0;
  int _volDigits = 0;

  int _fxCmd = 0;
  int _fxParam = 0;
  int _fxDigits = 0;

  int _instAccum = 0;
  int _instDigits = 0;

  int? _pendingSemi;
  bool _pendingSharp = false;

  // --- Volume column: two hex digits, high then low, value 00–40 (0–64). ---

  /// Feeds one hex digit; returns the column value, 0–64. The first digit of
  /// a pair stands alone (so "4" reads as 4 until the second arrives).
  int typeVolume(int hex) {
    _volAccum = (_volDigits == 0 ? hex : _volAccum * 16 + hex).clamp(0, 64);
    _volDigits = (_volDigits + 1) % 2;
    return _volAccum;
  }

  void resetVolume() {
    _volAccum = 0;
    _volDigits = 0;
  }

  // --- Effect column: command nibble, then a two-nibble parameter byte. ---

  /// Feeds one hex digit and returns the effect as typed so far. The first
  /// digit of three sets the command (and clears the parameter); the next two
  /// build the parameter byte; a fourth starts a new effect.
  ({int command, int param}) typeEffect(int hex) {
    switch (_fxDigits) {
      case 0:
        _fxCmd = hex;
        _fxParam = 0;
      case 1:
        _fxParam = hex;
      default:
        _fxParam = (_fxParam * 16 + hex) & 0xFF;
    }
    _fxDigits = (_fxDigits + 1) % 3;
    return (command: _fxCmd, param: _fxParam);
  }

  void resetEffect() {
    _fxCmd = 0;
    _fxParam = 0;
    _fxDigits = 0;
  }

  // --- Instrument column: two DECIMAL digits, a 1-based pool index. ---

  /// Feeds one decimal digit; returns the instrument index, clamped to
  /// 0..[poolSize] (0 = the channel default).
  int typeInstrument(int digit, {required int poolSize}) {
    final raw = _instDigits == 0 ? digit : _instAccum * 10 + digit;
    _instAccum = raw.clamp(0, poolSize);
    _instDigits = (_instDigits + 1) % 2;
    return _instAccum;
  }

  void resetInstrument() {
    _instAccum = 0;
    _instDigits = 0;
  }

  /// Forgets the digits typed in every column — the cursor moved to a new
  /// cell. The armed note name (a separate mode) is kept.
  void resetColumns() {
    resetVolume();
    resetEffect();
    resetInstrument();
  }

  // --- Note-name entry: letter, optional sharp, octave digit. ---

  /// Whether a note letter is armed and waiting for its octave.
  bool get noteArmed => _pendingSemi != null;

  /// The armed note's pitch class 0–11 (sharp included), or null.
  int? get armedPitchClass => _pendingSemi == null
      ? null
      : (_pendingSemi! + (_pendingSharp ? 1 : 0)) % 12;

  /// Arms a note letter by its semitone above C (a new letter replaces the
  /// old one and drops its sharp).
  void armNote(int semitone) {
    _pendingSemi = semitone;
    _pendingSharp = false;
  }

  /// Sharpens the armed note. Ignored when nothing is armed.
  void sharpen() {
    if (_pendingSemi != null) _pendingSharp = true;
  }

  /// Completes the armed note with [octave] and returns its MIDI number (0–127),
  /// disarming. Null — and nothing changes — when no note is armed.
  int? commitOctave(int octave) {
    final semi = _pendingSemi;
    if (semi == null) return null;
    final midi =
        ((octave + 1) * 12 + semi + (_pendingSharp ? 1 : 0)).clamp(0, 127);
    cancelNote();
    return midi;
  }

  /// Disarms any pending note name.
  void cancelNote() {
    _pendingSemi = null;
    _pendingSharp = false;
  }
}
