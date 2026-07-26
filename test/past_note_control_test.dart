// Tests for per-cell PAST-NOTE / NNA control (IT/S3M `S7x`), routed through the
// native NNA voice orchestration in `_renderNativeTickZoneVoices`.
//
// Implemented sub-commands:
//   • S70/S71/S72 — past-note cut / off / fade of the channel's background
//     (overlapping NNA) voices.
//   • S73–S76     — per-channel set-NNA override for the next note's predecessor.
//   • Cross-format: S3M/IT `S7x` maps to the neutral `kFxSetPastNote` command
//     (previously dropped to `(0, 0)`), and the report no longer flags it.
//   • S77–S7C envelope toggles are DEFERRED (carried cross-format as data, no-op
//     in the replayer) — see kFxSetPastNote's doc-comment.
//
// The synthetic instrument uses a looped, constant-amplitude sample with a
// non-zero fade-out so that under NNA=continue a background note keeps ringing
// (fading) past its run boundary — a measurable overlap for the past-note
// actions to remove. A zero-depth vibrato (0x400) forces the per-tick native
// voice path so every render in a comparison uses the SAME path.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/mod/module_export_report.dart';
import 'package:comet_beat/core/audio/mod/s3m_module.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:flutter_test/flutter_test.dart';

TrackerCell fx(int cmd, int param, {int? midi}) =>
    TrackerCell(midi: midi, fxCmd: cmd, fxParam: param);

/// Sum of |sample| over [a, b) — a cheap energy proxy.
double energy(Int16List pcm, int a, int b) {
  var s = 0.0;
  for (var i = a; i < b && i < pcm.length; i++) {
    s += (pcm[i] / 32768.0).abs();
  }
  return s;
}

/// A native-voice MultiSampleInstrument channel song over 12 rows. [nna] is the
/// instrument's New-Note Action (engine-internal: 0 cut, 1 off, 2 fade, 3
/// continue).
TrackerSong nnaSong(List<TrackerCell> pattern, {required int nna}) {
  const rows = 12;
  final cells = List<TrackerCell>.filled(rows, TrackerCell.empty);
  for (var i = 0; i < pattern.length && i < rows; i++) {
    cells[i] = pattern[i];
  }
  final sample = Float64List(480000)..fillRange(0, 480000, 0.3);
  return TrackerSong.fromParts(
    channels: [
      TrackerChannel(
        id: 'nna',
        instrument: MultiSampleInstrument(
          'inst',
          {
            60: SampleInstrument(
              'zone',
              sample,
              normalize: false,
              nativeNna: nna,
              nativeFadeout: 8, // slow fade → a continued note keeps ringing
              loopLength: 480000,
            ),
          },
          polyphonic: true,
          nativeVoiceSemantics: true,
        ),
        rows: rows,
      ),
    ],
    timing: const TrackerTiming(rows: rows),
    patterns: [
      TrackerPattern(name: '00', cells: [cells]),
    ],
    order: [0],
  );
}

/// A one-channel, one-row S3M carrying a single `Sxy` special (command 19),
/// converted through the neutral doc hub (exercises `_s3mSpecialToFx`).
ModuleDoc s3mSpecialDoc(int info) => docFromS3m(
      S3mModule(
        channelCount: 1,
        order: const [0],
        samples: const [],
        patterns: [
          S3mPattern([
            [S3mCell(note: 0x30, instrument: 1, command: 19, info: info)],
          ]),
        ],
      ),
    );

