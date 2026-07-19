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
        Articulation,
        ChordSymbol,
        ChordSymbolKind,
        Clef,
        DurationBase,
        KeySignature,
        Measure,
        NoteDuration,
        NoteElement,
        Ornament,
        Pitch,
        RestElement,
        Score,
        Slur,
        Step,
        TimeSignature,
        TupletSpan;

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

/// Two half notes joined by a curve: a **tie** when [tie] (same pitch — the
/// engraver draws it from `tieToNext`), else a **slur** across the two pitches.
Score _curvePair(int a, int b, {required bool tie}) => Score(
      clef: Clef.treble,
      measures: [
        Measure([
          NoteElement.note(
            pitchFromMidi(a),
            const NoteDuration(DurationBase.half),
            id: 'a',
            tieToNext: tie,
          ),
          NoteElement.note(
            pitchFromMidi(b),
            const NoteDuration(DurationBase.half),
            id: 'b',
          ),
        ]),
      ],
      slurs: tie ? const [] : const [Slur('a', 'b')],
    );

/// [midis] as quarter notes, each carrying [art] — so the mark is *shown*.
Score _articulated(
  List<int> midis,
  Articulation art, {
  Clef clef = Clef.treble,
}) =>
    Score(
      clef: clef,
      measures: [
        Measure([
          for (var i = 0; i < midis.length; i++)
            NoteElement.note(
              pitchFromMidi(midis[i]),
              const NoteDuration(DurationBase.quarter),
              articulations: {art},
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

/// Chords across measures, one per bar — a short progression, so a cadence's
/// two steps can be *seen* as well as heard.
Score _progression(List<List<int>> chords) => Score(
      clef: Clef.treble,
      measures: [
        for (var i = 0; i < chords.length; i++)
          Measure([
            NoteElement(
              pitches: chords[i].map(pitchFromMidi).toList(),
              duration: const NoteDuration(DurationBase.whole),
              id: 'c$i',
            ),
          ]),
      ],
    );

/// A pickup (anacrusis): a short lead-in bar drawn before a full downbeat bar,
/// so the upbeat itself is visible, not just described.
Score _pickup(List<int> lead, List<int> bar) => Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(4, 4),
      measures: [
        Measure(
          [
            for (var i = 0; i < lead.length; i++)
              NoteElement.note(
                pitchFromMidi(lead[i]),
                const NoteDuration(DurationBase.quarter),
                id: 'p$i',
              ),
          ],
          pickup: true,
        ),
        Measure([
          for (var i = 0; i < bar.length; i++)
            NoteElement.note(
              pitchFromMidi(bar[i]),
              const NoteDuration(DurationBase.quarter),
              id: 'b$i',
            ),
        ]),
      ],
    );

/// Explicitly-spelled notes, so enharmonic twins (F♯ vs G♭) can be *shown* at
/// their different staff positions even though they sound the same.
Score _spelled(List<(Step, int)> spellings, {int octave = 4}) => Score(
      clef: Clef.treble,
      measures: [
        Measure([
          for (var i = 0; i < spellings.length; i++)
            NoteElement.note(
              Pitch(spellings[i].$1, alter: spellings[i].$2, octave: octave),
              const NoteDuration(DurationBase.whole),
              showAccidental: true,
              id: 's$i',
            ),
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
          beats: _run([60, 64, 67, 72]),
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
          beats: _run([60, 60, 60, 60], ms: 480),
        ),
        TutorialStep(
          text: l10n.primerValuesRest,
          play: (a) => a.playNoteLength(1, isRest: true),
        ),
        // Active recall: the child counts the whole note's beats themselves.
        TutorialStep(
          text: l10n.primerValuesTry,
          score: _notes([60], dur: DurationBase.whole),
          choices: const [
            TutorialChoice('4', correct: true),
            TutorialChoice('2'),
            TutorialChoice('1'),
          ],
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
          beats: _run([60, 62, 64, 65], ms: 480),
        ),
        TutorialStep(
          text: l10n.primerMeasuresHalf,
          score: _notes([60, 64], dur: DurationBase.half),
          beats: _run([60, 64], ms: 960),
        ),
        // Active recall: count the beats in a full 4/4 bar.
        TutorialStep(
          text: l10n.primerMeasuresTry,
          score: _notes([60, 62, 64, 65]),
          choices: const [
            TutorialChoice('4', correct: true),
            TutorialChoice('3'),
            TutorialChoice('2'),
          ],
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
          beats: _run(_cMajor),
        ),
        TutorialStep(
          text: l10n.primerScalesMajor,
          beats: _run(_cMajor),
        ),
        TutorialStep(
          text: l10n.primerScalesMinor,
          beats: _run(_aMinor),
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
          beats: _run([60, 62, 64, 65, 64, 62, 60]),
        ),
        TutorialStep(
          text: l10n.primerCompositionQuestion,
          score: _notes([60, 62, 64, 67]), // stops up on G — unfinished
          beats: _run([60, 62, 64, 67]),
        ),
        TutorialStep(
          text: l10n.primerCompositionAnswer,
          score: _notes([67, 65, 64, 62, 60]), // comes home to C
          beats: _run([67, 65, 64, 62, 60]),
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
          beats: _run([36, 43, 50, 57], ms: 600),
        ),
        TutorialStep(
          text: l10n.primerCelloBass,
          score: _notes([36], clef: Clef.bass), // low C, thickest string
          play: (a) => a.playMidiNote(36),
        ),
        TutorialStep(
          text: l10n.primerCelloFinger,
          score: _notes([43, 45, 47], clef: Clef.bass), // G, then higher
          beats: _run([43, 45, 47], ms: 500),
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
          beats: _run([52, 57, 62, 67, 71, 76], ms: 450),
        ),
        TutorialStep(
          text: l10n.primerGuitarTab,
          play: (a) => a.playMidiNote(52), // the open low-E string
        ),
        TutorialStep(
          text: l10n.primerGuitarPlay,
          score: _notes([52, 76]), // low E up to high E
          beats: _run([52, 76], ms: 700),
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
          beats: _run([60, 60, 67, 67, 69, 69, 67]),
        ),
        TutorialStep(
          text: l10n.primerSongsMarker,
          score: _notes([65, 65, 64, 64, 62, 62, 60]), // Twinkle, line 2
          beats: _run([65, 65, 64, 64, 62, 62, 60]),
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
          beats: _run(_cMajor),
        ),
        TutorialStep(
          text: l10n.primerKeyboardFindC,
          score: _notes(_cMajor),
          beats: _run(_cMajor),
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
          beats: _run([60, 58], ms: 700), // ...sounds B♭
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
          beats: _run([36, 50, 36, 50], ms: 360),
        ),
      ],
    );

/// Modulation: a phrase can stay in one key, or move to a new home note partway
/// through. Game: modulation_ear.
Tutorial modulationPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerModulationTitle,
      steps: [
        TutorialStep(
          text: l10n.primerModulationStay,
          // C-major fragment twice: the same home note (C) both times.
          score: _notes([60, 64, 67, 64, 60, 62, 64, 60]),
          beats: _run([60, 64, 67, 64, 60, 62, 64, 60], ms: 360),
        ),
        TutorialStep(
          text: l10n.primerModulationMove,
          // Same fragment, then lifted up a 5th (to G): a new home note.
          score: _notes([60, 64, 67, 64, 60, 67, 71, 67]),
          beats: _run([60, 64, 67, 64, 60, 67, 71, 67], ms: 360),
        ),
      ],
    );

/// The orchestral instrument families: strings, winds (woodwind + brass),
/// percussion and keyboard — named with familiar examples. Game:
/// instrument_family.
Tutorial instrumentFamilyPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerFamilyTitle,
      steps: [
        TutorialStep(
          text: l10n.primerFamilyStrings,
          // A warm plucked/bowed-string triad to set the scene.
          play: (a) => a.playMidiChord([55, 62, 67]),
        ),
        TutorialStep(
          text: l10n.primerFamilyWinds,
          // A bright fanfare-ish chord for the wind families.
          play: (a) => a.playMidiChord([60, 64, 67]),
        ),
        TutorialStep(
          text: l10n.primerFamilyPercKeys,
          // A full keyboard-style stack (two hands) for percussion + keys.
          play: (a) => a.playMidiChord([48, 60, 64, 67]),
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
          beats: _run([43, 47, 50, 53, 57], ms: 460),
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
          beats: _run([79, 81, 84]),
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
          beats: _run([60, 61], ms: 600),
        ),
        TutorialStep(
          text: l10n.primerAccidentalsFlat,
          score: _notes([62, 61]), // D then Db (= same key as C#)
          beats: _run([62, 61], ms: 600),
        ),
        // Active recall: which sign raises the pitch?
        TutorialStep(
          text: l10n.primerAccidentalsTry,
          choices: const [
            TutorialChoice('♯', correct: true),
            TutorialChoice('♭'),
          ],
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
          beats: _run([60, 62], ms: 600),
        ),
        TutorialStep(
          text: l10n.primerStepSkipSkip,
          score: _notes([60, 64]), // C–E: line to the next line
          beats: _run([60, 64], ms: 600),
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
          beats: _run([60, 64], ms: 600),
        ),
        TutorialStep(
          text: l10n.primerIntervalsWide,
          score: _notes([60, 67]), // C to G = a 5th
          beats: _run([60, 67], ms: 600),
        ),
        TutorialStep(
          text: l10n.primerIntervalsEar,
          // A narrow 2nd, then a wide 6th, so the ear hears the difference.
          play: (a) => a.playChordSequence([
            [60, 62], // a 2nd
            [60, 69], // a 6th
          ]),
        ),
        TutorialStep(
          text: l10n.primerIntervalsSong,
          // You already know intervals from songs: the cuckoo's falling call is
          // a descending minor 3rd (G → E).
          score: _notes([67, 64]),
          beats: _run([67, 64], ms: 700),
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
          beats: _run([67, 69, 71, 72, 74, 76, 78, 79]),
        ),
        TutorialStep(
          text: l10n.primerKeySigCompare,
          // C major has none; listen for the one note that differs (F vs F#).
          beats: _run(_cMajor),
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
        // Active recall: read the top number of a 3/4 signature.
        TutorialStep(
          text: l10n.primerTimeSigTry,
          score: _notes(
            [60, 62, 64],
            timeSignature: const TimeSignature(3, 4),
          ),
          choices: const [
            TutorialChoice('3', correct: true),
            TutorialChoice('4'),
            TutorialChoice('2'),
          ],
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
          beats: _run([60, 62, 64, 65], ms: 500),
        ),
        TutorialStep(
          text: l10n.primerUpbeatUpbeat,
          // The pickup bar (G) drawn before the full downbeat bar (C D E F).
          score: _pickup(const [67], const [60, 62, 64, 65]),
          beats: _run([67, 60, 62, 64], ms: 500),
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
          // F♯ and G♭ drawn side by side: different spots, same sound.
          score: _spelled(const [(Step.f, 1), (Step.g, -1)]),
          beats: _run([66, 66], ms: 700),
        ),
        TutorialStep(
          text: l10n.primerEnharmonicTwins,
          // Another twin pair shown: C♯ and D♭.
          score: _spelled(const [(Step.c, 1), (Step.d, -1)]),
          beats: _run([61, 61], ms: 700),
        ),
      ],
    );

/// Stacking one more third on a triad: the seventh chord and its restlessness.
/// Game: triad_seventh.
Tutorial seventhPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerSeventhTitle,
      steps: [
        TutorialStep(
          text: l10n.primerSeventhTriad,
          score: _chord([60, 64, 67]), // C E G — root, third, fifth
          play: (a) => a.playMidiChord([60, 64, 67]),
        ),
        TutorialStep(
          text: l10n.primerSeventhAdd,
          score: _chord([60, 64, 67, 70]), // + B♭ = a dominant seventh
          play: (a) => a.playMidiChord([60, 64, 67, 70]),
        ),
      ],
    );

/// Roman numerals: naming a chord by WHICH scale degree it is built on.
/// Game: roman_numeral.
Tutorial romanPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerRomanTitle,
      steps: [
        TutorialStep(
          text: l10n.primerRomanDegree,
          score: _chord([60, 64, 67]), // C major in C major = I
          play: (a) => a.playMidiChord([60, 64, 67]),
        ),
        TutorialStep(
          text: l10n.primerRomanCase,
          score: _chord([62, 65, 69]), // D minor in C major = ii
          play: (a) => a.playMidiChord([62, 65, 69]),
        ),
      ],
    );

/// Cadences: how a phrase ends — musical punctuation.
/// Game: cadence_workshop.
Tutorial cadencePrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerCadenceTitle,
      steps: [
        TutorialStep(
          text: l10n.primerCadenceFull,
          // Away chord → home chord: the full stop.
          score: _progression(const [
            [67, 71, 74],
            [60, 64, 67],
          ]),
          play: (a) => a.playChordSequence(
            const [
              [67, 71, 74],
              [60, 64, 67],
            ],
          ),
        ),
        TutorialStep(
          text: l10n.primerCadenceHalf,
          // Home chord → away chord: left hanging, a question mark.
          score: _progression(const [
            [60, 64, 67],
            [67, 71, 74],
          ]),
          play: (a) => a.playChordSequence(
            const [
              [60, 64, 67],
              [67, 71, 74],
            ],
          ),
        ),
      ],
    );

/// Phrases as sentences: a question that hangs, an answer that comes home.
/// Games: ending_detective, question_answer.
Tutorial phrasePrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerPhraseTitle,
      steps: [
        TutorialStep(
          text: l10n.primerPhraseQuestion,
          score: _notes([60, 62, 64, 67]), // climbs away, stops in the air
          play: (a) => a.playPhrase([60, 62, 64, 67], noteMs: 480),
        ),
        TutorialStep(
          text: l10n.primerPhraseAnswer,
          score: _notes([67, 65, 64, 60]), // comes home to the tonic
          play: (a) => a.playPhrase([67, 65, 64, 60], noteMs: 480),
        ),
      ],
    );

