// lib/core/harmony/style_library.dart
//
// BB-A7 — the starter pack: SIX styles, done properly.
//
// Six chosen to span the axes that actually change how the band behaves, not
// six that sound different:
//
//   straight vs swung · two-feel vs four-feel bass · backbeat vs clave-ish ·
//   3/4 vs 4/4 · sparse vs busy comping · slow vs fast.
//
// If a seventh style needs new CODE rather than new values, `style_spec.dart`
// is short a mechanism and THAT is the finding — see its header.
//
// Drum `voice` indices are ordinals of `Drum` in `core/audio/synth.dart`, which
// is an ORDER-LOCKED palette (`interop/drum_tracker.dart` uses the ordinal as a
// MIDI note). They are named here so a reader does not have to count:
//   0 kick · 1 snare · 2 hat · 3 openHat · 4 clap · 5 tom
//   6 rim · 7 cowbell · 8 crash · 9 ride · 10 lowTom · 11 highTom
library;

import 'package:comet_beat/core/harmony/style_spec.dart';

const int _kick = 0;
const int _snare = 1;
const int _hat = 2;
const int _openHat = 3;
const int _rim = 6;
const int _ride = 9;

/// Every built-in style, in the order a picker should show them.
final List<StyleSpec> kStyles = [
  _straight,
  _swing,
  _ballad,
  _bossa,
  _waltz,
  _rock,
];

/// The style for [id], or the default when it is unknown or null.
///
/// Falls back rather than throwing: a chart saved with a style a later build
/// removed must still play.
StyleSpec styleFor(String? id) => kStyles.firstWhere(
      (s) => s.id == id,
      orElse: () => _straight,
    );

/// The style a chart gets when it asks for nothing.
StyleSpec get defaultStyle => _straight;

// ---------------------------------------------------------------------------

/// Straight eighths, four-on-the-floor-ish. The neutral default: it fits almost
/// any chart, which is what an unstyled chart needs.
const _straight = StyleSpec(
  id: 'straight',
  name: 'Straight',
  meters: [2, 3, 4, 5, 6, 7],
  tempoRange: (50, 220),
  levels: [
    // 0 — just the pulse, for reading a chart you do not know yet.
    StyleLevel(
      roles: {
        StyleRole.bass: RolePattern(bassMode: BassMode.root),
        StyleRole.comp: RolePattern(
          hits: [StyleHit(voice: 0, beat: 0, duration: 4, velocity: 0.55)],
        ),
      },
    ),
    // 1 — a kit arrives.
    StyleLevel(
      roles: {
        StyleRole.bass: RolePattern(bassMode: BassMode.twoFeel),
        StyleRole.comp: RolePattern(
          hits: [
            StyleHit(voice: 0, beat: 0, duration: 2, velocity: 0.6),
            StyleHit(voice: 0, beat: 2, duration: 2, velocity: 0.5),
          ],
        ),
        StyleRole.drums: RolePattern(
          hits: [
            StyleHit(voice: _kick, beat: 0, velocity: 0.9),
            StyleHit(beat: 1, voice: _hat, velocity: 0.5),
            StyleHit(beat: 2, voice: _snare),
            StyleHit(beat: 3, voice: _hat, velocity: 0.5),
          ],
        ),
      },
    ),
    // 2 — eighth-note hats, walking bass.
    StyleLevel(
      roles: {
        StyleRole.bass: RolePattern(bassMode: BassMode.walking),
        StyleRole.comp: RolePattern(
          hits: [
            StyleHit(voice: 0, beat: 0, velocity: 0.6),
            StyleHit(voice: 0, beat: 1.5, duration: 0.5, velocity: 0.45),
            StyleHit(voice: 0, beat: 2, velocity: 0.55),
            StyleHit(voice: 0, beat: 3.5, duration: 0.5, velocity: 0.45),
          ],
        ),
        StyleRole.drums: RolePattern(
          hits: [
            StyleHit(voice: _kick, beat: 0, velocity: 0.9),
            StyleHit(beat: 0.5, voice: _hat, velocity: 0.35),
            StyleHit(beat: 1, voice: _hat, velocity: 0.5),
            StyleHit(beat: 1.5, voice: _hat, velocity: 0.35),
            StyleHit(beat: 2, voice: _snare, velocity: 0.85),
            StyleHit(beat: 2.5, voice: _hat, velocity: 0.35),
            StyleHit(beat: 3, voice: _hat, velocity: 0.5),
            StyleHit(beat: 3.5, voice: _hat, velocity: 0.35),
          ],
        ),
      },
    ),
    // 3 — the last chorus.
    StyleLevel(
      roles: {
        StyleRole.bass: RolePattern(bassMode: BassMode.walking),
        StyleRole.comp: RolePattern(
          hits: [
            StyleHit(voice: 0, beat: 0, duration: 0.5, velocity: 0.75),
            StyleHit(voice: 0, beat: 1, duration: 0.5, velocity: 0.6),
            StyleHit(voice: 0, beat: 1.5, duration: 0.5, velocity: 0.7),
            StyleHit(voice: 0, beat: 2.5, duration: 0.5, velocity: 0.65),
            StyleHit(voice: 0, beat: 3, velocity: 0.7),
          ],
        ),
        StyleRole.drums: RolePattern(
          hits: [
            StyleHit(voice: _kick, beat: 0, velocity: 1),
            StyleHit(beat: 0.5, voice: _hat, velocity: 0.4),
            StyleHit(beat: 1, voice: _hat, velocity: 0.55),
            StyleHit(voice: _kick, beat: 1.5, velocity: 0.7),
            StyleHit(beat: 2, voice: _snare, velocity: 0.95),
            StyleHit(beat: 2.5, voice: _hat, velocity: 0.4),
            StyleHit(beat: 3, voice: _hat, velocity: 0.55),
            StyleHit(beat: 3.5, voice: _openHat, velocity: 0.5),
          ],
        ),
      },
    ),
  ],
);

