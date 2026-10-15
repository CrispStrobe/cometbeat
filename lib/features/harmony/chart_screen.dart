// lib/features/harmony/chart_screen.dart
//
// BB-U1 / BB-U2 — the chart surface: read it, edit it, hear it.
//
// This is NOT the Score Workshop with chords bolted on, and the difference is
// not cosmetic. The Workshop engraves noteheads on staves and its whole document
// model is a stream of notes; a chart has bars and chord names and no notes at
// all, and it has to stay legible on a music stand across a room. Two surfaces,
// two jobs, one shared harmony engine underneath.
//
// Chord symbols drawn ABOVE A STAFF are a separate feature, and a working one —
// the readers parse them and the layout engraves them. That is for a score that
// happens to carry harmony. This is for harmony that has no score.
library;

import 'dart:async';

import 'package:comet_beat/core/audio/loop_engine.dart' show GrooveSpec;
import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/harmony/band_playback.dart';
import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_analysis.dart';
import 'package:comet_beat/core/harmony/chart_import.dart';
import 'package:comet_beat/core/harmony/chart_playback.dart';
import 'package:comet_beat/core/harmony/chart_share.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:comet_beat/core/harmony/chart_to_groove.dart';
import 'package:comet_beat/core/harmony/chart_transpose.dart';
import 'package:comet_beat/core/harmony/form_realizer.dart';
import 'package:comet_beat/core/harmony/style_library.dart';
import 'package:comet_beat/core/harmony/style_spec.dart' show StyleSpec;
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/chart_store.dart';
import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:comet_beat/features/games/composition/score_analysis_view.dart'
    show AnalysisDepth;
import 'package:comet_beat/features/harmony/chart_analysis_panel.dart';
import 'package:comet_beat/features/harmony/chart_grid_view.dart';
import 'package:comet_beat/features/harmony/chart_library_sheet.dart';
import 'package:comet_beat/features/harmony/chord_keypad.dart';
import 'package:comet_beat/features/harmony/practice_modes.dart';
import 'package:comet_beat/features/harmony/setlist_screen.dart';
import 'package:comet_beat/features/harmony/streamed_band.dart';
import 'package:comet_beat/features/harmony/transpose_sheet.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/mixer_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Something to look at on first open. An empty grid teaches nothing, and a
/// blues is the shortest form that shows sections, repeats and a turnaround.
const kStarterChartText = '''
title: Twelve-Bar Blues
key: C
tempo: 100

[A] x2
| C7 | F7 | C7 | C7 |
| F7 | F7 | C7 | C7 |
| G7 | F7 | C7 | G7 |
''';

class ChartScreen extends StatefulWidget {
  const ChartScreen({super.key, this.initialChart});

  /// Opens on this chart instead of the starter one.
  final Chart? initialChart;

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  late Chart _chart;
  ChartBarRef? _selected;

  /// The name this chart was last opened or saved under, so the library does
  /// not ask for it again.
  String? _name;

  /// How many times through the form. Playback-only, so it is NOT stored on the
  /// chart: it is how you want to practise today, not what the tune is.
  int _choruses = 1;

  /// Sounding and display transposition. Like the chorus count, this is about
  /// the PLAYER rather than the tune, so it lives here and not on the chart —
  /// a chart shared with a trumpeter must not arrive pre-transposed.
  var _transpose = const ChartTransposition();

  /// What the grid shows: the tune plus whatever the reader's instrument and
  /// capo ask for.
  Chart get _printed => displayChart(_chart, _transpose);
  ChartBarRef? _playingBar;

  /// The transport clock. `playMixedTimedChords` renders a WAV and hands it to
  /// the player, so there is no position callback to follow — the highlight is
  /// driven by our own stopwatch started at the same moment.
  Timer? _ticker;
  Stopwatch? _clock;
  ChartPlayback? _playback;

  /// The band's timeline, when the band path is in use. Exactly one of this
  /// and [_playback] is non-null while playing.
  ({List<BandBarSpan> bars, int totalMs})? _band;

  /// BB-T1: the band streamed a window at a time where the platform can, so a
  /// long chart starts in about a second instead of after a whole render, and
  /// playing it again (or after a small edit) reuses what was rendered.
  final _streamed = StreamedBand();

  /// BB-U3 band settings, kept for the next Play and applied live to a
  /// streamed band. Intensity 0–3 (the form's base); swing null = the style's.
  int _intensity = 2;
  double? _swing;

  StyleSpec get _bandStyle {
    final style = styleFor(_chart.styleId);
    final swing = _swing;
    return swing == null ? style : style.withSwing(swing);
  }

  FormOptions get _bandForm => FormOptions(
        choruses: _choruses,
        baseIntensity: _intensity,
        countInBars: _countInBars,
      );