/// Bow direction: the two ways the bow travels.
/// Game: bowing.
Tutorial bowingPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerBowTitle,
      steps: [
        TutorialStep(
          text: l10n.primerBowDown,
          score: _articulated([48, 50], Articulation.downBow, clef: Clef.bass),
          play: (a) => a.playPhrase([48, 50], noteMs: 700),
        ),
        TutorialStep(
          text: l10n.primerBowUp,
          score: _articulated([48, 50], Articulation.upBow, clef: Clef.bass),
          play: (a) => a.playPhrase([48, 50], noteMs: 700, gain: 0.5),
        ),
      ],
    );

/// The tenor clef: a movable C-clef that keeps high cello notes off ledger lines.
/// Game: note_reading_tenor.
Tutorial tenorClefPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerTenorTitle,
      steps: [
        TutorialStep(
          text: l10n.primerTenorC,
          score:
              _notes([60], clef: Clef.tenor), // middle C, where the sign points
          play: (a) => a.playPhrase([60], noteMs: 700),
        ),
        TutorialStep(
          text: l10n.primerTenorWhy,
          score: _notes([65, 67, 69], clef: Clef.tenor),
          play: (a) => a.playPhrase([65, 67, 69], noteMs: 500),
        ),
      ],
    );

/// The grand staff: two staves braced together, one per hand.
/// Game: grand_staff_read.
Tutorial grandStaffPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerGrandTitle,
      steps: [
        TutorialStep(
          text: l10n.primerGrandTop,
          score: _notes([67, 72]), // right hand, treble
          play: (a) => a.playPhrase([67, 72], noteMs: 600),
        ),
        TutorialStep(
          text: l10n.primerGrandBottom,
          score: _notes([48, 53], clef: Clef.bass), // left hand, bass
          play: (a) => a.playPhrase([48, 53], noteMs: 600),
        ),
      ],
    );

