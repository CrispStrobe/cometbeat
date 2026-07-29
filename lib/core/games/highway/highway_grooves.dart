// lib/core/games/highway/highway_grooves.dart
//
// The Beat Highway's GROOVE LADDER.
//
// The first cut reused the Drum Kit's four starter presets and it was a bad
// exercise: every one of them runs hats on every eighth at 92 bpm, which on a
// touchscreen means three hat taps a second on top of kick and snare before
// you have played a single bar. That is not a beginner's first beat, and four
// of them is not a repertoire.
//
// So this is a ladder, not a menu:
//
//   level 1  kick and snare only, on the beat — 60 bpm
//   level 2  a backbeat, still no hat
//   level 3  hats on the QUARTERS (one per beat), the first three-limb pattern
//   level 4  hats on the eighths — the classic groove, once the hands are ready
//   level 5  off-beat hats, shuffles, half-time, and the busier patterns
//
// Tempo is per groove and deliberately slow at the bottom: a beat you can play
// at 60 teaches more than one you can watch at 92. The player can push it up
// with the tempo control, which is the right way round.
//
// Names are plain descriptions of the pattern or the genre, never a brand.
//
// Pure Dart, unit-tested in test/highway_grooves_test.dart.

import 'package:comet_beat/core/audio/synth.dart' show Drum;

/// One playable groove: a row of steps per kit piece, `x` = hit, `.` = rest.
/// One EIGHTH per character, so sixteen characters is two bars of 4/4.
class HighwayGroove {
  const HighwayGroove({
    required this.name,
    required this.level,
    required this.bpm,
    required this.rows,
  });

  final String name;

  /// 1 = the first beat anyone plays … 5 = needs three independent limbs.
  final int level;

  /// The tempo this groove is *learnable* at, not the fastest it can go.
  final double bpm;

  final Map<Drum, String> rows;

  /// The pattern as booleans, for the chart builder.
  Map<Drum, List<bool>> get steps => {
        for (final e in rows.entries)
          e.key: [for (final c in e.value.split('')) c == 'x'],
      };
}

