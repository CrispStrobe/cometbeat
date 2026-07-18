// lib/features/games/composition/form_analysis_view.dart
//
// AnaVis-style ANALYSIS views: non-quiz teaching surfaces that show the shape of
// music you can see and play.
//
//  • FormAnalysisView — a piece's FORM as a colour-coded section timeline (same
//    letter → same colour) above an engraved staff of the piece. Tap a block to
//    hear that section; play the whole piece. Lesson content for the form
//    concepts (musical_form / song_form) in the textbook.
//  • HarmonyAnalysisView — a chord progression coloured by HARMONIC FUNCTION
//    (tonic = home, subdominant = away, dominant = tension), with a legend. Tap
//    a chord to hear it. Lesson content for harmonic_function / cadences.
//  • AnalysisScreen / AnalysisHubScreen — host one concept's examples, or both
//    families together (the standalone "See the Music" tile).
//
// The examples are OUR OWN short renditions (abstract A/B/C/D motifs; plain
// C-major triads), so there is no melody-licensing risk.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/games/composition/form_timeline.dart';
import 'package:comet_beat/features/games/composition/score_analysis_view.dart';
import 'package:comet_beat/features/games/widgets/playing_staff.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/midi_pitch.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

// ===========================================================================
// FORM
// ===========================================================================

/// A distinct, memorable motif per section letter (mirrors the game's set, so
/// the aural language is consistent across the analysis view and the quiz).
const _motifs = <String, List<int>>{
  'A': [60, 64, 67, 72], // rising arpeggio
  'B': [71, 69, 67, 65], // falling line
  'C': [60, 62, 64, 65], // stepwise up
  'D': [67, 65, 64, 60], // stepwise down
};

const _noteMs = 320;

/// One worked form example: an ordered list of section letters + a localized
/// title (the form's everyday name) and a one-line caption.
class FormExample {
  const FormExample({
    required this.title,
    required this.caption,
    required this.pattern,
  });

  final String Function(AppLocalizations) title;
  final String Function(AppLocalizations) caption;

  /// The section letters in order, e.g. ['A', 'B', 'A'].
  final List<String> pattern;

  /// The (midi, ms) notes of one section.
  List<(int, int)> sectionPhrase(int i) =>
      [for (final m in _motifs[pattern[i]]!) (m, _noteMs)];

  /// The whole piece, section after section.
  List<(int, int)> get wholePhrase =>
      [for (var i = 0; i < pattern.length; i++) ...sectionPhrase(i)];

  /// The score note id of the [k]-th note of section [i] (matches [scoreOf]'s
  /// running 'n0', 'n1', … numbering).
  int _startOf(int i) {
    var s = 0;
    for (var k = 0; k < i; k++) {
      s += _motifs[pattern[k]]!.length;
    }
    return s;
  }

  /// Highlight schedule (one step per note) for section [i].
  List<PlayStep> sectionSteps(int i) {
    final start = _startOf(i);
    return [
      for (var k = 0; k < _motifs[pattern[i]]!.length; k++)
        (ids: {'n${start + k}'}, ms: _noteMs),
    ];
  }

  /// Highlight schedule for the whole piece.
  List<PlayStep> wholeSteps() =>
      [for (var i = 0; i < pattern.length; i++) ...sectionSteps(i)];

  /// An engraved score: one 4/4 bar per section, its motif as four quarters.
  Score scoreOf() {
    var n = 0;
    return Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(4, 4),
      measures: [
        for (final s in pattern)
          Measure([
            for (final m in _motifs[s]!)
              NoteElement.note(
                pitchFromMidi(m),
                const NoteDuration(DurationBase.quarter),
                id: 'n${n++}',
              ),
          ]),
      ],
    );
  }
}

/// A single form example: an engraved staff over a coloured, tappable timeline.
class FormAnalysisView extends StatefulWidget {
  const FormAnalysisView({super.key, required this.example});

  final FormExample example;

  @override
  State<FormAnalysisView> createState() => _FormAnalysisViewState();
}

class _FormAnalysisViewState extends State<FormAnalysisView> {
  int? _playing; // index of the section highlighted right now
  final _pb = ScorePlayback();
  late final Score _score = widget.example.scoreOf();

  @override
  void dispose() {
    _pb.dispose();
    super.dispose();
  }

