// lib/features/games/guitar/strum_toy_screen.dart
//
// "Strum Toy" — a free creative jam (docs/PLAN.md toy mechanics). Pick an open
// chord, then swipe across the strings to strum it (down = low→high, up =
// high→low) or tap a single string to pluck it. No scoring, no pressure — an
// air-guitar built on the guitar tuning.
//
// The synth plays one sound at a time, so a strum is voiced as an
// arpeggio-into-block-chord (AudioService.playArpeggioThenChord) rather than
// six ringing strings.

// Material also exports `Step`; partitura's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/services.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/features/games/note_reading/note_colors.dart';
import 'package:klang_universum/features/games/note_reading/note_names.dart';
import 'package:klang_universum/features/games/widgets/game_app_bar.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

/// An open-chord shape: a fret per string in low→high order (E A D G B e);
/// null = a muted (unplayed) string.
class _Shape {
  const _Shape(this.name, this.frets);
  final String name;
  final List<int?> frets; // length 6, low → high
}

const _chords = <_Shape>[
  _Shape('C', [null, 3, 2, 0, 1, 0]),
  _Shape('G', [3, 2, 0, 0, 0, 3]),
  _Shape('D', [null, null, 0, 2, 3, 2]),
  _Shape('Em', [0, 2, 2, 0, 0, 0]),
  _Shape('Am', [null, 0, 2, 2, 1, 0]),
];

class StrumToyScreen extends StatefulWidget {
  const StrumToyScreen({super.key});

  @override
  State<StrumToyScreen> createState() => _StrumToyScreenState();
}

/// Test handle onto the toy (the state class is private).
@visibleForTesting
abstract interface class StrumToyTester {
  String get chordName;
  void debugStrum({required bool down});
}

class _StrumToyScreenState extends State<StrumToyScreen>
    implements StrumToyTester {
  static final _tuning = Tuning.standardGuitar; // [e4,b3,g3,d3,a2,e2]

  _Shape _chord = _chords.first;
  final Set<int> _lit = {}; // lanes currently flashing
  int _litToken = 0;

  @override
  String get chordName => _chord.name;

  /// MIDI note sounding on lane [lane] (0 = low E … 5 = high e), or null if the
  /// string is muted in the current chord.
  int? _laneMidi(int lane) {
    final fret = _chord.frets[lane];
    if (fret == null) return null;
    // Lane 0 (low) → tuning.strings[5]; lane 5 (high) → tuning.strings[0].
    return _tuning.strings[5 - lane].midiNumber + fret;
  }

  // The open string's letter (guitarists label strings by their open note).
  Step _laneStep(int lane) => _tuning.strings[5 - lane].step;

  void _selectChord(_Shape shape) => setState(() => _chord = shape);

  void _pluck(int lane) {
    final midi = _laneMidi(lane);
    if (midi == null) return;
    context.read<AudioService>().playMidiNote(midi);
    _flash({lane});
  }

  void _strum({required bool down}) {
    final lanes = [
      for (var l = 0; l < 6; l++)
        if (_laneMidi(l) != null) l,
    ];
    if (lanes.isEmpty) return;
    final ordered = down ? lanes : lanes.reversed.toList();
    context
        .read<AudioService>()
        .playArpeggioThenChord([for (final l in ordered) _laneMidi(l)!]);
    _flash(lanes.toSet());
  }

  void _flash(Set<int> lanes) {
    final token = ++_litToken;
    setState(() {
      _lit
        ..clear()
        ..addAll(lanes);
    });
    Future.delayed(const Duration(milliseconds: 220), () {
      if (!mounted || token != _litToken) return;
      setState(_lit.clear);
    });
  }

  @override
  void debugStrum({required bool down}) => _strum(down: down);

  // Keyboard: 1–5 pick a chord, space/down = down-strum, up = up-strum.
  static final _digits = <LogicalKeyboardKey, int>{
    LogicalKeyboardKey.digit1: 0,
    LogicalKeyboardKey.digit2: 1,
    LogicalKeyboardKey.digit3: 2,
    LogicalKeyboardKey.digit4: 3,
    LogicalKeyboardKey.digit5: 4,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final chordIdx = _digits[event.logicalKey];
    if (chordIdx != null && chordIdx < _chords.length) {
      _selectChord(_chords[chordIdx]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _strum(down: true);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _strum(down: false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameStrumToy),
      body: SafeArea(
        child: Focus(
          autofocus: true,
          onKeyEvent: _onKey,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final shape in _chords)
                      ChoiceChip(
                        label: Text(
                          shape.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        selected: _chord == shape,
                        onSelected: (_) => _selectChord(shape),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragEnd: (d) {
                    final v = d.primaryVelocity ?? 0;
                    if (v.abs() > 60) _strum(down: v > 0);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Column(
                      children: [
                        // Strings drawn low (thick) at the top, high at the
                        // bottom — strum by swiping down or up across them.
                        for (var lane = 5; lane >= 0; lane--)
                          Expanded(
                            child: _StringBar(
                              step: _laneStep(lane),
                              muted: _chord.frets[lane] == null,
                              fret: _chord.frets[lane],
                              thickness: 1.5 + lane * 0.8,
                              lit: _lit.contains(lane),
                              onTap: () => _pluck(lane),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  l10n.strumToyHint,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StringBar extends StatelessWidget {
  const _StringBar({
    required this.step,
    required this.muted,
    required this.fret,
    required this.thickness,
    required this.lit,
    required this.onTap,
  });

  final Step step;
  final bool muted;
  final int? fret;
  final double thickness;
  final bool lit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = muted ? scheme.outlineVariant : pitchClassColor(step);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              muted ? '×' : noteNameFor(context, step),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: muted ? scheme.outline : color,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                height: lit ? thickness * 2.4 : thickness,
                decoration: BoxDecoration(
                  color: muted
                      ? scheme.outlineVariant
                      : (lit ? color : color.withValues(alpha: 0.75)),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow:
                      lit ? [BoxShadow(color: color, blurRadius: 12)] : null,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 28,
            child: Text(
              muted ? '' : '$fret',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
