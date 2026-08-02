// lib/core/music/sung_melody.dart
//
// Mode 2's plumbing: live microphone pitch → a melodic search query.
//
// Every link in this chain already existed and none of them were connected:
// `MicrophonePitchService` emits `PitchReading`s, `segmentNotes` (the shipped
// note-HMM) turns a `PitchTrack` into notes, and `melodyQueryFromNotes` turns
// notes into a query. What was missing is the join — and one thing neither end
// supplies.
//
// ⚠️ **A `PitchReading` has no timestamp.** It carries frequency, clarity, rms
// and zcr, but nothing about WHEN. `segmentNotes` needs `timeMs` per frame to
// give its notes an onset and offset, and `melodyQueryFromNotes` then filters on
// duration. So the time base has to be stamped as readings ARRIVE — which is
// why this is a collector with a clock rather than a pure `map`.
//
// Pure Dart: no Flutter, no plugin, no mic. The caller owns the microphone and
// pushes readings in, so the whole path is testable from a synthesised track
// (which is exactly how the rest of this app's audio work is validated).

import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/note_hmm.dart';
import 'package:comet_beat/core/music/melodic_search.dart';

/// How many frames must arrive before a query is worth attempting.
///
/// Not a musical threshold — a statistical one. The note-HMM needs a run of
/// frames to decode anything at all (its own `minFrames` drops shorter notes as
/// glitches), and asking it about a handful of frames returns noise that then
/// looks to the user like the search failing.
const int kMinSungFrames = 24;

/// Accumulates live pitch readings and turns them into a melodic query.
///
/// Deliberately takes raw values rather than a `PitchReading`: it keeps this
/// file independent of the detector's own type, so the same collector works
/// with the MPM detector, a pYIN track, or a synthesised one in a test.
class SungMelodyCollector {
  SungMelodyCollector({this.a4 = 440});

  /// Reference tuning, passed through to the segmenter.
  final double a4;

  final List<PitchFrame> _frames = [];

  /// The frames collected so far, oldest first.
  PitchTrack get track => List.unmodifiable(_frames);

  int get frameCount => _frames.length;

  /// Whether enough has been sung to be worth transcribing.
  bool get hasEnough => _frames.length >= kMinSungFrames;

  /// Records one analysis frame.
  ///
  /// [clarity] becomes the frame's `voicedProb`: the MPM detector's clarity IS
  /// a 0..1 confidence that the window is periodic, which is the same question
  /// `voicedProb` asks. A silent frame (frequency 0) is kept rather than
  /// dropped — silence is what separates one note from the next, and discarding
  /// it would fuse a repeated note into one long one, changing the shape.
  void add({
    required double frequency,
    required double clarity,
    required double timeMs,
  }) {
    _frames.add(
      (
        timeMs: timeMs,
        f0Hz: frequency,
        voicedProb: frequency > 0 ? clarity : 0.0,
      ),
    );
  }

  void clear() => _frames.clear();

  /// The notes decoded from what has been sung.
  List<NoteEvent> notes({double voicedThreshold = 0.5}) => _frames.length < 2
      ? const []
      : segmentNotes(_frames, voicedThreshold: voicedThreshold, a4: a4);

  /// What has been sung, as a melodic-search query.
  ///
  /// Returns empty until [hasEnough] — a query built from a handful of frames
  /// is noise, and ranking the catalog against noise produces confident-looking
  /// nonsense rather than an obvious failure.
  List<int> toQuery({
    double voicedThreshold = 0.5,
    double minDurationMs = 90,
    double minConfidence = 0.5,
    int maxNotes = kMaxSungQueryNotes,
  }) {
    if (!hasEnough) return const [];
    return melodyQueryFromNotes(
      notes(voicedThreshold: voicedThreshold),
      minDurationMs: minDurationMs,
      minConfidence: minConfidence,
      maxNotes: maxNotes,
    );
  }
}