  /// BB-T2 band settings: voices, count-in length and sound, the click.
  Instrument _compVoice = Instrument.piano;
  Instrument _bassVoice = Instrument.piano;
  int _countInBars = 1;
  bool _clickCountIn = false;
  BandClick _click = BandClick.off;

  BandSettings get _bandSettings => BandSettings(
        style: _bandStyle,
        form: _bandForm,
        compInstrument: _compVoice,
        bassInstrument: _bassVoice,
        click: _click,
        clickCountIn: _clickCountIn,
      );

  /// Whether the band in play is the streamed one (live controls work).
  bool _streaming = false;

  /// BB-T3: practice mode — the tune loops and each time round is a pass with
  /// its own tempo, key, fade and drop-outs. Needs the streamed band; the
  /// whole-render fallback plays the tune once, plainly.
  bool _practiceOn = false;
  int _shownPass = 0;
  PracticeConfig _practice = const PracticeConfig();

  /// Applies the current band settings to a streamed band from its next bar.
  void _replanLive({bool tempo = false}) {
    if (!_streaming) return;
    unawaited(
      _streamed.replan(
        chart: tempo ? soundingChart(_chart, _transpose) : null,
        settings: _bandSettings,
      ),
    );
  }

  /// Null until SharedPreferences resolves. Every write goes through
  /// [_persist], which is a no-op until then rather than a queue — losing the
  /// first half-second of edits to a cold start is not a real failure mode, and
  /// a queue would be a second source of truth.
  ChartStore? _store;

  bool get _playing => _ticker != null;

  @override
  void initState() {
    super.initState();
    // The chart the caller asked for, else whatever was on screen last time,
    // else the starter. Restoring beats the starter: coming back to your own
    // half-written tune is the whole point of the working slot.
    _chart = widget.initialChart ?? parseChartText(kStarterChartText).chart;
    unawaited(_restore());
  }

  /// Attaches the store and restores the chart that was on screen last time.
  ///
  /// ⚠️ Guarded, because this runs unawaited from `initState`: on any platform
  /// where the shared_preferences channel is absent — a plain widget test, a
  /// misconfigured host — `getInstance()` THROWS, and an unhandled error in an
  /// unawaited future fails the enclosing test rather than the screen. Losing
  /// persistence is a degraded screen; throwing is a broken one, and the whole
  /// point of the working slot is that it is best-effort.
  Future<void> _restore() async {
    final ChartStore store;
    try {
      store = ChartStore(await SharedPreferences.getInstance());
    } catch (_) {
      return; // no storage on this platform; the screen still works
    }
    if (!mounted) return;
    final working = widget.initialChart == null ? store.readWorking() : null;
    setState(() {
      _store = store;
      if (working != null && !working.isEmpty) _chart = working;
    });
  }

