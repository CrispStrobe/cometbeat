// lib/core/harmony/chart_to_targets.dart
//
// BB-T5 — grade a player against a REAL chart, so there are not two chart types.
//
// `ChordProgressionEngine` scores live playing against a `ChordChart` of
// `TargetChord`s. Those were hand-written constants; a chart the user actually
// wrote could not be practised against. This projects one onto the other.
//
// ⚠️ IT TOUCHES `chord_progression.dart` NOT AT ALL, which is a deliberate
// departure from the card's "add `ChordChart.fromRealizedBars`". That file is
// hot — it backs a shipped game — and `ChordChart`'s constructor is public and
// const, so the projection can live here and the shipped scorer keeps a
// byte-identical definition. A factory inside it would buy nothing and risk
// something.
//
// 🔴 THE NARROWING IS NOT COSMETIC, AND IT IS THE POINT OF THIS FILE.
// `TargetChord.matches` requires the detector's suffix EXACTLY, and the
// detector knows eight: '' m 7 m7 maj7 sus4 dim aug (`kChordTemplates`). A
// target outside that set can never be emitted by the detector, so it can never
// be hit — the bar would sit there unscorable for the whole exercise. Narrowing
// is therefore mandatory, not a convenience, and every narrowing is reported.
library;

import 'package:comet_beat/core/audio/chord_progression.dart';
import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_playback.dart' show barBeats;
import 'package:comet_beat/core/harmony/chart_score_bridge.dart'
    show BridgeLoss, BridgeResult;
import 'package:comet_beat/core/harmony/chord_spec.dart';
import 'package:comet_beat/core/harmony/form_realizer.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart' show Pitch;

/// The suffixes the live detector can produce. Anything else is unscorable.
///
/// Mirrors `kChordTemplates` in `chroma_analysis.dart`. Duplicated as a NAMED
/// set rather than imported so this file states the contract it depends on: if
/// the detector ever grows a template, this is the line that has to change with
/// it, and a test asserts the two agree.
const kScorableSuffixes = <String>{
  '',
  'm',
  '7',
  'm7',
  'maj7',
  'sus4',
  'dim',
  'aug',
};

/// A chart as something the live scorer can grade against.
///
/// [bars] is the realised timeline, so repeats and chorus counts are already
/// expanded — the player practises what they will hear. Count-in and ending
/// bars carry no target: nobody should be scored on a bar that exists to set
/// the tempo.
BridgeResult<ChordChart> targetsFromRealizedBars(
  List<RealizedBar> bars, {
  required String name,
  required int bpm,
}) {
  final targets = <TargetChord>[];
  final losses = <BridgeLoss>[];

  var beat = 0.0;
  var barNumber = 0;

  for (final bar in bars) {
    final beats = barBeats(bar.meter);
    if (bar.role != BarRole.tune) {
      beat += beats;
      continue;
    }
    barNumber++;

    final chords = bar.chords;
    for (var i = 0; i < chords.length; i++) {
      final chord = chords[i];
      final next = i + 1 < chords.length ? chords[i + 1].beat : beats;
      final span = (next - chord.beat).clamp(0.25, beats);

      final mapped = scorableSuffixFor(chord.chord);
      if (mapped.detail != null) {
        losses.add(
          BridgeLoss(
            barNumber: barNumber,
            symbol: chord.chord.text,
            detail: mapped.detail!,
            keptAs: _rootName(chord.chord.root) + mapped.suffix,
          ),
        );
      }
      targets.add(
        TargetChord(
          rootPc: _pitchClass(chord.chord.root),
          suffix: mapped.suffix,
          startBeat: beat + chord.beat,
          beats: span,
        ),
      );
    }
    beat += beats;
  }

  return BridgeResult(
    ChordChart(name: name, bpm: bpm, chords: targets),
    losses,
  );
}

