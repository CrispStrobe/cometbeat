// lib/shared/tutorial/primers.dart
//
// Authored tutorial content: one zero-knowledge "primer" per module, teaching
// exactly the musical facts its games drill — each fact shown (engraved
// notation) AND heard (playable audio). These are attached to representative
// games in game_registry.dart via GameInfo.tutorial and auto-shown on first
// play (see features/games/tutorial_gate.dart). Text lives in the ARBs (EN/DE).
//
// Adding a module's primer: write it here, add its ARB strings, and hang it on
// the module's entry game. See PLAN.md "Learnability & UX".

import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/midi_pitch.dart';
import 'package:comet_beat/shared/tutorial/tutorial.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show
        ChordSymbol,
        ChordSymbolKind,
        Clef,
        DurationBase,
        KeySignature,
        Measure,
        NoteDuration,
        NoteElement,
        RestElement,
        Score,
        TimeSignature;

// ---- notation helpers -------------------------------------------------------

/// A single-measure staff of [midis] as notes of the given [dur], on [clef]
/// (treble by default; pass `Clef.bass` for low-voice/cello/drum examples).
Score _notes(
  List<int> midis, {
  DurationBase dur = DurationBase.quarter,
  int dots = 0,
  Clef clef = Clef.treble,
  KeySignature keySignature = const KeySignature(0),
  TimeSignature? timeSignature,
  List<ChordSymbol> chordSymbols = const [],
}) =>
    Score(
      clef: clef,
      keySignature: keySignature,
      timeSignature: timeSignature,
      chordSymbols: chordSymbols,
      measures: [
        Measure([
          for (var i = 0; i < midis.length; i++)
            NoteElement.note(
              pitchFromMidi(midis[i]),
              NoteDuration(dur, dots: dots),
              id: 'n$i',
            ),
        ]),
      ],
    );

/// A single-measure staff mixing notes and rests: a `null` entry becomes a rest
/// of the same value, so silence can be *shown* next to sound.
Score _rhythm(
  List<int?> midis, {
  DurationBase dur = DurationBase.quarter,
}) =>
    Score(
      clef: Clef.treble,
      measures: [
        Measure([
          for (var i = 0; i < midis.length; i++)
            if (midis[i] case final int m)
              NoteElement.note(pitchFromMidi(m), NoteDuration(dur), id: 'n$i')
            else
              RestElement(NoteDuration(dur), id: 'r$i'),
        ]),
      ],
    );

/// A single stacked chord (whole note) of [midis] on a treble staff.
Score _chord(List<int> midis) => Score(
      clef: Clef.treble,
      measures: [
        Measure([
          NoteElement(
            pitches: midis.map(pitchFromMidi).toList(),
            duration: const NoteDuration(DurationBase.whole),
            id: 'chord',
          ),
        ]),
      ],
    );

const _cMajor = [60, 62, 64, 65, 67, 69, 71, 72]; // C D E F G A B C
const _aMinor = [57, 59, 60, 62, 64, 65, 67, 69]; // A B C D E F G A

List<(int, int)> _run(List<int> midis, {int ms = 320}) =>
    [for (final m in midis) (m, ms)];

// ---- primers ----------------------------------------------------------------

/// Reading notes on the staff (treble). Module: note_reading.
Tutorial readingPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerReadingTitle,
      steps: [
        TutorialStep(
          text: l10n.primerReadingStaff,
          score: _notes([64, 67, 71]), // E G B
        ),
        TutorialStep(
          text: l10n.primerReadingHigher,
          score: _notes([60, 64, 67, 72]), // C E G C'
          play: (a) => a.playSequence(_run([60, 64, 67, 72])),
        ),
        TutorialStep(
          text: l10n.primerReadingNames,
          score: _notes([64]), // E
          play: (a) => a.playMidiNote(64),
        ),
      ],
    );

