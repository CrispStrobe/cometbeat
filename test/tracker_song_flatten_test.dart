// A tracker song is its patterns in play order, not the one on screen.
//
// `TrackerSong.channels` is the editing view — the pattern currently loaded into
// the engine. Two converters read it as though it were the song, so everything
// after the first pattern vanished, and because a one-pattern fixture makes the
// two identical, every existing test agreed with them.
//
// These use a genuinely multi-pattern song, which is the only shape that can
// tell the two apart.

import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/core/interop/tracker_song_flatten.dart';
import 'package:flutter_test/flutter_test.dart';

const _rows = 4;

/// One channel of [midis], one note per row, `null` = an empty (ringing) row.
List<TrackerCell> _col(List<int?> midis) => [
      for (final m in midis)
        if (m == null) TrackerCell.empty else TrackerCell(midi: m),
    ];

/// A song of [patterns] (each a single channel's rows), played in [order].
TrackerSong _song(List<List<int?>> patterns, {List<int>? order}) {
  final pats = <TrackerPattern>[
    for (var i = 0; i < patterns.length; i++)
      TrackerPattern(
        name: i.toString().padLeft(2, '0'),
        cells: [_col(patterns[i])],
      ),
  ];
  return TrackerSong.fromParts(
    channels: [
      TrackerChannel(
        id: 'lead',
        instrument: kTrackerInstruments.first.build(),
        rows: _rows,
        cells: pats.first.cells.first,
      ),
    ],
    timing: const TrackerTiming(rows: _rows),
    patterns: pats,
    order: order ?? [for (var i = 0; i < patterns.length; i++) i],
  );
}

List<int?> _midisOf(TrackerChannel channel) =>
    [for (final cell in channel.cells) cell.midi];

/// Every pattern's note numbers, for proving a read left the song alone.
String _snapshot(TrackerSong song) => [
      for (final pattern in song.patterns)
        [for (final col in pattern.cells) col.map((c) => c.midi).toList()],
    ].toString();

void main() {
  test('every pattern in the order is included, in order', () {
    final song = _song([
      [60, 61, 62, 63],
      [64, 65, 66, 67],
      [68, 69, 70, 71],
    ]);

    final channels = trackerChannelsAcrossOrder(song);
    expect(channels, hasLength(1));
    expect(_midisOf(channels.first), [
      60, 61, 62, 63, //
      64, 65, 66, 67, //
      68, 69, 70, 71, //
    ]);
    expect(trackerRowsAcrossOrder(song), 12);
  });

  test('a pattern played twice appears twice', () {
    // The order list is a playlist, not a set — an A-B-A song is three
    // patterns long even though it holds two.
    const abaOrder = [0, 1, 0];
    final song = _song(
      [
        [60, null, null, null],
        [67, null, null, null],
      ],
      order: abaOrder,
    );

    expect(trackerRowsAcrossOrder(song), 12);
    expect(
      _midisOf(trackerChannelsAcrossOrder(song).first).whereType<int>(),
      [60, 67, 60],
    );
  });

  test('a pattern left out of the order is left out of the song', () {
    const skipsTheMiddle = [0, 2];
    final song = _song(
      [
        [60, null, null, null],
        [99, null, null, null], // never played
        [67, null, null, null],
      ],
      order: skipsTheMiddle,
    );

    expect(
      _midisOf(trackerChannelsAcrossOrder(song).first).whereType<int>(),
      [60, 67],
      reason: 'an unplayed pattern is not part of the song',
    );
  });

  test('an order entry pointing at no pattern is skipped, not fatal', () {
    // An order list can outlive the pattern it points at (delete a pattern,
    // load an older file). Dropping the song on the floor would be worse than
    // dropping the entry.
    const withDeadEntries = [0, 7, -1, 0];
    final song = _song(
      [
        [60, null, null, null],
      ],
      order: withDeadEntries,
    );

    expect(
      _midisOf(trackerChannelsAcrossOrder(song).first).whereType<int>(),
      [60, 60],
    );
  });

  test('the flattened channel keeps its identity and instrument', () {
    final song = _song([
      [60, null, null, null],
      [62, null, null, null],
    ]);
    final flat = trackerChannelsAcrossOrder(song).first;
    expect(flat.id, 'lead');
    expect(flat.instrument, isNotNull);
    expect(flat.cells, hasLength(8));
  });

  test('reading a song does not modify it', () {
    // A converter is a reader. The first cut of this called `syncCurrent()` to
    // pick up unsaved grid edits, which WRITES the engine's cells back into the
    // pattern — mutating the document on the way past. Live edits are still
    // included; they are read from the engine instead.
    final song = _song([
      [60, 61, 62, 63],
      [64, 65, 66, 67],
    ]);
    final before = _snapshot(song);
    trackerChannelsAcrossOrder(song);
    expect(_snapshot(song), before);
  });

  test('a song whose patterns are const cell lists still flattens', () {
    // `TrackerSong.fromParts` is the module-importer entry point and test
    // fixtures reach for `const` cell lists, which are UNMODIFIABLE. Writing to
    // them throws outright, so a reader that mutates fails here and nowhere
    // else — which is exactly how this escaped the first time.
    final song = TrackerSong.fromParts(
      channels: [
        TrackerChannel(
          id: 'lead',
          instrument: kTrackerInstruments.first.build(),
          rows: 2,
          cells: const [TrackerCell(midi: 60), TrackerCell.empty],
        ),
      ],
      timing: const TrackerTiming(rows: 2),
      patterns: [
        TrackerPattern(
          name: '00',
          cells: const [
            [TrackerCell(midi: 60), TrackerCell.empty],
          ],
        ),
        TrackerPattern(
          name: '01',
          cells: const [
            [TrackerCell(midi: 67), TrackerCell.empty],
          ],
        ),
      ],
      order: const [0, 1],
    );

    final channels = trackerChannelsAcrossOrder(song);
    expect(
      _midisOf(channels.first).whereType<int>(),
      [60, 67],
      reason: 'both patterns, and no write to an unmodifiable list',
    );
  });

  test('a single-pattern song is unchanged — the case that hid the bug', () {
    final song = _song([
      [60, 62, 64, 65],
    ]);
    expect(_midisOf(trackerChannelsAcrossOrder(song).first), [60, 62, 64, 65]);
    expect(trackerRowsAcrossOrder(song), _rows);
  });
}
