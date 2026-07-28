// What a loudness reading MEANS — WS-A5.
//
// `crisp_dsp/loudness.dart` produces the numbers; this turns them into a
// judgement, and it lives apart from the widget on purpose. A meter that prints
// "−9.3 LUFS, −0.4 dBTP, correlation −0.2" has told a learner nothing: the
// numbers only mean something against a target, and the useful part is what
// happens to the mix BECAUSE of them. Keeping that here makes the reasoning
// testable — a test can assert the advice is right, which is the actual claim,
// rather than that a sheet opened.
//
// The thresholds are published delivery conventions, not taste:
//   · streaming services normalise playback to roughly −14 LUFS
//   · EBU R128 broadcast is −23 LUFS
//   · the delivery ceiling is −1 dBTP, because a lossy encoder (and the
//     conversion back to analogue) can overshoot samples that never clipped
//   · a negative stereo correlation largely disappears when summed to mono,
//     which is what a phone speaker does

import 'package:comet_beat/core/audio/crisp_dsp/loudness.dart';

/// Where the mix is going, which is the only thing that makes a LUFS number
/// good or bad.
enum LoudnessTarget {
  /// Roughly what streaming services normalise playback to. The default,
  /// because it is where almost everything anyone makes here ends up.
  streaming(-14, 'Streaming', 'Services normalise playback to about −14 LUFS'),

  /// EBU R128. Quieter, and strict about it.
  broadcast(-23, 'Broadcast', 'EBU R128 delivery is −23 LUFS'),

  /// No target — report the numbers and check only the things that are wrong
  /// at ANY level (clipping, phase).
  none(0, 'No target', 'Just the measurements');

  const LoudnessTarget(this.lufs, this.label, this.blurb);

  final double lufs;
  final String label;
  final String blurb;
}

/// How worried to be.
enum LoudnessStatus {
  /// Nothing to do.
  good,

  /// Worth knowing, not a defect.
  note,

  /// Something will audibly go wrong on delivery.
  warn,
}

/// One line of a meter readout: what was measured, and what it means.
typedef LoudnessNote = ({
  String headline,
  String detail,
  LoudnessStatus status,
});

/// How far from [target] a mix may sit before it is worth mentioning. Below
/// this, the difference is inaudible and flagging it would train people to
/// chase a number instead of listening.
const double kLoudnessToleranceDb = 1.0;

/// Read [reading] against [target] and say what it means.
///
/// Ordered by consequence: the things that will audibly break on delivery come
/// first, then level, then phase. A reading of digital silence short-circuits —
/// every other line would be a comment on nothing.
List<LoudnessNote> loudnessAdvice(
  LoudnessReading reading, {
  LoudnessTarget target = LoudnessTarget.streaming,
}) {
  if (reading.integratedLufs <= kLoudnessSilenceLufs) {
    return const [
      (
        headline: 'Silence',
        detail: 'Nothing above the measurement gate — there is no mix to '
            'measure yet.',
        status: LoudnessStatus.note,
      ),
    ];
  }

  final notes = <LoudnessNote>[];

  // 1. True peak. Checked FIRST and regardless of target, because it is the
  //    only reading here that describes actual damage rather than a preference.
  if (reading.truePeakDb > -1) {
    notes.add(
      (
        headline: 'True peak ${reading.truePeakDb.toStringAsFixed(2)} dBTP',
        detail: 'Above −1 dBTP. The samples may not clip, but a lossy encoder '
            'and the conversion back to analogue both overshoot — so this can '
            'distort on the listener\'s side while looking clean here. Pull the '
            'master down, or put a limiter on it.',
        status: LoudnessStatus.warn,
      ),
    );
  } else {
    notes.add(
      (
        headline: 'True peak ${reading.truePeakDb.toStringAsFixed(2)} dBTP',
        detail: 'Under the −1 dBTP delivery ceiling.',
        status: LoudnessStatus.good,
      ),
    );
  }

  // 2. Level against the target.
  if (target != LoudnessTarget.none) {
    final delta = reading.integratedLufs - target.lufs;
    if (delta > kLoudnessToleranceDb) {
      notes.add(
        (
          headline: '${delta.toStringAsFixed(1)} dB louder than '
              '${target.label.toLowerCase()}',
          detail:
              'Integrated ${reading.integratedLufs.toStringAsFixed(1)} LUFS '
              'against ${target.lufs.toStringAsFixed(0)}. It will simply be '
              'turned DOWN on playback, so the extra loudness buys nothing — and '
              'whatever dynamics were squeezed out to get it are gone for good.',
          status: LoudnessStatus.note,
        ),
      );
    } else if (delta < -kLoudnessToleranceDb) {
      notes.add(
        (
          headline: '${(-delta).toStringAsFixed(1)} dB quieter than '
              '${target.label.toLowerCase()}',
          detail:
              'Integrated ${reading.integratedLufs.toStringAsFixed(1)} LUFS '
              'against ${target.lufs.toStringAsFixed(0)}. It will be turned up '
              'on playback, which is fine — the dynamics survive. Only raise it '
              'if it needs to sit next to something louder.',
          status: LoudnessStatus.good,
        ),
      );
    } else {
      notes.add(
        (
          headline: 'Level is on target',
          detail:
              'Integrated ${reading.integratedLufs.toStringAsFixed(1)} LUFS, '
              'within $kLoudnessToleranceDb dB of ${target.lufs.toStringAsFixed(0)}.',
          status: LoudnessStatus.good,
        ),
      );
    }
  } else {
    notes.add(
      (
        headline:
            '${reading.integratedLufs.toStringAsFixed(1)} LUFS integrated',
        detail: 'Short-term ${reading.shortTermLufs.toStringAsFixed(1)}, '
            'momentary ${reading.momentaryLufs.toStringAsFixed(1)}.',
        status: LoudnessStatus.good,
      ),
    );
  }

  // 3. Phase. A stereo meter cannot show this, which is exactly why it earns a
  //    line: the failure only appears on a device you are not listening on.
  if (reading.correlation < 0) {
    notes.add(
      (
        headline: 'Phase ${reading.correlation.toStringAsFixed(2)} — mono risk',
        detail: 'The channels are pulling against each other. A phone speaker '
            'sums to mono, and material like this largely cancels when it does — '
            'so parts of the mix can vanish on the most common speaker there is.',
        status: LoudnessStatus.warn,
      ),
    );
  } else if (reading.correlation > 0.95) {
    notes.add(
      (
        headline: 'Phase ${reading.correlation.toStringAsFixed(2)} — near mono',
        detail:
            'The two channels are almost identical. Nothing is wrong; there '
            'is just no stereo width to lose.',
        status: LoudnessStatus.note,
      ),
    );
  } else {
    notes.add(
      (
        headline: 'Phase ${reading.correlation.toStringAsFixed(2)}',
        detail: 'Folds to mono safely.',
        status: LoudnessStatus.good,
      ),
    );
  }

  // 4. The peak-to-loudness range, last because it is a description rather
  //    than a problem — but it is the number that says "this is squashed".
  final psr = reading.truePeakDb - reading.shortTermLufs;
  if (psr.isFinite && psr < 6) {
    notes.add(
      (
        headline: 'Dynamics are tight (${psr.toStringAsFixed(1)} dB crest)',
        detail: 'Little distance between the loudest moment and the average. '
            'That is a choice, not a fault — but it is the thing that makes a '
            'mix tiring over a whole track.',
        status: LoudnessStatus.note,
      ),
    );
  }

  return notes;
}