/// Medium swing. The ride carries it, the bass walks, the comp is off the beat.
const _swing = StyleSpec(
  id: 'swing',
  name: 'Swing',
  // 0.67 rather than 1.0: full triplet swing is a hard shuffle, and most swing
  // sits short of it. The continuous ratio is the whole reason it is a double.
  swing: 0.67,
  tempoRange: (70, 260),
  levels: [
    StyleLevel(
      roles: {
        StyleRole.bass: RolePattern(bassMode: BassMode.twoFeel),
        StyleRole.comp: RolePattern(
          hits: [StyleHit(voice: 0, beat: 0, duration: 4, velocity: 0.5)],
        ),
      },
    ),
    StyleLevel(
      roles: {
        StyleRole.bass: RolePattern(bassMode: BassMode.twoFeel),
        StyleRole.comp: RolePattern(
          hits: [
            StyleHit(voice: 0, beat: 1.5, duration: 0.5, velocity: 0.6),
            StyleHit(voice: 0, beat: 3, velocity: 0.55),
          ],
        ),
        StyleRole.drums: RolePattern(
          hits: [
            StyleHit(beat: 0, voice: _ride, velocity: 0.6),
            StyleHit(beat: 1, voice: _ride, velocity: 0.45),
            StyleHit(beat: 1.67, voice: _ride, velocity: 0.4),
            StyleHit(beat: 2, voice: _ride, velocity: 0.55),
            StyleHit(beat: 3, voice: _ride, velocity: 0.45),
            StyleHit(beat: 3.67, voice: _ride, velocity: 0.4),
            StyleHit(beat: 1, voice: _hat, velocity: 0.35),
            StyleHit(beat: 3, voice: _hat, velocity: 0.35),
          ],
        ),
      },
    ),
    StyleLevel(
      roles: {
        StyleRole.bass: RolePattern(bassMode: BassMode.walking),
        StyleRole.comp: RolePattern(
          hits: [
            StyleHit(voice: 0, beat: 0.67, duration: 0.5, velocity: 0.6),
            StyleHit(voice: 0, beat: 1.5, duration: 0.5, velocity: 0.65),
            StyleHit(voice: 0, beat: 2.67, duration: 0.5, velocity: 0.55),
          ],
        ),
        StyleRole.drums: RolePattern(
          hits: [
            StyleHit(beat: 0, voice: _ride, velocity: 0.65),
            StyleHit(beat: 1, voice: _ride, velocity: 0.5),
            StyleHit(beat: 1.67, voice: _ride, velocity: 0.45),
            StyleHit(beat: 2, voice: _ride, velocity: 0.6),
            StyleHit(beat: 3, voice: _ride, velocity: 0.5),
            StyleHit(beat: 3.67, voice: _ride, velocity: 0.45),
            StyleHit(beat: 1, voice: _hat, velocity: 0.4),
            StyleHit(beat: 3, voice: _hat, velocity: 0.4),
            StyleHit(voice: _kick, beat: 2, velocity: 0.35),
          ],
        ),
      },
    ),
    StyleLevel(
      roles: {
        StyleRole.bass: RolePattern(bassMode: BassMode.walking),
        StyleRole.comp: RolePattern(
          hits: [
            StyleHit(voice: 0, beat: 0, duration: 0.5, velocity: 0.7),
            StyleHit(voice: 0, beat: 0.67, duration: 0.5, velocity: 0.6),
            StyleHit(voice: 0, beat: 1.5, duration: 0.5, velocity: 0.75),
            StyleHit(voice: 0, beat: 2.67, duration: 0.5, velocity: 0.65),
            StyleHit(voice: 0, beat: 3.5, duration: 0.5, velocity: 0.6),
          ],
        ),
        StyleRole.drums: RolePattern(
          hits: [
            StyleHit(beat: 0, voice: _ride, velocity: 0.75),
            StyleHit(beat: 1, voice: _ride, velocity: 0.6),
            StyleHit(beat: 1.67, voice: _ride, velocity: 0.55),
            StyleHit(beat: 2, voice: _ride, velocity: 0.7),
            StyleHit(beat: 3, voice: _ride, velocity: 0.6),
            StyleHit(beat: 3.67, voice: _ride, velocity: 0.55),
            StyleHit(beat: 1, voice: _hat, velocity: 0.45),
            StyleHit(beat: 3, voice: _hat, velocity: 0.45),
            StyleHit(beat: 2, voice: _snare, velocity: 0.5),
            StyleHit(voice: _kick, beat: 3.5, velocity: 0.5),
          ],
        ),
      },
    ),
  ],
);

