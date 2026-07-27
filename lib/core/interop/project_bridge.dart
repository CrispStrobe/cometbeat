// lib/core/interop/project_bridge.dart
//
// C3 — one door between the five modes.
//
// By now every conversion exists somewhere: `tab_tracker.dart`, `loop_tab.dart`,
// `tracker_notation.dart`, `multipart_to_tracker.dart`, `TabDocument.toScore`,
// `groove_notation.dart`. What did NOT exist is a single place to ask "can I
// take this there, and what will it cost me?" — so every screen that wanted an
// "open in…" action had to know which converter to call, in which direction,
// and had to guess at the losses to warn about (which in practice meant not
// warning at all).
//
// This file ADDS NO CONVERSION LOGIC. It is routing plus honest reporting: it
// dispatches to the converters above and returns their [ConversionReport]
// alongside the document, so a caller can show the user what will change BEFORE
// they commit. A pair with no route says so explicitly instead of throwing or,
// worse, silently returning something empty.
//
// Pure Dart, no Flutter — the "Open in…" menu (C4) sits on top.

import 'package:comet_beat/core/audio/loop_engine.dart' show PatternCell;
import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show AdditiveInstrument, TrackerChannel, TrackerTiming;
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/core/interop/annotation_codecs.dart';
import 'package:comet_beat/core/interop/loop_tab.dart';
import 'package:comet_beat/core/interop/loop_tracker.dart';
import 'package:comet_beat/core/interop/symbolic_annotation.dart';
import 'package:comet_beat/core/interop/tab_tracker.dart';
import 'package:comet_beat/core/interop/tracker_song_flatten.dart';
import 'package:comet_beat/features/games/composition/multipart_to_tracker.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:crisp_notation/crisp_notation.dart';

/// The five top-level authoring modes (see PLAN.md, "Five-mode product
/// architecture").
enum AppMode {
  /// Pattern matrix, channels, effect commands. Document: [TrackerSong].
  tracker,

  /// Loops of symbolic events. Document: `List<PatternCell>` (one track).
  loop,

  /// Conventional notation. Document: [MultiPartScore].
  score,

  /// Strings, frets, fingering. Document: [TabDocument].
  tab,

  /// The DAW. Reached by BOUNCING — see [ProjectBridge.canConvert].
  audio,
}

/// A short user-facing name for a mode.
String appModeLabel(AppMode mode) => switch (mode) {
      AppMode.tracker => 'Tracker',
      AppMode.loop => 'Loop Studio',
      AppMode.score => 'Score',
      AppMode.tab => 'Tab',
      AppMode.audio => 'Audio',
    };

/// The outcome of a conversion.
class ConversionResult {
  ConversionResult({
    required this.document,
    required this.report,
    SymbolicAnnotations? annotations,
    this.unsupportedReason,
  }) : annotations = annotations ?? SymbolicAnnotations();

  /// The converted document, or null when [isUnsupported].
  ///
  /// Its runtime type follows the TARGET mode: [TrackerSong], [TabDocument],
  /// [MultiPartScore], or `List<PatternCell>`.
  final Object? document;

  /// What the target model could not hold. Carry it along and hand it back to
  /// the reverse conversion for a round trip.
  final SymbolicAnnotations annotations;

  /// What was lost or approximated, in the user's terms.
  final ConversionReport report;

  /// Set when there is no route; [document] is then null.
  final String? unsupportedReason;

  bool get isUnsupported => unsupportedReason != null;
  bool get lossless => !isUnsupported && report.lossless;
}

/// Routes a document from one mode to another.
abstract final class ProjectBridge {
  /// Whether a route exists from [from] to [to].
  ///
  /// [AppMode.audio] is deliberately one-way. Everything can BOUNCE into Audio
  /// (any mode renders to PCM), but coming back is transcription — a guess from
  /// a waveform, not a conversion — and pretending it is a peer of the symbolic
  /// routes would misrepresent what the user gets. The transcription path stays
  /// an explicit, separately-invoked feature.
  static bool canConvert(AppMode from, AppMode to) {
    if (from == to) return true;
    if (to == AppMode.audio) return true;
    if (from == AppMode.audio) return false;
    return true;
  }

  /// Every mode reachable from [from], excluding [from] itself.
  static List<AppMode> targetsFrom(AppMode from) => [
        for (final mode in AppMode.values)
          if (mode != from && canConvert(from, mode)) mode,
      ];