/// [chart] as a scorable progression, realised with [options].
BridgeResult<ChordChart> targetsFromChart(
  Chart chart, {
  String? name,
  FormOptions options = const FormOptions(countIn: false, ending: false),
}) =>
    targetsFromRealizedBars(
      realizeForm(chart, options: options),
      name: name ?? (chart.title.isEmpty ? 'Chart' : chart.title),
      bpm: chart.tempoBpm < 1 ? 1 : chart.tempoBpm,
    );

/// The detector suffix closest to [spec], and what that cost.
///
/// [detail] is null when the detector can name the chord exactly.
({String suffix, String? detail}) scorableSuffixFor(ChordSpec spec) {
  final dropped = <String>[];

  // The eight templates are triads and plain sevenths. Everything above a
  // seventh, and every alteration, is invisible to the detector — so it is
  // dropped from the TARGET as well, or the player is asked to produce
  // something that can never be recognised.
  if (spec.extension != 0) dropped.add('the ${spec.extension}th');
  if (spec.alterations.isNotEmpty) dropped.add('its alterations');
  if (spec.added.isNotEmpty) dropped.add('its added tones');
  if (spec.bass != null) dropped.add('the slash bass');

  final suffix = switch (spec.triad) {
    // sus2 has no template; sus4 is the nearest sound with a moving fourth.
    ChordTriad.sus2 => () {
        dropped.add('the sus2 (heard as sus4)');
        return 'sus4';
      }(),
    ChordTriad.sus4 => 'sus4',
    ChordTriad.augmented => 'aug',
    ChordTriad.fifthOnly => () {
        dropped.add('the missing third (heard as major)');
        return '';
      }(),
    ChordTriad.diminished => () {
        if (spec.seventh != ChordSeventh.none) {
          dropped.add('the seventh over a diminished triad');
        }
        return 'dim';
      }(),
    ChordTriad.major => switch (spec.seventh) {
        ChordSeventh.none => '',
        ChordSeventh.minor => '7',
        ChordSeventh.major => 'maj7',
        ChordSeventh.sixth => () {
            dropped.add('the sixth (heard as a triad)');
            return '';
          }(),
        ChordSeventh.diminished => () {
            dropped.add('the diminished seventh');
            return '';
          }(),
      },
    ChordTriad.minor => switch (spec.seventh) {
        ChordSeventh.none => 'm',
        ChordSeventh.minor => 'm7',
        ChordSeventh.major => () {
            dropped.add('the major seventh over a minor triad');
            return 'm';
          }(),
        ChordSeventh.sixth => () {
            dropped.add('the sixth (heard as a triad)');
            return 'm';
          }(),
        ChordSeventh.diminished => () {
            dropped.add('the diminished seventh');
            return 'm';
          }(),
      },
  };

  // A minor triad with a flat five is diminished, which the detector DOES know
  // — so it is recognised rather than reported, the same absorption the
  // score bridge makes.
  final flatFive = spec.alterations.contains(ChordAlteration.flatFive);
  if (flatFive && spec.triad == ChordTriad.minor) {
    dropped.remove('its alterations');
    if (spec.seventh == ChordSeventh.none) {
      return (
        suffix: 'dim',
        detail: dropped.isEmpty ? null : _phrase(dropped),
      );
    }
    // m7♭5 is not a template; the detector would hear the diminished triad.
    dropped.add('the seventh over a half-diminished chord');
    return (suffix: 'dim', detail: _phrase(dropped));
  }

  return (suffix: suffix, detail: dropped.isEmpty ? null : _phrase(dropped));
}

String _phrase(List<String> dropped) =>
    '${dropped.join(', ')} cannot be heard by the detector';

int _pitchClass(Pitch pitch) => (pitch.midiNumber % 12 + 12) % 12;

String _rootName(Pitch root) {
  final letter = root.step.name.toUpperCase();
  if (root.alter > 0) return letter + '#' * root.alter;
  if (root.alter < 0) return letter + 'b' * -root.alter;
  return letter;
}