/// Slow, sparse, held. The test of whether the model can express RESTRAINT —
/// most style sets only get louder.
const _ballad = StyleSpec(
  id: 'ballad',
  name: 'Ballad',
  meters: [3, 4],
  tempoRange: (50, 90),
  levels: [
    StyleLevel(
      roles: {
        StyleRole.bass: RolePattern(bassMode: BassMode.pedal),
        StyleRole.pad: RolePattern(
          hits: [StyleHit(voice: 0, beat: 0, duration: 4, velocity: 0.4)],
        ),
      },
    ),
    StyleLevel(
      roles: {
        StyleRole.bass: RolePattern(bassMode: BassMode.root),
        StyleRole.comp: RolePattern(
          hits: [StyleHit(voice: 0, beat: 0, duration: 4, velocity: 0.5)],
        ),
        StyleRole.pad: RolePattern(
          hits: [StyleHit(voice: 0, beat: 0, duration: 4, velocity: 0.35)],
        ),
      },
    ),
    StyleLevel(
      roles: {
        StyleRole.bass: RolePattern(bassMode: BassMode.arpeggiated),
        StyleRole.comp: RolePattern(
          hits: [
            StyleHit(voice: 0, beat: 0, duration: 2, velocity: 0.5),
            StyleHit(voice: 0, beat: 2, duration: 2, velocity: 0.45),
          ],
        ),
        StyleRole.drums: RolePattern(
          hits: [
            StyleHit(voice: _kick, beat: 0, velocity: 0.6),
            StyleHit(beat: 2, voice: _rim, velocity: 0.5),
          ],
        ),
      },
    ),
    StyleLevel(
      roles: {
        StyleRole.bass: RolePattern(bassMode: BassMode.twoFeel),
        StyleRole.comp: RolePattern(
          hits: [
            StyleHit(voice: 0, beat: 0, velocity: 0.6),
            StyleHit(voice: 0, beat: 2, velocity: 0.55),
            StyleHit(voice: 0, beat: 3, velocity: 0.5),
          ],
        ),
        StyleRole.drums: RolePattern(
          hits: [
            StyleHit(voice: _kick, beat: 0, velocity: 0.7),
            StyleHit(beat: 1, voice: _hat, velocity: 0.35),
            StyleHit(beat: 2, voice: _snare, velocity: 0.65),
            StyleHit(beat: 3, voice: _hat, velocity: 0.35),
          ],
        ),
      },
    ),
  ],
);

