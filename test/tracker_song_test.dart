// TrackerSong — the Advanced Tracker's document model. Covers the arrangement
// layer the Beginner grid lacks: endless pattern length (setRows), endless
// tracks (add/removeChannel), and multi-pattern songs (patterns + order list).
// Pure Dart, no device audio — mirrors tracker_engine_test.dart.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart' show kFxSetSpeed;
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:flutter_test/flutter_test.dart';

int _wavPcmLen(Uint8List wav) => (wav.length - 44) ~/ 2; // samples after header

void main() {
  group('TrackerSong defaults', () {
    test('starts with one pattern, one order entry, the default band', () {
      final song = TrackerSong();
      expect(song.patterns.length, 1);
      expect(song.order, [0]);
      expect(song.channelCount, defaultTrackerChannels().length);
      expect(song.rows, 32);
      expect(song.isEmpty, isTrue);
      // Every pattern column is channel-major and row-sized.
      expect(song.current.cells.length, song.channelCount);
      for (final col in song.current.cells) {
        expect(col.length, song.rows);
      }
    });
  });

  group('endless length (setRows)', () {
    test('grows and shrinks every pattern, keeping notes in range', () {
      final song = TrackerSong()..addPattern();
      // Place a note near the end of a 32-row pattern on channel 0.
      song.engine.setCell(0, 30, const TrackerCell(midi: 60));
      song.setRows(64);
      expect(song.rows, 64);
      for (final p in song.patterns) {
        for (final col in p.cells) {
          expect(col.length, 64);
        }
      }
      // The note at row 30 survived the grow.
      expect(song.engine.cellAt(0, 30).midi, 60);

      // Shrinking below the note drops it; rows that remain are intact.
      song.engine.setCell(0, 10, const TrackerCell(midi: 62));
      song.setRows(16);
      expect(song.rows, 16);
      expect(song.engine.cellAt(0, 10).midi, 62);
      expect(song.current.cells.first.length, 16);
    });

    test('a 128-row pattern is far past the Beginner one-bar ceiling', () {
      final song = TrackerSong()..setRows(128);
      expect(song.rows, 128);
      // Render still produces a valid, longer loop.
      final wav = song.renderCurrentPatternWav();
      expect(wav.length, greaterThan(44));
    });
  });

  group('endless tracks (add/removeChannel)', () {
    test('addChannel grows the band and every pattern column', () {
      final song = TrackerSong()..addPattern();
      final before = song.channelCount;
      song.addChannel();
      expect(song.channelCount, before + 1);
      for (final p in song.patterns) {
        expect(p.cells.length, before + 1);
        expect(p.cells.last.length, song.rows);
      }
      // The new channel is editable and renders.
      song.engine
          .setCell(song.channelCount - 1, 0, const TrackerCell(midi: 64));
      expect(song.engine.cellAt(song.channelCount - 1, 0).midi, 64);
    });

    test('removeChannel keeps existing notes on the surviving channels', () {
      final song = TrackerSong();
      song.engine.setCell(0, 0, const TrackerCell(midi: 60)); // ch0
      song.engine.setCell(2, 1, const TrackerCell(midi: 67)); // ch2
      song.removeChannel(1); // drop the middle channel
      expect(song.channelCount, defaultTrackerChannels().length - 1);
      expect(song.engine.cellAt(0, 0).midi, 60); // ch0 intact
      expect(song.engine.cellAt(1, 1).midi, 67); // old ch2 shifted to ch1
    });

    test('cannot remove the last channel', () {
      final song = TrackerSong(
        channels: [
          TrackerChannel(
            id: 'only',
            instrument: const AdditiveInstrument('piano', Instrument.piano),
            rows: 32,
          ),
        ],
      );
      song.removeChannel(0);
      expect(song.channelCount, 1);
    });
  });

  group('multi-pattern songs + order list', () {
    test('selectPattern saves and restores per-pattern cells', () {
      final song = TrackerSong();
      song.engine.setCell(0, 0, const TrackerCell(midi: 60)); // pattern 0
      final p1 = song.addPattern();
      song.selectPattern(p1);
      expect(song.engine.cellAt(0, 0).isEmpty, isTrue); // fresh pattern
      song.engine.setCell(0, 0, const TrackerCell(midi: 72)); // pattern 1
      song.selectPattern(0);
      expect(song.engine.cellAt(0, 0).midi, 60); // pattern 0 restored
      song.selectPattern(p1);
      expect(song.engine.cellAt(0, 0).midi, 72); // pattern 1 restored
    });

    test('addPattern(cloneCurrent) copies without aliasing', () {
      final song = TrackerSong();
      song.engine.setCell(0, 0, const TrackerCell(midi: 60));
      final clone = song.addPattern(cloneCurrent: true);
      song.selectPattern(clone);
      expect(song.engine.cellAt(0, 0).midi, 60); // copied
      song.engine.setCell(0, 0, const TrackerCell(midi: 65)); // edit the clone
      song.selectPattern(0);
      expect(song.engine.cellAt(0, 0).midi, 60); // original untouched
    });

    test('song length is the sum of its order entries', () {
      final song = TrackerSong(); // 32 rows
      song.engine.setCell(0, 0, const TrackerCell(midi: 60));
      final p1 = song.addPattern(cloneCurrent: true);
      // Order: pattern0, pattern1, pattern0  -> three patterns back to back.
      song.addToOrder(p1);
      song.addToOrder(0);
      expect(song.order, [0, p1, 0]);

      final one = song.renderCurrentPatternWav();
      final full = song.renderSongWav();
      final onePcm = _wavPcmLen(one);
      final fullPcm = _wavPcmLen(full);
      // Three patterns -> ~3x one pattern (allow rounding slack).
      expect((fullPcm - 3 * onePcm).abs(), lessThan(8));
      expect(song.patternStartMs(1), song.timing.totalMs);
      expect(song.songTotalMs, song.timing.totalMs * 3);
    });

    test('removePattern remaps the order list and keeps a valid current', () {
      final song = TrackerSong();
      final p1 = song.addPattern(); // index 1
      final p2 = song.addPattern(); // index 2
      song.addToOrder(p1);
      song.addToOrder(p2);
      expect(song.order, [0, 1, 2]);
      song.removePattern(1); // drop the middle pattern
      expect(song.patterns.length, 2);
      // Entries that referenced pattern 1 are gone; pattern 2 shifts to 1.
      expect(song.order, [0, 1]);
      expect(song.currentIndex, inInclusiveRange(0, 1));
    });

    test('cannot remove the last pattern or empty the order', () {
      final song = TrackerSong();
      song.removePattern(0);
      expect(song.patterns.length, 1);
      song.removeFromOrder(0);
      expect(song.order, isNotEmpty);
    });
  });

  group('mute / solo', () {
    int peak(Uint8List wav) {
      final data = ByteData.sublistView(wav);
      var p = 0;
      for (var i = 44; i + 1 < wav.length; i += 2) {
        final s = data.getInt16(i, Endian.little).abs();
        if (s > p) p = s;
      }
      return p;
    }

    test('muting the only sounding channel silences the mix', () {
      final song = TrackerSong();
      song.engine.setCell(0, 0, const TrackerCell(midi: 60));
      expect(peak(song.renderCurrentPatternWav()), greaterThan(0));

      song.toggleMute(0);
      expect(song.isMuted(0), isTrue);
      expect(peak(song.renderCurrentPatternWav()), 0);

      song.toggleMute(0);
      expect(song.isMuted(0), isFalse);
      expect(peak(song.renderCurrentPatternWav()), greaterThan(0));
    });

    test('solo suppresses every non-soloed channel', () {
      final song = TrackerSong();
      song.engine.setCell(0, 0, const TrackerCell(midi: 60));
      song.engine.setCell(1, 0, const TrackerCell(midi: 64));
      final both = peak(song.renderCurrentPatternWav());

      song.toggleSolo(0);
      expect(song.isAudible(0), isTrue);
      expect(song.isAudible(1), isFalse);
      final solo0 = peak(song.renderCurrentPatternWav());
      expect(solo0, greaterThan(0));
      expect(solo0, lessThanOrEqualTo(both));

      song.toggleSolo(0); // clear solo -> everyone audible again
      expect(song.isAudible(1), isTrue);
    });

    test('channelRms is >0 where a note sounds and 0 when muted', () {
      final song = TrackerSong();
      song.engine.setCell(0, 0, const TrackerCell(midi: 60));
      song.engine.renderLoop(); // populate the stem cache
      expect(song.engine.channelRms(0, 100, 1470), greaterThan(0));
      song.toggleMute(0);
      expect(song.engine.channelRms(0, 100, 1470), 0);
    });

    test('setChannelGain scales a channel down in the mix', () {
      final song = TrackerSong();
      song.engine.setCell(0, 0, const TrackerCell(midi: 60));
      final loud = peak(song.renderCurrentPatternWav());
      song.setChannelGain(0, 0.1);
      final quiet = peak(song.renderCurrentPatternWav());
      expect(quiet, lessThan(loud));
      expect(quiet, greaterThan(0));
    });

    test('mute/solo indices follow a channel removal', () {
      final song = TrackerSong();
      song.toggleMute(3);
      expect(song.isMuted(3), isTrue);
      song.removeChannel(1); // channels above 1 shift down by one
      expect(song.isMuted(2), isTrue); // old ch3 -> ch2
      expect(song.isMuted(3), isFalse);
    });
  });

  group('block operations', () {
    TrackerSong seeded() {
      final song = TrackerSong()..setRows(16);
      song.engine.setCell(0, 0, const TrackerCell(midi: 60));
      song.engine.setCell(0, 1, const TrackerCell(midi: 62));
      song.engine.setCell(1, 0, const TrackerCell(midi: 67));
      return song;
    }

    test('copy then paste-overwrite reproduces the block elsewhere', () {
      final song = seeded();
      final block = song.copyBlock(0, 0, 1, 1); // 2 rows × 2 channels
      expect(block.length, 2);
      expect(block[0].length, 2);
      song.pasteBlock(block, 0, 8); // paste at row 8
      expect(song.engine.cellAt(0, 8).midi, 60);
      expect(song.engine.cellAt(0, 9).midi, 62);
      expect(song.engine.cellAt(1, 8).midi, 67);
    });

    test('cut = copy then clearBlock empties the source', () {
      final song = seeded();
      final block = song.copyBlock(0, 0, 0, 1);
      song.clearBlock(0, 0, 0, 1);
      expect(song.engine.cellAt(0, 0).isEmpty, isTrue);
      expect(song.engine.cellAt(0, 1).isEmpty, isTrue);
      song.pasteBlock(block, 0, 4);
      expect(song.engine.cellAt(0, 4).midi, 60);
    });

    test('paste-mix only fills empty cells', () {
      final song = seeded();
      final block = [
        [const TrackerCell(midi: 72)],
      ];
      // Target row 0 ch0 already has 60 -> mix leaves it; row 2 is empty -> fills.
      song.pasteBlock(block, 0, 0, mix: true);
      expect(song.engine.cellAt(0, 0).midi, 60); // preserved
      song.pasteBlock(block, 0, 2, mix: true);
      expect(song.engine.cellAt(0, 2).midi, 72); // filled
    });

    test('interpolateNotesBlock fills a chromatic run between top and bottom',
        () {
      final song = TrackerSong()..setRows(16);
      // C4 at row 0, C5 at row 4 (an octave up), rows 1-3 empty.
      song.engine.setCell(0, 0, const TrackerCell(midi: 60, instrument: 2));
      song.engine.setCell(0, 4, const TrackerCell(midi: 72));

      song.interpolateNotesBlock(0, 0, 0, 4);
      // Linear semitone ramp fills every row 0..4.
      expect(song.engine.cellAt(0, 0).midi, 60);
      expect(song.engine.cellAt(0, 1).midi, 63); // 60 + 12*0.25
      expect(song.engine.cellAt(0, 2).midi, 66);
      expect(song.engine.cellAt(0, 3).midi, 69);
      expect(song.engine.cellAt(0, 4).midi, 72);
      // The top note's instrument is carried onto the filled rows.
      expect(song.engine.cellAt(0, 2).instrument, 2);
    });

    test('interpolateNotesBlock skips a channel missing an endpoint note', () {
      final song = TrackerSong()..setRows(16);
      song.engine.setCell(0, 0, const TrackerCell(midi: 60));
      // No note at the bottom row -> the run is a no-op for this channel.
      song.interpolateNotesBlock(0, 0, 0, 4);
      expect(song.engine.cellAt(0, 1).isEmpty, isTrue);
      expect(song.engine.cellAt(0, 4).isEmpty, isTrue);
    });

    test('transposeBlock shifts notes and clamps, leaving rests', () {
      final song = seeded();
      song.transposeBlock(0, 0, 0, 1, 12); // up an octave
      expect(song.engine.cellAt(0, 0).midi, 72);
      expect(song.engine.cellAt(0, 1).midi, 74);
      expect(song.engine.cellAt(0, 2).isEmpty, isTrue); // rest untouched
    });

    test('coordinates auto-order (end before start still works)', () {
      final song = seeded();
      final block = song.copyBlock(1, 1, 0, 0); // reversed corners
      expect(block.length, 2);
      expect(block[0].length, 2);
    });

    test('copy/paste and transpose carry the per-cell instrument column', () {
      final song = seeded();
      // Give the source cells distinct per-cell voices.
      song.engine.setCellInstrument(0, 0, 3);
      song.engine.setCellInstrument(0, 1, 5);

      final block = song.copyBlock(0, 0, 0, 1);
      expect(block[0][0].instrument, 3); // survives the copy
      expect(block[1][0].instrument, 5);

      song.pasteBlock(block, 0, 8); // overwrite-paste elsewhere
      expect(song.engine.cellAt(0, 8).instrument, 3);
      expect(song.engine.cellAt(0, 9).instrument, 5);

      // Transposing the pasted block keeps the voice while shifting the note.
      song.transposeBlock(0, 8, 0, 9, 12);
      expect(song.engine.cellAt(0, 8).midi, 72);
      expect(song.engine.cellAt(0, 8).instrument, 3);
      expect(song.engine.cellAt(0, 9).instrument, 5);
    });
  });

  group('effect column (replayer)', () {
    // The mix normalizes each stem to unit peak, so a Cxx on a note is only
    // observable RELATIVE to a louder note in the same channel. Keep a loud
    // reference note at row 0 (the peak) and measure a later note's region with
    // vs. without the command.
    int regionPeak(Uint8List wav, TrackerTiming t, int row) {
      final data = ByteData.sublistView(wav);
      final s0 = 44 + t.stepStartSample(row) * 2;
      final s1 = 44 + t.stepStartSample(row + 1) * 2;
      var p = 0;
      for (var i = s0; i + 1 < s1 && i + 1 < wav.length; i += 2) {
        final s = data.getInt16(i, Endian.little).abs();
        if (s > p) p = s;
      }
      return p;
    }

    test('a Cxx set-volume command quietens that note', () {
      final song = TrackerSong()..setRows(8);
      song.engine.setCell(0, 0, const TrackerCell(midi: 60)); // loud reference
      song.engine.setCell(0, 4, const TrackerCell(midi: 72)); // full
      final full = regionPeak(song.renderCurrentPatternWav(), song.timing, 4);
      song.engine.setCell(
        0,
        4,
        const TrackerCell(midi: 72, fxCmd: 0xC, fxParam: 0x10), // C10 = 16/64
      );
      final quiet = regionPeak(song.renderCurrentPatternWav(), song.timing, 4);
      expect(quiet, lessThan(full));
      expect(quiet, greaterThan(0));
    });
  });

  group('orderIndexAtMs', () {
    test('maps song time to the sounding order position', () {
      final song = TrackerSong(); // 32 rows
      song.addToOrder(0);
      song.addToOrder(0); // order = [0,0,0]
      final patMs = song.timing.totalMs;
      expect(song.orderIndexAtMs(0), 0);
      expect(song.orderIndexAtMs(patMs + 1), 1);
      expect(song.orderIndexAtMs(2 * patMs + 1), 2);
      // Past the end clamps to the last entry.
      expect(song.orderIndexAtMs(99 * patMs), 2);
    });
  });

  group('cell edits preserve the fx + instrument columns', () {
    test('setCellVolume / setCellEffect keep fxCmd/fxParam/instrument', () {
      final song = TrackerSong(timing: const TrackerTiming(rows: 4));
      song.engine.setCell(
        0,
        0,
        const TrackerCell(midi: 60, fxCmd: 0x1, fxParam: 0x08, instrument: 2),
      );

      song.engine.setCellVolume(0, 0, 0.5);
      var c = song.engine.cellAt(0, 0);
      expect(c.volume, 0.5);
      expect(c.fxCmd, 0x1);
      expect(c.fxParam, 0x08);
      expect(c.instrument, 2);

      song.engine.setCellEffect(0, 0, TrackerEffect.vibrato);
      c = song.engine.cellAt(0, 0);
      expect(c.effect, TrackerEffect.vibrato);
      expect(c.fxCmd, 0x1);
      expect(c.instrument, 2);
    });

    test('transposeBlock keeps fxCmd/fxParam/instrument (only shifts pitch)',
        () {
      final song = TrackerSong(timing: const TrackerTiming(rows: 4));
      song.engine.setCell(
        0,
        0,
        const TrackerCell(midi: 60, fxCmd: 0x1, fxParam: 0x08, instrument: 3),
      );
      song.transposeBlock(0, 0, 0, 0, 2);
      final c = song.engine.cellAt(0, 0);
      expect(c.midi, 62); // pitch shifted
      expect(c.fxCmd, 0x1);
      expect(c.fxParam, 0x08);
      expect(c.instrument, 3);
    });
  });

  group('per-pattern variable length (Feature B)', () {
    test('setPatternRows resizes only the named pattern; others untouched', () {
      final song = TrackerSong(
        timing: const TrackerTiming(rows: 8),
        patternCount: 3,
      );
      song.setPatternRows(1, 16);
      expect(song.patterns[0].rows, 8);
      expect(song.patterns[1].rows, 16);
      expect(song.patterns[2].rows, 8);
      // Resizing a non-current pattern does not re-time the engine.
      expect(song.rows, 8);
    });

    test('setPatternRows truncates, preserving surviving rows', () {
      final song = TrackerSong(timing: const TrackerTiming(rows: 8));
      song.engine.setCell(0, 0, const TrackerCell(midi: 60));
      song.engine.setCell(0, 3, const TrackerCell(midi: 64));
      song.engine.setCell(0, 6, const TrackerCell(midi: 67));
      song.syncCurrent();
      song.setPatternRows(0, 4); // current pattern, truncate to 4
      expect(song.rows, 4); // engine re-timed
      expect(song.patterns[0].cells[0][0].midi, 60);
      expect(song.patterns[0].cells[0][3].midi, 64);
      expect(song.patterns[0].cells[0].length, 4); // row 6 gone
    });

    test('setPatternRows pads the current pattern with empty rows', () {
      final song = TrackerSong(timing: const TrackerTiming(rows: 4));
      song.engine.setCell(0, 0, const TrackerCell(midi: 60));
      song.syncCurrent();
      song.setPatternRows(0, 8);
      expect(song.rows, 8);
      expect(song.patterns[0].cells[0][0].midi, 60);
      expect(song.patterns[0].cells[0][7].isEmpty, isTrue);
      // The engine accepts an edit on a freshly-added row.
      song.engine.setCell(0, 7, const TrackerCell(midi: 72));
      song.syncCurrent();
      expect(song.patterns[0].cells[0][7].midi, 72);
    });

    test('setPatternRows to the same size is a no-op', () {
      final song = TrackerSong(timing: const TrackerTiming(rows: 8));
      song.setPatternRows(0, 8);
      expect(song.rows, 8);
    });

    test('selectPattern re-times to the selected pattern length', () {
      final song = TrackerSong(
        timing: const TrackerTiming(rows: 8),
        patternCount: 2,
      );
      song.setPatternRows(1, 12);
      song.selectPattern(1);
      expect(song.rows, 12);
      song.selectPattern(0);
      expect(song.rows, 8);
    });

    test('renderSongWav sums differing pattern lengths', () {
      final song = TrackerSong(
        timing: const TrackerTiming(rows: 8),
        patternCount: 2,
      );
      song.setPatternRows(1, 16);
      song.selectPattern(0);
      song.engine.setCell(0, 0, const TrackerCell(midi: 60));
      song.order
        ..clear()
        ..addAll([0, 1]);
      song.syncCurrent();
      final wav = song.renderSongWav();
      final expectedSamples = song.timing.stepMs * 24 * 44100 ~/ 1000;
      expect((_wavPcmLen(wav) - expectedSamples).abs(), lessThan(200));
    });

    test('an all-equal-length song still reports the uniform length', () {
      final song = TrackerSong(
        timing: const TrackerTiming(rows: 8),
        patternCount: 2,
      );
      song.order
        ..clear()
        ..addAll([0, 1, 0]);
      expect(song.songTotalMs, song.timing.totalMs * 3);
    });
  });

  group('songTotalMs reflects live engine edits', () {
    test(
        'a just-authored mid-song Fxx tempo lengthens the song (no manual '
        'sync)', () {
      // Regression: songTotalMs read snapshots without syncing the live engine,
      // so a GUI-authored Fxx tempo (edited via engine.setCell on the current
      // pattern) was invisible until a render/selectPattern synced it — the
      // transport then looped at the wrong length. songTotalMs now syncs first,
      // like the render methods.
      final song = TrackerSong(timing: const TrackerTiming(rows: 8));
      final base = song.songTotalMs;
      // Author a mid-song tempo drop (120 → 80 BPM) at row 4 on the live engine.
      song.engine.setCell(
        4,
        0,
        const TrackerCell(fxCmd: kFxSetSpeed, fxParam: 0x50),
      );
      // No explicit syncCurrent() — songTotalMs must still see it.
      expect(song.songTotalMs, greaterThan(base));
    });
  });

  group('removeInstrument', () {
    test('remaps the per-cell instrument column', () {
      final song = TrackerSong(timing: const TrackerTiming(rows: 4));
      // The pool starts with 4 default voices; add two more (1-based 5 and 6).
      song.instruments.add(const AdditiveInstrument('x', Instrument.piano));
      song.instruments.add(const AdditiveInstrument('y', Instrument.cello));
      song.engine.setCell(0, 0, const TrackerCell(midi: 60, instrument: 1));
      song.engine.setCell(0, 1, const TrackerCell(midi: 62, instrument: 5));
      song.engine.setCell(0, 2, const TrackerCell(midi: 64, instrument: 6));
      final poolBefore = song.instruments.length; // 6

      song.removeInstrument(4); // pool index 4 = the 1-based value 5
      expect(song.instruments.length, poolBefore - 1);
      // At 1 (before the removed one) → unchanged; == 5 → 0 (default); 6 → 5.
      expect(song.engine.cellAt(0, 0).instrument, 1);
      expect(song.engine.cellAt(0, 1).instrument, 0);
      expect(song.engine.cellAt(0, 2).instrument, 5);
      // Notes themselves untouched.
      expect(song.engine.cellAt(0, 2).midi, 64);
    });

    test('out-of-range index is a no-op', () {
      final song = TrackerSong(timing: const TrackerTiming(rows: 4));
      final n = song.instruments.length;
      song.removeInstrument(-1);
      song.removeInstrument(999);
      expect(song.instruments.length, n);
    });
  });

  group('chord helper (stampChordAcross / stampArpeggio)', () {
    test('stampChordAcross lays one tone per consecutive track', () {
      final song = TrackerSong(); // default band, ≥3 channels
      final placed = song.stampChordAcross(0, 0, 60, const [0, 4, 7]);
      expect(placed, 3);
      expect(song.engine.cellAt(0, 0).midi, 60); // C
      expect(song.engine.cellAt(1, 0).midi, 64); // E
      expect(song.engine.cellAt(2, 0).midi, 67); // G
    });

    test('stampChordAcross stops at the last channel (extra tones dropped)',
        () {
      final song = TrackerSong();
      final last = song.channelCount - 1;
      final placed = song.stampChordAcross(last, 0, 60, const [0, 4, 7]);
      expect(placed, 1); // only the root fits
      expect(song.engine.cellAt(last, 0).midi, 60);
    });

    test('stampArpeggio lays the tones down one column at the step', () {
      final song = TrackerSong()..setRows(16);
      final placed = song.stampArpeggio(0, 0, 60, const [0, 4, 7, 12], step: 2);
      expect(placed, 4);
      expect(song.engine.cellAt(0, 0).midi, 60);
      expect(song.engine.cellAt(0, 2).midi, 64);
      expect(song.engine.cellAt(0, 4).midi, 67);
      expect(song.engine.cellAt(0, 6).midi, 72);
      // Rows between the steps stay empty.
      expect(song.engine.cellAt(0, 1).isEmpty, isTrue);
    });

    test('stampArpeggio drops tones past the pattern end', () {
      final song = TrackerSong()..setRows(4);
      final placed = song.stampArpeggio(0, 2, 60, const [0, 4, 7, 12]);
      expect(placed, 2); // rows 2, 3 fit; 4, 5 are past the end
      expect(song.engine.cellAt(0, 3).midi, 64);
    });

    test('chord notes carry the given instrument voice', () {
      final song = TrackerSong();
      song.stampChordAcross(0, 0, 60, const [0, 4, 7], instrument: 3);
      expect(song.engine.cellAt(1, 0).instrument, 3);
    });
  });

  group('renamePattern (song sections)', () {
    test('renames a pattern and trims whitespace', () {
      final song = TrackerSong()..addPattern();
      song.renamePattern(1, '  Chorus  ');
      expect(song.patterns[1].name, 'Chorus');
    });

    test('ignores a blank name and an out-of-range index', () {
      final song = TrackerSong();
      final original = song.patterns[0].name;
      song.renamePattern(0, '   ');
      expect(song.patterns[0].name, original); // unchanged
      song.renamePattern(5, 'Nope'); // no such pattern
      expect(song.patterns.length, 1);
    });
  });

  group('quantizeRowToBeat', () {
    // stepsPerBeat 4, 16 rows: beats at 0, 4, 8, 12.
    test('snaps back to the nearest earlier beat', () {
      expect(quantizeRowToBeat(1, 0.2, 4, 16), 0);
      expect(quantizeRowToBeat(5, 0.0, 4, 16), 4);
    });

    test('a late hit rounds forward to the next beat', () {
      expect(quantizeRowToBeat(2, 0.5, 4, 16), 4); // 2.5/4 -> 1 -> 4
      expect(quantizeRowToBeat(6, 0.0, 4, 16), 8); // 6/4 -> 2 -> 8
    });

    test('the last beat wraps to the pattern start', () {
      expect(quantizeRowToBeat(15, 0.9, 4, 16), 0); // 15.9/4 -> 4 -> 16 % 16
    });

    test('no-op when there is no beat grid', () {
      expect(quantizeRowToBeat(3, 0.4, 1, 16), 3);
      expect(quantizeRowToBeat(3, 0.4, 4, 0), 3);
    });
  });

  group('swing / groove', () {
    test('setSwing re-times off-beat step onsets and clamps the range', () {
      final song = TrackerSong(timing: const TrackerTiming(rows: 8));
      expect(song.timing.swing, 0.0);
      // Straight: every step falls on its exact grid slot.
      final straightOdd = song.timing.stepOnsetMs(1);
      expect(straightOdd, closeTo(song.timing.stepMs.toDouble(), 0.001));

      song.setSwing(0.5);
      expect(song.timing.swing, 0.5);
      // Off-beats (odd steps) are delayed; even steps stay put.
      expect(
        song.timing.stepOnsetMs(2),
        closeTo(2.0 * song.timing.stepMs, 0.5),
      );
      expect(
        song.timing.stepOnsetMs(1),
        closeTo(1.5 * song.timing.stepMs, 0.5),
      );
      // The loop length is unchanged by swing.
      expect(song.timing.totalMs, 8 * song.timing.stepMs);

      // Clamps above the valid range, and a repeat set is a no-op.
      song.setSwing(5.0);
      expect(song.timing.swing, 0.9);
    });
  });

  group('revoiceChannel — whole-track re-voice', () {
    test(
        'sets the channel default AND clears per-cell instrument refs across '
        'every pattern, so a module-style track (explicit pool refs) actually '
        'switches voice', () {
      final song = TrackerSong();
      // A pool instrument a cell can reference (instrument column = 1) — the
      // shape every imported module has.
      song.instruments.add(const AdditiveInstrument('lead', Instrument.piano));
      song.engine.setCell(0, 0, const TrackerCell(midi: 60, instrument: 1));
      // A second pattern with another ch0 cell that references the pool.
      final p1 = song.addPattern();
      song.selectPattern(p1);
      song.engine.setCell(0, 4, const TrackerCell(midi: 64, instrument: 1));
      song.selectPattern(0);

      const newVoice = AdditiveInstrument('revoiced', Instrument.piano);
      song.revoiceChannel(0, newVoice);

      // Channel default is the new voice.
      expect(song.engine.channels[0].instrument.id, 'revoiced');
      // The current pattern's ch0 cell now falls back to the channel default…
      expect(song.engine.cellAt(0, 0).instrument, 0);
      expect(song.engine.cellAt(0, 0).midi, 60); // pitch preserved
      // …and the NON-current pattern was cleared too.
      song.selectPattern(p1);
      expect(song.engine.cellAt(0, 4).instrument, 0);
      expect(song.engine.cellAt(0, 4).midi, 64);
    });

    test('is a no-op for an out-of-range channel', () {
      final song = TrackerSong();
      const v = AdditiveInstrument('x', Instrument.piano);
      expect(() => song.revoiceChannel(-1, v), returnsNormally);
      expect(() => song.revoiceChannel(999, v), returnsNormally);
    });
  });
}