/// How long a note lasts. Module: note_values.
Tutorial noteValuesPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerValuesTitle,
      steps: [
        TutorialStep(
          text: l10n.primerValuesWhole,
          score: _notes([60], dur: DurationBase.whole),
          play: (a) => a.playNoteLength(4, isRest: false),
        ),
        TutorialStep(
          text: l10n.primerValuesQuarter,
          score: _notes([60, 60, 60, 60]),
          play: (a) => a.playSequence(_run([60, 60, 60, 60], ms: 480)),
        ),
        TutorialStep(
          text: l10n.primerValuesRest,
          play: (a) => a.playNoteLength(1, isRest: true),
        ),
      ],
    );

/// Filling a measure to the beat. Module: measures.
Tutorial measuresPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerMeasuresTitle,
      steps: [
        TutorialStep(text: l10n.primerMeasuresBars),
        TutorialStep(
          text: l10n.primerMeasuresFill,
          score: _notes([60, 62, 64, 65]), // 4 quarters
          play: (a) => a.playSequence(_run([60, 62, 64, 65], ms: 480)),
        ),
        TutorialStep(
          text: l10n.primerMeasuresHalf,
          score: _notes([60, 64], dur: DurationBase.half),
          play: (a) => a.playSequence(_run([60, 64], ms: 960)),
        ),
      ],
    );

/// A scale is a ladder of notes; major vs minor colour. Module: scales.
Tutorial scalesPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerScalesTitle,
      steps: [
        TutorialStep(
          text: l10n.primerScalesLadder,
          score: _notes(_cMajor),
          play: (a) => a.playSequence(_run(_cMajor)),
        ),
        TutorialStep(
          text: l10n.primerScalesMajor,
          play: (a) => a.playSequence(_run(_cMajor)),
        ),
        TutorialStep(
          text: l10n.primerScalesMinor,
          play: (a) => a.playSequence(_run(_aMinor)),
        ),
      ],
    );

/// Stacking notes into chords/triads; major vs minor. Module: chords.
Tutorial chordsPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerChordsTitle,
      steps: [
        TutorialStep(
          text: l10n.primerChordsStack,
          score: _chord([60, 64, 67]), // C E G
          play: (a) => a.playMidiChord([60, 64, 67]),
        ),
        TutorialStep(
          text: l10n.primerChordsColour,
          play: (a) => a.playChordSequence([
            [60, 64, 67], // C major
            [60, 63, 67], // C minor
          ]),
        ),
        TutorialStep(
          text: l10n.primerChordsArpeggio,
          play: (a) => a.playArpeggioThenChord([60, 64, 67]),
        ),
      ],
    );

/// Chords have jobs: home (Tonic), pull (Dominant), the journey (cadence).
/// Module: harmony.
Tutorial harmonyPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerHarmonyTitle,
      steps: [
        TutorialStep(
          text: l10n.primerHarmonyHome,
          score: _chord([60, 64, 67]), // C major = home (Tonic)
          play: (a) => a.playMidiChord([60, 64, 67]),
        ),
        TutorialStep(
          text: l10n.primerHarmonyPull,
          score: _chord([67, 71, 74]), // G major = Dominant, pulls home
          play: (a) => a.playChordSequence([
            [67, 71, 74], // Dominant leaning...
            [60, 64, 67], // ...back to home
          ]),
        ),
        TutorialStep(
          text: l10n.primerHarmonyCadence,
          play: (a) => a.playChordSequence([
            [60, 64, 67], // I  — home
            [65, 69, 72], // IV — away
            [67, 71, 74], // V  — pull
            [60, 64, 67], // I  — home again
          ]),
        ),
      ],
    );

