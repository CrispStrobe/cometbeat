// lib/core/harmony/style_spec.dart
//
// BB-A2 — a style is DATA, so adding one is content work, not code work.
//
// The point of this file is that "swing", "bossa" and "ballad" differ only in
// values here. Nothing downstream branches on a style id: the bass generator
// reads a `BassMode`, the drum generator reads a `RolePattern`, and neither
// knows what the style is called. A style that needs new CODE is a signal the
// model is short a mechanism — that finding is worth more than the style.
//
// TWO DELIBERATE CHOICES, both of which keep styles transposable and reusable:
//
//   * A pattern is expressed RELATIVE TO THE HARMONY — attack points, a voicing
//     slot, an accent — never absolute pitches. A comp pattern that named MIDI
//     notes would only fit one chord.
//   * Everything is per INTENSITY LEVEL (0..3). A chart's last chorus lifts by
//     asking for a higher level, not by a separate "loud" style, which is how
//     you end up with six styles that are really two.
library;

/// Who is playing. Roles are fixed because the generators are written per role;
/// a style chooses which ones it uses and what they play.
enum StyleRole { drums, bass, comp, pad, perc }

/// How the bass moves. An enum rather than a pattern because a bass line is
/// generated from the harmony (root, next root, approach), not stamped out.
enum BassMode {
  /// The root, on the downbeat.
  root,

  /// Root and fifth alternating — the country/polka backbone.
  rootFive,

  /// Half notes: two to the bar.
  twoFeel,

  /// Quarter notes that walk into the next chord.
  walking,

  /// One held note under everything.
  pedal,

  /// Broken chord tones.
  arpeggiated,

  /// The syncopated son/salsa figure.
  tumbao,

  /// Low-high-middle-high, the keyboard left hand.
  alberti,
}

/// One attack in a role's pattern.
///
/// [beat] is in QUARTER-note beats from the bar start, matching the chart clock
/// (see `barBeats` in chart_playback.dart) so a pattern reads the same in 4/4
/// and 6/8 rather than needing a per-meter rewrite.
class StyleHit {
  const StyleHit({
    required this.beat,
    required this.voice,
    this.velocity = 0.8,
    this.duration = 1.0,
  });

  /// Quarter-note beats from the start of the bar.
  final double beat;

  /// 0..1, scaled into the renderer's range by the caller.
  final double velocity;

  /// What this hit plays, interpreted BY ROLE — a drum voice index for
  /// `StyleRole.drums`, a voicing slot for comp roles. Deliberately not typed
  /// per role: one pattern type keeps the validator and the codec single.
  ///
  /// REQUIRED rather than defaulting to 0, because 0 is the kick: a drum hit
  /// that simply omitted it would read as "unspecified" when it actually means
  /// "kick", and `avoid_redundant_argument_values` would strip every `_kick`
  /// out of the style data the moment anyone ran `dart fix`.
  final int voice;

  /// How long it sounds, in quarter-note beats. Comp and pad care; drums do not.
  final double duration;

  @override
  String toString() =>
      'StyleHit($beat, v$voice, ${velocity.toStringAsFixed(2)})';
}

/// What one role plays in one bar at one intensity.
class RolePattern {
  const RolePattern({this.hits = const [], this.bassMode});

  final List<StyleHit> hits;

  /// Set for [StyleRole.bass] only; the hits are then ignored and the line is
  /// generated. Null for every other role.
  final BassMode? bassMode;

  bool get isEmpty => hits.isEmpty && bassMode == null;

  /// The latest beat this pattern touches, for the bar-overrun check.
  double get lastBeat => hits.isEmpty
      ? 0
      : hits.map((h) => h.beat + h.duration).reduce((a, b) => a > b ? a : b);
}

/// One intensity level: what every role plays.
class StyleLevel {
  const StyleLevel({required this.roles});

  final Map<StyleRole, RolePattern> roles;

  RolePattern? operator [](StyleRole role) => roles[role];
}

/// A playing style.
class StyleSpec {
  const StyleSpec({
    required this.id,
    required this.name,
    required this.levels,
    this.swing = 0,
    this.meters = const [4],
    this.tempoRange = const (60, 220),
    this.kickPattern,
  });

  /// Stable id, stored in `Chart.styleId`.
  final String id;

  /// Display name. Not localised: style names are proper nouns in music
  /// ("Bossa", "Swing"), the same way a chord symbol is not localised.
  final String name;

  /// Intensity 0..3. A style must supply every level it claims; the validator
  /// checks that rather than letting a missing level fall back silently.
  final List<StyleLevel> levels;