/// Which way a melody moves: climbing vs falling.
/// Games: direction_ear, run_direction, pitch_sort (+bass).
Tutorial directionPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerDirectionTitle,
      steps: [
        TutorialStep(
          text: l10n.primerDirectionUp,
          score: _notes([60, 62, 64, 67]),
          play: (a) => a.playPhrase([60, 62, 64, 67], noteMs: 450),
        ),
        TutorialStep(
          text: l10n.primerDirectionDown,
          score: _notes([67, 64, 62, 60]),
          play: (a) => a.playPhrase([67, 64, 62, 60], noteMs: 450),
        ),
      ],
    );

/// Telling "the very same pitch" from "a different pitch" by ear.
/// Game: same_diff.
Tutorial sameDiffPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerSameDiffTitle,
      steps: [
        TutorialStep(
          text: l10n.primerSameDiffSame,
          score: _notes([60, 60]), // the same note twice — an echo
          play: (a) => a.playPhrase([60, 60], noteMs: 600),
        ),
        TutorialStep(
          text: l10n.primerSameDiffDifferent,
          score: _notes([60, 62]), // a step apart — clearly not an echo
          play: (a) => a.playPhrase([60, 62], noteMs: 600),
        ),
      ],
    );

/// Counting how many separate notes go by — aural attention, no staff needed.
/// Game: count_notes.
Tutorial countNotesPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerCountTitle,
      steps: [
        TutorialStep(
          text: l10n.primerCountThree,
          score: _notes([60, 64, 67]),
          play: (a) => a.playPhrase([60, 64, 67], noteMs: 550),
        ),
        TutorialStep(
          text: l10n.primerCountFour,
          score: _notes([60, 62, 64, 65]),
          play: (a) => a.playPhrase([60, 62, 64, 65], noteMs: 550),
        ),
      ],
    );