/// A melody is a journey; phrases ask a question and give an answer.
/// Module: composition.
Tutorial compositionPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerCompositionTitle,
      steps: [
        TutorialStep(
          text: l10n.primerCompositionJourney,
          score: _notes([60, 62, 64, 65, 64, 62, 60]), // up then home
          play: (a) => a.playSequence(_run([60, 62, 64, 65, 64, 62, 60])),
        ),
        TutorialStep(
          text: l10n.primerCompositionQuestion,
          score: _notes([60, 62, 64, 67]), // stops up on G — unfinished
          play: (a) => a.playSequence(_run([60, 62, 64, 67])),
        ),
        TutorialStep(
          text: l10n.primerCompositionAnswer,
          score: _notes([67, 65, 64, 62, 60]), // comes home to C
          play: (a) => a.playSequence(_run([67, 65, 64, 62, 60])),
        ),
      ],
    );

/// The four cello strings (C G D A) on the bass clef, and how fingers raise
/// the pitch. Module: cello.
Tutorial celloPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerCelloTitle,
      steps: [
        TutorialStep(
          text: l10n.primerCelloStrings,
          score: _notes([36, 43, 50, 57], clef: Clef.bass), // C G D A
          play: (a) => a.playSequence(_run([36, 43, 50, 57], ms: 600)),
        ),
        TutorialStep(
          text: l10n.primerCelloBass,
          score: _notes([36], clef: Clef.bass), // low C, thickest string
          play: (a) => a.playMidiNote(36),
        ),
        TutorialStep(
          text: l10n.primerCelloFinger,
          score: _notes([43, 45, 47], clef: Clef.bass), // G, then higher
          play: (a) => a.playSequence(_run([43, 45, 47], ms: 500)),
        ),
      ],
    );

/// The six guitar strings (E A D G B E) and how tab works. Module: guitar.
Tutorial guitarPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerGuitarTitle,
      steps: [
        TutorialStep(
          // Written an octave up, as guitar notation is — E3..E5.
          text: l10n.primerGuitarStrings,
          score: _notes([52, 57, 62, 67, 71, 76]), // E A D G B E
          play: (a) => a.playSequence(_run([52, 57, 62, 67, 71, 76], ms: 450)),
        ),
        TutorialStep(
          text: l10n.primerGuitarTab,
          play: (a) => a.playMidiNote(52), // the open low-E string
        ),
        TutorialStep(
          text: l10n.primerGuitarPlay,
          score: _notes([52, 76]), // low E up to high E
          play: (a) => a.playSequence(_run([52, 76], ms: 700)),
        ),
      ],
    );

/// How the song screens work: a tune drawn left-to-right, a marker to follow.
/// Module: songs.
Tutorial songsPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerSongsTitle,
      steps: [
        TutorialStep(
          text: l10n.primerSongsPick,
          score: _notes([60, 60, 67, 67, 69, 69, 67]), // Twinkle, line 1
          play: (a) => a.playSequence(_run([60, 60, 67, 67, 69, 69, 67])),
        ),
        TutorialStep(
          text: l10n.primerSongsMarker,
          score: _notes([65, 65, 64, 64, 62, 62, 60]), // Twinkle, line 2
          play: (a) => a.playSequence(_run([65, 65, 64, 64, 62, 62, 60])),
        ),
      ],
    );

/// The piano layout (white A–G, black in 2s and 3s), finding C, the grand
/// staff. Module: keyboard.
Tutorial keyboardPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerKeyboardTitle,
      steps: [
        TutorialStep(
          text: l10n.primerKeyboardWhite,
          play: (a) => a.playSequence(_run(_cMajor)),
        ),
        TutorialStep(
          text: l10n.primerKeyboardFindC,
          score: _notes(_cMajor),
          play: (a) => a.playSequence(_run(_cMajor)),
        ),
        TutorialStep(
          text: l10n.primerKeyboardHands,
          // Left hand low C + right hand C–E–G, sounding together.
          play: (a) => a.playMidiChord([48, 60, 64, 67]),
        ),
      ],
    );