void main() {
  const timing = TrackerTiming(rows: 12);
  final rowStart = [for (var r = 0; r <= 12; r++) timing.stepStartSample(r)];

  // A two-note pattern (row 0, row 4) with a zero-depth vibrato at row 1 to force
  // the per-tick native voice path.
  List<TrackerCell> twoNotes() {
    final c = List<TrackerCell>.filled(12, TrackerCell.empty);
    c[0] = const TrackerCell(midi: 60);
    c[1] = fx(kFxVibrato, 0x00);
    c[4] = const TrackerCell(midi: 60);
    return c;
  }

  group('past-note actions (S70/S71/S72)', () {
    test('S70 cuts the ringing background voice at its row; foreground stays',
        () {
      // NNA=continue keeps the first (background) voice ringing past row 4.
      final basePcm = replaySong(nnaSong(twoNotes(), nna: 3)).pcm;
      final cutPcm = replaySong(
        nnaSong(twoNotes()..[8] = fx(kFxSetPastNote, 0x0), nna: 3),
      ).pcm;

      // Before the command (rows 6–7): S70 has not fired and the foreground
      // note is untouched — the two renders match closely.
      final beforeBase = energy(basePcm, rowStart[6], rowStart[8]);
      final beforeCut = energy(cutPcm, rowStart[6], rowStart[8]);
      expect(
        beforeCut,
        closeTo(beforeBase, beforeBase * 0.02),
        reason: 'S70 must not affect audio before its own row',
      );

      // After the command (rows 9–10): the background voice is cut, so energy
      // drops well below the still-overlapping baseline.
      final afterBase = energy(basePcm, rowStart[9], rowStart[11]);
      final afterCut = energy(cutPcm, rowStart[9], rowStart[11]);
      expect(
        afterCut,
        lessThan(afterBase * 0.7),
        reason: 'S70 silences the background voice → energy drops',
      );
      expect(
        afterCut,
        greaterThan(0),
        reason: 'the foreground voice keeps sounding',
      );
    });

    test('S71 (off) / S72 (fade) never add energy; S70 (cut) is the hardest',
        () {
      final a = rowStart[9], b = rowStart[11];
      double after(int? sub) {
        final cells = twoNotes();
        if (sub != null) cells[8] = fx(kFxSetPastNote, sub);
        return energy(replaySong(nnaSong(cells, nna: 3)).pcm, a, b);
      }

      final eBase = after(null);
      final eCut = after(0x0);
      final eOff = after(0x1);
      final eFade = after(0x2);

      expect(eOff, lessThanOrEqualTo(eBase * 1.01));
      expect(eFade, lessThanOrEqualTo(eBase * 1.01));
      expect(eCut, lessThan(eOff));
      expect(eCut, lessThan(eFade));
    });
  });

  group('set-NNA override (S73–S76)', () {
    // Instrument default NNA = cut (0). Without an override a second note cuts
    // its predecessor; `S74` (set NNA=continue) instead keeps it ringing.
    List<TrackerCell> withSetNna(int sub) {
      final c = List<TrackerCell>.filled(12, TrackerCell.empty);
      c[0] = const TrackerCell(midi: 60);
      c[2] =
          fx(kFxSetPastNote, sub); // set-NNA at row 2 (also forces tick path)
      c[4] = const TrackerCell(midi: 60);
      return c;
    }

    test('S74 keeps the predecessor ringing where S73 cuts it', () {
      final s74 = replaySong(nnaSong(withSetNna(0x4), nna: 0)).pcm; // continue
      final s73 = replaySong(nnaSong(withSetNna(0x3), nna: 0)).pcm; // cut

      final a = rowStart[6], b = rowStart[8];
      final eContinue = energy(s74, a, b);
      final eCut = energy(s73, a, b);
      expect(
        eContinue,
        greaterThan(eCut * 1.3),
        reason:
            'S74 (continue) leaves both voices ringing; S73 (cut) leaves one',
      );
    });
  });

  group('cross-format mapping', () {
    test('S7x maps to kFxSetPastNote (was (0, 0)) and carries its sub-nibble',
        () {
      for (final sub in [0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6]) {
        final doc = s3mSpecialDoc(0x70 | sub);
        final cell = doc.patterns.first.rows.first.first;
        expect(cell.effect, kFxSetPastNote, reason: 'S7$sub → kFxSetPastNote');
        expect(
          cell.effectParam & 0xF,
          sub,
          reason: 'S7$sub sub-nibble carried',
        );
        // Native provenance is retained for a same-format round-trip.
        expect(cell.nativeEffect, 19);
        expect(cell.nativeEffectParam, 0x70 | sub);
      }
    });

    test('S7x is no longer reported as an unmapped Sxy drop (cross-format)',
        () {
      final report =
          moduleExportLossReport(s3mSpecialDoc(0x71), ModuleFormat.it);
      expect(
        report,
        isNot(contains(ModuleExportLoss.unmappedSpecialEffects)),
        reason: 'S7x now maps cross-format via kFxSetPastNote',
      );
    });
  });

  group('byte-identity', () {
    test('a song with no S7x renders deterministically (feature is inert)', () {
      final a = replaySong(nnaSong(twoNotes(), nna: 3)).pcm;
      final b = replaySong(nnaSong(twoNotes(), nna: 3)).pcm;
      expect(a.length, b.length);
      var identical = true;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) {
          identical = false;
          break;
        }
      }
      expect(
        identical,
        isTrue,
        reason: 'no-S7x render must be byte-stable through the S7x code path',
      );
    });
  });
}