/// Bossa. Straight eighths, rim on the clave-ish figure, tumbao-ish bass — the
/// case that proves a style is not just "how loud the drums are".
const _bossa = StyleSpec(
  id: 'bossa',
  name: 'Bossa',
  tempoRange: (100, 180),
  levels: [
    StyleLevel(
      roles: {
        StyleRole.bass: RolePattern(bassMode: BassMode.rootFive),
        StyleRole.comp: RolePattern(
          hits: [StyleHit(voice: 0, beat: 0, duration: 4, velocity: 0.45)],
        ),
      },
    ),
    StyleLevel(
      roles: {
        StyleRole.bass: RolePattern(bassMode: BassMode.tumbao),
        StyleRole.comp: RolePattern(
          hits: [
            StyleHit(voice: 0, beat: 0, duration: 1.5, velocity: 0.55),
            StyleHit(voice: 0, beat: 1.5, velocity: 0.5),
            StyleHit(voice: 0, beat: 3, velocity: 0.5),
          ],
        ),
        StyleRole.drums: RolePattern(
          hits: [
            StyleHit(beat: 0, voice: _rim, velocity: 0.6),
            StyleHit(beat: 1.5, voice: _rim, velocity: 0.5),
            StyleHit(beat: 2.5, voice: _rim, velocity: 0.55),
            StyleHit(beat: 0, voice: _hat, velocity: 0.3),
            StyleHit(beat: 1, voice: _hat, velocity: 0.3),
            StyleHit(beat: 2, voice: _hat, velocity: 0.3),
            StyleHit(beat: 3, voice: _hat, velocity: 0.3),
          ],
        ),
      },
    ),
    StyleLevel(
      roles: {
        StyleRole.bass: RolePattern(bassMode: BassMode.tumbao),
        StyleRole.comp: RolePattern(
          hits: [
            StyleHit(voice: 0, beat: 0, duration: 1.5, velocity: 0.6),
            StyleHit(voice: 0, beat: 1.5, velocity: 0.55),
            StyleHit(voice: 0, beat: 3, velocity: 0.55),
          ],
        ),
        StyleRole.drums: RolePattern(
          hits: [
            StyleHit(beat: 0, voice: _rim, velocity: 0.65),
            StyleHit(beat: 1.5, voice: _rim, velocity: 0.55),
            StyleHit(beat: 2.5, voice: _rim, velocity: 0.6),
            StyleHit(voice: _kick, beat: 0, velocity: 0.5),
            StyleHit(voice: _kick, beat: 2, velocity: 0.45),
            StyleHit(beat: 0.5, voice: _hat, velocity: 0.3),
            StyleHit(beat: 1.5, voice: _hat, velocity: 0.3),
            StyleHit(beat: 2.5, voice: _hat, velocity: 0.3),
            StyleHit(beat: 3.5, voice: _hat, velocity: 0.3),
          ],
        ),
      },
    ),
    StyleLevel(
      roles: {
        StyleRole.bass: RolePattern(bassMode: BassMode.tumbao),
        StyleRole.comp: RolePattern(
          hits: [
            StyleHit(voice: 0, beat: 0, duration: 1.5, velocity: 0.7),
            StyleHit(voice: 0, beat: 1.5, velocity: 0.6),
            StyleHit(voice: 0, beat: 2.5, duration: 0.5, velocity: 0.6),
            StyleHit(voice: 0, beat: 3, velocity: 0.6),
          ],
        ),
        StyleRole.drums: RolePattern(
          hits: [
            StyleHit(beat: 0, voice: _rim, velocity: 0.7),
            StyleHit(beat: 1.5, voice: _rim, velocity: 0.6),
            StyleHit(beat: 2.5, voice: _rim, velocity: 0.65),
            StyleHit(voice: _kick, beat: 0, velocity: 0.6),
            StyleHit(voice: _kick, beat: 2, velocity: 0.5),
            StyleHit(beat: 0.5, voice: _hat, velocity: 0.35),
            StyleHit(beat: 1.5, voice: _hat, velocity: 0.35),
            StyleHit(beat: 2.5, voice: _hat, velocity: 0.35),
            StyleHit(beat: 3.5, voice: _openHat, velocity: 0.4),
          ],
        ),
      },
    ),
  ],
);

