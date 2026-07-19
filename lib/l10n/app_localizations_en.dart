// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'CometBeat';

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
  String get workshopClefMidBar => 'Clef (mid-bar)';

  @override
  String get workshopVoice1 => 'V1';

  @override
  String get workshopVoice2 => 'V2';

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
  String get musicExportTitle => 'Export as…';

  @override
  String get musicExportEmpty => 'Nothing to export yet';

  @override
  String get musicExportFailed => 'Export failed';

  @override
  String get audioExportTitle => 'Export sound';

  @override
  String get audioExportWav => 'WAV (uncompressed)';

  @override
  String get audioExportMp3 => 'MP3 (smaller)';

  @override
  String get audioExportEmpty => 'Nothing to export yet';

  @override
  String get audioExportFailed => 'Export failed';

  @override
  String audioExportSavedTo(String path) {
    return 'Saved to $path';
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
  String get workshopTempo => 'Tempo';

  @override
  String get workshopInitialTempo => 'Initial tempo…';

  @override
  String get workshopTempoNone => 'None';

  @override
  String get workshopGraceNotes => 'Grace notes…';

  @override
  String get workshopGraceEmpty =>
      'No grace notes yet — tap a note to add one.';

  @override
  String get workshopGraceAcciaccatura => 'Acciaccatura';

  @override
  String get workshopGraceAppoggiatura => 'Appoggiatura';

  @override
  String get workshopStop => 'Stop';

  @override
  String get workshopPlayWithInstrument => 'Play with an instrument…';

  @override
  String get workshopMutePart => 'Mute';

  @override
  String get workshopPlaybackSpeed => 'Playback speed';

  @override
  String get workshopCountIn => 'Count-in';

  @override
  String get workshopLoopSelection => 'Loop selection';

  @override
  String get workshopArticulations => 'Articulations & ties';

  @override
  String get workshopOrnament => 'Ornament';

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
  String get workshopAnalysis => 'Analysis (colour by harmony)';

  @override
  String get workshopInspector => 'Inspector';

  @override
  String get workshopInspectorEmpty => 'Select a note to see its properties.';

  @override
  String get workshopStructure => 'Structure';

  @override
  String get workshopInsertMode => 'Insert';

  @override
  String get workshopSelectMode => 'Select';

  @override
  String get workshopStudioMode => 'Studio mode';

  @override
  String get workshopSplitNotes => 'Split notes across barlines';

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
  String get workshopTuplet => 'Triplet (3 in the time of 2)';

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
  String get gameArticulation => 'Read the Mark';

  @override
  String get gameArticulationSubtitle =>
      'Match the articulation mark on the note to its name';

  @override
  String get articulationPrompt => 'Which mark is on the note?';

  @override
  String get articulationStaccato => 'Staccato';

  @override
  String get articulationTenuto => 'Tenuto';

  @override
  String get articulationAccent => 'Accent';

  @override
  String get articulationMarcato => 'Marcato';

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
  String get gameEnharmonic => 'Enharmonic Twins';

  @override
  String get gameEnharmonicSubtitle =>
      'Same sound spelled two ways, or different notes?';

  @override
  String get enharmonicPrompt => 'Do these two notes sound the same?';

  @override
  String get enharmonicSame => 'Same sound';

  @override
  String get enharmonicDifferent => 'Different';

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
  String get gameSpotUpbeat => 'Spot the Upbeat';

  @override
  String get gameSpotUpbeatSubtitle =>
      'Does the tune start on the beat, or with a pickup?';

  @override
  String get spotUpbeatPrompt => 'Where does the melody begin?';

  @override
  String get spotUpbeatUpbeat => 'Upbeat';

  @override
  String get spotUpbeatOnBeat => 'On the beat';

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
  String get gameFretboardFind => 'Find the Note';

  @override
  String get gameFretboardFindSubtitle =>
      'Tap where the note is on the fretboard';

  @override
  String get gameCapoMatch => 'Capo Match';

  @override
  String get gameCapoMatchSubtitle =>
      'With a capo, what does the shape sound like?';

  @override
  String get primerFretboardTitle => 'One note, many places';

  @override
  String get primerFretboardSame =>
      'The same note lives in several spots on the fretboard — different strings, different frets.';

  @override
  String get primerFretboardAny =>
      'So when you look for a note, tapping ANY of its spots is right!';

  @override
  String get primerCapoTitle => 'What a capo does';

  @override
  String get primerCapoClamp =>
      'A capo clamps all the strings up a fret — like a new nut higher up the neck.';

  @override
  String get primerCapoShape => 'So a shape you know, like C…';

  @override
  String get primerCapoSounds =>
      '…sounds HIGHER. With the capo on the 2nd fret, that C shape rings out as a D.';

  @override
  String get capoMatchPrompt =>
      'With the capo on, what does this shape sound like?';

  @override
  String get capoMatchShapeLabel => 'chord shape';

  @override
  String capoMatchCapo(int fret) {
    return 'Capo $fret';
  }

  @override
  String fretboardFindPrompt(String note) {
    return 'Find $note on the fretboard';
  }

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
  String get gameMelodyDoodle => 'Melody doodle';

  @override
  String get gameMelodyDoodleSubtitle => 'Draw a line and hear it as a tune';

  @override
  String get melodyDoodlePrompt =>
      'Drag a line across the box — higher is higher!';

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
  String get loopVoiceWithInstrument => 'Play with a saved instrument';

  @override
  String get loopVoiceReset => 'Reset to built-in sound';

  @override
  String get loopVoiceUnavailable =>
      'This voice needs its SoundFont file, so it can\'t be used here.';

  @override
  String get loopMixerPrompt => 'Tap the cards to start your band!';

  @override
  String get loopMixerStop => 'Stop';

  @override
  String get loopMixerSwing => 'Swing';

  @override
  String get loopMixerHarmony => 'Harmony';

  @override
  String get loopMixerKey => 'Key';

  @override
  String get loopMixerScale => 'Scale';

  @override
  String get loopMixerScaleMajor => 'Major';

  @override
  String get loopMixerScaleMinor => 'Minor';

  @override
  String get loopMixerKit => 'Kit';

  @override
  String get loopMixerKitClean => 'Clean';

  @override
  String get loopMixerKitDeep => 'Deep';

  @override
  String get loopMixerKitWarm => 'Warm';

  @override
  String get loopMixerKitLofi => 'Lo-fi';

  @override
  String get loopMixerFilter => 'Filter';

  @override
  String get loopMixerQuantize => 'Quantize launch (drop in on the beat)';

  @override
  String get loopMixerSolo => 'Solo pad (drag to play in key)';

  @override
  String get loopMixerSoloKeep => 'Keep';

  @override
  String get loopMixerScenes => 'Sections';

  @override
  String get loopMixerScenesHint =>
      'Tap to launch, hold to capture the current layers';

  @override
  String get loopMixerChain => 'Chain sections (auto-advance)';

  @override
  String get loopMixerExportArrangement => 'Export the sections as one track';

  @override
  String get loopMixerChallengeSparkle =>
      'Try: add something high and sparkly ✨';

  @override
  String get loopMixerChallengeBass => 'Try: add a deep bassline';

  @override
  String get loopMixerChallengeMelody => 'Try: add a tune on top';

  @override
  String get loopMixerChallengeLayers => 'Try: stack three layers at once';

  @override
  String get loopMixerChallengeFullBand => 'Try: play the whole band together';

  @override
  String get loopMixerChallengeDone => 'Nice! Tap for another idea →';

  @override
  String get loopMixerStyle => 'Style';

  @override
  String get loopMixerStyleClassic => 'Classic';

  @override
  String get loopMixerStyleFour => 'Four-on-floor';

  @override
  String get loopMixerStyleChill => 'Lounge';

  @override
  String get loopMixerHarmonyOff => 'Free';

  @override
  String get loopMixerRoll => 'Surprise me — roll a new groove';

  @override
  String get loopMixerSaveSlot => 'Save to my grooves';

  @override
  String get loopMixerMySlots => 'My grooves';

  @override
  String get loopMixerSlotNameHint => 'Name your groove';

  @override
  String get loopMixerSave => 'Save';

  @override
  String loopMixerSlotSaved(String name) {
    return 'Saved “$name”';
  }

  @override
  String get loopMixerNoSlots => 'No saved grooves yet';

  @override
  String loopMixerComboFound(String name) {
    return 'Combo unlocked: $name!';
  }

  @override
  String get loopMixerCombosTip => 'Secret combos found';

  @override
  String get loopMixerComboRhythmSection => 'Rhythm Section';

  @override
  String get loopMixerComboDuo => 'Duo';

  @override
  String get loopMixerComboDreamy => 'Dreamy';

  @override
  String get loopMixerComboMarching => 'Marching Band';

  @override
  String get loopMixerComboFullBand => 'Full Band';

  @override
  String get loopMixerScore => 'Show as sheet music';

  @override
  String get loopMixerScoreEmpty =>
      'Turn on a layer to see it written as notes.';

  @override
  String get loopMixerShare => 'Share your groove';

  @override
  String get loopMixerCopyCode => 'Copy groove code';

  @override
  String get loopMixerPasteCode => 'Paste a groove code';

  @override
  String get loopMixerCodeCopied => 'Groove code copied — paste it anywhere!';

  @override
  String get loopMixerCodeInvalid => 'That groove code didn\'t work';

  @override
  String get loopMixerSaveAudio => 'Save as audio (WAV)';

  @override
  String get loopMixerSaveSongBook => 'Save to Song Book';

  @override
  String get loopMixerExportMusicXml => 'Export sheet music (MusicXML)';

  @override
  String get loopMixerOpenTracker => 'Open in the Tracker';

  @override
  String get loopMixerOpenWorkshop => 'Open in the Score Workshop';

  @override
  String get loopMixerSaveTitle => 'Name your groove';

  @override
  String get loopMixerSaveFailed => 'Saving audio isn\'t available here';

  @override
  String get loopMixerLoad => 'Load';

  @override
  String get loopMixerInfinite =>
      'Infinite mode — every loop a little different';

  @override
  String get loopMixerSend => 'Space effect (reverb / echo)';

  @override
  String get loopMixerSing => 'Sing a track!';

  @override
  String get loopMixerSingAgain => 'Sing your track again';

  @override
  String get loopMixerSingNow => 'Sing now!';

  @override
  String get loopMixerSingNothing => 'We couldn\'t hear a tune — try again!';

  @override
  String get loopMixerTrackVoice => 'My voice';

  @override
  String get loopMixerBeatbox => 'Beatbox a beat!';

  @override
  String get loopMixerBeatboxAgain => 'Beatbox again';

  @override
  String get loopMixerBeatNow => 'Beatbox now!';

  @override
  String get loopMixerTrackBeat => 'My beat';

  @override
  String get loopMixerJam => 'Jam along — best with headphones';

  @override
  String get loopMixerJamHint =>
      'Play or sing along — green fits the chord! Headphones help the mic hear only you.';

  @override
  String get loopMixerJamHintAec =>
      'Play or sing along — the band listens back! Green fits the chord.';

  @override
  String get loopMixerJamGraded => '🎧 Band cancelled — this grades you';

  @override
  String get loopMixerJamHeadphones => 'Headphones help the mic hear only you';

  @override
  String get loopMixerFollow => 'Follow the melody';

  @override
  String loopMixerFollowScore(int pct) {
    return '🎯 Melody match: $pct%';
  }

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
  String get gameTrackerAdvanced => 'Advanced Tracker';

  @override
  String get workshopModeScore => 'Score Workshop';

  @override
  String get workshopModeTracker => 'Tracker';

  @override
  String get workshopModeTab => 'Guitar Tab';

  @override
  String get workshopModeLoop => 'Loop Mixer';

  @override
  String get workshopModeDrums => 'Drum Kit';

  @override
  String get workshopModeTranscribe => 'Transcribe';

  @override
  String get transcribeTitle => 'Transcribe a recording';

  @override
  String get transcribeIntro =>
      'Turn a recording into notes. Works best on a single clear melody or voice; chords and full songs use the neural engine when it is available.';

  @override
  String get transcribePickFile => 'Choose an audio file (WAV)';

  @override
  String get transcribeEngineAuto => 'Auto';

  @override
  String get transcribeEngineMono => 'Melody';

  @override
  String get transcribeEngineNeural => 'Neural';

  @override
  String get transcribeNeuralWebNote =>
      'The neural engine needs the app (not the web version) — the melody engine will be used here.';

  @override
  String transcribeResult(int count, int bpm) {
    return '$count notes · $bpm BPM';
  }

  @override
  String transcribeEngineUsed(String engine) {
    return 'Engine: $engine';
  }

  @override
  String get transcribeOpenSongBook => 'Open in Song Book';

  @override
  String get transcribeNoNotes =>
      'No notes found — try a clearer solo recording.';

  @override
  String transcribeError(String message) {
    return 'Couldn\'t transcribe: $message';
  }

  @override
  String get dawTitle => 'Multitrack';

  @override
  String get dawAddBeat => 'Add beat';

  @override
  String get dawAddSample => 'Add sample';

  @override
  String get dawAddTune => 'Add tune';

  @override
  String get dawEmpty =>
      'Add a beat or a tune, then press play — they layer together.';

  @override
  String get dawSend => 'To Multitrack';

  @override
  String get dawSent => 'Added to the Multitrack';

  @override
  String dawBpm(int n) {
    return '$n BPM';
  }

  @override
  String get dawTempoUp => 'Faster';

  @override
  String get dawTempoDown => 'Slower';

  @override
  String get dawAddTrack => 'Add track';

  @override
  String get dawTrackTitle => 'Track';

  @override
  String get dawTrackName => 'Name';

  @override
  String get dawRenameTrack => 'Rename';

  @override
  String get dawRemoveTrack => 'Remove track';

  @override
  String get dawRename => 'Rename';

  @override
  String get dawCancel => 'Cancel';

  @override
  String get dawSaveProject => 'Save project';

  @override
  String get dawOpenProject => 'Open project';

  @override
  String get dawProjectSaved => 'Project saved';

  @override
  String get dawProjectSaveFailed => 'Could not save the project';

  @override
  String get dawProjectOpenFailed => 'Could not open the project';

  @override
  String get dawMergeAll => 'Merge all';

  @override
  String get dawMerged => 'Merged into one audio take';

  @override
  String get dawDuplicate => 'Duplicate';

  @override
  String get dawFreeze => 'Freeze to audio';

  @override
  String get dawFrozen => 'Frozen to an audio take';

  @override
  String get dawUndo => 'Undo';

  @override
  String get dawRedo => 'Redo';

  @override
  String get dawGain => 'Volume';

  @override
  String get dawFadeIn => 'Fade in';

  @override
  String get dawTrimStart => 'Trim start';

  @override
  String get dawTrimEnd => 'Trim end';

  @override
  String get dawFadeOut => 'Fade out';

  @override
  String get dawRemoveClip => 'Remove';

  @override
  String get dawLoop => 'Loop';

  @override
  String get dawSnap => 'Snap to grid';

  @override
  String get drumkitTitle => 'Drum Kit';

  @override
  String get drumkitRecord => 'Record';

  @override
  String get drumkitStopRecording => 'Stop recording';

  @override
  String get drumkitBeatbox => 'Beatbox';

  @override
  String get drumkitStopListening => 'Stop';

  @override
  String get drumkitBeatboxNothing => 'Nothing heard — try beatboxing louder.';

  @override
  String get drumkitSave => 'Save to Song Book';

  @override
  String get drumkitExport => 'Export';

  @override
  String get drumkitSaveTitle => 'Name your beat';

  @override
  String get drumkitDefaultName => 'My beat';

  @override
  String get drumkitSaved => 'Saved to the Song Book';

  @override
  String get drumkitStraight => 'Straight';

  @override
  String get drumkitSwing => 'Swing';

  @override
  String get drumkitKick => 'Kick';

  @override
  String get drumkitSnare => 'Snare';

  @override
  String get drumkitHat => 'Hi-hat';

  @override
  String get tabWorkshopTitle => 'Guitar Tab';

  @override
  String get tabImport => 'Open a file';

  @override
  String get tabDemo => 'Demo riff';

  @override
  String get tabTuning => 'Tuning';

  @override
  String get tabCapo => 'Capo';

  @override
  String get tabShowStandard => 'Standard notation';

  @override
  String get tabTempo => 'Tempo';

  @override
  String get tabMic => 'Play it in (microphone)';

  @override
  String get tabMicDenied => 'Microphone permission is needed';

  @override
  String get tabMicFailed => 'Couldn\'t start the microphone';

  @override
  String get tabTracks => 'Tracks';

  @override
  String get tabAddTrack => 'Add track';

  @override
  String get tabRemoveTrack => 'Remove track';

  @override
  String get tabOpenSongBook => 'Open from Song Book';

  @override
  String get tabOpenWorkshop => 'Open in Score Workshop';

  @override
  String get soundLabTitle => 'Sound Lab';

  @override
  String get soundLabPlay => 'Play';

  @override
  String get soundLabExport => 'Export WAV';

  @override
  String get soundLabShare => 'Copy share code';

  @override
  String get soundLabRandomize => 'Randomize';

  @override
  String get soundLabMutate => 'Mutate';

  @override
  String get soundLabSetA => 'Snapshot A';

  @override
  String get soundLabSetB => 'Snapshot B';

  @override
  String get soundLabMorphHint =>
      'Snapshot two sounds into A and B to blend between them.';

  @override
  String get soundLabCopied => 'Share code copied';

  @override
  String get soundLabExportFailed => 'Export failed';

  @override
  String soundLabSavedTo(String path) {
    return 'Saved to $path';
  }

  @override
  String get soundLabSaveTitle => 'Save…';

  @override
  String get soundLabSaveRecipe => 'Save recipe (My Sounds)';

  @override
  String get soundLabToSamples => 'Save as sample (My Samples)';

  @override
  String get soundLabSfxName => 'Sample name';

  @override
  String get soundLabMyTitle => 'My Sounds';

  @override
  String get soundLabSaveName => 'Name';

  @override
  String get soundLabCancel => 'Cancel';

  @override
  String get soundLabSave => 'Save';

  @override
  String get soundLabDelete => 'Delete';

  @override
  String soundLabDefaultName(int n) {
    return 'Sound $n';
  }

  @override
  String soundLabSaved(String name) {
    return 'Saved “$name”';
  }

  @override
  String get soundLabMyEmpty =>
      'No saved sounds yet. Make one, then tap the bookmark to keep it.';

  @override
  String get soundLabSquare => 'Square';

  @override
  String get soundLabSaw => 'Saw';

  @override
  String get soundLabSine => 'Sine';

  @override
  String get soundLabNoise => 'Noise';

  @override
  String get soundLabPitch => 'Pitch';

  @override
  String get soundLabSlide => 'Slide';

  @override
  String get soundLabAttack => 'Attack';

  @override
  String get soundLabHold => 'Hold';

  @override
  String get soundLabFade => 'Fade';

  @override
  String get soundLabPunch => 'Punch';

  @override
  String get soundLabBuzz => 'Buzz';

  @override
  String get soundLabWobble => 'Wobble';

  @override
  String get soundLabBright => 'Bright';

  @override
  String get soundLabCrunch => 'Crunch';

  @override
  String get soundLabEcho => 'Echo';

  @override
  String get voiceLabTitle => 'Voice Lab';

  @override
  String get voiceLabPlay => 'Play';

  @override
  String get voiceLabSurprise => 'Surprise me';

  @override
  String get voiceLabExport => 'Export WAV';

  @override
  String get voiceLabRecord => 'Record';

  @override
  String get voiceLabLoad => 'Load audio';

  @override
  String get voiceLabHint =>
      'Record your voice or load a sound, then transform it.';

  @override
  String get voiceLabCharacter => 'Character';

  @override
  String get voiceLabPitch => 'Pitch';

  @override
  String get voiceLabSpeed => 'Speed';

  @override
  String get voiceLabTremolo => 'Wobble';

  @override
  String get voiceLabGate => 'Gate';

  @override
  String get voiceLabReverb => 'Reverb';

  @override
  String get voiceLabAlien => 'Alien';

  @override
  String get voiceLabCrunch => 'Crunch';

  @override
  String get voiceLabEcho => 'Echo';

  @override
  String get voiceLabNoMic => 'Microphone permission is needed';

  @override
  String get voiceLabRecordFailed => 'Couldn\'t record';

  @override
  String get voiceLabExportFailed => 'Export failed';

  @override
  String voiceLabSavedTo(String path) {
    return 'Saved to $path';
  }

  @override
  String get voiceLabSaveTitle => 'Save to My Samples';

  @override
  String get voiceLabMyTitle => 'My Samples';

  @override
  String get voiceLabSaveName => 'Name';

  @override
  String get voiceLabCancel => 'Cancel';

  @override
  String get voiceLabSave => 'Save';

  @override
  String get voiceLabDelete => 'Delete';

  @override
  String voiceLabDefaultName(int n) {
    return 'Voice $n';
  }

  @override
  String get voiceLabMyEmpty =>
      'No saved samples yet. Shape a voice, then tap the bookmark to keep it.';

  @override
  String get sampleExtractTitle => 'Sample Extractor';

  @override
  String get sampleExtractOpen => 'Open modules…';

  @override
  String get sampleExtractHint =>
      'Open one or more tracker modules (.mod, .xm, .s3m, .it) to lift out their samples. You can preview each, export it as a WAV, or add it to My Samples.\n\nUse only files you have the right to reuse — the app makes no licensing claim about a module\'s samples.';

  @override
  String sampleExtractCount(int n) {
    return '$n samples';
  }

  @override
  String sampleExtractLibrary(int n) {
    return 'My Samples: $n';
  }

  @override
  String sampleExtractMeta(String module, String secs) {
    return '$module · ${secs}s';
  }

  @override
  String get sampleExtractBrowsePacks => 'Browse free packs';

  @override
  String get samplePackSearch => 'Search instruments…';

  @override
  String get samplePackHint =>
      'Free instrument sample packs. Only packs whose licence is clearly permissive are listed — anything ambiguous is hidden.';

  @override
  String get samplePackEmpty => 'No packs found';

  @override
  String get mySamplesTitle => 'My Samples';

  @override
  String get myInstrumentsTitle => 'My Instruments';

  @override
  String get myInstrumentsEmpty =>
      'No saved instruments yet. Shape a voice and tap “Save as instrument”.';

  @override
  String get myInstrumentsAudition => 'Play a note';

  @override
  String get myInstrumentsPlay => 'Play';

  @override
  String get instrumentPlayOctaveDown => 'Octave down';

  @override
  String get instrumentPlayOctaveUp => 'Octave up';

  @override
  String get instrumentPlayHint => 'Tap the keys to play your instrument.';

  @override
  String get myInstrumentsDelete => 'Delete';

  @override
  String get voiceLabSaveInstrument => 'Save as instrument';

  @override
  String voiceLabInstrumentSaved(String name) {
    return 'Saved “$name” to My Instruments';
  }

  @override
  String get voiceLabMyInstruments => 'My Instruments';

  @override
  String get mySamplesEmpty =>
      'No saved samples yet. Extract some from a module or pack, or save a voice.';

  @override
  String get mySamplesCredits => 'Credits';

  @override
  String get mySamplesClose => 'Close';

  @override
  String get mySamplesImport => 'Import file';

  @override
  String get mySamplesImportFailed => 'Couldn\'t read that audio file.';

  @override
  String get mySamplesPreview => 'Preview';

  @override
  String get mySamplesDelete => 'Delete';

  @override
  String get sampleExtractPreview => 'Preview';

  @override
  String get sampleExtractExport => 'Export WAV';

  @override
  String get sampleExtractExportFolder => 'Export all to a folder';

  @override
  String sampleExtractSavedFolder(int n, String dir) {
    return 'Saved $n WAVs to $dir';
  }

  @override
  String get sampleExtractAdd => 'Add to My Samples';

  @override
  String get sampleExtractAddAll => 'Add all to My Samples';

  @override
  String sampleExtractAdded(String name) {
    return 'Added “$name”';
  }

  @override
  String sampleExtractAddedAll(int n) {
    return 'Added $n samples';
  }

  @override
  String sampleExtractFailed(String files) {
    return 'Could not read: $files';
  }

  @override
  String get tabPasteAscii => 'Paste ASCII tab';

  @override
  String get tabPasteAsciiHint => 'e|--0--3--|\nB|--1-----|\n...';

  @override
  String get tabSongBookEmpty => 'Your Song Book is empty';

  @override
  String get tabSaveSongBook => 'Save to Song Book';

  @override
  String tabSaved(String title) {
    return 'Saved “$title”';
  }

  @override
  String get tabPlay => 'Play';

  @override
  String get tabCountIn => 'Count-in';

  @override
  String get tabClear => 'Clear';

  @override
  String get tabDuration => 'Note length';

  @override
  String get tabClearCell => 'Clear';

  @override
  String get tabAddColumn => 'Add step';

  @override
  String get tabRemoveColumn => 'Remove step';

  @override
  String get tabDuplicateBar => 'Duplicate bar';

  @override
  String get tabTechnique => 'Technique';

  @override
  String get tabTechHammer => 'H/P';

  @override
  String get tabTechSlide => 'Slide';

  @override
  String get tabTechBend => 'Bend';

  @override
  String get tabTechVibrato => 'Vibrato';

  @override
  String get tabTechDead => 'Dead ✕';

  @override
  String get tabTechGhost => 'Ghost';

  @override
  String get tabTechHarmonic => 'Harmonic';

  @override
  String get tabChord => 'Chord';

  @override
  String get tabChordPick => 'Pick a chord';

  @override
  String get tabChordNone => 'No chord';

  @override
  String get tabPattern => 'Insert…';

  @override
  String get tabPatternChord => 'Chord';

  @override
  String get tabPatternProgression => 'Progression';

  @override
  String get tabPatternRepeat => 'Repeat';

  @override
  String get tabPatternScale => 'Scale';

  @override
  String get tabPatternStyle => 'Style';

  @override
  String get tabPatternStrum => 'Strum';

  @override
  String get tabPatternUp => 'Up';

  @override
  String get tabPatternDown => 'Down';

  @override
  String get tabPatternUpDown => 'Up-down';

  @override
  String get tabPatternDownUp => 'Down-up';

  @override
  String get tabPatternTravis => 'Travis';

  @override
  String get tabPatternBoomChuck => 'Boom-chuck';

  @override
  String get tabPatternStrumEighths => '8ths strum';

  @override
  String get tabPatternIsland => 'Island';

  @override
  String get tabPatternRoot => 'Root';

  @override
  String get tabPatternScaleType => 'Scale';

  @override
  String get tabPatternOctaves => 'Octaves';

  @override
  String get tabPatternPosition => 'Position';

  @override
  String get tabPatternPositionOpen => 'Open';

  @override
  String get tabPatternPreview => 'Preview';

  @override
  String get tabPatternInsert => 'Insert';

  @override
  String tabPatternAdded(int count) {
    return 'Added $count steps';
  }

  @override
  String get tabExport => 'Export';

  @override
  String get tabExportGp => 'Guitar Pro (.gp)';

  @override
  String get tabExportMusicXml => 'MusicXML';

  @override
  String get tabExportMidi => 'MIDI';

  @override
  String get tabExportFailed => 'Export failed';

  @override
  String tabSavedTo(String path) {
    return 'Saved to $path';
  }

  @override
  String get tabImportFailed => 'Couldn\'t open that file';

  @override
  String get libraryTitle => 'Free music libraries';

  @override
  String get librarySaveToMy => 'Save to My Samples';

  @override
  String librarySavedToMy(String name) {
    return 'Saved “$name” to My Samples';
  }

  @override
  String get librarySearchHint => 'Search by title or composer';

  @override
  String get libraryImport => 'Import';

  @override
  String libraryImported(String title) {
    return 'Imported “$title”';
  }

  @override
  String get libraryAlreadyImported => 'Already in your Song Book';

  @override
  String get libraryLicenseBlocked =>
      'That work isn\'t openly licensed — skipped';

  @override
  String get libraryImportFailed => 'Import failed';

  @override
  String get libraryLoadFailed => 'Couldn\'t load the library';

  @override
  String get libraryRetry => 'Retry';

  @override
  String get libraryNoResults => 'No matches';

  @override
  String get librarySourcesCredits => 'Sources & credits';

  @override
  String get libraryNoCredits => 'Nothing imported from a library yet';

  @override
  String get libraryCreditsSongs => 'Scores & songs';

  @override
  String get libraryCreditsSamples => 'Samples';

  @override
  String get libraryCreditsIntro =>
      'Works imported from open music libraries, with their licenses.';

  @override
  String get librarySupportDev => 'Support the developer';

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
  String get trackerChannelDrums => 'Drums';

  @override
  String get trackerChannelVoice => 'Voice';

  @override
  String get trackerToggleNotation => 'Show notation';

  @override
  String get trackerWideRange => 'Wide range (more octaves)';

  @override
  String get trackerSimplified =>
      'Simplified for Beginner mode (pitched notes snapped to the grid; drums dropped)';

  @override
  String get trackerImportTune => 'Load a tune';

  @override
  String get trackerSwing => 'Swing';

  @override
  String get trackerDemoTune => 'Simple tune (C D E G)';

  @override
  String get trackerChangeInstrument => 'Change instrument';

  @override
  String get trackerPattern => 'Pattern';

  @override
  String get trackerSong => 'Song';

  @override
  String get trackerPlaySong => 'Play song';

  @override
  String get trackerSoftNote => 'Soft note';

  @override
  String get trackerEffect => 'Effect';

  @override
  String get trackerEffectNone => 'None';

  @override
  String get trackerEffectArp => 'Arpeggio';

  @override
  String get trackerEffectVibrato => 'Vibrato';

  @override
  String get trackerEffectSlideUp => 'Slide up';

  @override
  String get trackerEffectSlideDown => 'Slide down';

  @override
  String get trackerImportMod => 'Import tune (MOD/XM/S3M/IT)…';

  @override
  String get trackerExportMod => 'Export .mod…';

  @override
  String get trackerImportMidi => 'Import MIDI…';

  @override
  String get trackerImportAbc => 'Import ABC…';

  @override
  String get trackerExportMidi => 'Export MIDI…';

  @override
  String get trackerModFailed => 'Couldn\'t read/write that .mod.';

  @override
  String get trackerBorrowSample => 'Borrow instrument…';

  @override
  String get trackerSaveSong => 'Save to Song Book';

  @override
  String get trackerImportScore => 'Import score (MusicXML/ABC/MEI/kern/MIDI)…';

  @override
  String get trackerExportXml => 'Export MusicXML…';

  @override
  String get trackerExportAbc => 'Export ABC…';

  @override
  String get trackerExportModule => 'Export module (.mod/.xm/.s3m/.it)…';

  @override
  String get trackerOpenWorkshop => 'Open in Score Workshop';

  @override
  String get trackerSavedSong => 'Saved to the Song Book';

  @override
  String get trackerSaveEmpty => 'Place some notes first';

  @override
  String get trackerBorrowEmpty => 'That module has no samples to borrow.';

  @override
  String get trackerChangeEffect => 'Channel effect';

  @override
  String get trackerFxNone => 'None';

  @override
  String get trackerFxDelay => 'Echo';

  @override
  String get trackerFxChorus => 'Chorus';

  @override
  String get trackerFxFlanger => 'Flanger';

  @override
  String get trackerFxReverb => 'Reverb';

  @override
  String get trackerFxRingMod => 'Robot';

  @override
  String get trackerFxCrunch => 'Crunch';

  @override
  String get trackerSfxrZap => 'Zap';

  @override
  String get trackerSfxrBlip => 'Blip';

  @override
  String get trackerSfxrLaser => 'Laser';

  @override
  String get trackerSfxrCoin => 'Coin';

  @override
  String get trackerSfxrBell => 'Bell';

  @override
  String get trackerSfxrExplosion => 'Boom';

  @override
  String get trackerRecord => 'Record';

  @override
  String get trackerRecording => 'Recording…';

  @override
  String get trackerRecordFailed => 'Couldn\'t use the microphone.';

  @override
  String get trackerRecordPrompt => 'Pick a voice, then record 2 seconds!';

  @override
  String get trackerVoiceNormal => 'Normal';

  @override
  String get trackerVoiceChipmunk => 'Chipmunk';

  @override
  String get trackerVoiceMonster => 'Monster';

  @override
  String get trackerVoiceDeep => 'Deep';

  @override
  String get trackerVoiceRobot => 'Robot';

  @override
  String get trackerVoiceAlien => 'Alien';

  @override
  String get trackerVoiceCyborg => 'Cyborg';

  @override
  String get trackerVoiceRadio => 'Radio';

  @override
  String get trackerVoiceDemon => 'Demon';

  @override
  String get trackerSpeedSlow => 'Slow';

  @override
  String get trackerSpeedNormal => 'Normal';

  @override
  String get trackerSpeedFast => 'Fast';

  @override
  String get trackerAdvancedTitle => 'Tracker · Advanced';

  @override
  String get trackerOpenAdvanced => 'Advanced Tracker';

  @override
  String get trackerModeToAdvanced => 'Advanced mode';

  @override
  String get trackerModeToBeginner => 'Beginner mode';

  @override
  String get trackerLength => 'Length';

  @override
  String get trackerAddTrack => 'Add track';

  @override
  String get trackerRemoveTrack => 'Remove this track';

  @override
  String get trackerPlay => 'Play';

  @override
  String get trackerPause => 'Pause';

  @override
  String get trackerStop => 'Stop';

  @override
  String get trackerBack => 'Back';

  @override
  String get trackerForward => 'Forward';

  @override
  String get trackerLoop => 'Loop';

  @override
  String get trackerPickNote => 'Pick a note';

  @override
  String get trackerOctave => 'Octave';

  @override
  String get trackerEditStep => 'Step';

  @override
  String get trackerPatternNew => 'New pattern';

  @override
  String get trackerPatternClone => 'Clone pattern';

  @override
  String get trackerRenamePattern => 'Rename section';

  @override
  String get trackerRenamePatternHint => 'e.g. Intro, Verse, Chorus';

  @override
  String get trackerTempo => 'Tempo';

  @override
  String get trackerSwingOff => 'Off';

  @override
  String get trackerSwingHelp =>
      'Groove: delays every off-beat step for a shuffle feel (0 = straight)';

  @override
  String get trackerCustomLength => 'Custom…';

  @override
  String get trackerCustomLengthPrompt => 'Rows (e.g. 64, 128, 256)';

  @override
  String get trackerEditStepHelp =>
      'Rows the cursor jumps down after each note';

  @override
  String get trackerCancel => 'Cancel';

  @override
  String get trackerOk => 'OK';

  @override
  String get trackerEntryPiano => 'Piano keys';

  @override
  String get trackerEntryNames => 'Note names';

  @override
  String get trackerKeyHelp => 'Keyboard';

  @override
  String get trackerShowKeys => 'Show key hints';

  @override
  String get trackerRecordLive => 'Live record (jam into the pattern)';

  @override
  String get trackerInterpolate => 'Interpolate volumes';

  @override
  String get trackerInterpNotes => 'Interpolate notes (run)';

  @override
  String get trackerChord => 'Chord';

  @override
  String get trackerChordRoot => 'Root';

  @override
  String get trackerChordAcross => 'Across tracks';

  @override
  String get trackerChordArp => 'Arpeggio (down)';

  @override
  String get trackerBlockFillVoice => 'Fill voice across block';

  @override
  String get trackerBlockFillVoiceHelp =>
      'Block menu — fills each column from its top voice';

  @override
  String get trackerInstColumn => 'Instrument column';

  @override
  String get trackerInstColumnHelp =>
      'Tab to it, type a pool number (Backspace = channel default)';

  @override
  String get trackerField => 'Column (note / vol / fx)';

  @override
  String get trackerPlayFromCursor => 'Play from cursor';

  @override
  String get trackerMetronome => 'Metronome';

  @override
  String get trackerQuantize => 'Quantize (snap to beat)';

  @override
  String get trackerFollow => 'Follow the playhead';

  @override
  String get trackerScope => 'Toggle the oscilloscope';

  @override
  String get trackerLoadDemo => 'Load a demo song';

  @override
  String get trackerZoomIn => 'Zoom in';

  @override
  String get trackerZoomOut => 'Zoom out';

  @override
  String get trackerClassicSkin => 'Classic tracker look';

  @override
  String get trackerInsertRow => 'Insert row (at cursor)';

  @override
  String get trackerDeleteRow => 'Delete row (at cursor)';

  @override
  String get trackerFxHelp => 'In the fx column, type: command + 2 hex digits';

  @override
  String get trackerFxPitch =>
      'arpeggio · porta up/down · tone-porta · vibrato';

  @override
  String get trackerFxTremVolSet => 'tremolo · volume slide · set volume';

  @override
  String get trackerFxFlow => 'jump · pattern break · speed/tempo · extended';

  @override
  String get trackerOrderMoveLeft => 'Move slot left';

  @override
  String get trackerOrderMoveRight => 'Move slot right';

  @override
  String get trackerOrderInsert => 'Insert a copy';

  @override
  String get trackerOrderPrevPat => 'Slot → previous pattern';

  @override
  String get trackerOrderNextPat => 'Slot → next pattern';

  @override
  String get trackerClearCell => 'Clear cell';

  @override
  String get trackerClearConfirm =>
      'Erase the whole pattern? This can\'t be undone.';

  @override
  String get trackerCursor => 'Move cursor';

  @override
  String get trackerFxColumn => 'Effect column (MOD)';

  @override
  String get trackerMixer => 'Tracks & mixer';

  @override
  String get trackerGain => 'Volume';

  @override
  String get trackerPan => 'Pan (left ↔ right)';

  @override
  String get trackerEnvelope => 'Volume shape (envelope)';

  @override
  String get trackerEnvFlat => 'Flat (no shape)';

  @override
  String get trackerEnvFadeIn => 'Fade in';

  @override
  String get trackerEnvFadeOut => 'Fade out';

  @override
  String get trackerEnvPluck => 'Pluck (quick decay)';

  @override
  String get trackerEnvSwell => 'Swell';

  @override
  String get trackerAutoPan => 'Auto-pan';

  @override
  String get trackerPanOff => 'Off (fixed)';

  @override
  String get trackerPanLR => 'Left → right';

  @override
  String get trackerPanRL => 'Right → left';

  @override
  String get trackerPanPingPong => 'Ping-pong';

  @override
  String get trackerInstruments => 'Instrument for new notes';

  @override
  String get trackerInstrumentDefault => 'Channel default';

  @override
  String get trackerLongPressToHear => 'Long-press a voice to hear it';

  @override
  String get trackerRecordSample => 'Record sample';

  @override
  String get trackerSampleTrim => 'Trim silence';

  @override
  String get trackerSampleTrimDrag => 'Drag the handles to trim the sample';

  @override
  String get trackerSampleNormalize => 'Normalize';

  @override
  String get trackerSampleReverse => 'Reverse';

  @override
  String get trackerSampleSustain => 'Sustain';

  @override
  String get trackerAssignSample => 'Use for this track';

  @override
  String get trackerLoadWav => 'Load WAV file…';

  @override
  String get trackerMySamples => 'From My Samples';

  @override
  String get trackerFreeSounds => 'Browse free sounds…';

  @override
  String get trackerStarterBeat => 'Add a starter beat';

  @override
  String get trackerLoadSoundFont => 'Load SoundFont…';

  @override
  String get trackerMyInstruments => 'My Instruments';

  @override
  String get trackerSoundLibrary => 'Sound library';

  @override
  String get trackerAddFromLibrary => 'Add from library…';

  @override
  String get trackerLibTonal => 'Tonal';

  @override
  String get trackerLibPlucked => 'Plucked';

  @override
  String get trackerLibChiptune => 'Chiptune';

  @override
  String get trackerLibDrum => 'Drum';

  @override
  String get trackerLibRecorded => 'Recorded';

  @override
  String get trackerLibPercussion => 'Percussion (CC0)';

  @override
  String get trackerRemove => 'Remove';

  @override
  String get trackerShareSong => 'Share song (token)';

  @override
  String get trackerLoadSong => 'Load song (token)';

  @override
  String get trackerSongCopied => 'Song token copied to clipboard';

  @override
  String get trackerCopy => 'Copy';

  @override
  String get trackerClose => 'Close';

  @override
  String get trackerPasteToken => 'Paste a song token (CBS1.…)';

  @override
  String get trackerLoad => 'Load';

  @override
  String get trackerTokenInvalid => 'That\'s not a valid song token.';

  @override
  String get trackerModArchive => 'Browse The Mod Archive…';

  @override
  String get modArchiveTitle => 'The Mod Archive';

  @override
  String get modArchiveKeyPrompt =>
      'This browses only the CC0 / Public-Domain modules and needs your own free API key from modarchive.org.';

  @override
  String get modArchiveKeyLabel => 'API key';

  @override
  String get modArchiveGetKey => 'Get a key';

  @override
  String get modArchiveSaveKey => 'Save';

  @override
  String get trackerPreview => 'Preview';

  @override
  String get trackerCopyInstrument => 'Copy instrument to…';

  @override
  String get trackerBlock => 'Block';

  @override
  String get trackerBlockMark => 'Mark (tap cells to select)';

  @override
  String get trackerBlockTrack => 'Select track';

  @override
  String get trackerBlockPattern => 'Select pattern';

  @override
  String get trackerBlockCopy => 'Copy';

  @override
  String get trackerBlockCut => 'Cut';

  @override
  String get trackerBlockPaste => 'Paste (overwrite)';

  @override
  String get trackerBlockPasteMix => 'Paste-mix (fill gaps)';

  @override
  String get trackerBlockTransUp => 'Transpose +1';

  @override
  String get trackerBlockTransDown => 'Transpose −1';

  @override
  String get trackerBlockOctUp => 'Transpose +octave';

  @override
  String get trackerBlockOctDown => 'Transpose −octave';

  @override
  String get trackerBlockClear => 'Clear block';

  @override
  String get trackerBlockUnmark => 'Unmark';

  @override
  String get trackerTutGrid =>
      'This is a pattern grid: time runs top-to-bottom in rows, and each column is a track. Tap a cell to move the edit cursor, then play a note into it.';

  @override
  String get trackerTutKeys =>
      'Type notes on your computer keyboard. \'Piano keys\' uses the classic tracker layout (Z–M is one octave, Q–I the next). \'Note names\' lets you type a letter then an octave digit, e.g. F then 2 = F2. The ⓘ button lists every shortcut. On a touch screen, use the piano at the bottom.';

  @override
  String get trackerTutStep =>
      '\'Step\' is how many rows the cursor jumps down after each note — set it to your beat (e.g. 4) to enter notes quickly, or 0 to stay on one row.';

  @override
  String get trackerTutTransport =>
      'The transport row plays and pauses, stops, and steps back/forward. \'Length\' sets how many rows a pattern has (no more 2–3 bars!), and \'Tempo\' sets the speed.';

  @override
  String get trackerTutArrange =>
      'Build several patterns, then chain them into a song: add each one to the order list and press \'Play song\'.';

  @override
  String get trackerTutTracks =>
      'Add as many tracks as you like, give each its own instrument, and mute (M) or solo (S) them while you work. You can even import a real .mod/.xm/.s3m/.it module and edit it.';

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
  String get importMusicFile =>
      'Import a file (MusicXML/MXL/ABC/MEI/kern/MIDI)…';

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
  String get gameSpotParallels => 'Spot the Parallels';

  @override
  String get gameSpotParallelsSubtitle =>
      'Clean voice-leading, or forbidden parallels?';

  @override
  String get spotParallelsPrompt =>
      'Between these two chords — is the voice-leading clean, or does it slip into parallels?';

  @override
  String get spotParallelsListen => 'Listen';

  @override
  String get spotParallelsClean => 'Clean';

  @override
  String get spotParallelsParallel => 'Parallels!';

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
  String get gameModulation => 'Key Change?';

  @override
  String get gameModulationSubtitle => 'Does the tune move to a new key?';

  @override
  String get modulationPrompt => 'Does it stay in one key, or change key?';

  @override
  String get modulationSame => 'Same key';

  @override
  String get modulationChanged => 'Key changed';

  @override
  String get primerModulationTitle => 'Same key, or a new one?';

  @override
  String get primerModulationStay =>
      'A tune has a home note. Here it climbs and comes back to the same home both times — it stays in one key.';

  @override
  String get primerModulationMove =>
      'This time the second half is lifted higher, landing on a new home note. The music has changed key — that is modulation.';

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
  String get gameMajorMinorSort => 'Major or Minor?';

  @override
  String get gameMajorMinorSortSubtitle =>
      'Read each triad and sort it by quality';

  @override
  String get majorMinorSortPrompt => 'Drag each chord into its basket';

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
  String get gameTempoOrder => 'Slow to Fast';

  @override
  String get gameTempoOrderSubtitle =>
      'Put the tempo words in order from slowest to fastest';

  @override
  String get tempoOrderPrompt => 'Tap the tempo words from slowest to fastest!';

  @override
  String get tempoOrderHint => 'Largo is the slowest, Presto is the fastest.';

  @override
  String get gameDynamicsOrder => 'Soft to Loud';

  @override
  String get gameDynamicsOrderSubtitle =>
      'Put the dynamic marks in order from softest to loudest';

  @override
  String get dynamicsOrderPrompt => 'Tap the dynamics from softest to loudest!';

  @override
  String get dynamicsOrderHint => 'pp is the softest, ff is the loudest.';

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
  String get gameTransposeWrite => 'Write It for the Instrument';

  @override
  String get gameTransposeWriteSubtitle =>
      'Name the note the instrument must read';

  @override
  String transposeWritePrompt(String instrument) {
    return 'What note does a $instrument read to sound this?';
  }

  @override
  String get transposeWriteHint =>
      'A transposing instrument reads a different note than sounds.';

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
  String get gameSpacingRead => 'Close or Open?';

  @override
  String get gameSpacingReadSubtitle =>
      'Read the SATB spacing — bunched or spread out?';

  @override
  String get spacingReadPrompt => 'Are the upper voices close or open?';

  @override
  String get spacingClose => 'Close';

  @override
  String get spacingOpen => 'Open';

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
  String get clefTenor => 'Tenor clef';

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
  String get gameConnectDegrees => 'Connect the Scale Degrees';

  @override
  String get gameConnectDegreesSubtitle =>
      'Match each degree number to its name (1 = Tonic, 5 = Dominant)';

  @override
  String get connectDegreesPrompt =>
      'Match each scale-degree number to its name — tap to hear it!';

  @override
  String get degreeTonic => 'Tonic';

  @override
  String get degreeSupertonic => 'Supertonic';

  @override
  String get degreeMediant => 'Mediant';

  @override
  String get degreeSubdominant => 'Subdominant';

  @override
  String get degreeDominant => 'Dominant';

  @override
  String get degreeSubmediant => 'Submediant';

  @override
  String get degreeLeadingTone => 'Leading tone';

  @override
  String get gameConnectTime => 'Connect the Time Signatures';

  @override
  String get gameConnectTimeSubtitle =>
      'Match each time signature to what its numbers mean';

  @override
  String get connectTimePrompt =>
      'What do the numbers mean? Connect each time signature to its beats!';

  @override
  String get timeSigMeaning44 => 'Four quarter beats';

  @override
  String get timeSigMeaning34 => 'Three quarter beats';

  @override
  String get timeSigMeaning24 => 'Two quarter beats';

  @override
  String get timeSigMeaning68 => 'Six eighth beats';

  @override
  String get timeSigMeaning22 => 'Two half beats';

  @override
  String get timeSigMeaning98 => 'Nine eighth beats';

  @override
  String get timeSigMeaning128 => 'Twelve eighth beats';

  @override
  String get timeSigMeaning54 => 'Five quarter beats';

  @override
  String get gameConnectKeysig => 'Connect the Key Signatures';

  @override
  String get gameConnectKeysigSubtitle =>
      'Match each key signature to how many sharps or flats it has';

  @override
  String get connectKeysigPrompt =>
      'How many sharps or flats? Connect each key signature to its count!';

  @override
  String get keySigNone => 'No sharps or flats';

  @override
  String keySigSharps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sharps',
      one: '1 sharp',
    );
    return '$_temp0';
  }

  @override
  String keySigFlats(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count flats',
      one: '1 flat',
    );
    return '$_temp0';
  }

  @override
  String get gameConnectRoadmap => 'Connect the Road Signs';

  @override
  String get gameConnectRoadmapSubtitle =>
      'Match each navigation sign to what it tells you to do';

  @override
  String get connectRoadmapPrompt =>
      'Read the map! Connect each road sign to what it means.';

  @override
  String get roadmapDaCapo => 'Go back to the beginning';

  @override
  String get roadmapDalSegno => 'Go back to the Segno sign';

  @override
  String get roadmapFine => 'The end — stop here';

  @override
  String get roadmapCoda => 'Jump to the ending section';

  @override
  String get roadmapSegno => 'The sign you jump back to';

  @override
  String get roadmapAlFine => '…keep going until Fine';

  @override
  String get roadmapAlCoda => '…then jump to the Coda';

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
  String get tutorialTryCorrect => 'That\'s right! 🎉';

  @override
  String get tutorialTryAgain => 'Not quite — try again!';

  @override
  String get tutorialTryHint => 'Here it is — tap the green one!';

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
  String get primerReadingTry => 'Now you try: what letter name is this note?';

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
  String get primerValuesTry =>
      'Now you try: how many beats does this whole note last?';

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
  String get primerMeasuresTry =>
      'Now you try: how many beats fill this 4/4 measure?';

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
  String get primerScalesTry =>
      'Now you try: how many different notes does a major scale have before it repeats?';

  @override
  String get primerIntervalsTry =>
      'Now you try: count the steps from C up to E (C-D-E). What number is it?';

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
  String get primerAccidentalsTry => 'Now you try: which sign RAISES a note?';

  @override
  String get primerSpacingTitle => 'Close and open';

  @override
  String get primerSpacingClose =>
      'In CLOSE position the top three voices are bunched together — the highest and the tenor sit within one octave.';

  @override
  String get primerSpacingOpen =>
      'In OPEN position the top voices are spread out — the highest note is more than an octave above the tenor.';

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
  String get primerIntervalsSong =>
      'You already know intervals from songs! A cuckoos call — “Kuck-uck” — is a falling minor 3rd. “Alle meine Entchen” starts with a major 2nd going up.';

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
  String get primerTimeSigTry =>
      'Now you try: how many beats are in a 3/4 measure?';

  @override
  String get primerChartTitle => 'Chord symbols';

  @override
  String get primerChartMajor =>
      'Above a tune you\'ll see chord symbols. A plain letter means a major chord: ‘C’ tells you to play a C major chord.';

  @override
  String get primerChartMinor =>
      'A small ‘m’ after the letter means minor: ‘Am’ is A minor — the same family, but a softer, sadder colour.';

  @override
  String get primerUpbeatTitle => 'Starting on the upbeat';

  @override
  String get primerUpbeatDownbeat =>
      'Most tunes start on beat 1 — the strong downbeat. Count ‘1-2-3-4’ and begin on the 1.';

  @override
  String get primerUpbeatUpbeat =>
      'An upbeat (or pickup) starts with a note or two BEFORE the first barline, leading into beat 1. Listen — the tune leans in.';

  @override
  String get primerEnharmonicTitle => 'The same note, two names';

  @override
  String get primerEnharmonicSame =>
      'This piano key can be written as F♯ or G♭ — the very same sound, spelled two ways. They are ‘enharmonic’ twins.';

  @override
  String get primerEnharmonicTwins =>
      'So F♯ and G♭ sound identical. Other twins: C♯=D♭, D♯=E♭, G♯=A♭, A♯=B♭.';

  @override
  String get primerExpressionTitle => 'Fast or slow, loud or soft';

  @override
  String get primerExpressionTempo =>
      'Expression is HOW you play. One part is the speed (tempo): listen to this phrase slow, then fast.';

  @override
  String get primerExpressionDynamics =>
      'The other part is how loud (dynamics): the same phrase soft (p), then loud (f). Charades asks you to name what you heard.';

  @override
  String get primerRoadmapTitle => 'Musical road signs';

  @override
  String get primerRoadmapDaCapo =>
      'Some signs tell you where to go. Da Capo (D.C.) means \"from the top\" — jump back to the very beginning and play again.';

  @override
  String get primerRoadmapCoda =>
      'Fine marks the end. Dal Segno (D.S.) jumps back to the sign, and a Coda is a special ending section you leap to. Match each sign to what it does!';

  @override
  String get primerTempoTitle => 'How fast? Tempo words';

  @override
  String get primerTempoSlow =>
      'At the top of a piece an Italian word gives the speed. Largo is very slow, Adagio is slow. Listen — these four notes are Adagio.';

  @override
  String get primerTempoFast =>
      'Allegro is fast, Presto very fast. The same four notes, just quicker — listen to the difference.';

  @override
  String get primerDynamicsTitle => 'How loud? p and f';

  @override
  String get primerDynamicsSoft =>
      'Dynamics tell you how loud to play. p (piano) means soft — and pp (pianissimo) is very soft. Listen: this is piano.';

  @override
  String get primerDynamicsLoud =>
      'f (forte) means loud, and ff (fortissimo) very loud. The same notes again — now forte.';

  @override
  String get primerDottedTitle => 'The dot that adds half';

  @override
  String get primerDottedPlain =>
      'A half note lasts 2 beats. Count ‘1-2’ while it rings.';

  @override
  String get primerDottedDotted =>
      'A dot after a note adds HALF its value again: 2 beats + 1 = a dotted half note of 3 beats. Count ‘1-2-3’.';

  @override
  String get primerRestsTitle => 'Silence has length';

  @override
  String get primerRestsSilence =>
      'A rest is silence — and you count it, just like a note. Here it goes play, rest, play, rest — one beat each.';

  @override
  String get primerRestsMatch =>
      'Every note value has a matching rest. A half note rings for 2 beats; a half rest is 2 beats of silence.';

  @override
  String get primerCurveTitle => 'Ties and slurs';

  @override
  String get primerCurveTie =>
      'A TIE joins two notes of the SAME pitch. Don\'t play the second one — hold the first right through both. C tied to C is one long C.';

  @override
  String get primerCurveSlur =>
      'A SLUR curves over DIFFERENT pitches. Play them smoothly, joined with no gap between them — that\'s legato.';

  @override
  String get primerArticulationTitle => 'How to play the note';

  @override
  String get primerArticulationStaccato =>
      'A dot above or below the notehead is staccato: play it short and detached, with air after it. (Careful — a dot BESIDE the note makes it longer instead!)';

  @override
  String get primerArticulationAccent =>
      'A wedge > is an accent: give that note an extra push so it stands out from its neighbours.';

  @override
  String get primerBeamTitle => 'Flags and beams';

  @override
  String get primerBeamFlag =>
      'A lone eighth note wears a flag on its stem. Here a rest splits the eighths apart, so each one keeps its own flag.';

  @override
  String get primerBeamBeam =>
      'When eighths share a beat they are joined by a BEAM instead of flags — the same sound, just tidier to read.';

  @override
  String get primerToneTitle => 'Half steps and whole steps';

  @override
  String get primerToneHalf =>
      'A half step (semitone) is the smallest step on the keyboard — neighbours with nothing between. E to F is a half step: no black key between them.';

  @override
  String get primerToneWhole =>
      'A whole step is two half steps. C to D is a whole step — there IS a black key between them.';

  @override
  String get primerClefTitle => 'Which clef?';

  @override
  String get primerClefTreble =>
      'The treble clef (G-clef) curls around the line that means G. It is used for higher notes — right hand, flute, violin.';

  @override
  String get primerClefBass =>
      'The bass clef (F-clef) puts two dots around the line that means F. It is used for lower notes — left hand, cello, bass.';

  @override
  String get primerVoicesTitle => 'Four voices at once';

  @override
  String get primerVoicesChord =>
      'A choir sings four lines together: Soprano (highest), Alto, Tenor, Bass (lowest). Sounded at the same time they make a chord.';

  @override
  String get primerVoicesFollow =>
      'To read one voice, follow only its line: the soprano is the top note, the bass the bottom. Listen — top voice, then bottom.';

  @override
  String get primerDirectionTitle => 'Up or down?';

  @override
  String get primerDirectionUp =>
      'When a melody climbs, every note is higher than the one before — on the staff the notes walk upward, and the sound rises.';

  @override
  String get primerDirectionDown =>
      'When it falls, every note is lower than the one before — the notes walk down the staff, and the sound sinks.';

  @override
  String get primerSameDiffTitle => 'Same or different?';

  @override
  String get primerSameDiffSame =>
      'Two notes at the SAME pitch sound exactly alike — like an echo. On the staff they sit in the very same place.';

  @override
  String get primerSameDiffDifferent =>
      'If the second note is even one step higher or lower, it is different — and it sits somewhere else on the staff. Listen: C then D.';

  @override
  String get primerCountTitle => 'How many notes?';

  @override
  String get primerCountThree =>
      'Listen and count how many separate notes go by. Here there are three — count one for each new sound.';

  @override
  String get primerCountFour =>
      'Now four. They come quickly, so count each one the moment it arrives.';

  @override
  String get primerAccentTitle => 'Strong and weak beats';

  @override
  String get primerAccentCount =>
      'In 4/4 you count 1-2-3-4 over and over. Beat 1 is the STRONG beat — the one you tap hardest. Beats 2, 3 and 4 are lighter.';

  @override
  String get primerAccentThree =>
      'The meter decides which beat is strong. In 3/4 you count 1-2-3, and the 1 is strong again — that\'s the lilt of a waltz.';

  @override
  String get primerAccentTry =>
      'Now you try: in 4/4, which beat is the strongest?';

  @override
  String get primerSeventhTitle => 'Adding a seventh';

  @override
  String get primerSeventhTriad =>
      'A triad is three notes — take one, skip one, take the next, skip one: C, E, G. That is C major, and it sounds settled.';

  @override
  String get primerSeventhAdd =>
      'Add one MORE note the same way (skip one, take the next) and you get a seventh chord: C E G B♭. It sounds restless — as if it wants to move on.';

  @override
  String get primerRomanTitle => 'Numbering the chords';

  @override
  String get primerRomanDegree =>
      'Number the notes of the scale 1 to 7. Build a chord on each step and name it with a Roman numeral. On step 1 of C major sits C E G — chord I.';

  @override
  String get primerRomanCase =>
      'CAPITALS mean a major chord (I, IV, V); small letters mean minor (ii, iii, vi). On step 2 of C major sits D F A — chord ii, D minor.';

  @override
  String get primerCadenceTitle => 'How a phrase ends';

  @override
  String get primerCadenceFull =>
      'A cadence is how a phrase ends — like the end of a sentence. Ending on the HOME chord sounds finished, like a full stop. Listen: away, then home.';

  @override
  String get primerCadenceHalf =>
      'Ending on a different chord leaves it hanging, like a question mark — your ear expects more to come. Listen: home, then away.';

  @override
  String get primerPhraseTitle => 'Question and answer';

  @override
  String get primerPhraseQuestion =>
      'Music comes in phrases, like sentences. This one climbs away and stops in the air — it sounds like a QUESTION.';

  @override
  String get primerPhraseAnswer =>
      'The answering phrase comes back to the note the tune started from — its home note. That is why it sounds finished.';

  @override
  String get primerBowTitle => 'Which way the bow goes';

  @override
  String get primerBowDown =>
      '⊓ means DOWN-bow: pull the bow from the frog (your hand) toward the tip. It\'s the heavier direction, so it suits strong beats.';

  @override
  String get primerBowUp =>
      '∨ means UP-bow: push from the tip back toward the frog. It\'s lighter — good for upbeats and lead-ins.';

  @override
  String get primerTenorTitle => 'The tenor clef';

  @override
  String get primerTenorC =>
      'The tenor clef is a C-clef: the middle of the sign points straight at middle C. Wherever the sign sits, that line IS middle C.';

  @override
  String get primerTenorWhy =>
      'Cellos and trombones use it for their higher notes — it keeps them on the staff instead of piling up ledger lines above the bass clef.';

  @override
  String get primerGrandTitle => 'Two staves, two hands';

  @override
  String get primerGrandTop =>
      'The piano writes on a GRAND STAFF: two staves joined by a brace. The top one is treble — usually your right hand.';

  @override
  String get primerGrandBottom =>
      'The bottom one is bass — usually your left hand. Middle C sits in the gap between the two staves, on its own little ledger line.';

  @override
  String get colorScaffoldLabel => 'Colour helper for beginners';

  @override
  String get colorScaffoldSubtitle =>
      'Tint notes by their letter — turn it off once the staff is familiar';

  @override
  String get notationFontLabel => 'Notation font';

  @override
  String get notationFontSubtitle =>
      'The typeface used to draw notes and symbols.';

  @override
  String get scoreFontBravura => 'Bravura';

  @override
  String get scoreFontPetaluma => 'Petaluma (handwritten)';

  @override
  String get scoreFontLeland => 'Leland';

  @override
  String get scoreFontLeipzig => 'Leipzig';

  @override
  String get showNoteNamesLabel => 'Note names under the staff';

  @override
  String get showNoteNamesSubtitle =>
      'Print each note\'s letter as a reading aid — hidden in games where naming the note is the challenge';

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
  String get gameMidiPlayAlong => 'Play a MIDI file';

  @override
  String get gameMidiPlayAlongSubtitle =>
      'Pick a .mid and play or sing along to it';

  @override
  String get midiPlayAlongHint =>
      'Choose a MIDI file and play or sing along to its melody on a moving score.';

  @override
  String get midiPlayAlongChoose => 'Choose a MIDI file';

  @override
  String get midiPlayAlongFailed => 'Couldn\'t read that MIDI file.';

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
      'CometBeat works entirely on your device. Microphone audio (for the tuner and play-along) is analysed locally in real time — never recorded, stored, or sent anywhere. There are no accounts, no ads, and no tracking.';

  @override
  String get aboutDisclaimer => 'Disclaimer';

  @override
  String get aboutDisclaimerText =>
      'CometBeat is a learning aid, provided as is and without warranty. Curriculum levels are generic guidance, not an official syllabus.';

  @override
  String get aboutCredits => 'Credits';

  @override
  String get aboutCreditsText =>
      'Music engraving uses the Bravura font (SIL Open Font License).';

  @override
  String get aboutOpenSourceLicenses => 'Open-source licenses';

  @override
  String get gameSyncRead => 'On the Beat or Off?';

  @override
  String get gameSyncReadSubtitle => 'Straight rhythm, or syncopated?';

  @override
  String get syncReadPrompt => 'Is this rhythm on the beat, or syncopated?';

  @override
  String get syncReadStraight => 'On the beat';

  @override
  String get syncReadSyncopated => 'Syncopated';

  @override
  String get gameTripletRead => 'Even or Triplet?';

  @override
  String get gameTripletReadSubtitle =>
      'Is the beat split in two, or in three?';

  @override
  String get tripletReadPrompt => 'How is the beat split?';

  @override
  String get tripletReadEven => 'Even (2)';

  @override
  String get tripletReadTriplet => 'Triplet (3)';

  @override
  String get gameOrnamentRead => 'Which Ornament?';

  @override
  String get gameOrnamentReadSubtitle => 'Read the trill, mordent or turn';

  @override
  String get ornamentReadPrompt => 'Which ornament is on the note?';

  @override
  String get ornamentTrill => 'Trill';

  @override
  String get ornamentMordent => 'Mordent';

  @override
  String get ornamentTurn => 'Turn';

  @override
  String get primerSyncTitle => 'On the beat, or off?';

  @override
  String get primerSyncStraight =>
      'Usually the notes land right ON the beats — count 1-2-3-4 and each note lands on a number. Steady and square.';

  @override
  String get primerSyncOff =>
      'Syncopation pushes notes OFF the beat, onto the \"and\" in between. The accent lands where your ear didnt expect it — thats the kick you feel in pop and jazz.';

  @override
  String get primerTripletTitle => 'Two or three in a beat';

  @override
  String get primerTripletEven =>
      'Normally a beat splits into TWO even halves: \"1-and\". Two eighth notes.';

  @override
  String get primerTripletThree =>
      'A triplet squeezes THREE equal notes into that same beat: \"trip-o-let\". It gets a little 3 above it.';

  @override
  String get primerOrnamentTitle => 'Decorating a note';

  @override
  String get primerOrnamentTrill =>
      'Ornaments are little signs that dress up a note. A trill (tr) shakes quickly between the note and the one just above it.';

  @override
  String get primerOrnamentTurn =>
      'A turn (a sideways S) curls AROUND the note: the note above, the note, the note below, then back. A mordent is just one quick flick up and back.';

  @override
  String get gameFormRead => 'Label the Form';

  @override
  String get gameFormReadSubtitle => 'Hear the sections; name the shape (ABA…)';

  @override
  String get formReadPrompt => 'What is the form? (same colour = same tune)';

  @override
  String get formReadListen => 'Listen';

  @override
  String get primerFormTitle => 'The shape of a piece';

  @override
  String get primerFormSection =>
      'Music is built from sections. Here is a little tune — call it section A. Whenever it comes back, it is A again.';

  @override
  String get primerFormAba =>
      'A different tune is a new letter — section B. Tune, different tune, then the first tune again makes the form A-B-A. Lots of songs are shaped this way!';

  @override
  String get gameMode => 'Which Mode?';

  @override
  String get gameModeSubtitle => 'Major, minor or Dorian?';

  @override
  String get modePrompt => 'Listen! Which mode is it?';

  @override
  String get modeMajor => 'Major';

  @override
  String get modeMinor => 'Minor';

  @override
  String get modeDorian => 'Dorian';

  @override
  String get primerModeTitle => 'Three colours of scale';

  @override
  String get primerModeMajor =>
      'A major scale sounds bright and happy. Listen to it climb.';

  @override
  String get primerModeMinor =>
      'A minor scale sounds darker — its 3rd, 6th and 7th steps sit a little lower.';

  @override
  String get primerModeDorian =>
      'Dorian is like minor, but its 6th step is raised — so it sounds minor with a brighter twist. That one note is the whole secret!';

  @override
  String get textbookTitle => 'Textbook';

  @override
  String get textbookIntro =>
      'Work through music from the very start. Each topic has a short lesson (see it, hear it) and games to practise it.';

  @override
  String get textbookComingSoon => 'Lesson coming soon';

  @override
  String get textbookReadLesson => 'Read the lesson';

  @override
  String get textbookPractise => 'Practise';

  @override
  String get formAnalysisTitle => 'See the form';

  @override
  String get formAnalysisPlayWhole => 'Play the whole piece';

  @override
  String get formAnalysisHint => 'Tap a block to hear that section.';

  @override
  String get harmonyAnalysisTitle => 'See the harmony';

  @override
  String get harmonyAnalysisHint => 'Tap a chord to hear it.';

  @override
  String get funcTonic => 'Home (tonic)';

  @override
  String get funcSubdominant => 'Away (subdominant)';

  @override
  String get funcDominant => 'Tension (dominant)';

  @override
  String get funcTonicKid => 'Home';

  @override
  String get funcSubdominantKid => 'Away';

  @override
  String get funcDominantKid => 'Tension';

  @override
  String get analysisHarmonyHeading => 'Harmony';

  @override
  String get analyzeAction => 'Analyse the harmony';

  @override
  String get inspectMode => 'Inspect (tap a note)';

  @override
  String get analysisFormLabel => 'Form';

  @override
  String get analysisCircleOfFifths => 'Circle of fifths';

  @override
  String get analysisTension => 'Tension';

  @override
  String get analysisVoiceLeading => 'Voice leading';

  @override
  String get analysisVoiceLeadingClean => 'No parallel 5ths or 8ves ✓';

  @override
  String get analysisParallelFifths => 'Parallel fifths';

  @override
  String get analysisParallelOctaves => 'Parallel octaves';

  @override
  String get analysisNonChordTones => 'Non-chord tones';

  @override
  String get cadenceAuthentic => 'perfect cadence';

  @override
  String get cadenceHalf => 'half cadence';

  @override
  String get cadencePlagal => 'plagal cadence';

  @override
  String get cadenceDeceptive => 'deceptive cadence';

  @override
  String get analysisDepthKids => 'Kids';

  @override
  String get analysisDepthLearner => 'Learner';

  @override
  String get analysisDepthExpert => 'Expert';

  @override
  String get harmonyExampleAuthentic =>
      'Home → away → tension → home (I–IV–V–I)';

  @override
  String get harmonyExampleAuthenticCaption =>
      'The story behind most music: the tonic (I) is home, the subdominant (IV) steps away, the dominant (V) builds tension, and I brings you home again.';

  @override
  String get harmonyExampleTwoFive => 'ii – V – I';

  @override
  String get harmonyExampleTwoFiveCaption =>
      'The most common way to arrive home: a subdominant (ii) sets up the dominant (V), which pulls strongly into the tonic (I).';

  @override
  String get harmonyExamplePerfect => 'Perfect cadence (… V → I)';

  @override
  String get harmonyExamplePerfectCaption =>
      'Ending on the tonic after the dominant sounds finished and settled — a full stop. Listen how the last chord comes to rest.';

  @override
  String get harmonyExampleHalf => 'Half cadence (… → V)';

  @override
  String get harmonyExampleHalfCaption =>
      'Stopping on the dominant instead sounds unfinished, like a question left hanging — the music still wants to go home.';

  @override
  String get cadenceMarkPerfect => 'comes to rest';

  @override
  String get cadenceMarkHalf => 'left open';

  @override
  String get gameAnalysisView => 'See the Music';

  @override
  String get gameAnalysisViewSubtitle => 'Watch a piece\'s form and harmony';

  @override
  String get analysisHubTitle => 'See the Music';

  @override
  String get analysisHubIntro =>
      'Music has shapes you can see. Watch a piece\'s form as coloured sections, and a chord progression coloured by its job — then tap to hear each part.';

  @override
  String get analysisHubForm => 'Form';

  @override
  String get analysisHubHarmony => 'Harmony & function';

  @override
  String get analysisHubComputed => 'Read from the notes (auto-analysis)';

  @override
  String get formExampleTernary => 'Ternary form (A–B–A)';

  @override
  String get formExampleTernaryCaption =>
      'A tune, a different middle tune, then the first tune again. Two of the three parts are the same — so A and A share a colour.';

  @override
  String get formExampleRondo => 'Rondo (A–B–A–C–A)';

  @override
  String get formExampleRondoCaption =>
      'One tune keeps coming back (A), with a new tune in between each time (B, then C). Like a chorus you return to again and again.';

  @override
  String get formExampleVerseChorus => 'Verse and chorus (A–B–A–B)';

  @override
  String get formExampleVerseChorusCaption =>
      'A is the verse (the words change), B is the chorus (it repeats the same). Most pop songs swap between them.';

  @override
  String get formExampleAaba => 'Song form (A–A–B–A)';

  @override
  String get formExampleAabaCaption =>
      'The main tune twice (A, A), then a contrasting middle (B, the “bridge”), then the main tune once more. A very common shape for songs.';

  @override
  String get proseIntervals =>
      'An interval is the distance between two notes — how big the jump is. Small jumps (a 2nd, a 3rd) sound smooth and close; big jumps (a 6th, an octave) sound wide and open. You can learn each one by the start of a song you know: a falling minor 3rd is the “cuck-oo” call.';

  @override
  String get proseTriads =>
      'A triad is a three-note chord built by stacking two thirds — a root, the note two steps up, and two steps up again. Major triads sound bright and cheerful; minor triads sound softer and sadder. Almost all the chords you meet start life as a triad.';

  @override
  String get proseKeySignatures =>
      'The sharps or flats at the very start of a line are the key signature: they tell you which notes stay raised or lowered for the whole piece, so you don’t have to write an accidental every time. Count them to name the key.';

  @override
  String get proseEnharmonics =>
      'One sound can have two names. F♯ and G♭ are the exact same key on a piano, just spelled differently depending on the key you’re in. Notes like these are called enharmonic — same pitch, two spellings (in German: Fis and Ges).';

  @override
  String get proseCircleOfFifths =>
      'Jump up a fifth each time — C, G, D, A… — and you travel around a circle that passes through every key and comes back home. Each step adds one sharp (going one way) or one flat (going the other), which is why it’s the mapmaker of key signatures.';

  @override
  String get proseMinorScales =>
      'Minor scales sound darker than major. Natural minor uses the plain notes of its key; harmonic minor raises the 7th step so the scale leans strongly back to its home note. That one raised note gives harmonic minor its exotic, pulling sound.';

  @override
  String get proseSeventhChords =>
      'Add one more third on top of a triad and you get a seventh chord — four notes instead of three. The extra note sounds restless and wants to move on, which is why a dominant seventh (V7) pulls so strongly back to the home chord.';

  @override
  String get proseCadences =>
      'A cadence is how a musical phrase ends — its punctuation. A perfect cadence (V→I) sounds like a full stop, finished and settled. A half cadence stops on the dominant and sounds like a question, still hanging, waiting for more.';

  @override
  String get proseHarmonicFunction =>
      'Chords have jobs. The tonic (I) is home — settled and at rest. The dominant (V) is tension that wants to pull back home. The subdominant (IV) is the step that moves away from home before the dominant pulls you back. Home → away → tension → home is the story behind most music.';

  @override
  String get proseRomanNumerals =>
      'Roman numerals name a chord by its step in the scale, not its letter — so the same numbers work in every key. CAPITALS mean a major chord (I, IV, V), small letters mean minor (ii, iii, vi). Now “V–I” describes an ending in any key at once.';

  @override
  String get proseModulation =>
      'Modulation is when a piece changes key partway through — it lifts to a new home note and stays there for a while. It often brightens or freshens the music, like opening a window into a new room, before it may find its way back.';

  @override
  String get proseModes =>
      'Modes are scales that start on different steps, each with its own flavour. Major (Ionian) is bright, natural minor (Aeolian) is dark, and Dorian is minor with a raised 6th — minor, but with a hopeful twist. Change one note and the whole colour of the tune changes.';

  @override
  String get proseSyncopation =>
      'Normally the strong beats land on the count — 1, 2, 3, 4. Syncopation puts the accent off the beat instead, in the gaps between counts. That push-and-pull is what makes music feel like it swings or dances instead of marching.';

  @override
  String get proseTriplets =>
      'A triplet squeezes three even notes into the space where you’d normally play two. Instead of “ta-ta”, you count “ta-ta-ta” in the same time. It’s a triple feel dropped into a duple beat — a gentle lilt.';

  @override
  String get proseSongForm =>
      'Songs are built from sections that repeat and contrast. A verse tells the story with changing words; a chorus comes back the same each time as the memorable hook. Labelling the parts with letters (A, B…) shows the shape at a glance.';

  @override
  String get proseMusicalForm =>
      'Form is the overall plan of a piece — how its sections are arranged. When a tune returns it keeps its letter; a new tune gets a new one. A–B–A (ternary) and A–B–A–C–A (rondo) are two of the oldest, clearest shapes. Seeing the letters makes a long piece easy to follow.';

  @override
  String get proseTransposingInstruments =>
      'Some instruments sound a different note from the one they read. A B♭ clarinet playing a written C sounds a B♭. So the same tune is written differently for different instruments, so that it sounds at the right pitch — that’s transposition.';

  @override
  String get prosePulse =>
      'Every piece has a heartbeat — a steady pulse you can clap or march to. It doesn’t speed up or slow down; it’s the ticking clock the rest of the music dances on top of.';

  @override
  String get proseHighLow =>
      'Some sounds are high and bright like a bird; others are low and deep like a big drum. Hearing which is higher is the very first step to reading notes — high notes sit high on the staff, low ones sit low.';

  @override
  String get proseMelodyDirection =>
      'A tune can climb up, step down, or stay level — that shape is its contour. Following whether the melody rises or falls is how your ear traces a tune, long before you can name the notes.';

  @override
  String get proseSameDifferent =>
      'Two sounds can be exactly the same, or different. Noticing “that’s the same note again” or “that one changed” trains the careful listening every other music skill is built on.';

  @override
  String get proseLoudSoft =>
      'Music can whisper or shout. Loud and soft (in Italian, forte and piano) are among a composer’s strongest tools — the very same tune feels gentle when soft and exciting when loud.';

  @override
  String get proseFastSlow =>
      'How quickly the beats come is the tempo. A slow tempo feels calm or sad; a fast one feels busy or happy. Same notes, different speed, a completely different mood.';

  @override
  String get proseLongShort =>
      'Some notes are held for a long time, others flick by quickly. These note lengths (durations) are the raw material of rhythm — patterns of long and short sounds.';

  @override
  String get proseCountSounds =>
      'Listening carefully enough to count how many notes you heard — two, three, four — sharpens your musical attention. If you can count them, you can start to remember and repeat them.';

  @override
  String get proseAuralMemory =>
      'Music lives in your memory. Hearing a short pattern and echoing it back — clapping or singing — builds the aural memory a musician uses every time they learn a tune by ear.';

  @override
  String get proseLearnSongs =>
      'The best way into music is real songs you can sing. Learning and recognising familiar melodies gives every abstract idea — beat, pitch, form — a tune you already know to hang it on.';

  @override
  String get proseTrebleStaff =>
      'The treble staff is five lines and four spaces where the higher notes live. Each line and space is a letter, and once you know them you can read the melody of most songs.';

  @override
  String get proseLedgerMiddleC =>
      'When a note is too high or low for the staff, we give it its own little ledger line. Middle C sits on one just below the treble staff — the doorway between the high and low staves.';

  @override
  String get proseNoteValues =>
      'A note’s shape tells you how long to hold it: a whole note lasts longest, then half, quarter and eighth notes, each half as long as the one before. This is how rhythm gets written down.';

  @override
  String get proseRests =>
      'Silence is part of music too. A rest is a written pause — every note value has a matching rest of the same length, so the music breathes and the gaps are as exact as the notes.';

  @override
  String get proseDottedNotes =>
      'A little dot after a note makes it longer — it adds half the note’s value again. A dotted half note lasts three beats instead of two, because half of two is one, and two plus one is three.';

  @override
  String get proseBeatsPerBar =>
      'Music is packed into equal boxes called bars (or measures). The beats inside each bar add up to the same total every time, so the pulse stays organised and easy to count.';

  @override
  String get proseTimeSignature =>
      'The two numbers at the start tell you how the bars are counted: the top is how many beats per bar, the bottom which note gets one beat. 4/4 means four quarter-note beats in every bar.';

  @override
  String get proseStrongWeakBeat =>
      'Within each bar some beats feel stronger than others — beat one is the strongest. That pattern of strong and weak beats is what makes a waltz feel different from a march.';

  @override
  String get proseDynamicsMarks =>
      'Composers write how loud to play with letters: p for piano (soft), f for forte (loud), and gentler steps in between (mp, mf). These dynamic marks shape the feeling of the music.';

  @override
  String get proseTempoTerms =>
      'Speed has names, mostly Italian: Largo is very slow, Adagio slow, Andante a walking pace, Allegro quick, Presto very fast. One word at the top sets the whole mood.';

  @override
  String get proseRhythmEcho =>
      'Hear a rhythm, then clap or tap it straight back. This call-and-response is how rhythm gets into your body — you feel the pattern of long and short before you ever read it.';

  @override
  String get proseStepsSkips =>
      'From one note to the next you can step (to the very next letter) or skip (jumping over one or more). Melodies are mostly gentle steps with the occasional skip for surprise.';

  @override
  String get proseCMajorScale =>
      'The C major scale is the white keys from C to C — the plainest, brightest ladder of notes, with no sharps or flats. It’s the home base from which every other scale is measured.';

  @override
  String get proseMajorMinorEar =>
      'The same notes can feel happy or sad depending on which few are lowered. Major sounds bright and cheerful, minor darker and more serious — your ear can learn to tell them apart in an instant.';

  @override
  String get proseReadingFluency =>
      'Reading music, like reading words, gets faster with practice until you don’t have to work each note out. Fluent reading in both clefs is what lets you play a new piece almost at sight.';

  @override
  String get proseSingWhatYouHear =>
      'Singing back a note or a short tune connects your ear to your voice. If you can sing what you hear, you truly understand the pitch — it’s the heart of ear training.';

  @override
  String get prosePlayKeyboard =>
      'On a keyboard the notes march left (low) to right (high), with the black keys grouped in twos and threes to guide you. Finding and playing the right keys turns the notes on the page into sound under your fingers.';

  @override
  String get prosePlayCello =>
      'The cello is played with a bow across four strings, the left-hand fingers pressing to change the pitch. Learning its strings, finger spots and bow strokes (down-bow and up-bow) is the path to a warm, singing tone.';

  @override
  String get prosePlayGuitar =>
      'The guitar has six strings you press behind frets and strum or pluck. Reading its strings and simple tab, and strumming in time, gets you playing chords and tunes surprisingly quickly.';

  @override
  String get prosePlayPercussion =>
      'Percussion is rhythm you can hit. Reading and playing a drum pattern — knowing which sound falls on which beat — is pure rhythm, the backbone that keeps a whole band together.';

  @override
  String get proseCompose =>
      'Making up your own melody is where all the rules become play. Choosing a few notes, arranging them into a shape you like, and hearing it back is composing — the most fun way to learn how music works.';

  @override
  String get proseBassClef =>
      'The bass clef reads the lower notes — the left hand on a piano, the cello, the bass. Its lines and spaces spell different letters from the treble clef, so learning it opens up the whole low half of music.';

  @override
  String get proseGrandStaff =>
      'Join the treble and bass staves with a brace and you get the grand staff — two staves read at once, one per hand. Middle C sits in the gap between them, shared by both.';

  @override
  String get proseClefSigns =>
      'A clef is the sign at the start that fixes which lines mean which notes. The treble (G) clef curls around the G line; the bass (F) clef’s two dots hug the F line. Same staff, different clef, different notes.';

  @override
  String get proseAccidentals =>
      'A sharp (♯) raises a note by a half step, a flat (♭) lowers it, and a natural (♮) cancels either. These accidentals are how we reach the black keys and the notes between the plain letters.';

  @override
  String get proseWholeHalfStep =>
      'The smallest step on a keyboard is a half step (right to the very next key). Two of them make a whole step. Scales are just particular ladders of whole and half steps — the pattern is what makes them sound the way they do.';

  @override
  String get proseMajorScales =>
      'Every major scale follows the same recipe of whole and half steps, starting from any note. Get the pattern right and C major, G major or any other all share that same bright, familiar sound.';

  @override
  String get proseTiesSlurs =>
      'A curved line can mean two things. A tie joins two of the SAME note into one longer sound; a slur over DIFFERENT notes means play them smoothly, joined together. Same curve, opposite jobs.';

  @override
  String get proseArticulation =>
      'Articulation is how a note is played — short and detached (staccato, a dot above the note) or leaned on hard (an accent). It’s the difference between speaking each word crisply or smoothly.';

  @override
  String get proseBeams =>
      'Short notes can wear separate flags or be joined by a thick beam. Beaming groups the notes within a beat, so a bar of quick notes is far easier to read at a glance than a row of loose flags.';

  @override
  String get proseAnacrusis =>
      'Not every tune starts on beat one. An upbeat (anacrusis) is a note or two of pickup before the first full bar — think of the “Hap-” before “Happy Birthday”. The music leans in before it lands.';

  @override
  String get proseCompoundMeter =>
      'In compound metre, like 6/8, the beat splits into threes instead of twos, giving a rolling, lilting feel. You count it in two big beats of three — one-and-a, two-and-a — like a boat on gentle waves.';

  @override
  String get proseArrangeLoops =>
      'You don’t have to write every note to make music. Layering and arranging ready-made loops — a drum groove, a bass line, a chord pad — teaches how parts fit together into a full, balanced track.';

  @override
  String get proseChordQualities =>
      'Beyond major and minor, triads come in two more flavours: diminished (both thirds small, tense and unstable) and augmented (both thirds wide, strange and dreamy). The quality is set by the exact sizes of the thirds stacked inside.';

  @override
  String get proseChordSymbols =>
      'Lead sheets name chords with short symbols above the tune — C, Am, G7, Dm. Learn to read them and you can play the harmony of a whole song from a single line of chords, the way a band does.';

  @override
  String get proseMelodicDictation =>
      'Hearing a short melody and writing it down is dictation — the ultimate test of the ear. It ties together pitch, rhythm and memory: you decode the tune the way you’d spell a word you just heard.';

  @override
  String get prosePhrasingQa =>
      'Melodies often come in pairs, like a conversation. The first phrase asks a question and hangs unresolved; the second answers it and comes to rest. Hearing that question-and-answer shape is how you feel where a tune is going.';

  @override
  String get proseInversions =>
      'A chord’s notes can be stacked in different orders. When a note other than the root sits at the bottom, the chord is inverted — same chord, different flavour and a smoother path from one chord to the next.';

  @override
  String get proseTenorClef =>
      'The tenor clef is a C-clef that points at middle C partway up the staff. It’s used for the higher notes of instruments like the cello and bassoon, so they don’t need a forest of ledger lines above the bass staff.';

  @override
  String get proseSatbVoices =>
      'Choral music is written in four voices — Soprano, Alto, Tenor and Bass, from highest to lowest. Reading all four at once, each with its own line, is how you follow a hymn or a chorale.';

  @override
  String get proseScoreReading =>
      'A full score stacks every instrument’s part on the page at once. Following it — keeping your place across several staves as the music moves — is the skill a conductor uses to hear the whole ensemble from paper.';

  @override
  String get proseOrnaments =>
      'Ornaments are little decorations added to a note — a trill (rapidly alternating with the note above), a mordent (a quick flick) or a turn (a curl around the note). They add sparkle without changing the tune underneath.';

  @override
  String get proseInstrumentFamilies =>
      'The orchestra sorts its instruments into families by how they make sound: strings (bowed or plucked), woodwind, brass, percussion and keyboards. Knowing the families helps you pick out who’s playing what when you listen.';

  @override
  String get proseVoiceLeading =>
      'Voice leading is how each note of a chord steps to the next — smoothly, with every voice moving as little as it can, so the parts sound like separate singing lines. The classic rule is to avoid parallel fifths and octaves: when two voices leap the same distance in the same direction, they stop sounding independent and blur into one. Spotting and smoothing those moves is what makes four parts feel alive.';

  @override
  String get gameInstrumentFamily => 'Which Family?';

  @override
  String get gameInstrumentFamilySubtitle =>
      'Sort an instrument into its family: strings, woodwind, brass, percussion or keyboard.';

  @override
  String get instrumentFamilyPrompt => 'Which family does it belong to?';

  @override
  String get familyStrings => 'Strings';

  @override
  String get familyWoodwind => 'Woodwind';

  @override
  String get familyBrass => 'Brass';

  @override
  String get familyPercussion => 'Percussion';

  @override
  String get familyKeyboard => 'Keyboard';

  @override
  String get instrViolin => 'Violin';

  @override
  String get instrCello => 'Cello';

  @override
  String get instrGuitar => 'Guitar';

  @override
  String get instrHarp => 'Harp';

  @override
  String get instrFlute => 'Flute';

  @override
  String get instrClarinet => 'Clarinet';

  @override
  String get instrOboe => 'Oboe';

  @override
  String get instrSaxophone => 'Saxophone';

  @override
  String get instrRecorder => 'Recorder';

  @override
  String get instrTrumpet => 'Trumpet';

  @override
  String get instrTrombone => 'Trombone';

  @override
  String get instrHorn => 'French horn';

  @override
  String get instrTuba => 'Tuba';

  @override
  String get instrDrums => 'Drums';

  @override
  String get instrXylophone => 'Xylophone';

  @override
  String get instrTimpani => 'Timpani';

  @override
  String get instrTriangle => 'Triangle';

  @override
  String get instrPiano => 'Piano';

  @override
  String get instrOrgan => 'Organ';

  @override
  String get primerFamilyTitle => 'Instrument families';

  @override
  String get primerFamilyStrings =>
      'Strings sing when you bow or pluck them: the violin, cello, guitar and harp.';

  @override
  String get primerFamilyWinds =>
      'Winds need your breath. Woodwinds like the flute, clarinet and saxophone; brass like the trumpet, trombone and tuba.';

  @override
  String get primerFamilyPercKeys =>
      'Percussion is struck — drums, xylophone and triangle. Keyboards like the piano and organ play many notes at once.';

  @override
  String get conceptPulse => 'A steady beat (pulse)';

  @override
  String get conceptHighLow => 'Higher and lower sounds';

  @override
  String get conceptMelodyDirection => 'A tune that climbs or falls';

  @override
  String get conceptSameDifferent => 'Same sound or different';

  @override
  String get conceptLoudSoft => 'Loud and soft';

  @override
  String get conceptFastSlow => 'Fast and slow';

  @override
  String get conceptLongShort => 'Long and short notes';

  @override
  String get conceptCountSounds => 'Counting the notes you hear';

  @override
  String get conceptTrebleStaff => 'Notes on the treble staff';

  @override
  String get conceptLedgerMiddleC => 'Ledger lines and middle C';

  @override
  String get conceptNoteValues => 'Whole, half, quarter, eighth notes';

  @override
  String get conceptRests => 'Rests are silence';

  @override
  String get conceptDottedNotes => 'The dot adds half again';

  @override
  String get conceptBeatsPerBar => 'Beats add up to fill a bar';

  @override
  String get conceptTimeSignature => 'Reading the time signature';

  @override
  String get conceptStrongWeakBeat => 'Strong and weak beats';

  @override
  String get conceptDynamicsMarks => 'p and f (piano/forte)';

  @override
  String get conceptTempoTerms => 'Italian tempo words';

  @override
  String get conceptRhythmEcho => 'Echo a rhythm you heard';

  @override
  String get conceptStepsSkips => 'Steps and skips';

  @override
  String get conceptCMajorScale => 'The C major scale';

  @override
  String get conceptMajorMinorEar => 'Major sounds bright, minor darker';

  @override
  String get conceptSongForm => 'Verse and chorus; repeats';

  @override
  String get conceptBassClef => 'Notes on the bass staff';

  @override
  String get conceptGrandStaff => 'Two staves, two hands';

  @override
  String get conceptClefSigns => 'Treble vs bass clef';

  @override
  String get conceptAccidentals => 'Sharps and flats';

  @override
  String get conceptEnharmonics => 'One key, two names (F♯ = G♭)';

  @override
  String get conceptWholeHalfStep => 'Whole steps and half steps';

  @override
  String get conceptKeySignatures => 'Key signatures';

  @override
  String get conceptMajorScales => 'Building major scales';

  @override
  String get conceptIntervals => 'Intervals: distance between notes';

  @override
  String get conceptTriads => 'Major and minor triads';

  @override
  String get conceptTiesSlurs => 'Ties and slurs';

  @override
  String get conceptArticulation => 'Staccato and accents';

  @override
  String get conceptBeams => 'Beams and flags';

  @override
  String get conceptAnacrusis => 'The upbeat (anacrusis)';

  @override
  String get conceptCompoundMeter => 'Compound metre (6/8)';

  @override
  String get conceptSyncopation => 'Off-beat accents (syncopation)';

  @override
  String get conceptTriplets => 'Triplets and tuplets';

  @override
  String get conceptCircleOfFifths => 'The circle of fifths';

  @override
  String get conceptMinorScales => 'Natural and harmonic minor';

  @override
  String get conceptChordQualities => 'Diminished and augmented';

  @override
  String get conceptSeventhChords => 'Seventh chords';

  @override
  String get conceptChordSymbols => 'Lead-sheet chord symbols';

  @override
  String get conceptCadences => 'How phrases end';

  @override
  String get conceptHarmonicFunction => 'Tonic, subdominant, dominant';

  @override
  String get conceptRomanNumerals => 'Roman numerals';

  @override
  String get conceptMelodicDictation => 'Write down a melody you hear';

  @override
  String get conceptPhrasingQa => 'Question-and-answer phrases';

  @override
  String get conceptMusicalForm => 'Form: ABA, rondo, theme & variations';

  @override
  String get conceptModulation => 'Changing key (modulation)';

  @override
  String get conceptInversions => 'Chord inversions';

  @override
  String get conceptTransposingInstruments => 'Transposing instruments';

  @override
  String get conceptTenorClef => 'The tenor clef';

  @override
  String get conceptSatbVoices => 'Reading four-part (SATB) music';

  @override
  String get conceptScoreReading => 'Following a multi-staff score';

  @override
  String get conceptOrnaments => 'Ornaments (trill, mordent, turn)';

  @override
  String get conceptModes => 'Church modes (Dorian, etc.)';

  @override
  String get conceptInstrumentFamilies => 'Instrument families / the orchestra';

  @override
  String get conceptReadingFluency => 'Reading notes fluently (both clefs)';

  @override
  String get conceptAuralMemory => 'Echo and remember what you hear';

  @override
  String get conceptSingWhatYouHear => 'Sing back a pitch or interval';

  @override
  String get conceptPlayKeyboard => 'Find and play notes on the keyboard';

  @override
  String get conceptPlayCello => 'Play the cello: strings, fingers, bowing';

  @override
  String get conceptPlayGuitar => 'Play the guitar: strings, tab, strumming';

  @override
  String get conceptPlayPercussion => 'Read and play a drum rhythm';

  @override
  String get conceptCompose => 'Make up your own melody';

  @override
  String get conceptArrangeLoops => 'Layer and arrange loops';

  @override
  String get conceptLearnSongs => 'Learn and recognise real songs';

  @override
  String get areaPulse => 'Pulse';

  @override
  String get areaReading => 'Reading';

  @override
  String get areaDuration => 'Note values';

  @override
  String get areaMeter => 'Metre';

  @override
  String get areaDynamics => 'Dynamics';

  @override
  String get areaTempo => 'Tempo';

  @override
  String get areaPitch => 'Pitch';

  @override
  String get areaScales => 'Scales';

  @override
  String get areaIntervals => 'Intervals';

  @override
  String get areaChords => 'Chords';

  @override
  String get areaHarmony => 'Harmony';

  @override
  String get areaArticulation => 'Articulation';

  @override
  String get areaTranspose => 'Transposition';

  @override
  String get areaForm => 'Form';

  @override
  String get areaTimbre => 'Timbre';

  @override
  String get areaTechnique => 'Playing';

  @override
  String get areaAural => 'Ear training';

  @override
  String get areaCreating => 'Creating';

  @override
  String get areaRepertoire => 'Repertoire';

  @override
  String get textbookBandG12 =>
      'Music starts with your body: feel the steady beat, notice high and low, loud and soft, fast and slow. You don’t read notes yet — you listen and move.';

  @override
  String get textbookBandG34 =>
      'Now notes get names and places on the staff. You learn how long each one lasts, how they fill a bar, and how to read a simple tune in C major.';

  @override
  String get textbookBandG56 =>
      'Both hands, both clefs. Sharps and flats give notes new colours; you measure the distance between notes (intervals) and stack them into your first chords.';

  @override
  String get textbookBandG78 =>
      'Music gets richer: minor keys, the circle of fifths, chords with a special 7th, and how phrases come to rest (cadences). You start to hear WHY chords move.';

  @override
  String get textbookBandG910 =>
      'The advanced toolkit: chord inversions, transposing instruments, reading a full score, and the shapes and colours (form, modes) composers use to build whole pieces.';

  @override
  String get textbookGradesG12 => 'Grades 1–2';

  @override
  String get textbookGradesG34 => 'Grades 3–4';

  @override
  String get textbookGradesG56 => 'Grades 5–6';

  @override
  String get textbookGradesG78 => 'Grades 7–8';

  @override
  String get textbookGradesG910 => 'Grades 9–10';

  @override
  String get tutorialReadAloud => 'Read aloud';

  @override
  String get ttsHdVoiceTitle => 'Natural voice (HD)';

  @override
  String get ttsHdVoiceSubtitle =>
      'A warmer, more natural reading voice for the lessons';

  @override
  String get ttsHdVoiceReady => 'On — narration uses the natural voice';

  @override
  String get ttsHdVoiceDownload => 'Download (~135 MB)';

  @override
  String get ttsHdVoiceDownloading => 'Downloading…';

  @override
  String get ttsHdVoiceFailed => 'Download failed — tap to retry';
}