/// Metric accent: not every beat carries the same weight.
/// Game: strong_beat.
Tutorial strongBeatPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerAccentTitle,
      steps: [
        TutorialStep(
          text: l10n.primerAccentCount,
          score: _notes(
            [60, 60, 60, 60],
            timeSignature: const TimeSignature(4, 4),
          ),
          // Beat 1 lands strong, beats 2-3-4 follow lighter — hear the pulse.
          play: (a) async {
            await a.playPhrase([60], noteMs: 480);
            await a.playPhrase([60, 60, 60], noteMs: 480, gain: 0.3);
          },
        ),
        TutorialStep(
          text: l10n.primerAccentThree,
          score: _notes(
            [60, 60, 60],
            timeSignature: const TimeSignature(3, 4),
          ),
          play: (a) async {
            await a.playPhrase([60], noteMs: 480);
            await a.playPhrase([60, 60], noteMs: 480, gain: 0.3);
          },
        ),
        // Active recall: name the strong beat in 4/4.
        TutorialStep(
          text: l10n.primerAccentTry,
          choices: const [
            TutorialChoice('1', correct: true),
            TutorialChoice('2'),
            TutorialChoice('3'),
            TutorialChoice('4'),
          ],
        ),
      ],
    );

/// The two curves that look alike: a tie holds one pitch, a slur means smooth.
/// Game: tie_slur.
Tutorial tieSlurPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerCurveTitle,
      steps: [
        TutorialStep(
          text: l10n.primerCurveTie,
          score: _curvePair(60, 60, tie: true), // C tied to C = one long C
          play: (a) => a.playPhrase([60], noteMs: 1600), // held, not replayed
        ),
        TutorialStep(
          text: l10n.primerCurveSlur,
          score: _curvePair(60, 64, tie: false), // C slurred to E
          play: (a) => a.playPhrase([60, 64], noteMs: 800),
        ),
      ],
    );