  /// Swing as a CONTINUOUS ratio, 0 = straight, 1 = full triplet. A boolean
  /// would make "a little behind" unrepresentable, which is most real swing.
  final double swing;

  /// Meters this style fits, as the numerator of a /4 meter. A bossa in 3 is
  /// not a bossa.
  final List<int> meters;

  final (int min, int max) tempoRange;

  /// Optional label for the kick feel, carried for the UI only.
  final String? kickPattern;

  StyleLevel levelAt(int intensity) =>
      levels[intensity.clamp(0, levels.length - 1)];

  bool fitsMeter(int beats) => meters.contains(beats);
  bool fitsTempo(int bpm) => bpm >= tempoRange.$1 && bpm <= tempoRange.$2;
}

/// What a style got wrong, named precisely enough to fix.
class StyleProblem {
  const StyleProblem(this.field, this.detail);

  /// e.g. `levels[2].drums.hits[3].beat`
  final String field;
  final String detail;

  @override
  String toString() => '$field: $detail';
}

/// Checks a style against the invariants the generators assume.
///
/// A malformed style must be caught HERE, with the offending field named,
/// rather than producing a bar that silently overruns or a level that silently
/// falls back — both of which sound like a bug in the band, not in the data.
List<StyleProblem> validateStyle(StyleSpec style) {
  final problems = <StyleProblem>[];

  if (style.id.trim().isEmpty) {
    problems.add(const StyleProblem('id', 'must not be empty'));
  }
  if (style.levels.isEmpty) {
    problems.add(const StyleProblem('levels', 'a style needs at least one'));
  }
  if (style.swing < 0 || style.swing > 1) {
    problems.add(StyleProblem('swing', '${style.swing} is outside 0..1'));
  }
  if (style.meters.isEmpty) {
    problems.add(const StyleProblem('meters', 'a style must fit some meter'));
  }
  if (style.tempoRange.$1 > style.tempoRange.$2) {
    problems.add(
      StyleProblem(
        'tempoRange',
        '${style.tempoRange.$1} > ${style.tempoRange.$2}',
      ),
    );
  }

  // The WIDEST meter the style claims. A pattern is written for the longest bar
  // and TRUNCATED to whatever the actual bar is, so nothing in it is ever dead
  // code — which is what validating against the longest checks.
  //
  // ⚠️ Truncation is a judgement the author makes, and the validator cannot
  // make it for them: a plain pulse survives being cut to three beats, a bossa
  // clave does not. That is exactly why `straight` claims 2..7 and every
  // characterful style claims one meter. Caught here by my own data — the first
  // draft wrote 4-beat patterns under `meters: [2,3,4,5,6,7]`.
  final longestBar =
      style.meters.isEmpty ? 4 : style.meters.reduce((a, b) => a > b ? a : b);

  for (var i = 0; i < style.levels.length; i++) {
    final level = style.levels[i];
    if (level.roles.isEmpty) {
      problems.add(StyleProblem('levels[$i]', 'has no roles'));
      continue;
    }
    for (final entry in level.roles.entries) {
      final role = entry.key;
      final pattern = entry.value;
      final where = 'levels[$i].${role.name}';

      if (role == StyleRole.bass && pattern.bassMode == null) {
        problems.add(StyleProblem(where, 'the bass role needs a bassMode'));
      }
      if (role != StyleRole.bass && pattern.bassMode != null) {
        problems.add(
          StyleProblem(where, 'bassMode is only meaningful on the bass role'),
        );
      }

      for (var h = 0; h < pattern.hits.length; h++) {
        final hit = pattern.hits[h];
        final at = '$where.hits[$h]';
        if (hit.beat < 0) {
          problems.add(StyleProblem('$at.beat', '${hit.beat} is negative'));
        }
        if (hit.beat >= longestBar) {
          problems.add(
            StyleProblem(
              '$at.beat',
              '${hit.beat} does not fit a $longestBar-beat bar',
            ),
          );
        }
        if (hit.duration <= 0) {
          problems.add(
            StyleProblem('$at.duration', '${hit.duration} must be positive'),
          );
        }
        if (hit.velocity < 0 || hit.velocity > 1) {
          problems.add(
            StyleProblem('$at.velocity', '${hit.velocity} is outside 0..1'),
          );
        }
        if (hit.voice < 0) {
          problems.add(StyleProblem('$at.voice', '${hit.voice} is negative'));
        }
      }
    }
  }
  return problems;
}