  void _playSection(int i) {
    setState(() => _playing = i);
    context.read<AudioService>().playSequence(widget.example.sectionPhrase(i));
    _pb.play(widget.example.sectionSteps(i)); // notes light up in time
  }

  void _playWhole() {
    setState(() => _playing = null);
    context.read<AudioService>().playSequence(widget.example.wholePhrase);
    _pb.play(widget.example.wholeSteps());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final sections = [
      for (var i = 0; i < widget.example.pattern.length; i++)
        FormSection(widget.example.pattern[i], highlighted: _playing == i),
    ];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.example.title(l10n),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              widget.example.caption(l10n),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            // The engraved piece: one bar per section, so the staff's barlines
            // line up with the coloured blocks below it.
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: PlayingStaffView(
                    score: _score,
                    controller: _pb,
                    theme: kidsScoreTheme,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            FormTimeline(sections: sections, onTapSection: _playSection),
            const SizedBox(height: 12),
            _PlayRow(onPlayWhole: _playWhole, hint: l10n.formAnalysisHint),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// HARMONY / FUNCTION
// ===========================================================================

/// The three broad jobs a chord can do — the colours of harmonic function.
enum HarmonyFunction { tonic, subdominant, dominant }

Color _functionColor(HarmonyFunction f) => switch (f) {
      HarmonyFunction.tonic => const Color(0xFF59A14F), // green — home / rest
      HarmonyFunction.subdominant => const Color(0xFF4E79A7), // blue — away
      HarmonyFunction.dominant => const Color(0xFFF28E2B), // orange — tension
    };

String _functionName(AppLocalizations l10n, HarmonyFunction f) => switch (f) {
      HarmonyFunction.tonic => l10n.funcTonic,
      HarmonyFunction.subdominant => l10n.funcSubdominant,
      HarmonyFunction.dominant => l10n.funcDominant,
    };

/// One chord in a progression: how it's labelled (a roman numeral), what job it
/// does, and the notes that sound.
class HarmonyChord {
  const HarmonyChord(this.label, this.function, this.midis);

  final String label; // e.g. 'I', 'IV', 'V'
  final HarmonyFunction function;
  final List<int> midis;
}

/// A worked harmony example: a titled, captioned chord progression, optionally
/// ending with a named cadence marked under its final chord.
class HarmonyExample {
  const HarmonyExample({
    required this.title,
    required this.caption,
    required this.chords,
    this.cadence,
  });

  final String Function(AppLocalizations) title;
  final String Function(AppLocalizations) caption;
  final List<HarmonyChord> chords;

  /// Short label for the cadence at the end (null → no cadence marker), shown
  /// as a bracket under the final chord.
  final String Function(AppLocalizations)? cadence;

  /// An engraved score: one 4/4 bar per chord, each a whole-note chord — the
  /// real score the function spans sit under.
  Score scoreOf() {
    var n = 0;
    return Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(4, 4),
      measures: [
        for (final c in chords)
          Measure([
            NoteElement(
              pitches: [for (final m in c.midis) pitchFromMidi(m)],
              duration: const NoteDuration(DurationBase.whole),
              id: 'c${n++}',
            ),
          ]),
      ],
    );
  }

  /// Highlight schedule for playing chord [i] alone.
  List<PlayStep> chordSteps(int i) => [
        (ids: {'c$i'}, ms: _chordMs),
      ];

  /// Highlight schedule for the whole progression.
  List<PlayStep> wholeChordSteps() => [
        for (var i = 0; i < chords.length; i++) (ids: {'c$i'}, ms: _chordMs),
      ];
}

/// Per-chord duration (matches AudioService.playChordSequence's default ms).
const _chordMs = 900;

// C-major triads used across the examples.
const _cI = [60, 64, 67]; // C  E  G
const _cii = [62, 65, 69]; // D  F  A
const _cIV = [65, 69, 72]; // F  A  C
const _cV = [67, 71, 74]; // G  B  D

/// A chord progression coloured by function, with a legend; tap a chord to hear
/// it, or play the whole progression.
class HarmonyAnalysisView extends StatefulWidget {
  const HarmonyAnalysisView({super.key, required this.example});

  final HarmonyExample example;

  @override
  State<HarmonyAnalysisView> createState() => _HarmonyAnalysisViewState();
}

class _HarmonyAnalysisViewState extends State<HarmonyAnalysisView> {
  int? _playing;
  final _pb = ScorePlayback();
  late final Score _score = widget.example.scoreOf();

  @override
  void dispose() {
    _pb.dispose();
    super.dispose();
  }

  void _playChord(int i) {
    setState(() => _playing = i);
    context
        .read<AudioService>()
        .playChordSequence([widget.example.chords[i].midis]);
    _pb.play(widget.example.chordSteps(i));
  }

  void _playWhole() {
    setState(() => _playing = null);
    context.read<AudioService>().playChordSequence(
      [for (final c in widget.example.chords) c.midis],
    );
    _pb.play(widget.example.wholeChordSteps());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // Which functions appear, in first-appearance order → the legend.
    final legend = <HarmonyFunction>[];
    for (final c in widget.example.chords) {
      if (!legend.contains(c.function)) legend.add(c.function);
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.example.title(l10n),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              widget.example.caption(l10n),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            // The engraved progression: one whole-note chord per bar, so the
            // function spans below line up bar-for-bar under each chord.
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: PlayingStaffView(
                    score: _score,
                    controller: _pb,
                    theme: kidsScoreTheme,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  for (var i = 0; i < widget.example.chords.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: _ChordBlock(
                          color: _functionColor(
                            widget.example.chords[i].function,
                          ),
                          label: widget.example.chords[i].label,
                          highlighted: _playing == i,
                          onTap: () => _playChord(i),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Cadence marker: a bracket under the final chord naming the cadence.
            if (widget.example.cadence != null)
              Row(
                children: [
                  for (var i = 0; i < widget.example.chords.length; i++)
                    Expanded(
                      child: i == widget.example.chords.length - 1
                          ? Column(
                              children: [
                                Icon(
                                  Icons.arrow_drop_up,
                                  size: 18,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                Text(
                                  widget.example.cadence!(l10n),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            const SizedBox(height: 10),
            // Legend: colour → function name.
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final f in legend)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: _functionColor(f),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _functionName(l10n, f),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _PlayRow(onPlayWhole: _playWhole, hint: l10n.harmonyAnalysisHint),
          ],
        ),
      ),
    );
  }
}

class _ChordBlock extends StatelessWidget {
  const _ChordBlock({
    required this.color,
    required this.label,
    required this.highlighted,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
            border: highlighted
                ? Border.all(color: scheme.onSurface, width: 3)
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Shared play row
// ===========================================================================

class _PlayRow extends StatelessWidget {
  const _PlayRow({required this.onPlayWhole, required this.hint});

  final VoidCallback onPlayWhole;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // A Column so the (localized, sometimes long) button and hint never
    // overflow a narrow phone: the button sizes to its content, and the hint
    // wraps in the full width beneath it.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.tonalIcon(
          onPressed: onPlayWhole,
          icon: const Icon(Icons.play_arrow),
          label: Text(l10n.formAnalysisPlayWhole),
        ),
        const SizedBox(height: 4),
        Text(
          hint,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ===========================================================================
// Example data + host screens
// ===========================================================================

/// Worked FORM examples per concept id (empty → no "See the form" button).
const Map<String, List<FormExample>> kFormExamples = {
  'musical_form': [
    FormExample(
      title: _ternaryTitle,
      caption: _ternaryCaption,
      pattern: ['A', 'B', 'A'],
    ),
    FormExample(
      title: _rondoTitle,
      caption: _rondoCaption,
      pattern: ['A', 'B', 'A', 'C', 'A'],
    ),
  ],
  'song_form': [
    FormExample(
      title: _verseChorusTitle,
      caption: _verseChorusCaption,
      pattern: ['A', 'B', 'A', 'B'],
    ),
    FormExample(
      title: _aabaTitle,
      caption: _aabaCaption,
      pattern: ['A', 'A', 'B', 'A'],
    ),
  ],
};

/// Worked HARMONY examples per concept id (empty → no "See the harmony" button).
const Map<String, List<HarmonyExample>> kHarmonyExamples = {
  'harmonic_function': [
    HarmonyExample(
      title: _authenticTitle,
      caption: _authenticCaption,
      chords: [
        HarmonyChord('I', HarmonyFunction.tonic, _cI),
        HarmonyChord('IV', HarmonyFunction.subdominant, _cIV),
        HarmonyChord('V', HarmonyFunction.dominant, _cV),
        HarmonyChord('I', HarmonyFunction.tonic, _cI),
      ],
    ),
    HarmonyExample(
      title: _twoFiveTitle,
      caption: _twoFiveCaption,
      chords: [
        HarmonyChord('ii', HarmonyFunction.subdominant, _cii),
        HarmonyChord('V', HarmonyFunction.dominant, _cV),
        HarmonyChord('I', HarmonyFunction.tonic, _cI),
      ],
    ),
  ],
  'cadences': [
    HarmonyExample(
      title: _perfectTitle,
      caption: _perfectCaption,
      cadence: _perfectMark,
      chords: [
        HarmonyChord('IV', HarmonyFunction.subdominant, _cIV),
        HarmonyChord('V', HarmonyFunction.dominant, _cV),
        HarmonyChord('I', HarmonyFunction.tonic, _cI),
      ],
    ),
    HarmonyExample(
      title: _halfTitle,
      caption: _halfCaption,
      cadence: _halfMark,
      chords: [
        HarmonyChord('I', HarmonyFunction.tonic, _cI),
        HarmonyChord('IV', HarmonyFunction.subdominant, _cIV),
        HarmonyChord('V', HarmonyFunction.dominant, _cV),
      ],
    ),
  ],
};

// Const tear-offs (a const map can't hold closures directly).
String _ternaryTitle(AppLocalizations l) => l.formExampleTernary;
String _ternaryCaption(AppLocalizations l) => l.formExampleTernaryCaption;
String _rondoTitle(AppLocalizations l) => l.formExampleRondo;
String _rondoCaption(AppLocalizations l) => l.formExampleRondoCaption;
String _verseChorusTitle(AppLocalizations l) => l.formExampleVerseChorus;
String _verseChorusCaption(AppLocalizations l) =>
    l.formExampleVerseChorusCaption;
String _aabaTitle(AppLocalizations l) => l.formExampleAaba;
String _aabaCaption(AppLocalizations l) => l.formExampleAabaCaption;
String _authenticTitle(AppLocalizations l) => l.harmonyExampleAuthentic;
String _authenticCaption(AppLocalizations l) =>
    l.harmonyExampleAuthenticCaption;
String _twoFiveTitle(AppLocalizations l) => l.harmonyExampleTwoFive;
String _twoFiveCaption(AppLocalizations l) => l.harmonyExampleTwoFiveCaption;
String _perfectTitle(AppLocalizations l) => l.harmonyExamplePerfect;
String _perfectCaption(AppLocalizations l) => l.harmonyExamplePerfectCaption;
String _halfTitle(AppLocalizations l) => l.harmonyExampleHalf;
String _halfCaption(AppLocalizations l) => l.harmonyExampleHalfCaption;
String _perfectMark(AppLocalizations l) => l.cadenceMarkPerfect;
String _halfMark(AppLocalizations l) => l.cadenceMarkHalf;

/// A screen of worked FORM examples for one concept (textbook "See the form").
class FormAnalysisScreen extends StatelessWidget {
  const FormAnalysisScreen({super.key, required this.examples});

  final List<FormExample> examples;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.formAnalysisTitle)),
      body: ListView(
        children: [
          for (final e in examples) FormAnalysisView(example: e),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// A screen of worked HARMONY examples for one concept ("See the harmony").
class HarmonyAnalysisScreen extends StatelessWidget {
  const HarmonyAnalysisScreen({super.key, required this.examples});

  final List<HarmonyExample> examples;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.harmonyAnalysisTitle)),
      body: ListView(
        children: [
          for (final e in examples) HarmonyAnalysisView(example: e),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// The standalone "See the Music" hub: every form example, then every harmony
/// example, in one scrollable page (the composition-module sandbox tile).
class AnalysisHubScreen extends StatelessWidget {
  const AnalysisHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(
            text.toUpperCase(),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.analysisHubTitle)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              l10n.analysisHubIntro,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          header(l10n.analysisHubForm),
          for (final list in kFormExamples.values)
            for (final e in list) FormAnalysisView(example: e),
          header(l10n.analysisHubHarmony),
          for (final list in kHarmonyExamples.values)
            for (final e in list) HarmonyAnalysisView(example: e),
          // Computed by the analysis engine straight from the notes.
          header(l10n.analysisHubComputed),
          for (final (title, score) in kAnalysisExamples)
            ScoreAnalysisView(title: title, score: score),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
