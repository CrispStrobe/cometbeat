// lib/features/games/composition/score_analysis_view.dart
//
// A COMPUTED AnaVis: feed it any real Score and it runs the crisp_notation
// analysis engine (analyze()) and shows the harmony — the detected key, each
// chord coloured by its function (tonic = home, subdominant = away, dominant =
// tension) and labelled with its roman numeral, and the cadences that close the
// phrases. Unlike the hand-authored FormAnalysisView/HarmonyAnalysisView, this
// reads the notes and works it out, so it can analyse a lesson example, a Song
// Book song, or (later) the child's own composition.
//
// One "detail dial" serves everyone: colours-only for young children, +roman
// numerals & cadence names for learners, +chord symbols & non-chord tones for
// experts.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/games/widgets/playing_staff.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/midi_pitch.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart' hide Key;
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

/// A score of one block chord (whole note) per measure, from midi note numbers.
Score blockChordScore(List<List<int>> chords) => Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(4, 4),
      measures: [
        for (final c in chords)
          Measure([
            NoteElement(
              pitches: [for (final m in c) pitchFromMidi(m)],
              duration: const NoteDuration(DurationBase.whole),
            ),
          ]),
      ],
    );

/// Built-in progressions to show a computed analysis on (language-neutral roman
/// titles). C major throughout, tonic-heavy so the key is detected reliably.
final List<(String, Score)> kAnalysisExamples = [
  (
    'I – IV – V – I',
    blockChordScore([
      [60, 64, 67],
      [65, 69, 72],
      [67, 71, 74],
      [60, 64, 67],
    ]),
  ),
  (
    'I – vi – ii – V – I',
    blockChordScore([
      [60, 64, 67],
      [69, 72, 76],
      [62, 65, 69],
      [67, 71, 74],
      [60, 64, 67],
    ]),
  ),
  (
    'I – V – vi – IV',
    blockChordScore([
      [60, 64, 67],
      [67, 71, 74],
      [69, 72, 76],
      [65, 69, 72],
    ]),
  ),
];

/// How much analytical detail to show — the "for kids and for experts" dial.
enum AnalysisDepth {
  /// Colours only (home / away / tension). For pre-readers.
  colours,

  /// + roman numerals and cadence names.
  learner,

  /// + chord symbols and non-chord tones.
  expert,
}

Color _functionColor(HarmonicFunction f) => switch (f) {
      HarmonicFunction.tonic => const Color(0xFF59A14F), // green — home
      HarmonicFunction.subdominant => const Color(0xFF4E79A7), // blue — away
      HarmonicFunction.dominant => const Color(0xFFF28E2B), // orange — tension
    };

String _functionName(AppLocalizations l, HarmonicFunction f, bool kid) {
  if (kid) {
    return switch (f) {
      HarmonicFunction.tonic => l.funcTonicKid,
      HarmonicFunction.subdominant => l.funcSubdominantKid,
      HarmonicFunction.dominant => l.funcDominantKid,
    };
  }
  return switch (f) {
    HarmonicFunction.tonic => l.funcTonic,
    HarmonicFunction.subdominant => l.funcSubdominant,
    HarmonicFunction.dominant => l.funcDominant,
  };
}

String _cadenceName(AppLocalizations l, CadenceType t) => switch (t) {
      CadenceType.authentic => l.cadenceAuthentic,
      CadenceType.half => l.cadenceHalf,
      CadenceType.plagal => l.cadencePlagal,
      CadenceType.deceptive => l.cadenceDeceptive,
    };

/// A card that analyses [score] and renders its harmony at the given [depth].
class ScoreAnalysisView extends StatefulWidget {
  const ScoreAnalysisView({
    super.key,
    required this.score,
    this.title,
    this.depth = AnalysisDepth.learner,
    this.showDepthDial = true,
  });

  final Score score;
  final String? title;
  final AnalysisDepth depth;

  /// Show the kids/learner/expert selector inside the card.
  final bool showDepthDial;

  @override
  State<ScoreAnalysisView> createState() => _ScoreAnalysisViewState();
}

class _ScoreAnalysisViewState extends State<ScoreAnalysisView> {
  final _pb = ScorePlayback();
  late ScoreAnalysis _analysis = analyze(widget.score);
  late AnalysisDepth _depth = widget.depth;
  int? _playing;

  @override
  void didUpdateWidget(ScoreAnalysisView old) {
    super.didUpdateWidget(old);
    if (old.score != widget.score) _analysis = analyze(widget.score);
    if (old.depth != widget.depth) _depth = widget.depth;
  }