/// The ladder, easiest first.
const List<HighwayGroove> kHighwayGrooves = [
  // --- level 1: two limbs, on the beat -------------------------------------
  HighwayGroove(
    name: 'Kick on every beat',
    level: 1,
    bpm: 60,
    rows: {Drum.kick: 'x.x.x.x.x.x.x.x.'},
  ),
  HighwayGroove(
    name: 'Kick and snare',
    level: 1,
    bpm: 60,
    rows: {
      Drum.kick: 'x...x...x...x...',
      Drum.snare: '..x...x...x...x.',
    },
  ),
  HighwayGroove(
    name: 'Snare on 2 and 4',
    level: 1,
    bpm: 64,
    rows: {
      Drum.kick: 'x.......x.......',
      Drum.snare: '....x.......x...',
    },
  ),
  HighwayGroove(
    name: 'Heartbeat',
    level: 1,
    bpm: 60,
    rows: {
      Drum.kick: 'xx......xx......',
      Drum.snare: '....x.......x...',
    },
  ),

  // --- level 2: a backbeat, still two limbs --------------------------------
  HighwayGroove(
    name: 'Backbeat',
    level: 2,
    bpm: 70,
    rows: {
      Drum.kick: 'x...x...x...x...',
      Drum.snare: '....x.......x...',
    },
  ),
  HighwayGroove(
    name: 'Double kick, one snare',
    level: 2,
    bpm: 70,
    rows: {
      Drum.kick: 'x..x....x..x....',
      Drum.snare: '....x.......x...',
    },
  ),
  HighwayGroove(
    name: 'Pickup snare',
    level: 2,
    bpm: 70,
    rows: {
      Drum.kick: 'x...x...x...x...',
      Drum.snare: '....x......xx...',
    },
  ),
  HighwayGroove(
    name: 'Waltz',
    level: 2,
    bpm: 72,
    rows: {
      Drum.kick: 'x.....x.....',
      Drum.snare: '..x.x...x.x.',
    },
  ),
  HighwayGroove(
    name: 'Marching',
    level: 2,
    bpm: 76,
    rows: {
      Drum.kick: 'x...x...x...x...',
      Drum.snare: 'x.x.x.x.x.x.x.x.',
    },
  ),

  // --- level 3: three limbs, hat on the QUARTERS ---------------------------
  HighwayGroove(
    name: 'Hat on the beat',
    level: 3,
    bpm: 72,
    rows: {
      Drum.kick: 'x...x...x...x...',
      Drum.snare: '....x.......x...',
      Drum.hat: 'x.x.x.x.x.x.x.x.',
    },
  ),
  HighwayGroove(
    name: 'Slow rock',
    level: 3,
    bpm: 70,
    rows: {
      Drum.kick: 'x.....x.x.....x.',
      Drum.snare: '....x.......x...',
      Drum.hat: 'x.x.x.x.x.x.x.x.',
    },
  ),
  HighwayGroove(
    name: 'Half-time',
    level: 3,
    bpm: 72,
    rows: {
      Drum.kick: 'x.......x.......',
      Drum.snare: '........x.......',
      Drum.hat: 'x.x.x.x.x.x.x.x.',
    },
  ),
  HighwayGroove(
    name: 'Four on the floor',
    level: 3,
    bpm: 76,
    rows: {
      Drum.kick: 'x.x.x.x.x.x.x.x.',
      Drum.snare: '....x.......x...',
      Drum.hat: '..x...x...x...x.',
    },
  ),
  HighwayGroove(
    name: 'Tom groove',
    level: 3,
    bpm: 72,
    rows: {
      Drum.kick: 'x...x...x...x...',
      Drum.snare: '....x.......x...',
      Drum.tom: '..x...x...x...x.',
    },
  ),

  // --- level 4: the classic eighth-note grooves ----------------------------
  HighwayGroove(
    name: 'Eighth hats',
    level: 4,
    bpm: 80,
    rows: {
      Drum.kick: 'x...x...x...x...',
      Drum.snare: '....x.......x...',
      Drum.hat: 'xxxxxxxxxxxxxxxx',
    },
  ),
  HighwayGroove(
    name: 'Rock',
    level: 4,
    bpm: 84,
    rows: {
      Drum.kick: 'x...x...x...x...',
      Drum.snare: '..x...x...x...x.',
      Drum.hat: 'xxxxxxxxxxxxxxxx',
    },
  ),
  HighwayGroove(
    name: 'Pop',
    level: 4,
    bpm: 84,
    rows: {
      Drum.kick: 'x.....x.x.....x.',
      Drum.snare: '....x.......x...',
      Drum.hat: 'xxxxxxxxxxxxxxxx',
    },
  ),
  HighwayGroove(
    name: 'Driving eighths',
    level: 4,
    bpm: 88,
    rows: {
      Drum.kick: 'x.x.x.x.x.x.x.x.',
      Drum.snare: '....x.......x...',
      Drum.hat: 'xxxxxxxxxxxxxxxx',
    },
  ),
  HighwayGroove(
    name: 'Crash on one',
    level: 4,
    bpm: 80,
    rows: {
      Drum.kick: 'x...x...x...x...',
      Drum.snare: '....x.......x...',
      Drum.hat: '..x...x...x...x.',
      Drum.crash: 'x...............',
    },
  ),

  // --- level 5: independence -----------------------------------------------
  HighwayGroove(
    name: 'Off-beat hats',
    level: 5,
    bpm: 80,
    rows: {
      Drum.kick: 'x...x...x...x...',
      Drum.snare: '....x.......x...',
      Drum.hat: '.x.x.x.x.x.x.x.x',
    },
  ),
  HighwayGroove(
    name: 'Shuffle',
    level: 5,
    bpm: 76,
    rows: {
      Drum.kick: 'x..x..x..x..',
      Drum.snare: '...x.....x..',
      Drum.hat: 'x.xx.xx.xx.x',
    },
  ),
  HighwayGroove(
    name: 'Syncopated kick',
    level: 5,
    bpm: 80,
    rows: {
      Drum.kick: 'x..x.x..x..x.x..',
      Drum.snare: '....x.......x...',
      Drum.hat: 'x.x.x.x.x.x.x.x.',
    },
  ),
  HighwayGroove(
    name: 'Ghost snares',
    level: 5,
    bpm: 76,
    rows: {
      Drum.kick: 'x...x...x...x...',
      Drum.snare: '..x.x..x..x.x...',
      Drum.hat: 'x.x.x.x.x.x.x.x.',
    },
  ),
  HighwayGroove(
    name: 'Train',
    level: 5,
    bpm: 84,
    rows: {
      Drum.kick: 'x...x...x...x...',
      Drum.snare: 'xxxxxxxxxxxxxxxx',
    },
  ),
  HighwayGroove(
    name: 'Bossa feel',
    level: 5,
    bpm: 76,
    rows: {
      Drum.kick: 'x..x..x.x..x..x.',
      Drum.rim: '..x..x..x..x..x.',
      Drum.hat: 'x.x.x.x.x.x.x.x.',
    },
  ),
  HighwayGroove(
    name: 'Reggae one-drop',
    level: 5,
    bpm: 74,
    rows: {
      Drum.kick: '....x.......x...',
      Drum.snare: '....x.......x...',
      Drum.hat: '..x...x...x...x.',
    },
  ),
  HighwayGroove(
    name: 'Funk sixteenths',
    level: 5,
    bpm: 72,
    rows: {
      Drum.kick: 'x..x..x...x.x...',
      Drum.snare: '....x.......x...',
      Drum.hat: 'xxxxxxxxxxxxxxxx',
    },
  ),
  HighwayGroove(
    name: 'Tom march',
    level: 5,
    bpm: 78,
    rows: {
      Drum.kick: 'x...x...x...x...',
      Drum.tom: '..x.x...x.x.....',
      Drum.snare: '....x.......x...',
      Drum.crash: 'x...............',
    },
  ),
];