/// Transposing instruments read one note and sound another. Module: transpose.
Tutorial transposePrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerTransposeTitle,
      steps: [
        TutorialStep(
          text: l10n.primerTransposeSame,
          score: _notes([60]), // read C...
          play: (a) => a.playMidiNote(60), // ...hear C
        ),
        TutorialStep(
          text: l10n.primerTransposeShift,
          score: _notes([60]), // read C on a B-flat instrument...
          play: (a) => a.playSequence(_run([60, 58], ms: 700)), // ...sounds B♭
        ),
      ],
    );

/// Drum notation: which drum + when, not pitch. Module: drums.
Tutorial drumsPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerDrumsTitle,
      steps: [
        TutorialStep(
          text: l10n.primerDrumsWhat,
          play: (a) =>
              a.playSequence([(36, 300), (50, 300), (36, 300), (50, 300)]),
        ),
        TutorialStep(
          text: l10n.primerDrumsLines,
          score: _notes([36, 50, 36, 50], clef: Clef.bass), // kick / snare row
          play: (a) => a.playSequence(_run([36, 50, 36, 50], ms: 360)),
        ),
      ],
    );

// ---- per-game primers (a distinct fact within an already-covered module) ----

/// Reading on the BASS clef — its lines/spaces spell different notes than
/// treble. Game: note_reading_bass.
Tutorial readingBassPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerBassTitle,
      steps: [
        TutorialStep(
          text: l10n.primerBassClef,
          // The five bass-staff lines, bottom to top: G2 B2 D3 F3 A3.
          score: _notes([43, 47, 50, 53, 57], clef: Clef.bass),
          play: (a) => a.playSequence(_run([43, 47, 50, 53, 57], ms: 460)),
        ),
        TutorialStep(
          text: l10n.primerBassMiddleC,
          score: _notes([60], clef: Clef.bass), // middle C, above the staff
          play: (a) => a.playMidiNote(60),
        ),
      ],
    );

/// Ledger lines — the little extra lines for notes above/below the staff.
/// Game: ledger_leap.
Tutorial ledgerPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerLedgerTitle,
      steps: [
        TutorialStep(
          text: l10n.primerLedgerMiddleC,
          score: _notes([60]), // C4 on one ledger line below the treble staff
          play: (a) => a.playMidiNote(60),
        ),
        TutorialStep(
          text: l10n.primerLedgerHigh,
          score: _notes([79, 81, 84]), // G5 A5 C6 — ledger lines above
          play: (a) => a.playSequence(_run([79, 81, 84])),
        ),
      ],
    );

/// Sharps raise, flats lower, by a semitone. Game: accidental_sort.
Tutorial accidentalsPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerAccidentalsTitle,
      steps: [
        TutorialStep(
          text: l10n.primerAccidentalsSharp,
          score: _notes([60, 61]), // C then C#
          play: (a) => a.playSequence(_run([60, 61], ms: 600)),
        ),
        TutorialStep(
          text: l10n.primerAccidentalsFlat,
          score: _notes([62, 61]), // D then Db (= same key as C#)
          play: (a) => a.playSequence(_run([62, 61], ms: 600)),
        ),
      ],
    );

/// Steps go to the neighbour; skips jump over one. Game: step_skip.
Tutorial stepSkipPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerStepSkipTitle,
      steps: [
        TutorialStep(
          text: l10n.primerStepSkipStep,
          score: _notes([60, 62]), // C–D: line to the touching space
          play: (a) => a.playSequence(_run([60, 62], ms: 600)),
        ),
        TutorialStep(
          text: l10n.primerStepSkipSkip,
          score: _notes([60, 64]), // C–E: line to the next line
          play: (a) => a.playSequence(_run([60, 64], ms: 600)),
        ),
      ],
    );

/// Close vs open SATB spacing: are the upper voices bunched or spread out?
/// Game: spacing_read.
Tutorial spacingPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerSpacingTitle,
      steps: [
        TutorialStep(
          text: l10n.primerSpacingClose,
          score: _chord([60, 64, 67]), // C–E–G: the top voices bunched together
          play: (a) => a.playMidiChord([48, 60, 64, 67]),
        ),
        TutorialStep(
          text: l10n.primerSpacingOpen,
          score: _chord([60, 67, 76]), // C–G–E: spread over an octave
          play: (a) => a.playMidiChord([48, 60, 67, 76]),
        ),
      ],
    );

