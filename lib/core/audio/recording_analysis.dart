// lib/core/audio/recording_analysis.dart
//
// Run the pitch/chord analysis over a RECORDED audio file, not just the live
// mic. The detection core is already stream-based ([StreamingAudioAnalyzer]);
// this decodes a PCM16 WAV, downmixes to mono, and slides the analyzer across
// the whole recording at the FILE's own sample rate. Pure + Flutter-free, so
// both the app and `bin/listen.dart` share one tested implementation, and the
// detector hardening (non-finite/degenerate frames → silence) protects it.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/chroma_analysis.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/audio/streaming_analyzer.dart';
import 'package:comet_beat/core/audio/wav_io.dart';

/// The result of analysing one recording: its format + the per-window readings.
class RecordingAnalysis {
  const RecordingAnalysis({
    required this.sampleRate,
    required this.channels,
    required this.durationSeconds,
    required this.frames,
  });

  final int sampleRate;
  final int channels;
  final double durationSeconds;

  /// One [AnalyzerFrame] per completed window (pitch, and chord when analysed
  /// with [detectChords]).
  final List<AnalyzerFrame> frames;

  /// The windows that read a confident pitch.
  Iterable<AnalyzerFrame> get voiced => frames.where((f) => f.pitch.hasPitch);

  /// A rough monophonic transcription: the sequence of detected notes (nearest
  /// MIDI), collapsing consecutive equal notes and dropping unvoiced windows.
  ///
  /// [minFrames] drops any note held for fewer than that many consecutive
  /// windows — the single-window pitch glitch that appears at each note
  /// boundary (as one note's decaying tail slides into the next note's onset)
  /// is not a real note. The default of 2 removes those cleanly; pass 1 to keep
  /// every transient.
  List<int> noteRun({int minFrames = 2}) {
    // Maximal runs of identical consecutive voiced notes, with their lengths.
    final runs = <({int midi, int count})>[];
    for (final f in frames) {
      if (!f.pitch.hasPitch) continue;
      final midi = f.pitch.nearestMidi;
      if (runs.isNotEmpty && runs.last.midi == midi) {
        runs[runs.length - 1] = (midi: midi, count: runs.last.count + 1);
      } else {
        runs.add((midi: midi, count: 1));
      }
    }
    final out = <int>[];
    for (final run in runs) {
      if (run.count < minFrames) continue; // a boundary glitch, not a note
      if (out.isEmpty || out.last != run.midi) out.add(run.midi);
    }
    return out;
  }

  /// A real-audio-robust monophonic melody transcription. Where [noteRun] just
  /// collapses runs, this MEDIAN-SMOOTHS the per-window pitch first (window
  /// [smoothWindow]) — killing the single-window octave/semitone glitches and
  /// brief vibrato excursions that pepper real recordings — then keeps notes
  /// held at least [minFrames] windows.
  ///
  /// NB genuinely monophonic: it reads a solo instrument line well, but cannot
  /// transcribe polyphony (piano+accompaniment) or heavy vibrato singing — for
  /// those a monophonic pitch tracker is the wrong tool.
  List<int> melody({int smoothWindow = 5, int minFrames = 4}) {
    if (frames.isEmpty) return const [];
    // Per-frame nearest MIDI; -1 marks an unvoiced window.
    final track = [
      for (final f in frames) f.pitch.hasPitch ? f.pitch.nearestMidi : -1,
    ];
    final half = (smoothWindow < 1 ? 1 : smoothWindow) ~/ 2;
    final smoothed = <int>[];
    for (var i = 0; i < track.length; i++) {
      final votes = <int>[];
      for (var j = i - half; j <= i + half; j++) {
        if (j >= 0 && j < track.length && track[j] >= 0) votes.add(track[j]);
      }
      if (votes.isEmpty) {
        smoothed.add(-1);
        continue;
      }
      votes.sort();
      smoothed.add(votes[votes.length ~/ 2]); // median
    }
    final runs = <({int midi, int count})>[];
    for (final m in smoothed) {
      if (m < 0) continue;
      if (runs.isNotEmpty && runs.last.midi == m) {
        runs[runs.length - 1] = (midi: m, count: runs.last.count + 1);
      } else {
        runs.add((midi: m, count: 1));
      }
    }
    final out = <int>[];
    for (final run in runs) {
      if (run.count < minFrames) continue;
      if (out.isEmpty || out.last != run.midi) out.add(run.midi);
    }
    return out;
  }

