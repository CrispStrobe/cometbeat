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
  String get trickyNotesTitle => 'Your tricky notes';

  @override
  String get trickyNotesHint =>
      'The things you miss most — review will practise these first.';

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
  String get moduleCello => 'Cello Corner';

  @override
  String get moduleCelloSubtitle =>
      'Strings, fingers and clefs for young cellists';

  @override
  String get gameCelloStringQuiz => 'Which String?';

  @override
  String get gameCelloStringQuizSubtitle => 'Find the right cello string';

  @override
  String get celloStringPrompt => 'Which string plays this note?';

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
  String get myMelodyPrompt => 'Tap the staff to write your melody!';

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
  String get rhythmTapPrompt => 'Listen, then tap the rhythm!';

  @override
  String get tapHere => 'Tap here!';

  @override
  String get gameBeatCount => 'Count the Beats';

  @override
  String get gameBeatCountSubtitle => 'Dots and ties add up — how long is it?';

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
  String get whatIsThisSymbol => 'What is this symbol called?';

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
}