/// An interval is the distance between two notes; wide vs narrow.
/// Game: interval_ear.
Tutorial intervalsPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerIntervalsTitle,
      steps: [
        TutorialStep(
          text: l10n.primerIntervalsCount,
          score: _notes([60, 64]), // C to E, counting C-D-E = a 3rd
          play: (a) => a.playSequence(_run([60, 64], ms: 600)),
        ),
        TutorialStep(
          text: l10n.primerIntervalsWide,
          score: _notes([60, 67]), // C to G = a 5th
          play: (a) => a.playSequence(_run([60, 67], ms: 600)),
        ),
        TutorialStep(
          text: l10n.primerIntervalsEar,
          // A narrow 2nd, then a wide 6th, so the ear hears the difference.
          play: (a) => a.playChordSequence([
            [60, 62], // a 2nd
            [60, 69], // a 6th
          ]),
        ),
      ],
    );

/// A key signature writes the sharps/flats once at the start. Game: key_sig.
Tutorial keySignaturePrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerKeySigTitle,
      steps: [
        TutorialStep(
          text: l10n.primerKeySigWhat,
          // G major: one sharp (F#) drawn once at the front.
          score: _notes(
            [67, 69, 71, 72, 74, 76, 78, 79],
            keySignature: const KeySignature(1),
          ),
          play: (a) => a.playSequence(_run([67, 69, 71, 72, 74, 76, 78, 79])),
        ),
        TutorialStep(
          text: l10n.primerKeySigCompare,
          // C major has none; listen for the one note that differs (F vs F#).
          play: (a) => a.playSequence(_run(_cMajor)),
        ),
      ],
    );

/// The time signature: the top number is beats per measure. Game: time_signature.
Tutorial timeSignaturePrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerTimeSigTitle,
      steps: [
        TutorialStep(
          text: l10n.primerTimeSigFour,
          score: _notes(
            [60, 62, 64, 65], // four beats
            timeSignature: const TimeSignature(4, 4),
          ),
          play: (a) => a.playCountedNote(4),
        ),
        TutorialStep(
          text: l10n.primerTimeSigThree,
          score: _notes(
            [60, 62, 64], // a waltz's three
            timeSignature: const TimeSignature(3, 4),
          ),
          play: (a) => a.playCountedNote(3),
        ),
      ],
    );

/// Lead-sheet chord symbols: a letter names the chord above the tune.
/// Game: chord_chart.
Tutorial chordChartPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerChartTitle,
      steps: [
        TutorialStep(
          text: l10n.primerChartMajor,
          // "C" above the note = play a C major chord.
          score: _notes(
            [60],
            chordSymbols: [
              ChordSymbol('n0', pitchFromMidi(60), ChordSymbolKind.major),
            ],
          ),
          play: (a) => a.playMidiChord([60, 64, 67]),
        ),
        TutorialStep(
          text: l10n.primerChartMinor,
          // "Am" = A minor.
          score: _notes(
            [57],
            chordSymbols: [
              ChordSymbol('n0', pitchFromMidi(57), ChordSymbolKind.minor),
            ],
          ),
          play: (a) => a.playMidiChord([57, 60, 64]),
        ),
      ],
    );

/// Where a tune begins: on the downbeat (beat 1) vs with an upbeat / anacrusis —
/// a note or two BEFORE the first barline that lead into beat 1.
/// Game: spot_upbeat.
Tutorial upbeatPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerUpbeatTitle,
      steps: [
        TutorialStep(
          text: l10n.primerUpbeatDownbeat,
          score: _notes([60, 62, 64, 65]), // C D E F — starts on beat 1
          play: (a) => a.playSequence(_run([60, 62, 64, 65], ms: 500)),
        ),
        TutorialStep(
          text: l10n.primerUpbeatUpbeat,
          // A single pickup note leading into the downbeat — hear the lead-in.
          play: (a) => a.playSequence(_run([67, 60, 62, 64], ms: 500)),
        ),
      ],
    );

