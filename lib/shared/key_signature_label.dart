// lib/shared/key_signature_label.dart
//
// A key SIGNATURE as text, for song lists and metadata lines.
//
// The deliberate choice here is not to claim a tonality. A `KeySignature` stores
// only `fifths` — two sharps says "D major or B minor", and nothing in the data
// distinguishes them. Printing "D major" for a piece in B minor would be a
// confident lie, so the label shows the relative PAIR ("D / Bm") and lets the
// reader pick. `fifths == 0` is the ambiguous case people already read fluently
// as "no sharps or flats", so it prints "C / Am" too rather than "none".
//
// Pure Dart, no Flutter — unit-testable and usable from a CLI.

/// Major key names by circle-of-fifths position, −7…+7.
const _majors = [
  'C♭', 'G♭', 'D♭', 'A♭', 'E♭', 'B♭', 'F', // −7 … −1
  'C', // 0
  'G', 'D', 'A', 'E', 'B', 'F♯', 'C♯', // +1 … +7
];

/// The relative minor for each of [_majors], same order.
const _minors = [
  'A♭m', 'E♭m', 'B♭m', 'Fm', 'Cm', 'Gm', 'Dm', // −7 … −1
  'Am', // 0
  'Em', 'Bm', 'F♯m', 'C♯m', 'G♯m', 'D♯m', 'A♯m', // +1 … +7
];

/// The lowest and highest [fifths] this can name.
const int kMinFifths = -7;
const int kMaxFifths = 7;

/// `"D / Bm"` for [fifths] — the major key and its relative minor.
///
/// Returns null when [fifths] is outside −7…+7, which no standard signature
/// uses; a caller should then show nothing rather than a wrong key.
String? keySignatureLabel(int fifths) {
  if (fifths < kMinFifths || fifths > kMaxFifths) return null;
  final i = fifths - kMinFifths;
  return '${_majors[i]} / ${_minors[i]}';
}

/// Just the major name (`"D"`), for somewhere too narrow for the pair.
///
/// Prefer [keySignatureLabel] — this one silently picks a side of an ambiguity
/// the data does not resolve.
String? majorKeyName(int fifths) {
  if (fifths < kMinFifths || fifths > kMaxFifths) return null;
  return _majors[fifths - kMinFifths];
}

/// A metronome mark as `"♩=120"`, or a dotted/other beat unit spelled out.
///
/// [bpm] is rounded — a stored 119.99999 from a MusicXML round-trip should read
/// as 120, not as false precision.
String tempoLabel(double bpm) => '♩=${bpm.round()}';