/// Articulation marks: HOW a note is played (short vs emphasised).
/// Game: articulation_read.
Tutorial articulationPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerArticulationTitle,
      steps: [
        TutorialStep(
          text: l10n.primerArticulationStaccato,
          score: _articulated([60, 62, 64], Articulation.staccato),
          // Short and detached: brief notes with air between them.
          play: (a) => a.playPhrase([60, 62, 64], noteMs: 160),
        ),
        TutorialStep(
          text: l10n.primerArticulationAccent,
          score: _articulated([60, 62, 64], Articulation.accent),
          // Emphasised: the same notes, pushed harder.
          play: (a) => a.playPhrase([60, 62, 64], noteMs: 420),
        ),
      ],
    );

/// The two looks of eighth notes: a flag each, or joined by a beam.
/// Game: beam_flag.
Tutorial beamPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerBeamTitle,
      steps: [
        TutorialStep(
          text: l10n.primerBeamFlag,
          // Split by eighth rests, so each eighth keeps its own flag.
          score: _rhythm([60, null, 62, null], dur: DurationBase.eighth),
          play: (a) => a.playChordSequence(
            const [
              [60],
              [],
              [62],
              [],
            ],
            ms: 280,
          ),
        ),
        TutorialStep(
          text: l10n.primerBeamBeam,
          // Two eighths on one beat — the engraver joins them with a beam.
          score: _notes([60, 62], dur: DurationBase.eighth),
          play: (a) => a.playPhrase([60, 62], noteMs: 280),
        ),
      ],
    );

