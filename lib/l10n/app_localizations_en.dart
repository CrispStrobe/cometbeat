// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'KlangUniversum';

  @override
  String get homeTagline => 'Discover the universe of music!';

  @override
  String get moduleNoteValues => 'Note Values';

  @override
  String get moduleNoteValuesSubtitle =>
      'Whole, half, quarter — how long does a note last?';

  @override
  String get moduleNoteReading => 'Reading Notes';

  @override
  String get moduleNoteReadingSubtitle =>
      'Treble and bass clef — which note is that?';

  @override
  String get moduleMeasures => 'Measures & Meter';

  @override
  String get moduleMeasuresSubtitle => 'Fill the measure so everything adds up';

  @override
  String get moduleScales => 'Scales';

  @override
  String get moduleScalesSubtitle => 'Major and minor, step by step';

  @override
  String get moduleChords => 'Chords & Intervals';

  @override
  String get moduleChordsSubtitle => 'Build triads and train your ears';

  @override
  String get moduleHarmony => 'Harmony';

  @override
  String get moduleHarmonySubtitle => 'Tonic, subdominant, dominant';

  @override
  String get comingSoon => 'Coming soon!';

  @override
  String get locked => 'Locked';

  @override
  String get advancedGameHint =>
      'Advanced! Earn 2 stars in the other Cello Corner games first.';

  @override
  String unlockHint(String module) {
    return 'Play $module first to unlock this!';
  }

  @override
  String get reviewTitle => 'Review';

  @override
  String dueForReview(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items to review',
      one: '1 item to review',
      zero: 'Nothing to review',
    );
    return '$_temp0';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get progressTitle => 'Progress';

  @override
  String get karteikastenTitle => 'Flashcard boxes';

  @override
  String get trickyNotesTitle => 'Your tricky spots';

  @override
  String get trickyNotesHint =>
      'The skills you miss most — reading, rhythm, chords and more. Review practises these first.';

  @override
  String trickyMissed(int count) {
    return 'missed $count×';
  }

  @override
  String get moduleProgressTitle => 'Modules';

  @override
  String get boxNew => 'New';

  @override
  String get boxMastered => 'Mastered';

  @override
  String masteredOfTracked(int mastered, int tracked) {
    return '$mastered of $tracked mastered';
  }

  @override
  String get languageLabel => 'Language';

  @override
  String get systemDefault => 'System default';

  @override
  String get workshopTitle => 'Workshop';

  @override
  String get workshopComposeTitle => 'Composition Workshop';

  @override
  String get workshopTimeSignature => 'Time';

  @override
  String get workshopHint =>
      'Pick a note value, then tap the staff to write your tune.';

  @override
  String get workshopEditHint =>
      'Tap the staff to move this note, or Delete it.';

  @override
  String get workshopDelete => 'Delete';

  @override
  String get workshopRest => 'Rest';

  @override
  String get workshopRedo => 'Redo';

  @override
  String get workshopDot => 'Dotted';

  @override
  String get workshopAccidental => 'Accidental';

  @override
  String get workshopKey => 'Key';

  @override
  String get workshopSelectPrev => 'Select previous';

  @override
  String get workshopSelectNext => 'Select next';

  @override
  String get workshopUp => 'Up a semitone';

  @override
  String get workshopDown => 'Down a semitone';

  @override
  String get instrumentLabel => 'Instrument sound';

  @override
  String get instrumentPiano => 'Piano';

  @override
  String get instrumentCello => 'Cello';

  @override
  String get instrumentFlute => 'Flute';

  @override
  String get instrumentMusicBox => 'Music box';

  @override
  String get noteNamingLabel => 'Note names';

  @override
  String get noteNamingAuto => 'Follow language';

  @override
  String get noteNamingGerman => 'German (C D E F G A H)';

  @override
  String get noteNamingEnglish => 'English (C D E F G A B)';

  @override
  String get noteNamingSolfege => 'Solfège (Do Re Mi Fa Sol La Si)';

  @override
  String streakDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count-day streak',
      one: '1-day streak',
    );
    return '$_temp0';
  }

  @override
  String get statsTitle => 'Learning statistics';

  @override
  String get statsTracked => 'Tracked items';

  @override
  String get statsLearning => 'Still learning';

  @override
  String get gameNoteValueQuiz => 'Symbol Quiz';

  @override
  String get gameNoteValueQuizSubtitle => 'Which note or rest is this?';

  @override
  String get gameDurationDuel => 'Duration Duel';

  @override
  String get gameDurationDuelSubtitle => 'Tap the symbol that lasts longer';

  @override
  String get whichLastsLonger => 'Which one lasts longer?';

  @override
  String get gameNoteReadingTreble => 'Treble Clef';

  @override
  String get gameNoteReadingBass => 'Bass Clef';

  @override
  String get gameNoteReadingTenor => 'Tenor Clef';

  @override
  String get gameNoteReadingAlto => 'Alto Clef';

  @override
  String get gameNoteReadingSubtitle => 'Name the note on the staff';

  @override
  String get moduleGuitar => 'Guitar Corner';

  @override
  String get moduleGuitarSubtitle => 'Read tab and learn the strings';

  @override
  String get gameGuitarStringQuiz => 'Open Strings';

  @override
  String get gameGuitarStringQuizSubtitle =>
      'Name the open string (E A D G B E)';

  @override
  String get guitarStringPrompt => 'Which note is this open string?';

  @override
  String get gameGuitarTabRead => 'Read the Tab';

  @override
  String get gameGuitarTabReadSubtitle => 'What note does this fret play?';

  @override
  String get guitarTabReadPrompt => 'Which note is this?';

  @override
  String get moduleCello => 'Cello Corner';

  @override
  String get moduleCelloSubtitle =>
      'Strings, fingers and clefs for young cellists';

  @override
  String get gameCelloStringQuiz => 'Which String?';

  @override
  String get gameCelloStringQuizSubtitle => 'Find the right cello string';

  @override
  String get celloStringPrompt => 'Which open string is this?';

  @override
  String get gameCelloFingerQuiz => 'Finger Quiz';

  @override
  String get gameCelloFingerQuizSubtitle => 'First position: which finger?';

  @override
  String get moduleComposition => 'Composing';

  @override
  String get moduleCompositionSubtitle =>
      'Endings, phrases — and your own melodies';

  @override
  String get gameEndingDetective => 'Ending Detective';

  @override
  String get gameEndingDetectiveSubtitle => 'Does the melody sound finished?';

  @override
  String get endingDetectivePrompt =>
      'Listen! Does this melody sound finished?';

  @override
  String get soundsFinished => 'Finished!';

  @override
  String get soundsOpen => 'Not yet...';

  @override
  String get gameQuestionAnswer => 'Question & Answer';

  @override
  String get gameQuestionAnswerSubtitle => 'Find the answer phrase that fits';

  @override
  String get questionAnswerPrompt =>
      'The melody asks a question — which answer finishes it?';

  @override
  String get gameMyMelody => 'My Melody';

  @override
  String get gameMyMelodySubtitle => 'Compose and play your own tune';

  @override
  String get myMelodyPrompt =>
      'Write your melody — tap the staff or an instrument!';

  @override
  String get inputStaff => 'Staff';

  @override
  String get inputPiano => 'Piano';

  @override
  String get inputGuitar => 'Guitar';

  @override
  String get inputCello => 'Cello';

  @override
  String get myMelodyFull => 'Your melody is full — play it!';

  @override
  String get myMelodyPlay => 'Play';

  @override
  String get myMelodyUndo => 'Undo';

  @override
  String get myMelodyClear => 'Clear';

  @override
  String get myMelodySave => 'Save';

  @override
  String get myMelodySaveTitle => 'Name your melody';

  @override
  String get myMelodyDefaultName => 'My melody';

  @override
  String get myMelodySaved => 'Saved to the Song Book!';

  @override
  String get moduleSongs => 'Song Book';

  @override
  String get moduleSongsSubtitle => 'Real songs — read, listen, sing along';

  @override
  String get gameSongBook => 'Song Book';

  @override
  String get gameSongBookSubtitle =>
      'Full songs with lyrics and a play-along cursor';

  @override
  String get songStop => 'Stop';

  @override
  String get importTitle => 'Import songs';

  @override
  String get importTitleField => 'Title (optional)';

  @override
  String get importHint =>
      'Paste MusicXML (from MuseScore & co.) or ChordPro (lyrics with [C] chords) here — or pick a simple MIDI file below.';

  @override
  String get importAsMusicXml => 'Import as MusicXML';

  @override
  String get importAsAbc => 'Import as ABC';

  @override
  String get importAsChordPro => 'Import as ChordPro';

  @override
  String get importMidiFile => 'Pick a MIDI file…';

  @override
  String get importMusicXmlFile => 'Pick a MusicXML file…';

  @override
  String get importDone => 'Imported!';

  @override
  String importFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get importedSongs => 'My imported songs';

  @override
  String get chordSheets => 'Chord sheets';

  @override
  String get gameTuneQuiz => 'Name That Tune';

  @override
  String get gameTuneQuizSubtitle => 'Recognize the song from its opening';

  @override
  String get tuneQuizPrompt => 'Listen! Which song starts like this?';

  @override
  String get moduleKeyboard => 'Piano Corner';

  @override
  String get moduleKeyboardSubtitle => 'Find your way around the piano keys';

  @override
  String get gameKeyFind => 'Find the Key';

  @override
  String get gameKeyFindSubtitle => 'From the staff note to the piano key';

  @override
  String get keyFindPrompt => 'Tap the key for this note!';

  @override
  String get gameKeyName => 'Key Quiz';

  @override
  String get gameKeyNameSubtitle => 'Which key is marked?';

  @override
  String get keyNamePrompt => 'What is the marked key called?';

  @override
  String get gameKeyEar => 'Echo Keys';

  @override
  String get gameKeyEarSubtitle => 'Play back what you hear';

  @override
  String get keyEarPrompt =>
      'First you hear C, then the mystery note — tap it!';

  @override
  String get gameKeyMelody => 'Play the Melody';

  @override
  String get gameKeyMelodySubtitle => 'Read the staff, play the keys';

  @override
  String get keyMelodyPrompt => 'Play these notes in order!';

  @override
  String get gameKeyChord => 'Chord Grip';

  @override
  String get gameKeyChordSubtitle => 'Grab all three chord notes';

  @override
  String get gameGrandStaffRead => 'Grand Staff';

  @override
  String get gameGrandStaffReadSubtitle => 'Read notes on both clefs at once';

  @override
  String keyChordPrompt(String name) {
    return 'Play the $name major chord — tap all three keys!';
  }

  @override
  String celloFingerPrompt(String string) {
    return 'Which finger plays it on the $string string?';
  }

  @override
  String get whatIsThisNote => 'What is this note called?';

  @override
  String get hintButton => 'Need a hint?';

  @override
  String readingHintSame(String name) {
    return 'It\'s $name — a landmark note!';
  }

  @override
  String readingHintStepUp(String name) {
    return 'One step up from $name';
  }

  @override
  String readingHintStepDown(String name) {
    return 'One step down from $name';
  }

  @override
  String readingHintSkipUp(String name) {
    return 'A skip up from $name';
  }

  @override
  String readingHintSkipDown(String name) {
    return 'A skip down from $name';
  }

  @override
  String readingHintFarUp(int count, String name) {
    return '$count steps up from $name';
  }

  @override
  String readingHintFarDown(int count, String name) {
    return '$count steps down from $name';
  }

  @override
  String get noteNameC => 'C';

  @override
  String get noteNameD => 'D';

  @override
  String get noteNameE => 'E';

  @override
  String get noteNameF => 'F';

  @override
  String get noteNameG => 'G';

  @override
  String get noteNameA => 'A';

  @override
  String get noteNameB => 'B';

  @override
  String get gamePlaceNoteTreble => 'Place the Note (Treble)';

  @override
  String get gamePlaceNoteBass => 'Place the Note (Bass)';

  @override
  String get gamePlaceNoteSubtitle => 'Tap the right line or space';

  @override
  String placeNotePrompt(String name) {
    return 'Place the note $name!';
  }

  @override
  String get gameMeasureFill => 'Measure Filler';

  @override
  String get gameMeasureFillSubtitle => 'Complete the measure so it adds up';

  @override
  String get measureFillPrompt => 'Which note completes the measure?';

  @override
  String get gameScaleDetective => 'Scale Detective';

  @override
  String get gameScaleDetectiveSubtitle => 'Find the note that doesn\'t belong';

  @override
  String scaleDetectivePrompt(String name) {
    return 'Tap the wrong note in the $name major scale!';
  }

  @override
  String scaleDetectivePromptMinor(String name) {
    return 'Tap the wrong note in the $name minor scale!';
  }

  @override
  String get gameChordQuiz => 'Chord Quiz';

  @override
  String get gameChordQuizSubtitle => 'Name the chord on the staff';

  @override
  String get chordQuizPrompt => 'What chord is this?';

  @override
  String majorChordName(String name) {
    return '$name major';
  }

  @override
  String get gameHarmonyQuiz => 'Function Quiz';

  @override
  String get gameHarmonyQuizSubtitle => 'Tonic, subdominant or dominant?';

  @override
  String harmonyPrompt(String key) {
    return 'What is this chord\'s function in $key?';
  }

  @override
  String keyMajorName(String name) {
    return '$name major';
  }

  @override
  String get harmonicTonic => 'Tonic';

  @override
  String get harmonicSubdominant => 'Subdominant';

  @override
  String get harmonicDominant => 'Dominant';

  @override
  String get gameFunctionEar => 'Hear the Function';

  @override
  String get gameFunctionEarSubtitle =>
      'Listen for tonic, subdominant or dominant';

  @override
  String functionEarPrompt(String key) {
    return 'Listen to the home chords in $key, then name the last one';
  }

  @override
  String get functionEarReplayHint => 'Hear the key, then the chord again';

  @override
  String get functionEarTargetAgain => 'Just the chord';

  @override
  String get gameEchoSequence => 'Sound Echo';

  @override
  String get gameEchoSequenceSubtitle => 'Watch, listen, then repeat the tune';

  @override
  String get echoWatch => 'Watch and listen…';

  @override
  String get echoRepeat => 'Your turn — repeat it!';

  @override
  String echoLength(int count) {
    return 'Length: $count';
  }

  @override
  String get gameMajorMinorEar => 'Major or Minor?';

  @override
  String get gameMajorMinorEarSubtitle => 'Listen closely and decide';

  @override
  String get listenMajorMinorPrompt => 'Listen! Does it sound major or minor?';

  @override
  String get listenAgain => 'Hear it again';

  @override
  String get majorLabel => 'Major';

  @override
  String get minorLabel => 'Minor';

  @override
  String get gameIntervalEar => 'Interval Detective';

  @override
  String get gameIntervalEarSubtitle => 'How far apart are two notes?';

  @override
  String get listenIntervalPrompt => 'Listen! What interval is this?';

  @override
  String get intervalSecond => 'Second';

  @override
  String get intervalThird => 'Third';

  @override
  String get intervalFifth => 'Fifth';

  @override
  String get intervalOctave => 'Octave';

  @override
  String get gameTriadBuilder => 'Triad Builder';

  @override
  String get gameTriadBuilderSubtitle => 'Stack the chord on the staff';

  @override
  String triadBuilderPrompt(String name) {
    return 'Build the $name major triad!';
  }

  @override
  String get gameScaleBuilder => 'Scale Builder';

  @override
  String get gameScaleBuilderSubtitle => 'Build the scale step by step';

  @override
  String scaleBuilderPromptMinor(String name) {
    return 'Build the $name minor scale — tap the next note!';
  }

  @override
  String scaleBuilderPrompt(String name) {
    return 'Build the $name major scale — tap the next note!';
  }

  @override
  String get gameCadenceWorkshop => 'Cadence Workshop';

  @override
  String get gameCadenceWorkshopSubtitle => 'Build T–S–D–T cadences';

  @override
  String cadencePrompt(String function, String key) {
    return 'Tap the $function in $key!';
  }

  @override
  String get gameRhythmTap => 'Rhythm Echo';

  @override
  String get gameRhythmTapSubtitle => 'Listen and tap it back';

  @override
  String get rhythmTapPrompt => 'Tap the rhythm — hold the long notes!';

  @override
  String get tapHere => 'Tap here!';

  @override
  String get rhythmTapHold => 'Holding…';

  @override
  String get gameBeatCount => 'Count the Beats';

  @override
  String get gameBeatCountSubtitle => 'Dots and ties add up — how long is it?';

  @override
  String get gameBeatSort => 'Sort the Beats';

  @override
  String get gameBeatSortSubtitle => 'Drag each note to its beat bucket';

  @override
  String get beatSortPrompt => 'Drag each note into the right bucket!';

  @override
  String get beatCountPrompt => 'How many beats does this last? (♩ = 1)';

  @override
  String get gameMeterDetective => 'Meter Detective';

  @override
  String get gameMeterDetectiveSubtitle => 'March or waltz? Feel the beat';

  @override
  String get meterDetectivePrompt => 'Listen! How many beats per measure?';

  @override
  String get gameMelodyEcho => 'Melody Echo';

  @override
  String get gameMelodyEchoSubtitle => 'Find the melody you heard';

  @override
  String get melodyEchoPrompt => 'Listen! Which melody did you hear?';

  @override
  String get gameMelodyDictation => 'Melody Dictation';

  @override
  String get gameMelodyDictationSubtitle =>
      'Hear it, then write it on the staff';

  @override
  String get gameNoteMemory => 'Note Match';

  @override
  String get gameNoteMemorySubtitle =>
      'Memory game: match notes to their names';

  @override
  String get gameNoteOrder => 'Note Order';

  @override
  String get gameNoteOrderSubtitle => 'Tap the notes from lowest to highest';

  @override
  String get gameOddOneOut => 'Odd One Out';

  @override
  String get gameOddOneOutSubtitle =>
      'Two notes share a name — tap the odd one';

  @override
  String get oddOneOutPrompt => 'Which note is the odd one out?';

  @override
  String get oddOneOutHint =>
      'Two notes have the same letter name. Tap the different one!';

  @override
  String get gameNoteWhack => 'Note Whack';

  @override
  String get gameNoteWhackSubtitle => 'Whack the notes with the called name';

  @override
  String get noteWhackPrompt => 'Whack:';

  @override
  String get noteWhackHint =>
      'Tap every note that matches — a wrong whack costs a heart!';

  @override
  String get gameCharades => 'Fast or Loud?';

  @override
  String get gameCharadesSubtitle => 'Name the tempo or the dynamics you hear';

  @override
  String get charadesTempoPrompt => 'How fast is it?';

  @override
  String get charadesDynamicsPrompt => 'How loud is it?';

  @override
  String get gameIntervalLadder => 'Interval Ladder';

  @override
  String get gameIntervalLadderSubtitle =>
      'Climb the interval from the base note';

  @override
  String get intervalLadderPrompt => 'Tap the note the arrow points to!';

  @override
  String get intervalLadderHint =>
      '▲ up, ▼ down. The number is the interval (3 = a third).';

  @override
  String get gameStaffRunner => 'Staff Runner';

  @override
  String get gameStaffRunnerSubtitle => 'Name notes before the timer runs out';

  @override
  String get gameChordGripHero => 'Chord Grip Hero';

  @override
  String get gameChordGripHeroSubtitle =>
      'Press all the chord keys before it lands';

  @override
  String get chordGripHint => 'Press every glowing key!';

  @override
  String get gameNoteSnake => 'Note Snake';

  @override
  String get gameNoteSnakeSubtitle =>
      'Steer the snake to eat the matching note';

  @override
  String get noteSnakePrompt => 'Eat this note:';

  @override
  String get recitalTitle => 'Recital';

  @override
  String get recitalTooltip => 'Play a recital';

  @override
  String recitalProgress(int done, int total) {
    return '$done of $total pieces performed';
  }

  @override
  String get recitalCurtainCall => 'Bravo!';

  @override
  String get recitalDone => 'Take a bow';

  @override
  String get gameStrumToy => 'Strum Toy';

  @override
  String get gameStrumToySubtitle => 'Pick a chord and strum a free jam';

  @override
  String get strumToyHint =>
      'Swipe across the strings to strum, or tap one to pluck.';

  @override
  String get gameNameThatChord => 'Name That Chord';

  @override
  String get gameNameThatChordSubtitle =>
      'Read or hear a chord, pick its symbol';

  @override
  String get nameThatChordPrompt => 'Which chord is this?';

  @override
  String get curriculumTitle => 'Curriculum';

  @override
  String get curriculumTooltip => 'Curriculum by school year';

  @override
  String get curSchoolYears => 'By school year';

  @override
  String get curLevelGrades12 => 'Grades 1–2';

  @override
  String get curLevelGrades34 => 'Grades 3–4';

  @override
  String get curLevelGrades56 => 'Grades 5–6';

  @override
  String get curLevelGrades78 => 'Grades 7–8';

  @override
  String get curLevelGrades910 => 'Grades 9–10';

  @override
  String get curTopicNoteReading => 'Note reading';

  @override
  String get curTopicNoteValues => 'Note values & rhythm';

  @override
  String get curTopicMeter => 'Time & metre';

  @override
  String get curTopicDynamics => 'Dynamics & tempo';

  @override
  String get curTopicScales => 'Scales & keys';

  @override
  String get curTopicIntervals => 'Intervals';

  @override
  String get curTopicChords => 'Chords';

  @override
  String get curTopicHarmony => 'Harmony & cadences';

  @override
  String get curTopicTransposition => 'Transposition';

  @override
  String get curTopicEar => 'Ear training';

  @override
  String get curTopicSightReading => 'Sight-reading';

  @override
  String curReadiness(int pct) {
    return '$pct% ready';
  }

  @override
  String get curPracticeLevel => 'Practise this level';

  @override
  String get curContinueHere => 'Continue here';

  @override
  String get curPractiseWeakest => 'Practise your weakest topic';

  @override
  String get curTopicsHeader => 'Topics';

  @override
  String get curGuideNote =>
      'A practice guide — topics arranged by school year, distilled from public school curricula.';

  @override
  String get curNoGames => 'No games for this topic yet';

  @override
  String get gameChordBuilder => 'Chord Builder';

  @override
  String get gameChordBuilderSubtitle =>
      'Build the named chord — any voicing counts';

  @override
  String chordBuilderPrompt(String chord) {
    return 'Build a $chord chord';
  }

  @override
  String get chordBuilderHint =>
      'Tap three notes onto the staff. Any octave or inversion works.';

  @override
  String get chordBuilderClear => 'Clear';

  @override
  String get chordBuilderCheck => 'Check';

  @override
  String get moduleTranspose => 'Transposing';

  @override
  String get moduleTransposeSubtitle => 'Written vs concert pitch';

  @override
  String get gameConcertPitch => 'Concert Pitch';

  @override
  String get gameConcertPitchSubtitle => 'Name the note that really sounds';

  @override
  String concertPitchPrompt(String instrument) {
    return 'A $instrument reads this note. What sounds?';
  }

  @override
  String get concertPitchHint =>
      'A transposing instrument sounds a different note than written.';

  @override
  String get concertInstrumentBb => 'B♭ Trumpet';

  @override
  String get concertInstrumentEb => 'E♭ Alto Sax';

  @override
  String get concertInstrumentF => 'F Horn';

  @override
  String get gameBowing => 'Bowing';

  @override
  String get gameBowingSubtitle => 'Read the up-bow and down-bow marks';

  @override
  String get bowingPrompt => 'Which bow stroke is marked?';

  @override
  String get bowDown => 'Down-bow';

  @override
  String get bowUp => 'Up-bow';

  @override
  String get gameWhichBeat => 'Which Beat?';

  @override
  String get gameWhichBeatSubtitle =>
      'Tap the beat the coloured note starts on';

  @override
  String get whichBeatPrompt => 'Which beat does the coloured note fall on?';

  @override
  String get workshopExportAbc => 'Export ABC';

  @override
  String get workshopCopy => 'Copy';

  @override
  String get workshopCopied => 'ABC copied to clipboard';

  @override
  String get gameTimeSignature => 'Time Signatures';

  @override
  String get gameTimeSignatureSubtitle =>
      'Read the signature (incl. C and cut time)';

  @override
  String get timeSignaturePrompt => 'How many beats are in one bar?';

  @override
  String get gameDuet => 'Duet';

  @override
  String get gameDuetSubtitle =>
      'Read the highlighted part in a two-staff score';

  @override
  String get duetPrompt => 'Name the highlighted note';

  @override
  String get gamePerformIt => 'Perform It';

  @override
  String get gamePerformItSubtitle => 'Play or sing the note you see';

  @override
  String get performItPrompt => 'Play or sing this note!';

  @override
  String get performItOnTarget => 'Got it!';

  @override
  String get performItSkip => 'Skip';

  @override
  String get gameSingBack => 'Sing Back';

  @override
  String get gameSingBackSubtitle => 'Hear a note, then sing it back';

  @override
  String get singBackPrompt => 'Sing the note you heard!';

  @override
  String get singBackListen => 'Hear it again';

  @override
  String get gameCelloPlayIt => 'Play It';

  @override
  String get gameCelloPlayItSubtitle =>
      'Play the note on your real cello — the mic listens';

  @override
  String get celloPlayItPrompt => 'Play this note on your cello!';

  @override
  String celloPlayItOpenString(String string) {
    return '$string string — open';
  }

  @override
  String celloPlayItFingered(String string, int finger) {
    return '$string string — finger $finger';
  }

  @override
  String get moduleDrums => 'Drums';

  @override
  String get moduleDrumsSubtitle => 'Read and play rhythms';

  @override
  String get gameDrumRead => 'Drum Read';

  @override
  String get gameDrumReadSubtitle => 'Read the rhythm and tap it on the drum';

  @override
  String get drumReadHint =>
      'Tap the drum on each note, in time with the click.';

  @override
  String get drumReadGo => 'Play!';

  @override
  String beatsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count beats',
      one: '1 beat',
    );
    return '$_temp0';
  }

  @override
  String get clefBass => 'Bass clef';

  @override
  String get gameLineSpace => 'Line or Space?';

  @override
  String get gameLineSpaceSubtitle =>
      'Swipe: is the note on a line or in a space?';

  @override
  String get gameFallingNotes => 'Falling Notes';

  @override
  String get gameFallingNotesSubtitle => 'Name the notes before they land!';

  @override
  String get gameConnectLine => 'Connect the Notes';

  @override
  String get gameConnectLineSubtitle =>
      'Draw a line from each note to its name';

  @override
  String get connectLinePrompt => 'Connect each note to its name!';

  @override
  String get gameLedgerLeap => 'Ledger Leap';

  @override
  String get gameLedgerLeapSubtitle =>
      'Count the little helper lines above or below the staff';

  @override
  String get ledgerLeapPrompt => 'How many ledger lines?';

  @override
  String get gameFallingKeys => 'Falling Keys';

  @override
  String get gameFallingKeysSubtitle =>
      'Play each falling note on the piano before it lands!';

  @override
  String get gameConnectSymbols => 'Connect the Symbols';

  @override
  String get gameConnectSymbolsSubtitle =>
      'Draw a line from each note value to its name';

  @override
  String get connectSymbolsPrompt => 'Connect each symbol to its name!';

  @override
  String get gameCommandCaller => 'Follow the Conductor';

  @override
  String get gameCommandCallerSubtitle => 'Do the move the conductor calls!';

  @override
  String get commandCallerHint =>
      'Tap, hold, or swipe — before the bar runs out!';

  @override
  String get conductorPrompt => 'Follow the conductor\'s beat!';

  @override
  String get commandTap => 'Tap!';

  @override
  String get commandHold => 'Hold!';

  @override
  String get commandSwipeLeft => 'Swipe left!';

  @override
  String get commandSwipeRight => 'Swipe right!';

  @override
  String get commandSwipeUp => 'Swipe up!';

  @override
  String get commandSwipeDown => 'Swipe down!';

  @override
  String get gameKeySignature => 'Key Detective';

  @override
  String get gameKeySignatureSubtitle =>
      'Read the sharps or flats — name the key';

  @override
  String get keySignaturePrompt => 'Which major key is this?';

  @override
  String keyMajorLabel(String name) {
    return '$name major';
  }

  @override
  String get gameBeatRunner => 'Beat Runner';

  @override
  String get gameBeatRunnerSubtitle =>
      'Tap in time as the beats reach the line!';

  @override
  String get beatRunnerHint => 'Tap on the beat!';

  @override
  String get beatPerfect => 'Perfect!';

  @override
  String get beatGood => 'Good!';

  @override
  String get beatMiss => 'Miss';

  @override
  String get fallingSpeedUp => 'Speed up!';

  @override
  String fallingMultiplier(int mult) {
    return '×$mult';
  }

  @override
  String get lineSpacePrompt => 'Swipe ← Line   or   Space →';

  @override
  String get lineLabel => 'Line';

  @override
  String get spaceLabel => 'Space';

  @override
  String get noteOrderPrompt => 'Tap the notes from lowest to highest!';

  @override
  String get noteOrderHint => 'Each note plays when you tap it.';

  @override
  String get noteMemoryPrompt => 'Find the pairs: a note and its name!';

  @override
  String noteMemoryMoves(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count moves',
      one: '1 move',
    );
    return '$_temp0';
  }

  @override
  String get melodyDictationPrompt =>
      'The first note is given — add the ones you hear';

  @override
  String get dictationUndo => 'Undo';

  @override
  String get whatIsThisSymbol => 'What is this symbol called?';

  @override
  String get hearLength => 'Hear the length';

  @override
  String get countAlong => 'Count along';

  @override
  String get halfBeat => '½ beat';

  @override
  String get quarterBeat => '¼ beat';

  @override
  String symbolLength(String name, String length) {
    return '$name lasts $length';
  }

  @override
  String symbolLengthRest(String name, String length) {
    return '$name: $length of silence';
  }

  @override
  String roundOf(int current, int total) {
    return 'Round $current of $total';
  }

  @override
  String get feedbackCorrect => 'Correct!';

  @override
  String get feedbackTryAgain => 'Oops — try again!';

  @override
  String resultScore(int score) {
    return 'Score: $score';
  }

  @override
  String resultTime(String time) {
    return 'Your time: $time';
  }

  @override
  String resultBest(String time) {
    return 'Best: $time';
  }

  @override
  String get resultNewBest => 'New best time! 🎉';

  @override
  String get showTimerLabel => 'Show your time';

  @override
  String get colorScaffoldLabel => 'Colour helper for beginners';

  @override
  String get colorScaffoldSubtitle =>
      'Tint notes by their letter — turn it off once the staff is familiar';

  @override
  String get debugModeEnabled => 'Debug settings unlocked!';

  @override
  String get debugSectionTitle => 'Debug';

  @override
  String get debugUnlockLabel => 'Unlock all games';

  @override
  String get playAgain => 'Play again';

  @override
  String get backButton => 'Back';

  @override
  String get wholeNote => 'Whole note';

  @override
  String get halfNote => 'Half note';

  @override
  String get quarterNote => 'Quarter note';

  @override
  String get eighthNote => 'Eighth note';

  @override
  String get sixteenthNote => 'Sixteenth note';

  @override
  String get wholeRest => 'Whole rest';

  @override
  String get halfRest => 'Half rest';

  @override
  String get quarterRest => 'Quarter rest';

  @override
  String get eighthRest => 'Eighth rest';

  @override
  String get sixteenthRest => 'Sixteenth rest';

  @override
  String get gameTuner => 'Tuner';

  @override
  String get gameTunerSubtitle => 'Live intonation — play or sing a note';

  @override
  String get gamePlayAlong => 'Play along';

  @override
  String get gamePlayAlongSubtitle =>
      'Follow the moving score in first position';

  @override
  String get gamePlayAlongGuitarSubtitle =>
      'Follow the moving score on the guitar';

  @override
  String get gamePlayAlongKeyboardSubtitle =>
      'Play the moving score on the keys';

  @override
  String get gameSingAlong => 'Sing along';

  @override
  String get gameSingAlongSubtitle => 'Match the moving score with your voice';

  @override
  String get gameChordListener => 'Chord listener';

  @override
  String get gameChordListenerSubtitle => 'Name the chord you strum or play';

  @override
  String get gameChordProgression => 'Chord play-along';

  @override
  String get gameChordProgressionSubtitle =>
      'Strum the progression as it scrolls by';

  @override
  String get micStart => 'Start listening';

  @override
  String get micStop => 'Stop';

  @override
  String get micPermissionDenied =>
      'Microphone permission denied. Enable it in system settings.';

  @override
  String get micUnsupported => 'PCM capture is not supported on this device.';

  @override
  String micStartFailed(String detail) {
    return 'Could not start the microphone: $detail';
  }

  @override
  String get tunerPrompt => 'Play or sing a note';

  @override
  String tunerCents(String cents) {
    return '$cents cents';
  }

  @override
  String get playAlongScore => 'Score';

  @override
  String get playAlongNow => 'Now';

  @override
  String get playAlongYou => 'You';

  @override
  String get playAlongCountIn => 'count-in';

  @override
  String get playAlongPreview => 'Preview';

  @override
  String get playAlongViewLabel => 'View';

  @override
  String get playAlongViewHighway => 'Highway';

  @override
  String get playAlongViewNotation => 'Notation';

  @override
  String get playAlongViewFalling => 'Falling';

  @override
  String get playAlongViewCoach => 'Coach';

  @override
  String get playAlongNext => 'next';

  @override
  String get playAlongBacking => 'Backing (use headphones)';

  @override
  String get chordListenerPrompt => 'Strum or play a chord';

  @override
  String chordListenerMatch(int percent) {
    return '$percent% match';
  }

  @override
  String get chordListenerHeard => 'Heard pitch classes';

  @override
  String get aboutTitle => 'About';

  @override
  String get aboutSubtitle => 'Version, licenses and credits';

  @override
  String get appLegalese => '© 2026 Christian Ströbele';

  @override
  String get aboutTagline =>
      'Music notation & harmony — from primary school onward';

  @override
  String aboutVersionLabel(String version) {
    return 'Version $version';
  }

  @override
  String get aboutProvider => 'Provider';

  @override
  String get aboutContact => 'Contact';

  @override
  String get aboutPrivacy => 'Privacy';

  @override
  String get aboutPrivacyText =>
      'KlangUniversum works entirely on your device. Microphone audio (for the tuner and play-along) is analysed locally in real time — never recorded, stored, or sent anywhere. There are no accounts, no ads, and no tracking.';

  @override
  String get aboutDisclaimer => 'Disclaimer';

  @override
  String get aboutDisclaimerText =>
      'KlangUniversum is a learning aid, provided as is and without warranty. Curriculum levels are generic guidance, not an official syllabus.';

  @override
  String get aboutCredits => 'Credits';

  @override
  String get aboutCreditsText =>
      'Music engraving uses the Bravura font (SIL Open Font License).';

  @override
  String get aboutOpenSourceLicenses => 'Open-source licenses';
}
