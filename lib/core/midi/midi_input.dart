// WS-X5 step 1 — what arrives from a MIDI keyboard, and what to do with it.
//
// There is no MIDI input in this app at all (`MidiDevice`: 0 hits before this).
// The full card also wants a platform binding, which means a dependency across
// macOS, iOS, Android, desktop and web with permissions on two of them — a
// decision with weight. So this is the SEAM: the message model, the input
// contract, and the held-note bookkeeping every record path needs. A binding
// drops in behind `MidiInput` later without any consumer changing.
//
// Pure Dart and Flutter-free on purpose: it is testable without a device, and
// the CLI could drive it.

import 'dart:async';

/// What a MIDI message means, reduced to what this app can act on.
///
/// Deliberately not the whole spec. System-exclusive, MTC and the rest are
/// real, and nothing here would know what to do with them — modelling them
/// would be pretending.
enum MidiMessageKind { noteOn, noteOff, controlChange, pitchBend, unknown }

/// One message from an input.
class MidiMessage {
  const MidiMessage({
    required this.kind,
    this.channel = 0,
    this.data1 = 0,
    this.data2 = 0,
  });

  final MidiMessageKind kind;

  /// 0–15. Kept because a controller often sends drums on channel 10 and
  /// anything ignoring the channel would merge two players into one.
  final int channel;

  /// Note number, controller number, or the pitch-bend LSB.
  final int data1;

  /// Velocity, controller value, or the pitch-bend MSB.
  final int data2;

  /// Note number, for note messages.
  int get note => data1;

  /// Velocity, for note messages.
  int get velocity => data2;

  /// ⚠️ **A note-on with velocity 0 IS a note-off.** This is in the standard
  /// and a great many controllers rely on it (it lets them use running status),
  /// so anything that treats note-on as "start sounding" without this check
  /// leaves notes stuck on forever. It is the single most common MIDI bug.
  bool get isNoteOff =>
      kind == MidiMessageKind.noteOff ||
      (kind == MidiMessageKind.noteOn && velocity == 0);

  bool get isNoteOn => kind == MidiMessageKind.noteOn && velocity > 0;

  /// Parse one message from raw bytes.
  ///
  /// Returns null for anything with too few bytes or a status byte this app has
  /// no use for — a caller should skip it, not guess.
  static MidiMessage? fromBytes(List<int> bytes) {
    if (bytes.isEmpty) return null;
    final status = bytes[0];
    if (status < 0x80) return null; // a data byte with no status: running
    final kindNibble = status & 0xF0;
    final channel = status & 0x0F;
    int at(int i) => i < bytes.length ? bytes[i] & 0x7F : 0;

    return switch (kindNibble) {
      0x90 => MidiMessage(
          kind: MidiMessageKind.noteOn,
          channel: channel,
          data1: at(1),
          data2: at(2),
        ),
      0x80 => MidiMessage(
          kind: MidiMessageKind.noteOff,
          channel: channel,
          data1: at(1),
          data2: at(2),
        ),
      0xB0 => MidiMessage(
          kind: MidiMessageKind.controlChange,
          channel: channel,
          data1: at(1),
          data2: at(2),
        ),
      0xE0 => MidiMessage(
          kind: MidiMessageKind.pitchBend,
          channel: channel,
          data1: at(1),
          data2: at(2),
        ),
      _ => null,
    };
  }

  /// Pitch bend as −1…+1, centre 0.
  double get bend {
    if (kind != MidiMessageKind.pitchBend) return 0;
    final raw = (data2 << 7) | data1; // 0…16383, centre 8192
    return (raw - 8192) / 8192;
  }

  @override
  String toString() => '${kind.name}(ch$channel, $data1, $data2)';
}

/// A MIDI input device, as this app needs one.
///
/// An interface rather than a class so the platform binding, a test double and
/// an on-screen keyboard are all the same thing to a consumer. That is the
/// whole point of doing the seam first: a surface written against this does not
/// change when real hardware arrives.
abstract interface class MidiInput {
  /// Messages as they arrive. Broadcast: several surfaces may listen, and one
  /// of them closing must not silence the others.
  Stream<MidiMessage> get messages;

  /// Human-readable names of what is connected, for a picker.
  List<String> get devices;

  /// Whether anything is actually there.
  bool get isAvailable;

  Future<void> dispose();
}

/// The input for a platform with no MIDI — which is every platform today.
///
/// Not a placeholder to be replaced: web and any device without a controller
/// will always need this, and a consumer that only works when hardware is
/// present is a consumer that breaks on most machines.
class NullMidiInput implements MidiInput {
  @override
  Stream<MidiMessage> get messages => const Stream.empty();

  @override
  List<String> get devices => const [];

  @override
  bool get isAvailable => false;

  @override
  Future<void> dispose() async {}
}

/// An input a test — or an on-screen keyboard — can push messages into.
class ManualMidiInput implements MidiInput {
  ManualMidiInput({List<String> devices = const ['On-screen']})
      : _devices = devices;

  final _controller = StreamController<MidiMessage>.broadcast();
  final List<String> _devices;

  @override
  Stream<MidiMessage> get messages => _controller.stream;

  @override
  List<String> get devices => List.unmodifiable(_devices);

  @override
  bool get isAvailable => true;

  void send(MidiMessage message) {
    if (!_controller.isClosed) _controller.add(message);
  }

  void sendBytes(List<int> bytes) {
    if (MidiMessage.fromBytes(bytes) case final message?) send(message);
  }

  @override
  Future<void> dispose() => _controller.close();
}

/// Which notes are down right now.
///
/// Every record path needs this and it is where the bugs live: a note-on with
/// velocity 0 is a note-off; the same note can arrive twice without an
/// intervening off (a stuck key, or two controllers); and notes on different
/// channels are different notes even at the same pitch.
class HeldNotes {
  final Map<(int channel, int note), int> _held = {};

  /// Apply [message]; returns true when the held set CHANGED, so a caller can
  /// skip redrawing on the messages that do not matter (a control change, a
  /// duplicate note-on).
  bool apply(MidiMessage message) {
    final key = (message.channel, message.note);
    if (message.isNoteOff) {
      return _held.remove(key) != null;
    }
    if (message.isNoteOn) {
      final had = _held[key];
      _held[key] = message.velocity;
      // A repeated note-on at the same velocity is not a change; at a
      // different velocity it is (an aftertouch-ish re-strike).
      return had != message.velocity;
    }
    return false;
  }

  /// The notes down, lowest first — a stable order, so a chord read out of this
  /// does not shuffle between frames.
  List<int> notesOn({int? channel}) {
    final out = [
      for (final entry in _held.entries)
        if (channel == null || entry.key.$1 == channel) entry.key.$2,
    ]..sort();
    return out;
  }

  /// The velocity a note arrived with, or null if it is not down.
  int? velocityOf(int note, {int channel = 0}) => _held[(channel, note)];

  bool get isEmpty => _held.isEmpty;
  int get length => _held.length;

  /// Forget everything — what to do when an input disconnects, since the
  /// note-offs for anything held will never arrive.
  void clear() => _held.clear();
}