/// The smallest step vs the step that skips a key: semitone vs whole tone.
/// Game: whole_half.
Tutorial wholeHalfPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerToneTitle,
      steps: [
        TutorialStep(
          text: l10n.primerToneHalf,
          score: _notes([64, 65]), // E–F: neighbours, no key between
          play: (a) => a.playPhrase([64, 65], noteMs: 650),
        ),
        TutorialStep(
          text: l10n.primerToneWhole,
          score: _notes([60, 62]), // C–D: a black key sits between
          play: (a) => a.playPhrase([60, 62], noteMs: 650),
        ),
      ],
    );

/// The clef sign tells you which notes the lines mean.
/// Game: which_clef.
Tutorial clefsPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerClefTitle,
      steps: [
        TutorialStep(
          text: l10n.primerClefTreble,
          score:
              _notes([67]), // G above middle C, on the line the clef curls on
          play: (a) => a.playPhrase([67], noteMs: 700),
        ),
        TutorialStep(
          text: l10n.primerClefBass,
          score:
              _notes([53], clef: Clef.bass), // F below middle C, between dots
          play: (a) => a.playPhrase([53], noteMs: 700),
        ),
      ],
    );

/// Four voices at once: which line is yours?
/// Games: duet, read_voice, which_voice, hear_voice.
Tutorial voicesPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerVoicesTitle,
      steps: [
        TutorialStep(
          text: l10n.primerVoicesChord,
          score: _chord([60, 64, 67, 72]), // four voices sounding together
          play: (a) => a.playMidiChord([60, 64, 67, 72]),
        ),
        TutorialStep(
          text: l10n.primerVoicesFollow,
          // The outer voices only — soprano on top, bass at the bottom.
          score: _chord([60, 72]),
          play: (a) => a.playPhrase([72, 60], noteMs: 700),
        ),
      ],
    );