  /// Converts [document] from [from] to [to].
  ///
  /// [annotations] is a side-car from an EARLIER conversion of the same
  /// material; passing it back makes a round trip exact where the target can
  /// hold the detail again.
  ///
  /// Never throws for an unsupported pair — it returns a [ConversionResult]
  /// with [ConversionResult.unsupportedReason] set, so a caller can render the
  /// reason instead of handling an exception.
  static ConversionResult convert({
    required AppMode from,
    required AppMode to,
    required Object document,
    SymbolicAnnotations? annotations,
    Tuning? tuning,
    int capo = 0,
  }) {
    if (from == to) {
      return ConversionResult(document: document, report: ConversionReport());
    }
    if (to == AppMode.audio) {
      return ConversionResult(
        document: null,
        report: ConversionReport()
          ..addLost('everything symbolic — a bounce produces audio only'),
        unsupportedReason:
            'Bounce to Audio from the mode\'s own export, so it can use that '
            'mode\'s instruments and effects.',
      );
    }
    if (from == AppMode.audio) {
      return ConversionResult(
        document: null,
        report: ConversionReport(),
        unsupportedReason:
            'Audio cannot become notes directly — use Transcribe, which '
            'estimates the notes and can be corrected afterwards.',
      );
    }

    // An explicit tuning wins; otherwise honour one an earlier hop recorded, so
    // a DADGAD tab that travelled through a mode with no strings comes back in
    // DADGAD rather than silently in standard.
    final strings = tuning ??
        tuningFromAnnotation(annotations?.docMeta[AnnotationKeys.tuning]) ??
        Tuning.standardGuitar;

    // The "never throws" contract is load-bearing: a menu offers every target
    // before knowing whether THIS document can make the trip, so a converter
    // that rejects an edge case must surface as a readable sentence rather than
    // an exception mid-tap. An empty tracker song hitting Score is the concrete
    // case the matrix test found — `MultiPartScore` requires at least one part,
    // so a song with no notes asserted instead of converting.
    try {
      return _carryForward(
        annotations,
        _route(from, to, document, annotations, strings, capo),
      );
    } on Object catch (error) {
      return ConversionResult(
        document: null,
        report: ConversionReport(),
        unsupportedReason:
            'This ${appModeLabel(from)} document cannot become a '
            '${appModeLabel(to)} one: $error',
      );
    }
  }

