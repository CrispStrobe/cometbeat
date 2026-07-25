// Ready-made Drum Kit grooves so a beginner sees how a beat is built. Each
// preset is a full [DrumRowsPattern] on the standard 16-step (2-bar eighth)
// grid the Drum Kit / Loop Mixer share. Authored with [stepRow] so each row
// reads like a drum-machine line: `x` = hit, `.` = rest.
//
// One eighth per step → a bar is 8 steps (beats on 0/2/4/6). These are classic,
// genre-defining patterns (kept generic — no branded kit names).
//
// Pure Dart → unit-tested in test/drum_presets_test.dart.

import 'package:comet_beat/core/audio/loop_engine.dart'
    show DrumRowsPattern, kPatternSteps, stepRow;
import 'package:comet_beat/core/audio/synth.dart' show Drum;

/// A named starter groove.
class DrumPreset {
  const DrumPreset(this.name, this.pattern);

  /// Short display name (English; the screen can localize known ones).
  final String name;
  final DrumRowsPattern pattern;
}

DrumRowsPattern _p(Map<Drum, String> rows) {
  // Every preset row is padded/truncated to the shared grid so a preset is a
  // drop-in for the Drum Kit grid regardless of authored length.
  final built = <Drum, List<bool>>{
    for (final d in Drum.values) d: List<bool>.filled(kPatternSteps, false),
  };
  for (final e in rows.entries) {
    final row = stepRow(e.value);
    for (var i = 0; i < kPatternSteps && i < row.length; i++) {
      built[e.key]![i] = row[i];
    }
  }
  return DrumRowsPattern(built);
}

/// The built-in Drum Kit presets, in menu order.
final List<DrumPreset> kDrumPresets = [
  DrumPreset(
    'Rock',
    _p({
      Drum.kick: 'x...x...x...x...',
      Drum.snare: '..x...x...x...x.',
      Drum.hat: 'xxxxxxxxxxxxxxxx',
    }),
  ),
  DrumPreset(
    'Pop',
    _p({
      Drum.kick: 'x.....x.x.....x.',
      Drum.snare: '..x...x...x...x.',
      Drum.hat: 'x.x.x.x.x.x.x.x.',
    }),
  ),
  DrumPreset(
    'Funk',
    _p({
      Drum.kick: 'x..x..x...x.x...',
      Drum.snare: '..x...x...x...x.',
      Drum.hat: 'xxxxxxxxxxxxxxxx',
      Drum.openHat: '....x.......x...',
    }),
  ),
  DrumPreset(
    'Hip-hop',
    _p({
      Drum.kick: 'x.......x.x.....',
      Drum.snare: '..x...x...x...x.',
      Drum.hat: 'x.x.x.x.x.x.x.x.',
    }),
  ),
  DrumPreset(
    'Disco',
    _p({
      Drum.kick: 'x...x...x...x...',
      Drum.snare: '..x...x...x...x.',
      Drum.openHat: '.x.x.x.x.x.x.x.x',
      Drum.clap: '..x...x...x...x.',
    }),
  ),
  DrumPreset(
    'House',
    _p({
      Drum.kick: 'x...x...x...x...',
      Drum.clap: '..x...x...x...x.',
      Drum.openHat: '.x.x.x.x.x.x.x.x',
    }),
  ),
  DrumPreset(
    'Reggae',
    _p({
      Drum.kick: '....x.......x...',
      Drum.snare: '....x.......x...',
      Drum.hat: '.x.x.x.x.x.x.x.x',
      Drum.rim: '..x...x...x...x.',
    }),
  ),
  DrumPreset(
    'Latin',
    _p({
      Drum.kick: 'x..x..x.x..x..x.',
      Drum.cowbell: 'x.xx.x.xx.x.xx.x',
      Drum.snare: '..x...x...x...x.',
      Drum.tom: '.......x.......x',
    }),
  ),
  DrumPreset(
    'Ballad',
    _p({
      Drum.kick: 'x.......x.......',
      Drum.snare: '....x.......x...',
      Drum.hat: 'x.x.x.x.x.x.x.x.',
      Drum.ride: 'x.x.x.x.x.x.x.x.',
    }),
  ),
  DrumPreset(
    'Marching',
    _p({
      Drum.snare: 'xxx.x.x.xxx.x.x.',
      Drum.kick: 'x...x...x...x...',
      Drum.crash: 'x...............',
    }),
  ),
  DrumPreset(
    'Techno',
    _p({
      Drum.kick: 'x...x...x...x...',
      Drum.openHat: '..x...x...x...x.',
      Drum.clap: '....x.......x...',
      Drum.hat: 'x.x.x.x.x.x.x.x.',
    }),
  ),
  DrumPreset(
    'Trap',
    _p({
      Drum.kick: 'x.....x..x.x....',
      Drum.snare: '........x.......',
      Drum.hat: 'x.xxx.x.x.xxx.x.',
    }),
  ),
  DrumPreset(
    'Drum & bass',
    _p({
      Drum.kick: 'x......x..x.....',
      Drum.snare: '....x.....x...x.',
      Drum.hat: 'x.x.x.x.x.x.x.x.',
    }),
  ),
  DrumPreset(
    'Boom-bap',
    _p({
      Drum.kick: 'x.....x.x.......',
      Drum.snare: '....x.......x...',
      Drum.hat: 'x.x.x.x.x.x.x.x.',
    }),
  ),
  DrumPreset(
    'Reggaeton',
    _p({
      Drum.kick: 'x...x...x...x...',
      Drum.snare: 'x..x..x.x..x..x.',
      Drum.hat: 'x.x.x.x.x.x.x.x.',
    }),
  ),
  DrumPreset(
    'Afrobeat',
    _p({
      Drum.kick: 'x..x...x..x...x.',
      Drum.snare: '....x.......x...',
      Drum.rim: 'x..x.x..x..x.x..',
      Drum.hat: 'xxxxxxxxxxxxxxxx',
    }),
  ),
  DrumPreset(
    'Samba',
    _p({
      Drum.kick: 'x..x..x.x..x..x.',
      Drum.snare: 'x.xx.x.xx.x.xx.x',
      Drum.hat: 'x.x.x.x.x.x.x.x.',
    }),
  ),
  DrumPreset(
    'Bossa nova',
    _p({
      Drum.rim: 'x..x..x.x..x..x.',
      Drum.kick: 'x.....x.x.....x.',
      Drum.hat: 'x.x.x.x.x.x.x.x.',
    }),
  ),
  DrumPreset(
    'Breakbeat',
    _p({
      Drum.kick: 'x.....x.x.......',
      Drum.snare: '....x.......x.x.',
      Drum.hat: 'x.x.x.x.x.x.x.x.',
    }),
  ),
  DrumPreset(
    'Half-time',
    _p({
      Drum.kick: 'x.......x.......',
      Drum.snare: '........x.......',
      Drum.hat: 'x.x.x.x.x.x.x.x.',
    }),
  ),
  DrumPreset(
    'Motown',
    _p({
      Drum.kick: 'x...x...x...x...',
      Drum.snare: '....x.......x...',
      Drum.clap: 'x.x.x.x.x.x.x.x.',
      Drum.hat: 'x.x.x.x.x.x.x.x.',
    }),
  ),
  DrumPreset(
    'Trance',
    _p({
      Drum.kick: 'x...x...x...x...',
      Drum.openHat: '..x...x...x...x.',
      Drum.clap: '....x.......x...',
    }),
  ),
];