  @override
  void dispose() {
    _pb.dispose();
    super.dispose();
  }

  void _playChord(int segIndex, List<int> midis) {
    setState(() => _playing = segIndex);
    context.read<AudioService>().playChordSequence([midis]);
  }

  void _playWhole() {
    setState(() => _playing = null);
    final chords = [
      for (final s in _analysis.segments)
        if (s.hasChord) [for (final p in s.pitches) p.midiNumber],
    ];
    if (chords.isNotEmpty) {
      context.read<AudioService>().playChordSequence(chords);
    }
  }

  String _keyName(AppLocalizations l) {
    final k = _analysis.key;
    final letter = k.tonic.step.name.toUpperCase();
    final alter = k.tonic.alter;
    final acc = alter > 0 ? '♯' * alter : (alter < 0 ? '♭' * -alter : '');
    return '$letter$acc ${k.isMajor ? l.modeMajor : l.modeMinor}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final kid = _depth == AnalysisDepth.colours;
    final segs = _analysis.segments;
    // A cadence marker per resolving segment index.
    final cadenceAt = {for (final c in _analysis.cadences) c.segmentIndex: c};

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title ?? l10n.analysisHarmonyHeading,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.vpn_key, size: 16),
                  label: Text(_keyName(l10n)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: PlayingStaffView(
                    score: widget.score,
                    controller: _pb,
                    theme: kidsScoreTheme,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Function-coloured chord blocks, one per segment.
            SizedBox(
              height: 58,
              child: Row(
                children: [
                  for (var i = 0; i < segs.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _SegmentBlock(
                          segment: segs[i],
                          depth: _depth,
                          highlighted: _playing == i,
                          onTap: segs[i].hasChord
                              ? () => _playChord(
                                    i,
                                    [
                                      for (final p in segs[i].pitches)
                                        p.midiNumber,
                                    ],
                                  )
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Cadence markers under the resolving blocks (learner+).
            if (!kid && cadenceAt.isNotEmpty)
              Row(
                children: [
                  for (var i = 0; i < segs.length; i++)
                    Expanded(
                      child: cadenceAt[i] == null
                          ? const SizedBox.shrink()
                          : Column(
                              children: [
                                Icon(
                                  Icons.arrow_drop_up,
                                  size: 16,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                Text(
                                  _cadenceName(l10n, cadenceAt[i]!.type),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                    ),
                ],
              ),
            const SizedBox(height: 10),
            _legend(l10n, theme, kid),
            const SizedBox(height: 12),
            // Wrap so the play button + depth dial never overflow a phone.
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _playWhole,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.formAnalysisPlayWhole),
                ),
                if (widget.showDepthDial) _depthDial(l10n),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(AppLocalizations l10n, ThemeData theme, bool kid) {
    final used = <HarmonicFunction>[];
    for (final s in _analysis.segments) {
      final f = s.function;
      if (f != null && !used.contains(f)) used.add(f);
    }
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final f in used)
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
                _functionName(l10n, f, kid),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
      ],
    );
  }

  Widget _depthDial(AppLocalizations l10n) => SegmentedButton<AnalysisDepth>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [
          ButtonSegment(
            value: AnalysisDepth.colours,
            label: Text(l10n.analysisDepthKids),
          ),
          ButtonSegment(
            value: AnalysisDepth.learner,
            label: Text(l10n.analysisDepthLearner),
          ),
          ButtonSegment(
            value: AnalysisDepth.expert,
            label: Text(l10n.analysisDepthExpert),
          ),
        ],
        selected: {_depth},
        onSelectionChanged: (s) => setState(() => _depth = s.first),
      );
}

class _SegmentBlock extends StatelessWidget {
  const _SegmentBlock({
    required this.segment,
    required this.depth,
    required this.highlighted,
    this.onTap,
  });

  final HarmonicSegment segment;
  final AnalysisDepth depth;
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final f = segment.function;
    final color =
        f == null ? scheme.surfaceContainerHighest : _functionColor(f);
    final onColor = f == null ? scheme.onSurfaceVariant : Colors.white;

    final label =
        depth == AnalysisDepth.colours ? '' : (segment.roman?.symbol ?? '·');
    final sub = depth == AnalysisDepth.expert ? segment.chord?.symbol : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: highlighted
                ? Border.all(color: scheme.onSurface, width: 3)
                : null,
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: onColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    if (sub != null)
                      Text(
                        sub,
                        style: TextStyle(
                          color: onColor.withValues(alpha: 0.9),
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
