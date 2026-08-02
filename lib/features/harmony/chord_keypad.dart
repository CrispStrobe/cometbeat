// lib/features/harmony/chord_keypad.dart
//
// BB-U2 — chord entry fast enough to be used.
//
// The product metric is taps, not features: a 32-bar tune has to go in inside a
// couple of minutes or nobody enters one. So the common case is ONE tap (pick a
// root, the chord is major) and everything else is two — root, then quality.
// The extras (slash bass, alterations) are a third tap and are deliberately out
// of the way, because they are rare and putting them on the main surface would
// slow the case that matters.
//
// It edits a `ChordSpec` rather than a string, so what the user builds is
// exactly what plays; the symbol shown at the top is `format()` of the live
// spec, which makes the model's canonical spelling visible while typing.
library;

import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_level.dart';
import 'package:comet_beat/core/harmony/chord_spec.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart' show Pitch, Step;
// Material exports a \`Step\` (the Stepper widget's); the musical one is what
// this file is about.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

/// What the keypad returns: a chord, an explicitly empty bar, or nothing.
sealed class ChordKeypadResult {
  const ChordKeypadResult();
}

/// The bar should hold this chord.
class ChordChosen extends ChordKeypadResult {
  const ChordChosen(this.chord);
  final ChordSpec chord;
}

/// The bar should be emptied — which in chart notation means "hold the previous
/// chord", not "silence".
class ChordCleared extends ChordKeypadResult {
  const ChordCleared();
}

/// The seven naturals, in the order a keyboard lays them out.
const _roots = [Step.c, Step.d, Step.e, Step.f, Step.g, Step.a, Step.b];

/// The qualities on the main grid, in rough order of how often a chart uses
/// them. Every one is a single tap once a root is chosen.
/// A quality is a triad, a seventh AND any alteration the NAME already
/// implies. That third field is not decoration: a half-diminished is a MINOR
/// core with a flattened fifth, and `chord_spec.dart` is explicit that it is
/// NOT merged with a diminished seventh. Building `m7b5` as a diminished triad
/// made the keypad hand back `Cdim7` — a different chord (B♭♭, not B♭) — under
/// a button labelled `m7b5`.
const _qualities = <(
  String label,
  ChordTriad triad,
  ChordSeventh seventh,
  Set<ChordAlteration> implied,
)>[
  ('', ChordTriad.major, ChordSeventh.none, {}),
  ('m', ChordTriad.minor, ChordSeventh.none, {}),
  ('7', ChordTriad.major, ChordSeventh.minor, {}),
  ('m7', ChordTriad.minor, ChordSeventh.minor, {}),
  ('maj7', ChordTriad.major, ChordSeventh.major, {}),
  ('6', ChordTriad.major, ChordSeventh.sixth, {}),
  ('m6', ChordTriad.minor, ChordSeventh.sixth, {}),
  ('sus4', ChordTriad.sus4, ChordSeventh.none, {}),
  ('sus2', ChordTriad.sus2, ChordSeventh.none, {}),
  ('7sus4', ChordTriad.sus4, ChordSeventh.minor, {}),
  ('dim', ChordTriad.diminished, ChordSeventh.none, {}),
  ('dim7', ChordTriad.diminished, ChordSeventh.diminished, {}),
  ('m7b5', ChordTriad.minor, ChordSeventh.minor, {ChordAlteration.flatFive}),
  ('aug', ChordTriad.augmented, ChordSeventh.none, {}),
  ('5', ChordTriad.fifthOnly, ChordSeventh.none, {}),
];

/// Every alteration that some quality button implies. Switching quality clears
/// these and re-applies the new one's, so a ♭5 cannot outlive the `m7b5` that
/// brought it — while an alteration the PLAYER chose is left alone, because
/// that one is theirs.
final _impliedByAnyQuality = <ChordAlteration>{
  for (final (_, _, _, implied) in _qualities) ...implied,
};