  static ConversionResult _route(
    AppMode from,
    AppMode to,
    Object document,
    SymbolicAnnotations? annotations,
    Tuning strings,
    int capo,
  ) {
    return switch ((from, to)) {
      // ── Tab ───────────────────────────────────────────────────────────────
      (AppMode.tab, AppMode.tracker) => _fromTab(
          document,
          (doc) {
            final out = trackerSongFromTabDocument(doc, capo: capo);
            return ConversionResult(
              document: out.song,
              annotations: out.annotations,
              report: out.report,
            );
          },
        ),
      (AppMode.tab, AppMode.loop) => _fromTab(
          document,
          (doc) {
            final out = loopCellsFromTabDocument(
              doc,
              annotations: annotations,
              capo: capo,
            );
            return ConversionResult(
              document: out.cells,
              annotations: out.annotations,
              report: out.report,
            );
          },
        ),
      (AppMode.tab, AppMode.score) => _fromTab(
          document,
          (doc) => ConversionResult(
            document: MultiPartScore([doc.toScore(capo: capo)]),
            // A score has no strings, so the fretting context goes in the
            // side-car — otherwise a later trip back to Tab has to guess a
            // tuning, and guesses standard.
            annotations: SymbolicAnnotations()
              ..docMeta[AnnotationKeys.sourceMode] = 'tab'
              ..docMeta[AnnotationKeys.capo] = capo
              ..docMeta[AnnotationKeys.tuning] = tuningToAnnotation(doc.tuning),
            // Lossless: `toScore` records each column's string/fret in the
            // score's `tabVoicings` side-car (C4), so the exact fretting rides
            // along and a later trip back to Tab reproduces it note-for-note —
            // it is no longer "chosen for you".
            report: ConversionReport(),
          ),
        ),

      // ── Tracker ───────────────────────────────────────────────────────────
      (AppMode.tracker, AppMode.tab) => _fromTracker(
          document,
          (song) {
            final out = tabDocumentFromTrackerSong(
              song,
              annotations: annotations,
              fallbackTuning: strings,
            );
            return ConversionResult(document: out.doc, report: out.report);
          },
        ),
      (AppMode.tracker, AppMode.score) => _fromTracker(
          document,
          (song) => ConversionResult(
            document: multiPartScoreFromTrackerSong(song),
            report: ConversionReport()
              ..addLost('effect-column commands and per-cell instruments'),
          ),
        ),
      (AppMode.tracker, AppMode.loop) => _fromTracker(
          document,
          (song) {
            // D1: DIRECT. This used to detour through Tab, which fret-maps
            // every pitch onto six strings — right for a guitar part, wrong for
            // a piano channel and nonsense for a drum one. Both models are a
            // monophonic-per-step grid already, so no detour is needed.
            // The WHOLE song, laid out in play order. Reading `song.channels`
            // here took only the pattern currently loaded in the editor, so a
            // song imported from a score arrived as its first 64 rows — and the
            // report called that lossless.
            final channels = trackerChannelsAcrossOrder(song);
            if (channels.isEmpty) {
              return ConversionResult(
                document: const <PatternCell>[],
                report: ConversionReport()
                  ..addLost('this song has no channels'),
              );
            }
            final busiest = channels.reduce(
              (a, b) => _noteCount(b) > _noteCount(a) ? b : a,
            );
            final out = loopCellsFromTrackerChannel(
              busiest,
              song.timing.copyWith(rows: busiest.cells.length),
            );
            final report = out.report;
            if (channels.length > 1) {
              report.addLost(
                'the other ${channels.length - 1} channels — a loop track '
                'is one voice',
              );
            }
            return ConversionResult(
              document: out.cells,
              annotations: out.annotations,
              report: report,
            );
          },
        ),

      // ── Score ─────────────────────────────────────────────────────────────
      (AppMode.score, AppMode.tracker) => _fromScore(
          document,
          (mp) => ConversionResult(
            document: trackerSongFromMultiPart(mp),
            report: ConversionReport()
              ..addApproximated('notes quantized onto the pattern grid'),
          ),
        ),
      (AppMode.score, AppMode.tab) => _fromScore(
          document,
          (mp) {
            final part = mp.parts.first;
            final report = ConversionReport();
            // The auto-fretter only picks a string for notes that DON'T already
            // carry a voicing (C4). A score that came from Tab has one per note,
            // so nothing is guessed; a hand-engraved score has none, so every
            // note is. Report exactly the notes actually being invented.
            final notes = _scoreNoteCount(part);
            final voiced = part.tabVoicings.length.clamp(0, notes);
            if (voiced < notes) {
              report.addApproximated(
                voiced == 0
                    ? 'fingering chosen for you — a score does not say which '
                        'string'
                    : 'fingering chosen for the ${notes - voiced} notes '
                        'without a stored voicing',
              );
            }
            if (mp.parts.length > 1) {
              report.addLost('parts beyond the first (a tab holds one part)');
            }
            return ConversionResult(
              document: TabDocument.fromScore(part, strings, capo: capo),
              report: report,
            );
          },
        ),
      (AppMode.score, AppMode.loop) => _fromScore(
          document,
          (mp) {
            final doc =
                TabDocument.fromScore(mp.parts.first, strings, capo: capo);
            final loop = loopCellsFromTabDocument(doc, capo: capo);
            return ConversionResult(
              document: loop.cells,
              report: loop.report
                ..addApproximated('notes snapped to the eighth-note loop grid'),
            );
          },
        ),

      // ── Loop ──────────────────────────────────────────────────────────────
      (AppMode.loop, AppMode.tab) => _fromLoop(
          document,
          (cells) {
            final out = tabDocumentFromLoopCells(
              cells,
              strings,
              annotations: annotations,
              capo: capo,
            );
            return ConversionResult(
              document: out.doc,
              annotations: out.annotations,
              report: out.report,
            );
          },
        ),
      (AppMode.loop, AppMode.tracker) => _fromLoop(
          document,
          (cells) {
            // D1: DIRECT, for the same reason as above — and it also keeps
            // CHORDS, by spreading them across as many channels as the widest
            // one needs. The old Tab detour collapsed them onto a fretboard.
            final steps = cells.fold<int>(0, (sum, c) => sum + c.steps);
            final rows = steps < 1 ? 1 : steps;
            final timing = TrackerTiming(
              rows: rows,
              stepsPerBeat: kLoopStepsPerBeatGrid,
            );
            final channels = trackerChannelsFromLoopCells(
              cells,
              timing,
              idPrefix: 'loop',
              instrument: const AdditiveInstrument('loop', Instrument.piano),
            );
            final report = ConversionReport();
            if (channels.length > 1) {
              report.addApproximated(
                'chords spread across ${channels.length} channels — a channel '
                'plays one note at a time',
              );
            }
            return ConversionResult(
              document: TrackerSong.fromParts(
                channels: channels,
                timing: timing,
                patterns: [
                  TrackerPattern(
                    name: 'loop',
                    cells: [
                      for (final c in channels) List.of(c.cells),
                    ],
                  ),
                ],
                order: const [0],
              ),
              report: report,
            );
          },
        ),
      (AppMode.loop, AppMode.score) => _fromLoop(
          document,
          (cells) {
            final tab = tabDocumentFromLoopCells(cells, strings, capo: capo);
            return ConversionResult(
              document: MultiPartScore([tab.doc.toScore(capo: capo)]),
              annotations: tab.annotations,
              report: tab.report
                ..addLost('per-note velocity (a score carries dynamics marks, '
                    'not values)'),
            );
          },
        ),
      _ => ConversionResult(
          document: null,
          report: ConversionReport(),
          unsupportedReason:
              'No route from ${appModeLabel(from)} to ${appModeLabel(to)}.',
        ),
    };
  }