/// Enharmonic twins: one piano key, two spellings (F♯ = G♭), the same sound.
/// Game: enharmonic.
Tutorial enharmonicPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerEnharmonicTitle,
      steps: [
        TutorialStep(
          text: l10n.primerEnharmonicSame,
          score: _notes([66]), // one key — spelled F♯ or G♭
          play: (a) => a.playSequence(_run([66], ms: 600)),
        ),
        TutorialStep(
          text: l10n.primerEnharmonicTwins,
          // The same pitch twice — identical sound, two names.
          play: (a) => a.playSequence(_run([66, 66], ms: 500)),
        ),
      ],
    );

/// Italian tempo words: the speed written at the top of a piece. The SAME phrase
/// is played slow then fast, so the word maps onto a heard difference.
/// Games: tempo_duel, connect_tempo.
Tutorial tempoTermsPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerTempoTitle,
      steps: [
        TutorialStep(
          text: l10n.primerTempoSlow,
          score: _notes([60, 62, 64, 65]),
          play: (a) => a.playPhrase([60, 62, 64, 65], noteMs: 750), // Adagio
        ),
        TutorialStep(
          text: l10n.primerTempoFast,
          score: _notes([60, 62, 64, 65]),
          play: (a) => a.playPhrase([60, 62, 64, 65], noteMs: 220), // Allegro
        ),
      ],
    );

/// Dynamics: p/f and their families. The same phrase is played soft then loud
/// (a real gain difference), so the letters map onto a heard difference.
/// Games: dynamics_duel, connect_dynamics.
Tutorial dynamicsPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerDynamicsTitle,
      steps: [
        TutorialStep(
          text: l10n.primerDynamicsSoft,
          score: _notes([60, 64, 67]),
          play: (a) => a.playPhrase([60, 64, 67], gain: 0.22), // piano
        ),
        TutorialStep(
          text: l10n.primerDynamicsLoud,
          score: _notes([60, 64, 67]),
          play: (a) => a.playPhrase([60, 64, 67]), // forte (full gain)
        ),
      ],
    );

/// The augmentation dot: it adds HALF the note's value again. Shown as a half
/// note (2 beats) beside a dotted half (3 beats), and heard at those lengths.
/// Game: dotted_sort.
Tutorial dottedNotePrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerDottedTitle,
      steps: [
        TutorialStep(
          text: l10n.primerDottedPlain,
          score: _notes([60], dur: DurationBase.half),
          play: (a) => a.playPhrase([60], noteMs: 1000), // 2 beats
        ),
        TutorialStep(
          text: l10n.primerDottedDotted,
          score: _notes([60], dur: DurationBase.half, dots: 1),
          play: (a) => a.playPhrase([60], noteMs: 1500), // 3 beats — half again
        ),
      ],
    );

/// Rests: silence with a written length. Shown as note/rest/note/rest and heard
/// with real gaps, then paired value-for-value with notes.
/// Game: connect_rests.
Tutorial restsPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerRestsTitle,
      steps: [
        TutorialStep(
          text: l10n.primerRestsSilence,
          score: _rhythm([60, null, 62, null]),
          // An empty chord is a beat of silence — play, rest, play, rest.
          play: (a) => a.playChordSequence(
            const [
              [60],
              [],
              [62],
              [],
            ],
            ms: 500,
          ),
        ),
        TutorialStep(
          text: l10n.primerRestsMatch,
          // A half note then a half rest: same value, one sounds, one doesn't.
          score: _rhythm([60, null], dur: DurationBase.half),
          play: (a) => a.playChordSequence(
            const [
              [60],
              [],
            ],
            ms: 1000,
          ),
        ),
      ],
    );