/// Waltz — the reason `meters` exists. Every hit is inside a 3-beat bar, so the
/// validator would reject anything written for 4/4 here.
const _waltz = StyleSpec(
  id: 'waltz',
  name: 'Waltz',
  meters: [3],
  tempoRange: (60, 200),
  levels: [
    StyleLevel(
      roles: {
        StyleRole.bass: RolePattern(bassMode: BassMode.root),
        StyleRole.comp: RolePattern(
          hits: [StyleHit(voice: 0, beat: 0, duration: 3, velocity: 0.5)],
        ),
      },
    ),
    StyleLevel(
      roles: {
        StyleRole.bass: RolePattern(bassMode: BassMode.root),
        StyleRole.comp: RolePattern(
          hits: [
            StyleHit(voice: 0, beat: 1, velocity: 0.55),
            StyleHit(voice: 0, beat: 2, velocity: 0.5),
          ],
        ),
        StyleRole.drums: RolePattern(
          hits: [
            StyleHit(voice: _kick, beat: 0),
            StyleHit(beat: 1, voice: _hat, velocity: 0.45),
            StyleHit(beat: 2, voice: _hat, velocity: 0.4),
          ],
        ),
      },
    ),
    StyleLevel(
      roles: {
        StyleRole.bass: RolePattern(bassMode: BassMode.rootFive),
        StyleRole.comp: RolePattern(
          hits: [
            StyleHit(voice: 0, beat: 1, velocity: 0.6),
            StyleHit(voice: 0, beat: 2, velocity: 0.55),
          ],
        ),
        StyleRole.drums: RolePattern(
          hits: [
            StyleHit(voice: _kick, beat: 0, velocity: 0.85),
            StyleHit(beat: 1, voice: _snare, velocity: 0.5),
            StyleHit(beat: 2, voice: _snare, velocity: 0.45),
          ],
        ),
      },
    ),
    StyleLevel(
      roles: {
        StyleRole.bass: RolePattern(bassMode: BassMode.arpeggiated),
        StyleRole.comp: RolePattern(
          hits: [
            StyleHit(voice: 0, beat: 0, duration: 0.5, velocity: 0.65),
            StyleHit(voice: 0, beat: 1, velocity: 0.6),
            StyleHit(voice: 0, beat: 2, velocity: 0.6),
          ],
        ),
        StyleRole.drums: RolePattern(
          hits: [
            StyleHit(voice: _kick, beat: 0, velocity: 0.9),
            StyleHit(beat: 1, voice: _snare, velocity: 0.55),
            StyleHit(beat: 2, voice: _snare, velocity: 0.5),
            StyleHit(beat: 2.5, voice: _hat, velocity: 0.4),
          ],
        ),
      },
    ),
  ],
);