  /// A one-line summary of what [from] -> [to] costs, for a menu subtitle.
  ///
  /// Computed WITHOUT a document, so a menu can be built before the user picks
  /// anything. It is the static shape of the edge; [convert]'s report is the
  /// document-specific truth.
  static String describeEdge(AppMode from, AppMode to) {
    if (from == to) return 'Already here.';
    if (to == AppMode.audio) {
      return 'Renders to audio — notes are not editable.';
    }
    if (from == AppMode.audio) return 'Needs transcription.';
    return switch ((from, to)) {
      (AppMode.tab, AppMode.tracker) =>
        'Keeps string and fret — one channel per string.',
      (AppMode.tracker, AppMode.tab) =>
        'Reads each channel as a string. Bring the side-car for techniques.',
      (AppMode.tab, AppMode.score) =>
        'Keeps pitches AND the string/fret (in the side-car).',
      (AppMode.score, AppMode.tab) => 'Picks a playable fingering for you.',
      (AppMode.tab, AppMode.loop) ||
      (AppMode.score, AppMode.loop) =>
        'Snaps to the eighth-note loop grid.',
      (AppMode.loop, AppMode.tab) =>
        'Picks a playable fingering; drops velocity.',
      (AppMode.loop, AppMode.score) => 'Engraves the loop; drops velocity.',
      (AppMode.loop, AppMode.tracker) =>
        'One channel per chord voice; keeps velocity.',
      (AppMode.tracker, AppMode.score) => 'Drops effect commands.',
      (AppMode.score, AppMode.tracker) => 'Quantizes onto the pattern grid.',
      (AppMode.tracker, AppMode.loop) =>
        'Takes the busiest channel onto the eighth-note grid.',
      _ => '',
    };
  }
}

/// How many cells of [channel] carry a note — used to pick the channel that
/// best represents a whole song as one loop track.
int _noteCount(TrackerChannel channel) =>
    channel.cells.where((c) => c.midi != null).length;

/// How many sounding notes/chords [score] holds — compared against the stored
/// [Score.tabVoicings] count to report exactly how many notes a score→tab
/// conversion has to invent a fingering for (one voicing entry per note).
int _scoreNoteCount(Score score) =>
    score.measures.expand((m) => m.elements).whereType<NoteElement>().length;

// ── typed unwrapping ────────────────────────────────────────────────────────
//
// A caller can hand us the wrong document for the mode it claims. That is a
// programming error, but it must not crash a menu action mid-tap — it becomes
// an unsupported result with a message that names what was actually passed.

ConversionResult _wrongType(String expected, Object document) =>
    ConversionResult(
      document: null,
      report: ConversionReport(),
      unsupportedReason:
          'Expected a $expected but got ${document.runtimeType}.',
    );

ConversionResult _fromTab(
  Object document,
  ConversionResult Function(TabDocument) convert,
) =>
    document is TabDocument
        ? convert(document)
        : _wrongType('TabDocument', document);

ConversionResult _fromTracker(
  Object document,
  ConversionResult Function(TrackerSong) convert,
) =>
    document is TrackerSong
        ? convert(document)
        : _wrongType('TrackerSong', document);

/// Lets document-level facts from an earlier hop survive one that cannot hold
/// them.
///
/// Only [SymbolicAnnotations.docMeta] travels. A tuning or a capo means the same
/// thing in every mode, so carrying it is safe and is the whole point of the
/// side-car; per-EVENT entries are keyed by an address the conversion has just
/// invalidated, so carrying those would attach a fact to the wrong note.
///
/// The route's own values win — it looked at the actual document, the incoming
/// side-car only remembers an earlier one.
ConversionResult _carryForward(
  SymbolicAnnotations? incoming,
  ConversionResult result,
) {
  if (incoming == null || incoming.docMeta.isEmpty) return result;
  for (final entry in incoming.docMeta.entries) {
    result.annotations.docMeta.putIfAbsent(entry.key, () => entry.value);
  }
  return result;
}

ConversionResult _fromScore(
  Object document,
  ConversionResult Function(MultiPartScore) convert,
) {
  if (document is MultiPartScore) {
    return document.parts.isEmpty
        ? _wrongType('non-empty MultiPartScore', document)
        : convert(document);
  }
  if (document is Score) return convert(MultiPartScore([document]));
  return _wrongType('MultiPartScore', document);
}

ConversionResult _fromLoop(
  Object document,
  ConversionResult Function(List<PatternCell>) convert,
) =>
    document is List<PatternCell>
        ? convert(document)
        : _wrongType('List<PatternCell>', document);