  /// The SUSTAINED chords over time (best-candidate name per window), collapsing
  /// repeats. [minFrames] drops chords held for fewer than that many consecutive
  /// windows — the transient guesses at a chord boundary (a straddling window)
  /// or a momentary harmonic ambiguity (a triad's overtones flickering to a 7th)
  /// aren't the played chord. Empty unless analysed with [detectChords].
  List<String> chordRun({int minFrames = 2}) {
    final runs = <({String name, int count})>[];
    for (final f in frames) {
      final name = f.chord?.best?.name;
      if (name == null) continue;
      if (runs.isNotEmpty && runs.last.name == name) {
        runs[runs.length - 1] = (name: name, count: runs.last.count + 1);
      } else {
        runs.add((name: name, count: 1));
      }
    }
    final out = <String>[];
    for (final run in runs) {
      if (run.count < minFrames) continue;
      if (out.isEmpty || out.last != run.name) out.add(run.name);
    }
    return out;
  }

  /// The plain-triad qualities (vs a 7th/extended chord).
  static const _triadSuffixes = {'', 'm', 'dim', 'aug'};

  /// The chord read for one frame, biased toward the SIMPLE triad: a real
  /// sustained chord's overtones make a 7th score just above the triad, but for
  /// a beginners' listener "C" beats "Cmaj7". If the best candidate is a 7th/
  /// extension and a triad sits within [triadMargin] of it, take the triad.
  String? _frameChord(ChordReading? c, double triadMargin) {
    if (c == null || c.candidates.isEmpty) return null;
    final best = c.candidates.first;
    if (_triadSuffixes.contains(best.suffix)) return best.name;
    for (final cand in c.candidates) {
      if (_triadSuffixes.contains(cand.suffix) &&
          best.score - cand.score <= triadMargin) {
        return cand.name;
      }
    }
    return best.name;
  }

  /// A real-audio-robust chord progression. Where [chordRun] just collapses
  /// runs, this MODE-SMOOTHS the chord track (window [smoothWindow]) — outvoting
  /// the transient 7th/relative-minor guesses a sustained, decaying real chord
  /// throws off from its overtones — biases each frame toward the plain triad
  /// (see [_frameChord]/[triadMargin]) and keeps chords held at least
  /// [minFrames] windows. Empty unless analysed with [detectChords].
  List<String> chordProgression({
    int smoothWindow = 5,
    int minFrames = 4,
    double triadMargin = 0.06,
  }) {
    if (frames.isEmpty) return const [];
    final track = [for (final f in frames) _frameChord(f.chord, triadMargin)];
    final half = (smoothWindow < 1 ? 1 : smoothWindow) ~/ 2;
    final smoothed = <String?>[];
    for (var i = 0; i < track.length; i++) {
      final counts = <String, int>{};
      for (var j = i - half; j <= i + half; j++) {
        if (j >= 0 && j < track.length && track[j] != null) {
          counts[track[j]!] = (counts[track[j]!] ?? 0) + 1;
        }
      }
      if (counts.isEmpty) {
        smoothed.add(null);
        continue;
      }
      // The most-voted chord in the window (first-seen wins ties).
      String? best;
      var bestCount = 0;
      for (var j = i - half; j <= i + half; j++) {
        if (j < 0 || j >= track.length || track[j] == null) continue;
        final c = counts[track[j]!]!;
        if (c > bestCount) {
          bestCount = c;
          best = track[j];
        }
      }
      smoothed.add(best);
    }
    final runs = <({String name, int count})>[];
    for (final name in smoothed) {
      if (name == null) continue;
      if (runs.isNotEmpty && runs.last.name == name) {
        runs[runs.length - 1] = (name: name, count: runs.last.count + 1);
      } else {
        runs.add((name: name, count: 1));
      }
    }
    final out = <String>[];
    for (final run in runs) {
      if (run.count < minFrames) continue;
      if (out.isEmpty || out.last != run.name) out.add(run.name);
    }
    return out;
  }
}

/// Analyse a PCM16 WAV [wavBytes]: pitch (and optionally chords when
/// [detectChords]) over sliding windows, at the file's own sample rate. Any
/// channel count downmixes to mono. Throws only if [wavBytes] isn't a readable
/// PCM WAV (see [readWavPcm16]); a valid-but-odd file (silent, tiny, unusual
/// rate) yields short/empty results rather than crashing.
RecordingAnalysis analyzeRecording(
  Uint8List wavBytes, {
  double a4 = kDefaultA4,
  bool detectChords = false,
}) {
  final wav = readWavPcm16(wavBytes);
  final mono = wavToMonoFloat(wav);
  final analyzer = StreamingAudioAnalyzer(
    detector: PitchDetector(sampleRate: wav.sampleRate, a4: a4),
    chordDetector:
        detectChords ? ChordDetector(sampleRate: wav.sampleRate, a4: a4) : null,
  );
  return RecordingAnalysis(
    sampleRate: wav.sampleRate,
    channels: wav.channels,
    durationSeconds: wav.sampleRate > 0 ? mono.length / wav.sampleRate : 0,
    frames: analyzer.addSamples(mono),
  );
}