/// Rock — backbeat, root-driven bass, the busiest kit. The loud end of the
/// range, so the intensity axis has something to reach.
const _rock = StyleSpec(
  id: 'rock',
  name: 'Rock',
  tempoRange: (80, 200),
  levels: [
    StyleLevel(
      roles: {
        StyleRole.bass: RolePattern(bassMode: BassMode.root),
        StyleRole.comp: RolePattern(
          hits: [StyleHit(voice: 0, beat: 0, duration: 4, velocity: 0.55)],
        ),
      },
    ),
    StyleLevel(
      roles: {
        StyleRole.bass: RolePattern(bassMode: BassMode.root),
        StyleRole.comp: RolePattern(
          hits: [
            StyleHit(voice: 0, beat: 0, duration: 2, velocity: 0.6),
            StyleHit(voice: 0, beat: 2, duration: 2, velocity: 0.55),
          ],
        ),
        StyleRole.drums: RolePattern(
          hits: [
            StyleHit(voice: _kick, beat: 0, velocity: 0.95),
            StyleHit(beat: 1, voice: _snare, velocity: 0.85),
            StyleHit(voice: _kick, beat: 2),
            StyleHit(beat: 3, voice: _snare, velocity: 0.85),
          ],
        ),
      },
    ),
    StyleLevel(
      roles: {
        StyleRole.bass: RolePattern(bassMode: BassMode.rootFive),
        StyleRole.comp: RolePattern(
          hits: [
            StyleHit(voice: 0, beat: 0, velocity: 0.65),
            StyleHit(voice: 0, beat: 1.5, duration: 0.5, velocity: 0.55),
            StyleHit(voice: 0, beat: 2, velocity: 0.6),
            StyleHit(voice: 0, beat: 3.5, duration: 0.5, velocity: 0.55),
          ],
        ),
        StyleRole.drums: RolePattern(
          hits: [
            StyleHit(voice: _kick, beat: 0, velocity: 1),
            StyleHit(beat: 0.5, voice: _hat, velocity: 0.45),
            StyleHit(beat: 1, voice: _snare, velocity: 0.9),
            StyleHit(beat: 1.5, voice: _hat, velocity: 0.45),
            StyleHit(voice: _kick, beat: 2, velocity: 0.85),
            StyleHit(beat: 2.5, voice: _hat, velocity: 0.45),
            StyleHit(beat: 3, voice: _snare, velocity: 0.9),
            StyleHit(beat: 3.5, voice: _hat, velocity: 0.45),
          ],
        ),
      },
    ),
    StyleLevel(
      roles: {
        StyleRole.bass: RolePattern(bassMode: BassMode.rootFive),
        StyleRole.comp: RolePattern(
          hits: [
            StyleHit(voice: 0, beat: 0, duration: 0.5, velocity: 0.75),
            StyleHit(voice: 0, beat: 0.5, duration: 0.5, velocity: 0.6),
            StyleHit(voice: 0, beat: 1.5, duration: 0.5, velocity: 0.7),
            StyleHit(voice: 0, beat: 2, duration: 0.5, velocity: 0.7),
            StyleHit(voice: 0, beat: 3, velocity: 0.7),
          ],
        ),
        StyleRole.drums: RolePattern(
          hits: [
            StyleHit(voice: _kick, beat: 0, velocity: 1),
            StyleHit(beat: 0.5, voice: _hat, velocity: 0.5),
            StyleHit(beat: 1, voice: _snare, velocity: 0.95),
            StyleHit(voice: _kick, beat: 1.5, velocity: 0.7),
            StyleHit(voice: _kick, beat: 2, velocity: 0.9),
            StyleHit(beat: 2.5, voice: _hat, velocity: 0.5),
            StyleHit(beat: 3, voice: _snare, velocity: 0.95),
            StyleHit(beat: 3.5, voice: _openHat, velocity: 0.55),
          ],
        ),
      },
    ),
  ],
);