/// Expression = the two things Charades listens for at once: how FAST (tempo)
/// and how LOUD (dynamics). Each axis is played as its two extremes.
/// Game: charades.
Tutorial expressionPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerExpressionTitle,
      steps: [
        TutorialStep(
          text: l10n.primerExpressionTempo,
          score: _notes([60, 62, 64, 65]),
          // Slow (Adagio) then fast (Presto) — the same phrase, two speeds.
          play: (a) async {
            await a.playPhrase([60, 62, 64, 65], noteMs: 750);
            await a.playPhrase([60, 62, 64, 65], noteMs: 200);
          },
        ),
        TutorialStep(
          text: l10n.primerExpressionDynamics,
          score: _notes([60, 64, 67]),
          // Soft (piano) then loud (forte) — the same phrase, two volumes.
          play: (a) async {
            await a.playPhrase([60, 64, 67], gain: 0.22);
            await a.playPhrase([60, 64, 67]);
          },
        ),
      ],
    );

/// Musical form: the shape a piece makes when its sections repeat.
/// Game: form_read.
Tutorial formPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerFormTitle,
      steps: [
        TutorialStep(
          text: l10n.primerFormSection,
          score: _notes([60, 64, 67, 72]), // section A — a rising tune
          beats: _run([60, 64, 67, 72]),
        ),
        TutorialStep(
          text: l10n.primerFormAba,
          score: _notes([71, 69, 67, 65]), // section B — a different tune
          // Play the whole shape: A, then B, then A again = the form A-B-A.
          play: (a) => a.playSequence([
            for (final m in [60, 64, 67, 72]) (m, 300),
            for (final m in [71, 69, 67, 65]) (m, 300),
            for (final m in [60, 64, 67, 72]) (m, 300),
          ]),
        ),
      ],
    );

/// Syncopation: pushing the accent off the beat, where the ear doesn't expect it.
/// Game: sync_read.
Tutorial syncopationPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerSyncTitle,
      steps: [
        TutorialStep(
          text: l10n.primerSyncStraight,
          score: _notes([60, 60, 60, 60]), // four quarters, on the beats
          play: (a) => a.playSequence([for (var i = 0; i < 4; i++) (60, 600)]),
        ),
        TutorialStep(
          text: l10n.primerSyncOff,
          // Eighth + 3 quarters + eighth: the middle notes land off the beat.
          score: Score(
            clef: Clef.treble,
            timeSignature: TimeSignature.fourFour,
            measures: [
              Measure([
                NoteElement.note(
                  pitchFromMidi(60),
                  const NoteDuration(DurationBase.eighth),
                  id: 's0',
                ),
                NoteElement.note(
                  pitchFromMidi(60),
                  const NoteDuration(DurationBase.quarter),
                  id: 's1',
                ),
                NoteElement.note(
                  pitchFromMidi(60),
                  const NoteDuration(DurationBase.quarter),
                  id: 's2',
                ),
                NoteElement.note(
                  pitchFromMidi(60),
                  const NoteDuration(DurationBase.quarter),
                  id: 's3',
                ),
                NoteElement.note(
                  pitchFromMidi(60),
                  const NoteDuration(DurationBase.eighth),
                  id: 's4',
                ),
              ]),
            ],
          ),
          play: (a) => a.playSequence(
            [(60, 300), (60, 600), (60, 600), (60, 600), (60, 300)],
          ),
        ),
      ],
    );

/// Triplets: three equal notes squeezed into one beat instead of two.
/// Game: triplet_read.
Tutorial tripletPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerTripletTitle,
      steps: [
        TutorialStep(
          text: l10n.primerTripletEven,
          score: _notes([60, 60], dur: DurationBase.eighth), // 1-and
          play: (a) => a.playSequence([(60, 300), (60, 300)]),
        ),
        TutorialStep(
          text: l10n.primerTripletThree,
          // A real triplet (bracket + 3): three eighths in the beat.
          score: Score(
            clef: Clef.treble,
            measures: [
              Measure(
                [
                  NoteElement.note(
                    pitchFromMidi(60),
                    const NoteDuration(DurationBase.eighth),
                    id: 't0',
                  ),
                  NoteElement.note(
                    pitchFromMidi(60),
                    const NoteDuration(DurationBase.eighth),
                    id: 't1',
                  ),
                  NoteElement.note(
                    pitchFromMidi(60),
                    const NoteDuration(DurationBase.eighth),
                    id: 't2',
                  ),
                ],
                tuplets: const [
                  TupletSpan(0, 2, actual: 3, normal: 2),
                ],
              ),
            ],
          ),
          play: (a) => a.playSequence([(60, 200), (60, 200), (60, 200)]),
        ),
      ],
    );