/// Chord entry for one bar. Returns null if dismissed without choosing.
Future<ChordKeypadResult?> showChordKeypad(
  BuildContext context, {
  ChordSpec? initial,
  ChordSymbolStyle style = ChordSymbolStyle.plain,
  ChartLevel? level,
}) {
  // The dial is read HERE rather than passed down from every call site, so a
  // new caller cannot forget it and silently get the expert keypad.
  final resolved = level ?? context.read<SettingsService>().chartLevel;
  return showModalBottomSheet<ChordKeypadResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) =>
        ChordKeypad(initial: initial, style: style, level: resolved),
  );
}

/// The keypad body. Public so a widget test can drive it directly.
class ChordKeypad extends StatefulWidget {
  const ChordKeypad({
    super.key,
    this.initial,
    this.style = ChordSymbolStyle.plain,
    this.level = ChartLevel.expert,
  });

  final ChordSpec? initial;
  final ChordSymbolStyle style;

  /// How much vocabulary to offer (BB-U6). Defaults to [ChartLevel.expert] so
  /// a caller that has not been taught about the dial still gets the full
  /// keypad — narrowing must be something you ASK for, never a silent default.
  final ChartLevel level;

  @override
  State<ChordKeypad> createState() => _ChordKeypadState();
}

class _ChordKeypadState extends State<ChordKeypad> {
  late Pitch _root;
  late ChordTriad _triad;
  late ChordSeventh _seventh;
  late int _extension;
  late Set<ChordAlteration> _alterations;
  Pitch? _bass;
  var _showExtras = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _root = initial?.root ?? const Pitch(Step.c);
    _triad = initial?.triad ?? ChordTriad.major;
    _seventh = initial?.seventh ?? ChordSeventh.none;
    _extension = initial?.extension ?? 0;
    _alterations = {...?initial?.alterations};
    _bass = initial?.bass;
    // Open the extras drawer when the chord already uses it, so reopening a
    // slash chord does not hide the part that makes it one.
    _showExtras = _bass != null || _alterations.isNotEmpty || _extension != 0;
  }

  ChordSpec get _spec => ChordSpec(
        root: _root,
        triad: _triad,
        seventh: _seventh,
        extension: _extension,
        alterations: _alterations,
        bass: _bass,
      );

  void _setRoot(Step step, int alter) =>
      setState(() => _root = Pitch(step, alter: alter));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The live symbol. Showing `format()` rather than the buttons the
            // user pressed makes the canonical spelling visible while typing.
            Center(
              child: Text(
                _spec.format(style: widget.style),
                key: const Key('chordKeypadPreview'),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _rootRow(),
            const SizedBox(height: 8),
            _accidentalRow(),
            const Divider(height: 24),
            _qualityGrid(),
            const SizedBox(height: 8),
            // Below expert the extensions/alterations/bass panel is not
            // offered. ⚠️ Hiding it does NOT strip anything: `_spec` is built
            // from `_alterations` either way, so a beginner opening someone's
            // `C7b9` keeps the ♭9, sees it in the preview, and hands it back
            // untouched. The vocabulary is narrowed, the chord is not.
            if (widget.level.offersExtras) ...[
              _extrasToggle(theme),
              if (_showExtras) _extras(theme),
            ],
            const Divider(height: 24),
            _actions(),
          ],
        ),
      ),
    );
  }

  Widget _rootRow() => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final step in _roots)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _key(
                  label: step.name.toUpperCase(),
                  selected: _root.step == step,
                  onTap: () => _setRoot(step, _root.alter),
                ),
              ),
            ),
        ],
      );

  Widget _accidentalRow() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final (label, alter) in const [('♭', -1), ('♮', 0), ('♯', 1)])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _key(
                label: label,
                selected: _root.alter == alter,
                onTap: () => _setRoot(_root.step, alter),
                width: 56,
              ),
            ),
        ],
      );

  Widget _qualityGrid() => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final (label, triad, seventh, implied) in _qualities)
            if (widget.level.offersQuality(label))
              _key(
                // A bare major has no suffix, so the button needs a word or it
                // reads as a blank key.
                label: label.isEmpty ? 'maj' : label,
                // Two qualities can share a triad and a seventh and differ only
                // in what they imply (`m7` against `m7b5`), so the implied set
                // is part of the identity check, not just of the tap.
                selected: _triad == triad &&
                    _seventh == seventh &&
                    _alterations.intersection(_impliedByAnyQuality).length ==
                        implied.length &&
                    _alterations.containsAll(implied),
                onTap: () => setState(() {
                  _triad = triad;
                  _seventh = seventh;
                  // Changing the quality drops an extension the new quality
                  // cannot carry, rather than silently keeping a 9 on a triad.
                  if (seventh == ChordSeventh.none) _extension = 0;
                  _alterations
                    ..removeAll(_impliedByAnyQuality)
                    ..addAll(implied);
                }),
                width: 74,
              ),
        ],
      );

  AppLocalizations get l10n => AppLocalizations.of(context)!;

  Widget _extrasToggle(ThemeData theme) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _showExtras = !_showExtras),
          icon: Icon(_showExtras ? Icons.expand_less : Icons.expand_more),
          label: Text(
            _showExtras ? l10n.chartKeypadFewer : l10n.chartKeypadMore,
          ),
        ),
      );

  Widget _extras(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text(l10n.chartKeypadExtension, style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: [
              for (final value in const [0, 9, 11, 13])
                _key(
                  label: value == 0 ? l10n.chartKeypadNone : '$value',
                  selected: _extension == value,
                  // An extension only means anything over a seventh; offering
                  // it on a plain triad would print a chord that is not one.
                  onTap: _seventh == ChordSeventh.none
                      ? null
                      : () => setState(() => _extension = value),
                  width: 64,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(l10n.chartKeypadAlterations, style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (label, alteration) in const [
                ('♭5', ChordAlteration.flatFive),
                ('♯5', ChordAlteration.sharpFive),
                ('♭9', ChordAlteration.flatNine),
                ('♯9', ChordAlteration.sharpNine),
                ('♯11', ChordAlteration.sharpEleven),
                ('♭13', ChordAlteration.flatThirteen),
                ('alt', ChordAlteration.altered),
              ])
                _key(
                  label: label,
                  selected: _alterations.contains(alteration),
                  onTap: () => setState(() {
                    if (!_alterations.remove(alteration)) {
                      _alterations.add(alteration);
                    }
                  }),
                  width: 62,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(l10n.chartKeypadBass, style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _key(
                label: l10n.chartKeypadNone,
                selected: _bass == null,
                onTap: () => setState(() => _bass = null),
                width: 64,
              ),
              for (final step in _roots)
                _key(
                  label: step.name.toUpperCase(),
                  selected: _bass?.step == step && _bass?.alter == 0,
                  onTap: () => setState(() => _bass = Pitch(step)),
                  width: 48,
                ),
              // Flats only: a slash bass is nearly always spelled flat, and
              // offering both doubles the row for a case charts rarely use.
              for (final step in _roots)
                _key(
                  label: '${step.name.toUpperCase()}♭',
                  selected: _bass?.step == step && _bass?.alter == -1,
                  onTap: () => setState(() => _bass = Pitch(step, alter: -1)),
                  width: 56,
                ),
            ],
          ),
        ],
      );

  Widget _actions() => Row(
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(const ChordCleared()),
            child: Text(l10n.chartKeypadClearBar),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.chartCancel),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('chordKeypadApply'),
            onPressed: () => Navigator.of(context).pop(ChordChosen(_spec)),
            child: Text(l10n.chartKeypadSet),
          ),
        ],
      );

  Widget _key({
    required String label,
    required bool selected,
    required VoidCallback? onTap,
    double? width,
  }) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    return SizedBox(
      width: width,
      height: 44,
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Center(
            child: Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: enabled
                    ? (selected ? theme.colorScheme.onPrimaryContainer : null)
                    : theme.disabledColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Replaces the chord of [bar] with [chord], keeping everything else about the
/// bar (its barline, ending number, meter change) intact.
///
/// A bar is more than its chords, and rebuilding it from scratch on every edit
/// would quietly discard the parts the keypad does not touch.
ChartBar barWithChord(ChartBar bar, ChordSpec? chord) => ChartBar(
      chords: chord == null ? const [] : [ChartBeatChord(chord: chord)],
      meterChange: bar.meterChange,
      barline: bar.barline,
      endingNumber: bar.endingNumber,
      navigation: bar.navigation,
      extra: bar.extra,
    );
