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
  String get workshopReady => 'Pick a value, then tap a note';

  @override
  String get workshopTapStaff => 'Tap the staff to place a note';

  @override
  String get workshopScoreSettings => 'Score settings';

  @override
  String get workshopClef => 'Clef';

  @override
  String get workshopZoomIn => 'Zoom in';

  @override
  String get workshopZoomOut => 'Zoom out';

  @override
  String get workshopOpen => 'Open a file…';

  @override
  String get workshopExport => 'Export…';

  @override
  String get workshopExportChoose => 'Choose a format';

  @override
  String workshopExportAllParts(int count) {
    return 'All $count parts';
  }

  @override
  String workshopExportActivePartOnly(String part) {
    return 'Only “$part” — this format cannot hold several parts';
  }

  @override
  String workshopSavedTo(String path) {
    return 'Saved: $path';
  }

  @override
  String get workshopExportXml => 'Export MusicXML';

  @override
  String get workshopExportSvg => 'Export SVG (print)';

  @override
  String get workshopExportImage => 'Export image (PNG)';

  @override
  String get workshopExportedImage => 'Image saved';

  @override
  String get workshopMarquee => 'Select notes (rubber-band)';

  @override
  String get workshopCut => 'Cut';

  @override
  String get workshopPaste => 'Paste';

  @override
  String get workshopMoveLeft => 'Move left';

  @override
  String get workshopMoveRight => 'Move right';

  @override
  String get workshopExtendLeft => 'Extend selection left';

  @override
  String get workshopExtendRight => 'Extend selection right';

  @override
  String workshopSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selected',
      one: '1 selected',
    );
    return '$_temp0';
  }

  @override
  String get workshopRepeatStart => 'Repeat starts here';

  @override
  String get workshopRepeatEnd => 'Repeat ends here';

  @override
  String get workshopChangeHere => 'Change from here…';

  @override
  String get workshopChangeHereTitle => 'Change from this note';

  @override
  String get workshopNoChange => 'No change';

  @override
  String get workshopVolta => 'Ending';

  @override
  String get workshopNavigation => 'Navigation';

  @override
  String get workshopArticulations => 'Articulations & ties';

  @override
  String get workshopStaccato => 'Staccato';

  @override
  String get workshopTenuto => 'Tenuto';

  @override
  String get workshopAccent => 'Accent';

  @override
  String get workshopMarcato => 'Marcato';

  @override
  String get workshopFermata => 'Fermata';

  @override
  String get workshopBarNumbers => 'Bar numbers';

  @override
  String get workshopNoteNames => 'Note names';

  @override
  String get workshopPasteTokens => 'Paste notation tokens…';

  @override
  String get workshopPasteTokensHint =>
      'Paste bekern / kern tokens (e.g. **kern <b> 4 c <b> *-)';

  @override
  String get workshopPasteTokensLoad => 'Load';

  @override
  String get workshopAddInstrument => 'Add instrument';

  @override
  String get workshopRemoveInstrument => 'Remove this part';

  @override
  String get workshopPartClef => 'Clef';

  @override
  String get workshopPartTransposition => 'Transposition';

  @override
  String get workshopConcertPitch => 'Concert pitch (C)';

  @override
  String get workshopBraceBelow => 'Brace with part below';

  @override
  String get workshopBreakBarlineBelow => 'Break barline below';

  @override
  String get workshopTie => 'Tie';

  @override
  String get workshopDynamics => 'Dynamics';

  @override
  String get workshopDynamicNone => 'None';

  @override
  String get workshopChord => 'Chord (stack notes)';

  @override
  String get workshopSlur => 'Slur (phrase the selected notes)';

  @override
  String get workshopCrescendo => 'Crescendo (getting louder)';

  @override
  String get workshopDiminuendo => 'Diminuendo (getting softer)';

  @override
  String get workshopPickup => 'Pickup (upbeat)';

  @override
  String get workshopPickupNone => 'No pickup';

  @override
  String get workshopLyric => 'Lyric';

  @override
  String get workshopLyricHint => 'Syllable…';

  @override
  String get workshopLyricVerse => 'Verse';

  @override
  String get workshopShortcuts => 'Keyboard shortcuts';

  @override
  String get workshopShortcutPlaceNote => 'Place a note (its pitch)';

  @override
  String get workshopShortcutNoteValue => 'Note value (whole … sixteenth)';

  @override
  String get workshopShortcutSelect => 'Select previous / next';

  @override
  String get workshopShortcutTranspose => 'Move pitch up / down';

  @override
  String get workshopShortcutUndoRedo => 'Undo / redo';

  @override
  String get workshopShortcutCopyPaste => 'Copy / cut / paste';

  @override
  String get workshopExitTitle => 'Leave the workshop?';

  @override
  String get workshopExitMessage => 'Your score has unsaved changes.';

  @override
  String get workshopKeepEditing => 'Keep editing';

  @override
  String get workshopDiscard => 'Discard';

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
  String get gameTempoDuel => 'Faster or Slower?';

  @override
  String get gameTempoDuelSubtitle =>
      'Read two tempo words and tap the faster one';

  @override
  String get whichIsFaster => 'Which tempo is faster?';

  @override
  String get gameDynamicsDuel => 'Louder or Softer?';

  @override
  String get gameDynamicsDuelSubtitle =>
      'Read two dynamic marks and tap the louder one';

  @override
  String get whichIsLouder => 'Which mark is louder?';

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
  String get gamePitchSort => 'High or Low?';

  @override
  String get gamePitchSortBass => 'High or Low? (bass)';

  @override
  String get gamePitchSortSubtitle =>
      'Drag each note into the high or low basket';

  @override
  String get pitchSortPrompt =>
      'Is each note high or low? Drop it in the right basket!';

  @override
  String get pitchHighLabel => 'High';

  @override
  String get pitchLowLabel => 'Low';

  @override
  String get gameAccidentalSort => 'Sharp or Flat?';

  @override
  String get gameAccidentalSortBass => 'Sharp or Flat? (bass)';

  @override
  String get gameAccidentalSortSubtitle =>
      'Drag each note into the sharp or flat basket';

  @override
  String get accidentalSortPrompt =>
      'Does the note have a sharp or a flat? Drop it in the right basket!';

  @override
  String get accidentalSharpLabel => 'Sharp';

  @override
  String get accidentalFlatLabel => 'Flat';

  @override
  String get accidentalNaturalLabel => 'Natural';

  @override
  String get gameDirectionEar => 'Higher or Lower?';

  @override
  String get gameDirectionEarSubtitle =>
      'Listen: does the second note go up or down?';

  @override
  String get directionEarPrompt =>
      'Two notes play. Is the second one higher or lower?';

  @override
  String get directionUpLabel => 'Higher';

  @override
  String get directionDownLabel => 'Lower';

  @override
  String get gameStepSkip => 'Step or Skip?';

  @override
  String get gameStepSkipBass => 'Step or Skip? (bass)';

  @override
  String get gameStepSkipSubtitle =>
      'Do the two notes step to a neighbour or skip a gap?';

  @override
  String get stepSkipPrompt =>
      'Does the second note step next door, or skip over a gap?';

  @override
  String get stepLabel => 'Step';

  @override
  String get skipLabel => 'Skip';

  @override
  String get leapLabel => 'Leap';

  @override
  String get gameTieSlur => 'Tie or Slur?';

  @override
  String get gameTieSlurSubtitle =>
      'Same pitch = a tie; different pitches = a slur';

  @override
  String get tieSlurPrompt => 'Is the curve a tie or a slur?';

  @override
  String get tieLabel => 'Tie';

  @override
  String get slurLabel => 'Slur';

  @override
  String get gameBeamFlag => 'Beam or Flag?';

  @override
  String get gameBeamFlagSubtitle =>
      'Eighths joined by a beam, or each with its own flag?';

  @override
  String get beamFlagPrompt => 'Are the eighth notes beamed or flagged?';

  @override
  String get beamLabel => 'Beam';

  @override
  String get flagLabel => 'Flag';

  @override
  String get gameWhichClef => 'Which Clef?';

  @override
  String get gameWhichClefSubtitle =>
      'Is it the treble clef or the bass clef? (Alto & tenor at 2★.)';

  @override
  String get whichClefPrompt => 'Which clef is this?';

  @override
  String get trebleClefLabel => 'Treble';

  @override
  String get bassClefLabel => 'Bass';

  @override
  String get altoClefLabel => 'Alto';

  @override
  String get tenorClefLabel => 'Tenor';

  @override
  String get gameWholeHalf => 'Whole or Half Step?';

  @override
  String get gameWholeHalfSubtitle =>
      'Two neighbour notes — a whole step (tone) or a half step (semitone)?';

  @override
  String get wholeHalfPrompt => 'Is the gap a whole step or a half step?';

  @override
  String get wholeStepLabel => 'Whole step';

  @override
  String get halfStepLabel => 'Half step';

  @override
  String get gameSameDiff => 'Same or Different?';

  @override
  String get gameSameDiffSubtitle =>
      'Two notes play — are they the same pitch or different?';

  @override
  String get sameDiffPrompt => 'Are the two notes the same, or different?';

  @override
  String get sameLabel => 'Same';

  @override
  String get differentLabel => 'Different';

  @override
  String get gameDottedSort => 'Dotted or Not?';

  @override
  String get gameDottedSortSubtitle =>
      'Sort the notes — does it carry a dot (half again as long)?';

  @override
  String get dottedSortPrompt => 'Drag each note: does it have a dot?';

  @override
  String get dottedLabel => 'Dotted';

  @override
  String get plainLabel => 'Plain';

  @override
  String get gameRunDirection => 'Ascending or Descending?';

  @override
  String get gameRunDirectionSubtitle =>
      'A little run of notes plays — does it climb up or step down?';

  @override
  String get runDirectionPrompt => 'Does the run go up or down?';

  @override
  String get gameCountNotes => 'Count the Notes';

  @override
  String get gameCountNotesSubtitle =>
      'Listen closely — how many notes did you hear?';

  @override
  String get countNotesPrompt => 'How many notes did you hear?';

  @override
  String get ascendingLabel => 'Ascending';

  @override
  String get descendingLabel => 'Descending';

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
  String get gameGridComposer => 'Colour Melody';

  @override
  String get gameGridComposerSubtitle =>
      'Tap colours to build a tune — no reading needed';

  @override
  String get gridComposerPrompt => 'Tap the colours to make a tune!';

  @override
  String get gridComposerPlay => 'Play';

  @override
  String get gridComposerClear => 'Clear';

  @override
  String get gameLoopMixer => 'Loop Mixer';

  @override
  String get gameLoopMixerSubtitle =>
      'Layer looping grooves — you are the band';

  @override
  String get loopMixerPrompt => 'Tap the cards to start your band!';

  @override
  String get loopMixerStop => 'Stop';

  @override
  String get loopMixerSwing => 'Swing';

  @override
  String get loopMixerHarmony => 'Harmony';

  @override
  String get loopMixerHarmonyOff => 'Free';

  @override
  String get loopMixerTempoChill => 'Chill';

  @override
  String get loopMixerTempoGroove => 'Groove';

  @override
  String get loopMixerTempoFast => 'Fast';

  @override
  String get loopMixerTrackDrums => 'Drums';

  @override
  String get loopMixerTrackBass => 'Bass';

  @override
  String get loopMixerTrackChords => 'Chords';

  @override
  String get loopMixerTrackMelody => 'Melody';

  @override
  String get loopMixerTrackSparkle => 'Sparkle';

  @override
  String get gameTracker => 'Tracker';

  @override
  String get gameTrackerSubtitle => 'Build a looping beat, track by track';

  @override
  String get trackerPrompt =>
      'Pick an instrument, then tap to build your loop!';

  @override
  String get trackerClear => 'Clear';

  @override
  String get trackerChannelMelody => 'Melody';

  @override
  String get trackerChannelSparkle => 'Sparkle';

  @override
  String get trackerChannelZap => 'Zap';

  @override
  String get trackerChannelBass => 'Bass';

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
  String get songbooksTitle => 'My songbooks';

  @override
  String get songbookNew => 'New songbook';

  @override
  String get songbookNameTitle => 'Name the songbook';

  @override
  String get songbookDefaultName => 'My songbook';

  @override
  String get songbookRename => 'Rename';

  @override
  String get songbookDelete => 'Delete songbook';

  @override
  String get songbookAddSongs => 'Add songs';

  @override
  String get songbookEmpty => 'No songs yet — tap Add songs.';

  @override
  String get songbookNoImports =>
      'Import or compose a song first, then add it here.';

  @override
  String get songbookRemoveFromBook => 'Remove from songbook';

  @override
  String songbookSongCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count songs',
      one: '1 song',
      zero: 'empty',
    );
    return '$_temp0';
  }

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
  String get gameKeyFindBass => 'Find the Key (Bass)';

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
  String get gameInScale => 'In the Scale?';

  @override
  String get gameInScaleSubtitle =>
      'Does the note belong to C major? Swipe or tap';

  @override
  String get inScalePrompt => 'Is this note in the C major scale?';

  @override
  String get inScaleLabel => 'In';

  @override
  String get notInScaleLabel => 'Out';

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
  String get gameRomanNumeral => 'Roman Numerals';

  @override
  String get gameRomanNumeralSubtitle =>
      'Which scale-degree chord is this? (I, IV, V …)';

  @override
  String romanNumeralPrompt(String key) {
    return 'In $key — which chord is this?';
  }

  @override
  String get romanNumeralReplay => 'Hear the chord again';

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
  String get diminishedLabel => 'Diminished';

  @override
  String get augmentedLabel => 'Augmented';

  @override
  String get listenChordQualityPrompt => 'Listen! Which chord quality is it?';

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
  String get intervalFourth => 'Fourth';

  @override
  String get intervalFifth => 'Fifth';

  @override
  String get intervalSixth => 'Sixth';

  @override
  String get intervalOctave => 'Octave';

  @override
  String get gameTriadSeventh => 'Triad or Seventh?';

  @override
  String get gameTriadSeventhSubtitle =>
      'Hear a chord — three notes, or four with a seventh?';

  @override
  String get triadSeventhPrompt => 'Triad or seventh chord?';

  @override
  String get triadLabel => 'Triad';

  @override
  String get seventhLabel => 'Seventh';

  @override
  String get gameSingInterval => 'Sing the Interval';

  @override
  String get gameSingIntervalSubtitle =>
      'Hear an interval, sing the top note back';

  @override
  String singIntervalPrompt(String interval) {
    return 'Sing the top note — a $interval up!';
  }

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
  String get gameValueOrder => 'Longest First';

  @override
  String get gameValueOrderSubtitle => 'Order the note values by length';

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
  String get gameChordChart => 'Chord Chart';

  @override
  String get gameChordChartSubtitle =>
      'Read the chord symbol, find its notation';

  @override
  String get chordChartPrompt => 'Which notation is this chord symbol?';

  @override
  String get curriculumTitle => 'Topics by grade';

  @override
  String get curriculumTooltip => 'Topics by grade';

  @override
  String get curSchoolYears => 'By grade';

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
      'A practice guide — topics arranged by grade, distilled from public school curricula.';

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
  String get gameStrongBeat => 'Strong Beat?';

  @override
  String get gameStrongBeatSubtitle => 'Is the marked beat strong or weak?';

  @override
  String strongBeatPrompt(int beat) {
    return 'Beat $beat: is it a strong or a weak beat?';
  }

  @override
  String get strongBeatStrong => 'Strong';

  @override
  String get strongBeatWeak => 'Weak';

  @override
  String get strongBeatReplay => 'Hear the beats again';

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
  String get gameReadVoice => 'Read the Voice';

  @override
  String get gameReadVoiceSubtitle =>
      'Follow one voice in a chord (Soprano to Bass)';

  @override
  String readVoicePrompt(String voice) {
    return 'Which note does the $voice sing?';
  }

  @override
  String get readVoiceHear => 'Hear this voice';

  @override
  String get voiceSoprano => 'Soprano';

  @override
  String get voiceAlto => 'Alto';

  @override
  String get voiceTenor => 'Tenor';

  @override
  String get voiceBass => 'Bass';

  @override
  String get gameWhichVoice => 'Which Voice?';

  @override
  String get gameWhichVoiceSubtitle =>
      'The highlighted note — Soprano, Alto, Tenor or Bass?';

  @override
  String get whichVoicePrompt => 'Which voice sings the highlighted note?';

  @override
  String get gameHearVoice => 'Hear the Voice';

  @override
  String get gameHearVoiceSubtitle => 'Listen — which voice do you hear alone?';

  @override
  String get hearVoicePrompt =>
      'The chord plays, then one voice. Which voice was it?';

  @override
  String get hearVoiceReplay => 'Play again';

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
  String get gameConnectIntervals => 'Connect the Steps';

  @override
  String get gameConnectIntervalsSubtitle =>
      'Count the note-names in each interval and match it to its number';

  @override
  String get connectIntervalsPrompt =>
      'How far apart? Connect each interval to its number!';

  @override
  String get gameConnectDynamics => 'Connect the Dynamics';

  @override
  String get gameConnectDynamicsSubtitle =>
      'Match each dynamic mark to how loud it means (pp = very soft)';

  @override
  String get connectDynamicsPrompt =>
      'How loud? Connect each mark to its meaning!';

  @override
  String get dynVerySoft => 'very soft';

  @override
  String get dynSoft => 'soft';

  @override
  String get dynMediumSoft => 'medium soft';

  @override
  String get dynMediumLoud => 'medium loud';

  @override
  String get dynLoud => 'loud';

  @override
  String get dynVeryLoud => 'very loud';

  @override
  String get gameConnectRests => 'Connect the Rests';

  @override
  String get gameConnectRestsSubtitle =>
      'Match each rest to the note it lasts as long as';

  @override
  String get connectRestsPrompt =>
      'How long is the silence? Connect each rest to its note!';

  @override
  String get gameConnectTempo => 'Connect the Tempo Words';

  @override
  String get gameConnectTempoSubtitle =>
      'Match each Italian tempo word to its meaning (Largo = very slow)';

  @override
  String get connectTempoPrompt =>
      'How fast? Connect each tempo word to its meaning!';

  @override
  String get tempoVerySlow => 'very slow';

  @override
  String get tempoSlow => 'slow';

  @override
  String get tempoWalking => 'walking pace';

  @override
  String get tempoModerate => 'moderate';

  @override
  String get tempoFast => 'fast';

  @override
  String get tempoLively => 'lively';

  @override
  String get tempoVeryFast => 'very fast';

  @override
  String get gameConnectBeats => 'Connect the Beats';

  @override
  String get gameConnectBeatsSubtitle =>
      'Match each note to how many beats it lasts in 4/4 time';

  @override
  String get connectBeatsPrompt =>
      'How many beats? Connect each note to its count (in 4/4)!';

  @override
  String get beatCount4 => '4 beats';

  @override
  String get beatCount2 => '2 beats';

  @override
  String get beatCount1 => '1 beat';

  @override
  String get beatCountHalf => '½ beat';

  @override
  String get beatCountQuarter => '¼ beat';

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
  String get valueOrderPrompt => 'Tap the notes from longest to shortest!';

  @override
  String get valueOrderHint => 'Each value plays its length when you tap it.';

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
  String get soundOnLabel => 'Sound';

  @override
  String get soundOnSubtitle =>
      'Notes, chords and sound effects (the microphone still works)';

  @override
  String get muteTooltip => 'Mute sound';

  @override
  String get unmuteTooltip => 'Turn sound on';

  @override
  String get howToPlayTooltip => 'How to play';

  @override
  String get tutorialNext => 'Next';

  @override
  String get tutorialGotIt => 'Got it!';

  @override
  String get tutorialListen => 'Listen';

  @override
  String get primerReadingTitle => 'Reading notes';

  @override
  String get primerReadingStaff =>
      'Music is written on five lines called a staff. Notes sit on the lines and in the spaces between them.';

  @override
  String get primerReadingHigher =>
      'The higher a note sits on the staff, the higher it sounds. Tap Listen and hear these notes climb!';

  @override
  String get primerReadingNames =>
      'Every note has a letter name: A B C D E F G. This one is E — tap Listen to hear it.';

  @override
  String get primerValuesTitle => 'How long is a note?';

  @override
  String get primerValuesWhole =>
      'A note\'s shape shows how LONG to hold it. This open oval with no stem is a whole note — a long sound (4 beats).';

  @override
  String get primerValuesQuarter =>
      'A filled note with a stem is a quarter note — one short beat. Four quarter notes last as long as one whole note.';

  @override
  String get primerValuesRest =>
      'A rest is a beat of SILENCE. Count it in your head, but don\'t play. Tap Listen to hear a beat of rest.';

  @override
  String get primerMeasuresTitle => 'Filling a measure';

  @override
  String get primerMeasuresBars =>
      'Music is split into measures (bars) by barlines. A time signature like 4/4 means each measure holds 4 beats.';

  @override
  String get primerMeasuresFill =>
      'Fill each measure so the beats add up. Four quarter notes make 4 beats — one full 4/4 measure.';

  @override
  String get primerMeasuresHalf =>
      'A half note lasts 2 beats, so two half notes also fill a 4/4 measure.';

  @override
  String get primerScalesTitle => 'What is a scale?';

  @override
  String get primerScalesLadder =>
      'A scale is a ladder of notes climbing step by step. This is C major: C D E F G A B C.';

  @override
  String get primerScalesMajor =>
      'A major scale sounds bright and cheerful. Listen to C major climb up.';

  @override
  String get primerScalesMinor =>
      'A minor scale sounds darker, a little sad. Listen to A minor.';

  @override
  String get primerChordsTitle => 'Building a chord';

  @override
  String get primerChordsStack =>
      'A chord is notes played at the SAME time. Stack three notes a gap apart and you get a triad — here, C E G.';

  @override
  String get primerChordsColour =>
      'A major triad sounds bright; a minor triad sounds softer and sadder. Listen to both.';

  @override
  String get primerChordsArpeggio =>
      'You can also play a chord one note at a time, bottom to top — that\'s an arpeggio.';

  @override
  String get primerHarmonyTitle => 'Chords have jobs';

  @override
  String get primerHarmonyHome =>
      'One chord feels like HOME — settled and finished. We call it the Tonic. Listen: this is C major, home base.';

  @override
  String get primerHarmonyPull =>
      'Other chords pull AWAY and want to return home. The Dominant tugs the hardest — hear how it leans right back to home.';

  @override
  String get primerHarmonyCadence =>
      'When chords travel home → away → home, that little journey to a resting point is a cadence. Listen to the whole trip.';

  @override
  String get primerCompositionTitle => 'Make a melody';

  @override
  String get primerCompositionJourney =>
      'A melody is a little journey of notes — some step up, some come down. Hum along as it rises and falls!';

  @override
  String get primerCompositionQuestion =>
      'A tune can ask a QUESTION — it stops high up in the air, sounding unfinished, as if it\'s waiting.';

  @override
  String get primerCompositionAnswer =>
      '…then it gives an ANSWER, coming back down to rest at home. A question and its answer make a phrase.';

  @override
  String get primerCelloTitle => 'Your four strings';

  @override
  String get primerCelloStrings =>
      'The cello has four strings. From low to high they are C, G, D, A — the lowest string is the thickest.';

  @override
  String get primerCelloBass =>
      'Cello notes live on the bass clef, the staff for low sounds. This deep note is C, your thickest string.';

  @override
  String get primerCelloFinger =>
      'Press a finger onto a string to shorten it and the note gets higher. The tuner listens and shows if you\'re spot on.';

  @override
  String get primerGuitarTitle => 'Six strings and tab';

  @override
  String get primerGuitarStrings =>
      'A guitar has six strings. From low (thick) to high (thin): E, A, D, G, B, E — yes, an E at each end!';

  @override
  String get primerGuitarTab =>
      'Guitar can be written as tab: six lines, one per string. A number is the fret to press; 0 means play the open string.';

  @override
  String get primerGuitarPlay =>
      'Play the note shown, or strum along. The thinner the string, the higher it sings — from low E up to high E.';

  @override
  String get primerSongsTitle => 'Follow the tune';

  @override
  String get primerSongsPick =>
      'Pick a song you know. The screen shows its tune as a line of notes, read left to right.';

  @override
  String get primerSongsMarker =>
      'A marker slides along the tune. Sing or play each note as it reaches the line — like following a bouncing ball.';

  @override
  String get primerKeyboardTitle => 'The piano keys';

  @override
  String get primerKeyboardWhite =>
      'The white keys are named A B C D E F G, repeating up the whole piano. The black keys sit in little groups of two and three.';

  @override
  String get primerKeyboardFindC =>
      'Find C: it\'s the white key just to the LEFT of every group of TWO black keys. From C, climb up C D E F G A B C.';

  @override
  String get primerKeyboardHands =>
      'Piano music uses two staves at once: the top staff for your right hand, the bottom staff for your left. Hear both together.';

  @override
  String get primerTransposeTitle => 'Read one note, hear another';

  @override
  String get primerTransposeSame =>
      'Most instruments sound the note they read. Read a C, hear a C — simple.';

  @override
  String get primerTransposeShift =>
      'But some are ‘transposing’: a trumpet in B♭ reads a C yet a B♭ comes out — a little lower. This game does that swap for you.';

  @override
  String get primerDrumsTitle => 'Reading drums';

  @override
  String get primerDrumsWhat =>
      'Drums don\'t play high and low tunes — a drum just goes THUMP or TSS. So drum music shows WHICH drum and WHEN, not a pitch.';

  @override
  String get primerDrumsLines =>
      'Each line and space is a different drum: low down is the bass drum you kick, higher up are the snare and cymbals. Read left to right and play the beat.';

  @override
  String get primerBassTitle => 'The bass clef';

  @override
  String get primerBassClef =>
      'This low staff is the bass clef (the F-clef). A cello or a left hand reads here. Its lines and spaces spell different notes than the treble clef.';

  @override
  String get primerBassMiddleC =>
      'Middle C — the note in the middle of the piano — sits just above the bass staff, on its own little ledger line.';

  @override
  String get primerLedgerTitle => 'Ledger lines';

  @override
  String get primerLedgerMiddleC =>
      'When a note won\'t fit on the five lines, we add a tiny extra line just for it — a ledger line. Middle C hangs on one, right below the treble staff.';

  @override
  String get primerLedgerHigh =>
      'The higher a note climbs above the staff, the more ledger lines it needs. Count them like the rungs of a ladder.';

  @override
  String get primerAccidentalsTitle => 'Sharps and flats';

  @override
  String get primerAccidentalsSharp =>
      'A sharp ♯ in front of a note lifts it up by the smallest step, a semitone. C♯ is a hair higher than C.';

  @override
  String get primerAccidentalsFlat =>
      'A flat ♭ lowers a note by a semitone. D♭ is the very same key as C♯ — it just leans down from D.';

  @override
  String get primerStepSkipTitle => 'Steps and skips';

  @override
  String get primerStepSkipStep =>
      'A STEP moves to the next-door note — a line to the space touching it, one letter along: C to D.';

  @override
  String get primerStepSkipSkip =>
      'A SKIP jumps over one — a line straight to the next line: C to E. Skips sound bouncier than steps.';

  @override
  String get primerIntervalsTitle => 'How far apart?';

  @override
  String get primerIntervalsCount =>
      'The distance between two notes is an interval. Count the letters including both ends: C to E is C-D-E — a 3rd.';

  @override
  String get primerIntervalsWide =>
      'The wider the gap, the bigger the number. C up to G is a 5th: C-D-E-F-G.';

  @override
  String get primerIntervalsEar =>
      'Narrow intervals sound close and gentle; wide ones sound open and bold. Listen to a small gap, then a big one.';

  @override
  String get primerKeySigTitle => 'Key signatures';

  @override
  String get primerKeySigWhat =>
      'Instead of marking every sharp, we write them once at the very start — a key signature. It applies to the whole piece. This is G major: one sharp, F♯.';

  @override
  String get primerKeySigCompare =>
      'C major has no sharps or flats at all. Listen to C major — every note is a plain white key.';

  @override
  String get primerTimeSigTitle => 'Time signatures';

  @override
  String get primerTimeSigFour =>
      'The two numbers at the start are the time signature. The top number is how many beats fill each measure — 4 means a steady four.';

  @override
  String get primerTimeSigThree =>
      'Change the top number to 3 and each measure has three beats — the gentle swing of a waltz. Count 1-2-3, 1-2-3.';

  @override
  String get primerChartTitle => 'Chord symbols';

  @override
  String get primerChartMajor =>
      'Above a tune you\'ll see chord symbols. A plain letter means a major chord: ‘C’ tells you to play a C major chord.';

  @override
  String get primerChartMinor =>
      'A small ‘m’ after the letter means minor: ‘Am’ is A minor — the same family, but a softer, sadder colour.';

  @override
  String get colorScaffoldLabel => 'Colour helper for beginners';

  @override
  String get colorScaffoldSubtitle =>
      'Tint notes by their letter — turn it off once the staff is familiar';

  @override
  String get handwrittenNotesLabel => 'Handwritten notes';

  @override
  String get handwrittenNotesSubtitle =>
      'Draw notation in a hand-written jazz style (Petaluma)';

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
  String get gameOdeToJoy => 'Ode to Joy';

  @override
  String get gameMaryLamb => 'Mary\'s Lamb';

  @override
  String get gameFreeSing => 'Free Sing';

  @override
  String get gameFreeSingSubtitle => 'Sing a tune and hear it back';

  @override
  String get freeSingPrompt => 'Sing a tune…';

  @override
  String get freeSingRecord => 'Record';

  @override
  String freeSingCaptured(int count) {
    return '$count notes captured';
  }

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
  String get tunerReference => 'Reference pitch';

  @override
  String get tunerInstrument => 'Instrument';

  @override
  String get tunerInstrumentChromatic => 'Chromatic';

  @override
  String get tunerInstrumentCello => 'Cello';

  @override
  String get tunerInstrumentGuitar => 'Guitar';

  @override
  String get tunerInstrumentViolin => 'Violin';

  @override
  String get tunerPickString => 'Tap a string to tune it';

  @override
  String tunerTuneString(String string) {
    return 'Tune the $string string';
  }

  @override
  String get tunerStringInTune => 'In tune!';

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
  String get playAlongLoopHint => 'Tap two notes to loop that section';

  @override
  String get playAlongLoopEnd => 'Now tap the last note of the loop';

  @override
  String get playAlongLooping => 'Looping this section — tap a note to clear';

  @override
  String get playAlongMarkFlat => 'flat';

  @override
  String get playAlongMarkSharp => 'sharp';

  @override
  String get playAlongMarkMiss => 'missed';

  @override
  String get playAlongBacking => 'Backing (use headphones)';

  @override
  String get playAlongTempo => 'Tempo';

  @override
  String get playAlongDifficulty => 'Difficulty';

  @override
  String get playAlongDifficultyEasy => 'Easy';

  @override
  String get playAlongDifficultyMedium => 'Medium';

  @override
  String get playAlongDifficultyHard => 'Hard';

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