  /// Remembers the chart, so leaving the screen is not destructive.
  ///
  /// Errors are swallowed for the same reason [_restore] guards: a failed
  /// autosave must not take the screen down with it.
  void _persist() {
    final store = _store;
    if (store == null) return;
    unawaited(store.saveWorking(_chart).catchError((_) {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_streamed.stop());
    super.dispose();
  }

  // ---------------------------------------------------------------- transport

  Future<void> _play() async {
    final audio = context.read<AudioService>();
    // BB-U4b: a saved chart joins "recently played".
    final name = _name;
    final store = _store;
    if (name != null && store != null) {
      unawaited(store.markPlayed(name).catchError((_) {}));
    }
    final sounding = soundingChart(_chart, _transpose);
    final style = _bandStyle;
    final form = _bandForm;

    if (await _playStreamed(sounding)) return;
    if (!mounted) return;

    // The band is the real path; the plain one is the fallback. A band that
    // fails to assemble must degrade to something that plays, not to silence.
    final band = renderBand(
      sounding,
      style: style,
      form: form,
      compInstrument: _compVoice,
      bassInstrument: _bassVoice,
    );

    if (band != null) {
      _band = (bars: band.bars, totalMs: band.totalMs);
      _clock = Stopwatch()..start();
      _ticker =
          Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
      setState(() {});
      await audio.playWavBytes(band.wav);
      return;
    }

    final playback = resolveChartPlayback(soundingChart(_chart, _transpose));
    if (playback.isEmpty) return;
    _playback = playback;
    _clock = Stopwatch()..start();
    // 60 Hz would be wasted: the highlight only changes on a bar boundary, and
    // at any sane tempo that is seconds apart.
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
    setState(() {});
    await audio.playMixedTimedChords(
      [playback.comp, playback.bass],
      gains: const [0.85, 0.7],
      clickBeatMs: playback.beatMs,
    );
  }

  /// Plays the band through the window stream. False when streaming is not
  /// available here (or there is no band), so the caller falls back.
  Future<bool> _playStreamed(Chart sounding) async {
    if (!await _streamed.play(
      sounding,
      _bandSettings,
      practice: _practiceOn ? _practice : null,
    )) {
      return false;
    }
    if (!mounted) {
      await _streamed.stop();
      return true;
    }
    _streaming = true;
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
    setState(() {});
    return true;
  }

  void _tick() {
    if (_streaming) {
      _streamed.sync();
      if (_streamed.finished) {
        _stop();
        return;
      }
      // A realised bar carries the DOCUMENT bar it came from, so the highlight
      // lands on the bar the user is looking at even across repeats and loops.
      final source = _streamed.current?.span?.bar.sourceBar;
      final ref =
          source == null ? null : ChartBarRef(source.section, source.bar);
      if (ref != _playingBar || _streamed.pass != _shownPass) {
        setState(() {
          _playingBar = ref;
          _shownPass = _streamed.pass;
        });
      }
      return;
    }

    final clock = _clock;
    if (clock == null) return;
    final ms = clock.elapsedMilliseconds;

    final band = _band;
    if (band != null) {
      if (ms >= band.totalMs) {
        _stop();
        return;
      }
      // A realised bar carries the DOCUMENT bar it came from, so the highlight
      // lands on the bar the user is looking at even across repeats — and a
      // generated bar (count-in, ending) highlights nothing, which is correct.
      final source = bandBarAt(band.bars, ms)?.bar.sourceBar;
      final ref =
          source == null ? null : ChartBarRef(source.section, source.bar);
      if (ref != _playingBar) setState(() => _playingBar = ref);
      return;
    }

    final playback = _playback;
    if (playback == null) return;
    if (ms >= playback.totalMs) {
      _stop();
      return;
    }
    final span = playback.barAt(ms);
    final ref =
        span == null ? null : _refForPlayedBar(span.sectionIndex, span.index);
    if (ref != _playingBar) setState(() => _playingBar = ref);
  }

  /// Maps a bar in PLAY order back to the document bar it came from.
  ///
  /// With repeats expanded several played bars share one document bar, so the
  /// highlight has to land on the document bar the user is looking at.
  ChartBarRef? _refForPlayedBar(int sectionIndex, int playedIndex) {
    var seen = 0;
    for (var s = 0; s < _chart.sections.length; s++) {
      final section = _chart.sections[s];
      final total = section.bars.length * section.passes;
      if (playedIndex < seen + total) {
        final within = (playedIndex - seen) % section.bars.length;
        return ChartBarRef(s, within);
      }
      seen += total;
    }
    return null;
  }

  Future<void> _stop() async {
    unawaited(_streamed.stop());
    _streaming = false;
    _ticker?.cancel();
    _ticker = null;
    _clock = null;
    _playback = null;
    _band = null;
    if (mounted) setState(() => _playingBar = null);
    await context.read<AudioService>().stop();
  }

  // ------------------------------------------------------------------ editing

  /// BB-T2: while a streamed band plays, a tapped bar is where to go next —
  /// on the next bar line, in the chorus that is playing.
  void _jumpTo(ChartBarRef ref) {
    final target = _realisedBarFor(ref);
    if (target != null) _streamed.transport.jumpTo(target);
  }

  /// The realised bar playing [ref], preferring the chorus now sounding.
  int? _realisedBarFor(ChartBarRef ref) {
    final bars = _streamedBars;
    final chorus = _streamed.current?.span?.bar.chorusIndex ?? 0;
    int? fallback;
    for (var i = 0; i < bars.length; i++) {
      final source = bars[i].bar.sourceBar;
      if (source == null ||
          source.section != ref.sectionIndex ||
          source.bar != ref.barIndex) {
        continue;
      }
      if (bars[i].bar.chorusIndex == chorus) return i;
      fallback ??= i;
    }
    return fallback;
  }

  List<BandBarSpan> get _streamedBars => _streamed.barsInPlay;

  /// BB-T2: loop (or stop looping) the section that is playing, in this
  /// chorus.
  void _toggleSectionLoop() {
    final t = _streamed.transport;
    if (t.loop != null) {
      setState(t.clearLoop);
      return;
    }
    final now = _streamed.current?.span?.bar;
    final source = now?.sourceBar;
    if (now == null || source == null) return;
    final bars = _streamedBars;
    int? first;
    int? last;
    for (var i = 0; i < bars.length; i++) {
      final b = bars[i].bar;
      if (b.chorusIndex == now.chorusIndex &&
          b.sourceBar?.section == source.section) {
        first ??= i;
        last = i;
      }
    }
    if (first != null && last != null) setState(() => t.setLoop(first!, last!));
  }

  Future<void> _editBar(ChartBarRef ref) async {
    if (_streaming) {
      _jumpTo(ref);
      return;
    }
    // Editing while the band plays is how you lose your place, and the card
    // asks for "no accidental edits while playing".
    if (_playing) return;

    setState(() => _selected = ref);
    final bar = _chart.sections[ref.sectionIndex].bars[ref.barIndex];
    // Open on what the user is LOOKING AT. With a capo or a B♭ instrument the
    // printed chord is not the stored one, and showing the stored one would
    // make the editor disagree with the grid.
    final printedBar = _printed.sections[ref.sectionIndex].bars[ref.barIndex];
    final current = printedBar.chordsInOrder.isEmpty
        ? null
        : printedBar.chordsInOrder.first.chord;

    final result = await showChordKeypad(context, initial: current);
    if (!mounted || result == null) return;

    final chosen = switch (result) {
      // …and convert back, or a trumpeter editing their own part would
      // silently rewrite the tune.
      ChordChosen(:final chord) => documentChordOf(chord, _transpose),
      ChordCleared() => null,
    };
    setState(() {
      _chart = _replaceBar(_chart, ref, barWithChord(bar, chosen));
      _selected = null;
    });
    _persist();
  }

  static Chart _replaceBar(Chart chart, ChartBarRef ref, ChartBar bar) {
    final sections = [
      for (var s = 0; s < chart.sections.length; s++)
        if (s != ref.sectionIndex)
          chart.sections[s]
        else
          ChartSection(
            label: chart.sections[s].label,
            repeatCount: chart.sections[s].repeatCount,
            feel: chart.sections[s].feel,
            tempoScale: chart.sections[s].tempoScale,
            intensity: chart.sections[s].intensity,
            extra: chart.sections[s].extra,
            bars: [
              for (var b = 0; b < chart.sections[s].bars.length; b++)
                if (b == ref.barIndex) bar else chart.sections[s].bars[b],
            ],
          ),
    ];
    return Chart(
      title: chart.title,
      composer: chart.composer,
      keyFifths: chart.keyFifths,
      minor: chart.minor,
      meter: chart.meter,
      tempoBpm: chart.tempoBpm,
      styleId: chart.styleId,
      sections: sections,
      pickupBeats: chart.pickupBeats,
      extra: chart.extra,
    );
  }

  /// Copies the chart as a `CB1.` token, and offers to read one back.
  ///
  /// Both directions in one sheet because they are the same idea from two ends
  /// — and because a "share" button with no "open" button leaves the receiving
  /// half of the feature invisible.
  Future<void> _share() async {
    if (_playing) await _stop();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('chartCopyToken'),
              leading: const Icon(Icons.copy_all_outlined),
              title: Text(l10n.chartShareCopy),
              subtitle: Text(l10n.chartShareCopyHint),
              enabled: !_chart.isEmpty,
              onTap: () async {
                await Clipboard.setData(
                  ClipboardData(text: encodeChartToken(_chart)),
                );
                if (sheet.mounted) Navigator.of(sheet).pop();
                messenger.showSnackBar(
                  SnackBar(content: Text(l10n.chartShareCopied)),
                );
              },
            ),
            ListTile(
              key: const Key('chartPasteToken'),
              leading: const Icon(Icons.content_paste_go_outlined),
              title: Text(l10n.chartSharePaste),
              subtitle: Text(l10n.chartSharePasteHint),
              onTap: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                // Reads whatever format the text turns out to be — a share
                // code, a chord grid, ChordPro, Nashville numbers or a JAMS
                // annotation. Which one it is is a fact about the text, not a
                // question to put to the user.
                final opened = importChart(data?.text ?? '');
                if (sheet.mounted) Navigator.of(sheet).pop();
                if (opened == null) {
                  // Says WHY rather than doing nothing: a paste that silently
                  // fails reads as a broken button.
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.chartSharePasteFailed)),
                  );
                  return;
                }
                if (!mounted) return;
                setState(() {
                  _chart = opened.chart;
                  _name = null;
                  _selected = null;
                });
                _persist();
                // Names the format it read: a paste that quietly reinterprets
                // is worse than one that reports. And when the source carried
                // no barlines, say the bars are a guess rather than let them
                // look authoritative.
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      opened.barsAreInferred
                          ? '${l10n.chartImportOpenedAs(_formatName(l10n, opened.format))}'
                              ' · ${l10n.chartImportBarsInferred}'
                          : l10n.chartImportOpenedAs(
                              _formatName(l10n, opened.format),
                            ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// BB-U5(c): the chart as a band you can drive in Loop Studio — its first
  /// bars projected onto the loop engine's six chords (BB-A0), every
  /// compromise said out loud rather than played wrong.
  Future<void> _openInLoopStudio() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final sounding = soundingChart(_chart, _transpose);
    final projection = chartToProgression(sounding);
    final progression = projection.progression;
    if (progression == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.chartLoopNothing)));
      return;
    }
    if (_playing) await _stop();
    if (!mounted) return;
    if (!projection.isExact) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.chartLoopReduced(
              projection.barsUsed,
              projection.barsAvailable,
              projection.unrepresentable.length,
              projection.reductions.length - projection.unrepresentable.length,
            ),
          ),
        ),
      );
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LoopMixerScreen(
          initialSpec: GrooveSpec(
            tempoBpm: sounding.tempoBpm,
            key: grooveKeyOf(sounding),
          ),
          initialProgression: progression,
        ),
      ),
    );
  }

  Future<void> _explain() async {
    // Explains what the grid SHOWS, so a transposed reading is explained in
    // the key the player is actually reading.
    final analysis = analyzeChart(_printed);
    var depth = AnalysisDepth.learner;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<AnalysisDepth>(
                key: const Key('chartAnalysisDepth'),
                segments: const [
                  ButtonSegment(
                    value: AnalysisDepth.colours,
                    icon: Icon(Icons.palette_outlined),
                  ),
                  ButtonSegment(
                    value: AnalysisDepth.learner,
                    icon: Icon(Icons.school_outlined),
                  ),
                  ButtonSegment(
                    value: AnalysisDepth.expert,
                    icon: Icon(Icons.psychology_outlined),
                  ),
                ],
                selected: {depth},
                onSelectionChanged: (s) => setSheetState(() => depth = s.first),
              ),
              Flexible(
                child: ChartAnalysisPanel(analysis: analysis, depth: depth),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _transposeDialog() async {
    // A SOUNDING change alters the audio, which is already rendered, so the
    // sheet is closed while playing exactly like the style and chorus pickers.
    if (_playing) await _stop();
    if (!mounted) return;
    final next = await showTransposeSheet(context, current: _transpose);
    if (!mounted || next == null) return;
    setState(() => _transpose = next);
  }

  Future<void> _openLibrary() async {
    if (_playing) await _stop();
    if (!mounted) return;
    final result = await showChartLibrary(
      context,
      current: _chart,
      currentName: _name,
    );
    if (!mounted || result == null) return;
    switch (result) {
      case ChartOpened(:final chart, :final name):
        setState(() {
          _chart = chart;
          _name = name;
          _selected = null;
        });
        _persist();
    }
  }

  Future<void> _editAsText() async {
    if (_playing) await _stop();
    if (!mounted) return;
    final edited = await showDialog<String>(
      context: context,
      builder: (context) => _ChartTextDialog(initial: formatChartText(_chart)),
    );
    if (!mounted || edited == null) return;

    final result = parseChartText(edited, defaults: _chart);
    setState(() => _chart = result.chart);
    _persist();

    // An unreadable chord is kept, so the chart is never silently shortened —
    // but the user has to be told which one, or they will not find it.
    if (!result.isClean && mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.chartUnreadableChords(
              result.problems.length,
              result.problems.map((p) => p.text).take(3).join(', '),
            ),
          ),
        ),
      );
    }
  }

  void _setStyle(String id) {
    setState(() => _chart = _ChartHeader.withStyle(_chart, id));
    _persist();
    // BB-U3: a streamed band takes the new style from its next window, which
    // is always a bar line.
    _replanLive();
  }

  /// BB-T3: the practice trainer's settings. They apply from the next Play.
  Future<void> _openPractice() async {
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          final p = _practice;
          void set(PracticeConfig next) {
            setSheet(() {});
            setState(() => _practice = next);
          }

          PracticeConfig copy({
            int? tempoStep,
            KeyCycle? keyCycle,
            bool? harmonyFade,
            double? dropOut,
            bool? densityTaper,
          }) =>
              PracticeConfig(
                tempoStep: tempoStep ?? p.tempoStep,
                keyCycle: keyCycle ?? p.keyCycle,
                harmonyFade: harmonyFade ?? p.harmonyFade,
                dropOut: dropOut ?? p.dropOut,
                densityTaper: densityTaper ?? p.densityTaper,
                seed: p.seed,
              );

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    key: const Key('practiceOn'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.chartPractice),
                    subtitle: Text(l10n.chartPracticeHelp),
                    value: _practiceOn,
                    onChanged: (v) {
                      setSheet(() {});
                      setState(() => _practiceOn = v);
                    },
                  ),
                  Text(l10n.chartPracticeTempoStep),
                  SegmentedButton<int>(
                    key: const Key('practiceTempoStep'),
                    showSelectedIcon: false,
                    segments: [
                      for (final n in const [0, 2, 5, 10])
                        ButtonSegment(
                          value: n,
                          label: Text(n == 0 ? '±0' : '+$n'),
                        ),
                    ],
                    selected: {p.tempoStep},
                    onSelectionChanged: (v) => set(copy(tempoStep: v.single)),
                  ),
                  const SizedBox(height: 12),
                  Text(l10n.chartPracticeKeys),
                  SegmentedButton<KeyCycle>(
                    key: const Key('practiceKeys'),
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: KeyCycle.none,
                        label: Text(l10n.chartClickOff),
                      ),
                      ButtonSegment(
                        value: KeyCycle.chromatic,
                        label: Text(l10n.chartPracticeKeysChromatic),
                      ),
                      ButtonSegment(
                        value: KeyCycle.fourths,
                        label: Text(l10n.chartPracticeKeysFourths),
                      ),
                      ButtonSegment(
                        value: KeyCycle.random,
                        label: Text(l10n.chartPracticeKeysRandom),
                      ),
                    ],
                    selected: {p.keyCycle},
                    onSelectionChanged: (v) => set(copy(keyCycle: v.single)),
                  ),
                  SwitchListTile(
                    key: const Key('practiceFade'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.chartPracticeFade),
                    subtitle: Text(l10n.chartPracticeFadeHelp),
                    value: p.harmonyFade,
                    onChanged: (v) => set(copy(harmonyFade: v)),
                  ),
                  SwitchListTile(
                    key: const Key('practiceTaper'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.chartPracticeTaper),
                    value: p.densityTaper,
                    onChanged: (v) => set(copy(densityTaper: v)),
                  ),
                  Text(l10n.chartPracticeDropOut((p.dropOut * 100).round())),
                  Slider(
                    key: const Key('practiceDropOut'),
                    value: p.dropOut,
                    max: 0.5,
                    divisions: 5,
                    onChanged: (v) => set(copy(dropOut: v)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// BB-U3: the band's live mix — one strip per role, the same strip the
  /// project mixer draws. Voice volumes: instant, nothing re-renders, and it
  /// holds for the next Play too.
  Future<void> _openBandMix() async {
    final l10n = AppLocalizations.of(context)!;
    final roles = _streamed.roles;
    String name(BandRole role) => switch (role) {
          BandRole.comp => l10n.loopMixerTrackChords,
          BandRole.bass => l10n.loopMixerTrackBass,
          BandRole.drums => l10n.loopMixerTrackDrums,
        };
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // Three strips are taller than the default half-height sheet on a phone.
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          void change(VoidCallback edit) {
            setSheet(edit);
            _streamed.applyRoles();
          }

          String voice(Instrument i) => switch (i) {
                Instrument.piano => l10n.instrumentPiano,
                Instrument.cello => l10n.instrumentCello,
                Instrument.flute => l10n.instrumentFlute,
                Instrument.musicBox => l10n.instrumentMusicBox,
              };
          Widget voicePicker(BandRole role) {
            final current = role == BandRole.comp ? _compVoice : _bassVoice;
            return DropdownButton<Instrument>(
              key: ValueKey('band-voice-${role.name}'),
              value: current,
              items: [
                for (final i in Instrument.values)
                  DropdownMenuItem(value: i, child: Text(voice(i))),
              ],
              onChanged: (i) {
                if (i == null) return;
                setSheet(() {});
                setState(() {
                  if (role == BandRole.comp) {
                    _compVoice = i;
                  } else {
                    _bassVoice = i;
                  }
                });
                _replanLive();
              },
            );
          }

          final swing = _swing ?? styleFor(_chart.styleId).swing;
          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Text(l10n.chartIntensity),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SegmentedButton<int>(
                            key: const Key('bandIntensity'),
                            showSelectedIcon: false,
                            segments: [
                              for (var i = 0; i <= 3; i++)
                                ButtonSegment(
                                  value: i,
                                  label: Text('${i + 1}'),
                                ),
                            ],
                            selected: {_intensity},
                            onSelectionChanged: (v) {
                              setSheet(() {});
                              setState(() => _intensity = v.single);
                              _replanLive();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Text(l10n.chartSwing),
                        Expanded(
                          child: Slider(
                            key: const Key('bandSwing'),
                            value: swing,
                            divisions: 10,
                            label: '${(swing * 100).round()}%',
                            onChanged: (v) {
                              setSheet(() {});
                              setState(() => _swing = v);
                            },
                            // Re-plan once per drag, not per frame.
                            onChangeEnd: (_) {
                              _replanLive();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(l10n.chartCountIn),
                        SegmentedButton<int>(
                          key: const Key('bandCountIn'),
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: 1, label: Text('1')),
                            ButtonSegment(value: 2, label: Text('2')),
                          ],
                          selected: {_countInBars},
                          onSelectionChanged: (v) {
                            setSheet(() {});
                            // Takes effect on the next Play: the count-in is
                            // over by the time anything could change it.
                            setState(() => _countInBars = v.single);
                          },
                        ),
                        FilterChip(
                          key: const Key('bandClickCountIn'),
                          label: Text(l10n.chartCountInClick),
                          selected: _clickCountIn,
                          onSelected: (v) {
                            setSheet(() {});
                            setState(() => _clickCountIn = v);
                          },
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Text(l10n.chartClick),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SegmentedButton<BandClick>(
                            key: const Key('bandClick'),
                            showSelectedIcon: false,
                            segments: [
                              ButtonSegment(
                                value: BandClick.off,
                                label: Text(l10n.chartClickOff),
                              ),
                              ButtonSegment(
                                value: BandClick.everyBeat,
                                label: Text(l10n.chartClickEveryBeat),
                              ),
                              ButtonSegment(
                                value: BandClick.downbeat,
                                label: Text(l10n.chartClickDownbeat),
                              ),
                            ],
                            selected: {_click},
                            onSelectionChanged: (v) {
                              setSheet(() {});
                              setState(() => _click = v.single);
                              _replanLive();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final role in BandRole.values)
                    MixerStripView(
                      id: 'band-${role.name}',
                      title: name(role),
                      muted: roles.muted.contains(role),
                      soloed: roles.soloed.contains(role),
                      level: roles.levelOf(role),
                      pan: roles.panOf(role),
                      onMute: () => change(
                        () => roles.muted.contains(role)
                            ? roles.muted.remove(role)
                            : roles.muted.add(role),
                      ),
                      onSolo: () => change(
                        () => roles.soloed.contains(role)
                            ? roles.soloed.remove(role)
                            : roles.soloed.add(role),
                      ),
                      onLevel: (v) => change(() => roles.setLevel(role, v)),
                      onPan: (v) => change(() => roles.setPan(role, v)),
                      trailing:
                          role == BandRole.drums ? null : voicePicker(role),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _setTempo(int bpm) {
    setState(() {
      _chart = _ChartHeader.withTempo(_chart, bpm.clamp(40, 300));
    });
    _persist();
  }

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_chart.title.isEmpty ? l10n.gameChart : _chart.title),
        actions: [
          // The style belongs to the chart; the chorus count belongs to this
          // playthrough. Both are disabled while playing, because the audio is
          // already rendered and changing either would desync the highlight.
          PopupMenuButton<String>(
            key: const Key('chartStyleMenu'),
            tooltip: l10n.chartStyle,
            // A streamed band can change style mid-song (BB-U3); the
            // whole-render fallback cannot.
            enabled: !_playing || _streaming,
            initialValue: styleFor(_chart.styleId).id,
            onSelected: _setStyle,
            itemBuilder: (context) => [
              for (final style in kStyles)
                PopupMenuItem(value: style.id, child: Text(style.name)),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(child: Text(styleFor(_chart.styleId).name)),
            ),
          ),
          PopupMenuButton<int>(
            key: const Key('chartChorusMenu'),
            tooltip: l10n.chartChoruses,
            enabled: !_playing,
            initialValue: _choruses,
            onSelected: (n) => setState(() => _choruses = n),
            itemBuilder: (context) => [
              for (final n in const [1, 2, 3, 4, 8])
                PopupMenuItem(value: n, child: Text('×$n')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(child: Text('×$_choruses')),
            ),
          ),
          // ⚠️ Only the BAND controls stay on the bar. Five icon buttons plus
          // two text menus overflowed a 375px phone by 48px in both locales —
          // caught by the layout audit — and the rest are occasional actions
          // that read fine in an overflow menu.
          PopupMenuButton<String>(
            key: const Key('chartMoreMenu'),
            icon: const Icon(Icons.more_vert),
            itemBuilder: (context) => [
              PopupMenuItem(
                key: const Key('chartExplainButton'),
                value: 'explain',
                child: ListTile(
                  leading: const Icon(Icons.lightbulb_outline),
                  title: Text(l10n.chartAnalysis),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                key: const Key('chartTransposeButton'),
                value: 'transpose',
                child: ListTile(
                  leading: const Icon(Icons.swap_vert),
                  title: Text(l10n.chartTranspose),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                key: const Key('chartShareButton'),
                value: 'share',
                child: ListTile(
                  leading: const Icon(Icons.ios_share),
                  title: Text(l10n.chartShare),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                key: const Key('chartLibraryButton'),
                value: 'library',
                child: ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: Text(l10n.chartLibrary),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                key: const Key('chartSetlistsButton'),
                value: 'setlists',
                child: ListTile(
                  leading: const Icon(Icons.queue_music),
                  title: Text(l10n.setlistTitle),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                key: const Key('chartLoopStudioButton'),
                value: 'loop',
                child: ListTile(
                  leading: const Icon(Icons.loop),
                  title: Text(l10n.chartOpenInLoopStudio),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                key: const Key('chartTextButton'),
                value: 'text',
                child: ListTile(
                  leading: const Icon(Icons.edit_note),
                  title: Text(l10n.chartEditAsText),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            onSelected: (value) => switch (value) {
              'explain' => _explain(),
              'transpose' => _transposeDialog(),
              'share' => _share(),
              'library' => _openLibrary(),
              'loop' => _openInLoopStudio(),
              'setlists' => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SetlistScreen(),
                  ),
                ),
              _ => _editAsText(),
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: ChartGridView(
                chart: _printed,
                playingBar: _playingBar,
                selected: _selected,
                onTapBar: _editBar,
              ),
            ),
          ),
          _transport(context, l10n, theme),
        ],
      ),
    );
  }

  Widget _transport(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) =>
      Material(
        elevation: 8,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                FilledButton.icon(
                  key: const Key('chartPlayButton'),
                  onPressed: _playing ? _stop : _play,
                  icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
                  label: Text(_playing ? l10n.chartStop : l10n.chartPlay),
                ),
                if (_streaming && _practiceOn)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      l10n.chartPracticePass(_shownPass + 1),
                      key: const Key('chartPracticePass'),
                    ),
                  ),
                // Practice owns the loop (the whole tune, round and round).
                if (_streaming && !_practiceOn)
                  IconButton(
                    key: const Key('chartLoopSectionButton'),
                    tooltip: l10n.chartLoopSection,
                    isSelected: _streamed.transport.loop != null,
                    icon: const Icon(Icons.repeat),
                    selectedIcon: const Icon(Icons.repeat_on),
                    onPressed: _toggleSectionLoop,
                  ),
                IconButton(
                  key: const Key('chartPracticeButton'),
                  tooltip: l10n.chartPractice,
                  isSelected: _practiceOn,
                  icon: const Icon(Icons.fitness_center_outlined),
                  selectedIcon: const Icon(Icons.fitness_center),
                  // Settings apply from the next Play.
                  onPressed: _playing ? null : _openPractice,
                ),
                IconButton(
                  key: const Key('chartBandMixButton'),
                  tooltip: l10n.chartBandMix,
                  icon: const Icon(Icons.tune),
                  onPressed: _openBandMix,
                ),
                const SizedBox(width: 16),
                Text('${_chart.tempoBpm}', style: theme.textTheme.titleMedium),
                Text(
                  ' ${l10n.chartBpm}',
                  style: theme.textTheme.bodySmall,
                ),
                Expanded(
                  child: Slider(
                    value: _chart.tempoBpm.toDouble().clamp(40, 300),
                    min: 40,
                    max: 300,
                    // BB-T2: a streamed band takes a new tempo from its next
                    // bar (re-planned once the drag ends); the whole-render
                    // fallback cannot follow, so it stays locked there.
                    onChanged: _playing && !_streaming
                        ? null
                        : (v) => _setTempo(v.round()),
                    onChangeEnd: (_) => _replanLive(tempo: true),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// Rebuilding a `Chart` with one field changed. The model is immutable and has
/// no `copyWith`, and hand-rolling the full constructor at each call site is
/// exactly how a field gets quietly dropped.
class _ChartHeader {
  static Chart withStyle(Chart chart, String id) => _copy(chart, styleId: id);

  static Chart withTempo(Chart chart, int bpm) => _copy(chart, tempoBpm: bpm);

  static Chart _copy(Chart chart, {String? styleId, int? tempoBpm}) => Chart(
        title: chart.title,
        composer: chart.composer,
        keyFifths: chart.keyFifths,
        minor: chart.minor,
        meter: chart.meter,
        tempoBpm: tempoBpm ?? chart.tempoBpm,
        styleId: styleId ?? chart.styleId,
        sections: chart.sections,
        pickupBeats: chart.pickupBeats,
        extra: chart.extra,
      );
}

class _ChartTextDialog extends StatefulWidget {
  const _ChartTextDialog({required this.initial});
  final String initial;

  @override
  State<_ChartTextDialog> createState() => _ChartTextDialogState();
}

class _ChartTextDialogState extends State<_ChartTextDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.chartEditAsText),
      content: SizedBox(
        width: 520,
        child: TextField(
          key: const Key('chartTextField'),
          controller: _controller,
          maxLines: 16,
          minLines: 8,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            helperText: l10n.chartTextHelp,
            helperMaxLines: 3,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.chartCancel),
        ),
        FilledButton(
          key: const Key('chartTextApply'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.chartOk),
        ),
      ],
    );
  }
}

/// The name of an import format, for the "opened as …" report.
String _formatName(AppLocalizations l10n, ChartFormat format) =>
    switch (format) {
      ChartFormat.token => l10n.chartImportFormatToken,
      ChartFormat.textGrid => l10n.chartImportFormatTextGrid,
      ChartFormat.chordPro => l10n.chartImportFormatChordPro,
      ChartFormat.nashville => l10n.chartImportFormatNashville,
      ChartFormat.jams => l10n.chartImportFormatJams,
    };
