// test/loop_tracker_drum_interop_test.dart
//
// D1 (direct Tracker <-> Loop) + D2 (Tracker -> Drum Kit).
//
// D1's point is that the old routes DETOURED: Loop -> Score -> Tracker had to
// engrave the loop first, and Tracker -> Tab -> Loop fret-mapped every pitch
// onto six strings — right for a guitar part, nonsense for a drum channel. So
// the tests here are about what the direct route keeps that the detour lost:
// exact pitches at any range, chords, and velocity.
//
// The fixtures spell out every grid parameter, including ones that match the
// default — these tests are about grid ratios, so an implicit stepsPerBeat
// would hide the case under test.
// ignore_for_file: avoid_redundant_argument_values
//
// D2's point is that `beat_to_tracker.dart` was one-way. The headline test is
// therefore `beat -> song -> beat` IDENTITY, which is the only thing that keeps
// the two encodings from drifting apart — a drum channel encodes its drum in
// the channel id AND (sometimes) in the note number, and it is easy to change
// one side and not the other.

import 'package:comet_beat/core/audio/beat_to_tracker.dart';
import 'package:comet_beat/core/audio/loop_engine.dart'
    show LoopTiming, PatternCell;
import 'package:comet_beat/core/audio/synth.dart' show Drum, Instrument;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/core/interop/drum_tracker.dart';
import 'package:comet_beat/core/interop/loop_tracker.dart';
import 'package:comet_beat/core/services/beat_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

const _piano = AdditiveInstrument('p', Instrument.piano);

TrackerChannel _channel(List<TrackerCell> cells, {String id = 'lead'}) =>
    TrackerChannel(
      id: id,
      instrument: _piano,
      rows: cells.length,
      cells: cells,
    );

SharedBeat _beat() => SharedBeat(
      rows: {
        Drum.kick: [true, false, false, false, true, false, false, false],
        Drum.snare: [false, false, true, false, false, false, true, false],
        Drum.hat: [true, true, true, true, true, true, true, true],
      },
      tempoBpm: 96,
      swing: 0.2,
      source: 'drumkit',
    );