/// Ornaments: little signs that tell you to decorate a note.
/// Game: ornament_read.
Tutorial ornamentPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerOrnamentTitle,
      steps: [
        TutorialStep(
          text: l10n.primerOrnamentTrill,
          score: Score(
            clef: Clef.treble,
            measures: [
              Measure([
                NoteElement.note(
                  pitchFromMidi(67),
                  const NoteDuration(DurationBase.half),
                  id: 'o',
                  ornament: Ornament.trill,
                ),
              ]),
            ],
          ),
          play: (a) => a.playSequence(
            [(67, 90), (69, 90), (67, 90), (69, 90), (67, 240)],
          ),
        ),
        TutorialStep(
          text: l10n.primerOrnamentTurn,
          score: Score(
            clef: Clef.treble,
            measures: [
              Measure([
                NoteElement.note(
                  pitchFromMidi(67),
                  const NoteDuration(DurationBase.half),
                  id: 'o',
                  ornament: Ornament.turn,
                ),
              ]),
            ],
          ),
          play: (a) =>
              a.playSequence([(69, 140), (67, 140), (66, 140), (67, 360)]),
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

/// Musical road signs — how to navigate repeats (Da Capo, Dal Segno, Fine,
/// Coda). Text-only: these are printed directions, not sounds. Game:
/// connect_roadmap.
Tutorial roadmapPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerRoadmapTitle,
      steps: [
        TutorialStep(text: l10n.primerRoadmapDaCapo),
        TutorialStep(text: l10n.primerRoadmapCoda),
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

/// Modes: three colours of scale from the same tonic — Major (bright), natural
/// Minor (darker), and Dorian (minor-shaped but with a brighter raised 6th).
/// Game: mode_ear.
Tutorial modePrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerModeTitle,
      steps: [
        TutorialStep(
          text: l10n.primerModeMajor,
          score: _notes(_cMajor), // C major = bright
          beats: _run(_cMajor),
        ),
        TutorialStep(
          text: l10n.primerModeMinor,
          // C natural minor: lowered 3rd, 6th and 7th — darker.
          score: _notes(const [60, 62, 63, 65, 67, 68, 70, 72]),
          beats: _run(const [60, 62, 63, 65, 67, 68, 70, 72]),
        ),
        TutorialStep(
          text: l10n.primerModeDorian,
          // C Dorian = C minor but the 6th (A♭→A) is raised: minor, yet brighter.
          score: _notes(const [60, 62, 63, 65, 67, 69, 70, 72]),
          beats: _run(const [60, 62, 63, 65, 67, 69, 70, 72]),
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

/// Every note lives in SEVERAL places on the fretboard — the same pitch sits on
/// different strings at different frets, so finding ANY one of them is right.
/// Game: fretboard_find.
Tutorial fretboardFindPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerFretboardTitle,
      steps: [
        TutorialStep(
          text: l10n.primerFretboardSame,
          play: (a) => a.playMidiNote(60),
        ),
        TutorialStep(text: l10n.primerFretboardAny),
      ],
    );

/// A capo clamps every string up a fret, so a familiar shape SOUNDS higher — a
/// C shape at capo 2 sounds like D. Game: capo_match.
Tutorial capoMatchPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerCapoTitle,
      steps: [
        TutorialStep(text: l10n.primerCapoClamp),
        TutorialStep(
          text: l10n.primerCapoShape,
          play: (a) => a.playMidiChord([60, 64, 67]), // a C major shape
        ),
        TutorialStep(
          text: l10n.primerCapoSounds,
          play: (a) =>
              a.playMidiChord([62, 66, 69]), // …sounds like D with capo 2
        ),
      ],
    );