void main() {
  group('D1 — tracker channel -> loop cells', () {
    test('a note plus its trailing empty rows is one cell', () {
      const timing = TrackerTiming(rows: 8, stepsPerBeat: 2);
      final channel = _channel(const [
        TrackerCell(midi: 60),
        TrackerCell.empty,
        TrackerCell(midi: 64),
        TrackerCell.empty,
        TrackerCell.empty,
        TrackerCell.empty,
        TrackerCell(midi: 67),
        TrackerCell.empty,
      ]);
      final out = loopCellsFromTrackerChannel(channel, timing);
      expect(out.cells.map((c) => c.midis).toList(), [
        [60],
        [64],
        [67],
      ]);
      expect(out.cells.map((c) => c.steps).toList(), [2, 4, 2]);
    });

    test('pitches are EXACT at any range — the Tab detour could not do this',
        () {
      // A bass note below the guitar's low E and a note above the 20th fret
      // both had nowhere to go through a fretboard.
      const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
      final channel = _channel(const [
        TrackerCell(midi: 24), // C1, below any guitar string
        TrackerCell.empty,
        TrackerCell(midi: 100), // E7, above the fretboard
        TrackerCell.empty,
      ]);
      final out = loopCellsFromTrackerChannel(channel, timing);
      expect(out.cells[0].midis, [24]);
      expect(out.cells[1].midis, [100]);
    });

    test('a rest run becomes a rest cell', () {
      const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
      final channel = _channel(const [
        TrackerCell.empty,
        TrackerCell.empty,
        TrackerCell(midi: 60),
        TrackerCell.empty,
      ]);
      final out = loopCellsFromTrackerChannel(channel, timing);
      expect(out.cells.first.midis, isNull);
      expect(out.cells.first.steps, 2);
    });

    test('the volume column becomes cell velocity', () {
      const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
      final channel = _channel(const [
        TrackerCell(midi: 60, volume: 0.4),
        TrackerCell.empty,
        TrackerCell(midi: 62),
        TrackerCell.empty,
      ]);
      final out = loopCellsFromTrackerChannel(channel, timing);
      expect(out.cells[0].velocity, 0.4);
      expect(out.cells[1].velocity, 1.0);
    });

    test('a finer tracker grid halves cleanly and says it quantized', () {
      // stepsPerBeat 4 = sixteenths; the loop grid is eighths, so two tracker
      // rows become one loop step.
      const timing = TrackerTiming(rows: 8, stepsPerBeat: 4);
      final channel = _channel(const [
        TrackerCell(midi: 60),
        TrackerCell.empty,
        TrackerCell.empty,
        TrackerCell.empty,
        TrackerCell(midi: 62),
        TrackerCell.empty,
        TrackerCell.empty,
        TrackerCell.empty,
      ]);
      final out = loopCellsFromTrackerChannel(channel, timing);
      expect(out.cells.map((c) => c.steps).toList(), [2, 2]);
      expect(out.annotations.docMeta['stepsPerBeat'], 4);
    });

    test('a sixteenth with nowhere to land is reported, not silently dropped',
        () {
      const timing = TrackerTiming(rows: 4, stepsPerBeat: 4);
      final channel = _channel(const [
        TrackerCell(midi: 60),
        TrackerCell(midi: 62), // a single 16th row
        TrackerCell(midi: 64),
        TrackerCell(midi: 65),
      ]);
      final out = loopCellsFromTrackerChannel(channel, timing);
      expect(out.cells, hasLength(4), reason: 'notes must not vanish');
      expect(
        out.report.approximated.any((s) => s.contains('snapped')),
        isTrue,
      );
    });

    test('the channel FX chain and envelopes are reported as lost', () {
      const timing = TrackerTiming(rows: 2, stepsPerBeat: 2);
      final channel = TrackerChannel(
        id: 'lead',
        instrument: _piano,
        rows: 2,
        cells: const [TrackerCell(midi: 60), TrackerCell.empty],
        effects: const [TrackerChannelEffect.reverb],
      );
      final out = loopCellsFromTrackerChannel(channel, timing);
      expect(out.report.lost.any((s) => s.contains('insert effects')), isTrue);
    });
  });

  group('D1 — loop cells -> tracker channel', () {
    test('round-trips exactly on a matching grid', () {
      const timing = TrackerTiming(rows: 8, stepsPerBeat: 2);
      const cells = [
        PatternCell(midis: [60], steps: 2),
        PatternCell(steps: 2),
        PatternCell(midis: [67], steps: 4),
      ];
      final channel = trackerChannelFromLoopCells(
        cells,
        timing,
        id: 'x',
        instrument: _piano,
      ).channel;
      final back = loopCellsFromTrackerChannel(channel, timing).cells;
      expect(back.map((c) => c.midis).toList(), [
        [60],
        null,
        [67],
      ]);
      expect(back.map((c) => c.steps).toList(), [2, 2, 4]);
    });

    test('velocity survives the round trip', () {
      const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
      const cells = [
        PatternCell(midis: [60], steps: 2, velocity: 0.3),
        PatternCell(midis: [64], steps: 2),
      ];
      final channel = trackerChannelFromLoopCells(
        cells,
        timing,
        id: 'x',
        instrument: _piano,
      ).channel;
      final back = loopCellsFromTrackerChannel(channel, timing).cells;
      expect(back[0].velocity, closeTo(0.3, 1e-9));
      expect(back[1].velocity, 1.0);
    });

    test('one channel truncates a chord and says so', () {
      const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
      const cells = [
        PatternCell(midis: [60, 64, 67], steps: 4),
      ];
      final out = trackerChannelFromLoopCells(
        cells,
        timing,
        id: 'x',
        instrument: _piano,
      );
      expect(out.channel.cells.first.midi, 60);
      expect(out.report.lost.any((s) => s.contains('chord notes')), isTrue);
    });

    test('spreading a chord over channels keeps every note', () {
      const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
      const cells = [
        PatternCell(midis: [60, 64, 67], steps: 4),
      ];
      final channels = trackerChannelsFromLoopCells(
        cells,
        timing,
        idPrefix: 'c',
        instrument: _piano,
      );
      expect(channels, hasLength(3));
      expect(
        channels.map((c) => c.cells.first.midi).toList(),
        [60, 64, 67],
      );
    });

    test('the channel is exactly timing.rows long, padded or trimmed', () {
      const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
      final short = trackerChannelFromLoopCells(
        const [
          PatternCell(midis: [60], steps: 2),
        ],
        timing,
        id: 'x',
        instrument: _piano,
      );
      expect(short.channel.cells, hasLength(4));

      final long = trackerChannelFromLoopCells(
        const [
          PatternCell(midis: [60], steps: 16),
        ],
        timing,
        id: 'x',
        instrument: _piano,
      );
      expect(long.channel.cells, hasLength(4));
      expect(long.report.lost.any((s) => s.contains('past the end')), isTrue);
    });

    test('an empty cell list still yields a valid, silent channel', () {
      const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
      final out = trackerChannelFromLoopCells(
        const [],
        timing,
        id: 'x',
        instrument: _piano,
      );
      expect(out.channel.cells, hasLength(4));
      expect(out.channel.hasAnyNote, isFalse);
    });

    test('a partial-bar pattern is flagged — a loop needs a clean length', () {
      const timing = TrackerTiming(rows: 3, stepsPerBeat: 2);
      final channel = _channel(
        const [TrackerCell(midi: 60), TrackerCell.empty, TrackerCell.empty],
      );
      final out = loopCellsFromTrackerChannel(channel, timing);
      final total = out.cells.fold<int>(0, (s, c) => s + c.steps);
      expect(total % LoopTiming.stepsPerBar, isNot(0));
      expect(
        out.report.approximated.any((s) => s.contains('whole bars')),
        isTrue,
      );
    });
  });

  group('D2 — tracker -> drum kit', () {
    test('beat -> song -> beat is IDENTITY', () {
      // The property that keeps the two encodings from drifting apart.
      final beat = _beat();
      final song = drumSongFromBeat(beat);
      final back = sharedBeatFromTrackerSong(song).beat!;

      for (final drum in [Drum.kick, Drum.snare, Drum.hat]) {
        expect(back.rows[drum], beat.rows[drum], reason: '$drum');
      }
      expect(back.tempoBpm, beat.tempoBpm);
      expect(back.swing, beat.swing);
    });

    test('an edit made in the Tracker comes back out', () {
      // The whole reason this direction exists.
      final song = drumSongFromBeat(_beat());
      final kickChannel = song.channels.indexWhere((c) => c.id == 'drum_kick');
      expect(kickChannel, greaterThanOrEqualTo(0));
      song.engine.setCell(kickChannel, 2, const TrackerCell(midi: 0));

      final back = sharedBeatFromTrackerSong(song).beat!;
      expect(back.rows[Drum.kick]![2], isTrue);
      expect(_beat().rows[Drum.kick]![2], isFalse, reason: 'fixture changed');
    });

    test('the channel id is authoritative, not the note number', () {
      // A sample-voiced drum channel plays note 60, which says nothing about
      // WHICH drum it is — only the id does.
      final beat = SharedBeat(
        rows: {
          Drum.snare: [true, false, true, false],
        },
        tempoBpm: 120,
      );
      final song = drumSongFromBeat(beat);
      final back = sharedBeatFromTrackerSong(song).beat!;
      expect(back.rows[Drum.snare], [true, false, true, false]);
    });

    test('a song with no drum channels returns null and explains why', () {
      final song = TrackerSong(timing: const TrackerTiming(rows: 8));
      song.engine.setCell(0, 0, const TrackerCell(midi: 60));
      final out = sharedBeatFromTrackerSong(song);
      expect(out.beat, isNull);
      expect(
        out.report.lost.any((s) => s.contains('no drum channels')),
        isTrue,
      );
    });

    test('a pitched channel alongside drums is reported, not silently dropped',
        () {
      // The realistic case: a user adds a bassline next to their beat.
      final song = drumSongFromBeat(_beat());
      final bassIndex = song.channels.length;
      final mixed = TrackerSong.fromParts(
        channels: [
          ...song.channels,
          TrackerChannel(
            id: 'bass',
            instrument: _piano,
            rows: song.timing.rows,
          ),
        ],
        timing: song.timing,
        // fromParts imports the FIRST pattern's cells into the engine, so an
        // empty pattern list would blank every channel we just built.
        patterns: [
          TrackerPattern(
            name: '00',
            cells: [
              for (final c in song.channels) List.of(c.cells),
              [
                const TrackerCell(midi: 36),
                for (var i = 1; i < song.timing.rows; i++) TrackerCell.empty,
              ],
            ],
          ),
        ],
        order: const [0],
      );
      expect(mixed.channels[bassIndex].hasAnyNote, isTrue);
      final out = sharedBeatFromTrackerSong(mixed);
      expect(out.beat, isNotNull);
      expect(out.report.lost.any((s) => s.contains('pitched channel')), isTrue);
    });

    test('a hand-built percussion channel is still read', () {
      // No `drum_` id, but a PercussionInstrument encoding the drum in the note.
      const cells = [
        TrackerCell(midi: 2), // Drum.values[2]
        TrackerCell.empty,
        TrackerCell(midi: 2),
        TrackerCell.empty,
      ];
      final song = TrackerSong.fromParts(
        channels: [
          TrackerChannel(
            id: 'my beat',
            instrument: const PercussionInstrument('perc'),
            rows: 4,
            cells: cells,
          ),
        ],
        timing: const TrackerTiming(rows: 4, stepsPerBeat: 2),
        patterns: [
          TrackerPattern(name: '00', cells: [List.of(cells)]),
        ],
        order: const [0],
      );
      final out = sharedBeatFromTrackerSong(song);
      expect(out.beat, isNotNull);
      expect(out.beat!.rows[Drum.values[2]], [true, false, true, false]);
    });

    test('per-hit velocity is reported as lost — a beat row is on or off', () {
      final song = drumSongFromBeat(_beat());
      final kick = song.channels.indexWhere((c) => c.id == 'drum_kick');
      song.engine.setCell(kick, 0, const TrackerCell(midi: 0, volume: 0.3));
      final out = sharedBeatFromTrackerSong(song);
      expect(out.report.lost.any((s) => s.contains('velocity')), isTrue);
    });

    test('drumForChannel refuses to guess from a pitched channel', () {
      // A bassline on low MIDI numbers must NOT become a kick pattern.
      final bass = _channel(
        const [TrackerCell(midi: 1), TrackerCell.empty],
        id: 'bass',
      );
      expect(drumForChannel(bass), isNull);
    });
  });
}
