import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'KlangUniversum'**
  String get appTitle;

  /// No description provided for @homeTagline.
  ///
  /// In en, this message translates to:
  /// **'Discover the universe of music!'**
  String get homeTagline;

  /// No description provided for @moduleNoteValues.
  ///
  /// In en, this message translates to:
  /// **'Note Values'**
  String get moduleNoteValues;

  /// No description provided for @moduleNoteValuesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Whole, half, quarter — how long does a note last?'**
  String get moduleNoteValuesSubtitle;

  /// No description provided for @moduleNoteReading.
  ///
  /// In en, this message translates to:
  /// **'Reading Notes'**
  String get moduleNoteReading;

  /// No description provided for @moduleNoteReadingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Treble and bass clef — which note is that?'**
  String get moduleNoteReadingSubtitle;

  /// No description provided for @moduleMeasures.
  ///
  /// In en, this message translates to:
  /// **'Measures & Meter'**
  String get moduleMeasures;

  /// No description provided for @moduleMeasuresSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Fill the measure so everything adds up'**
  String get moduleMeasuresSubtitle;

  /// No description provided for @moduleScales.
  ///
  /// In en, this message translates to:
  /// **'Scales'**
  String get moduleScales;

  /// No description provided for @moduleScalesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Major and minor, step by step'**
  String get moduleScalesSubtitle;

  /// No description provided for @moduleChords.
  ///
  /// In en, this message translates to:
  /// **'Chords & Intervals'**
  String get moduleChords;

  /// No description provided for @moduleChordsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Build triads and train your ears'**
  String get moduleChordsSubtitle;

  /// No description provided for @moduleHarmony.
  ///
  /// In en, this message translates to:
  /// **'Harmony'**
  String get moduleHarmony;

  /// No description provided for @moduleHarmonySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tonic, subdominant, dominant'**
  String get moduleHarmonySubtitle;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon!'**
  String get comingSoon;

  /// No description provided for @locked.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get locked;

  /// No description provided for @advancedGameHint.
  ///
  /// In en, this message translates to:
  /// **'Advanced! Earn 2 stars in the other Cello Corner games first.'**
  String get advancedGameHint;

  /// No description provided for @unlockHint.
  ///
  /// In en, this message translates to:
  /// **'Play {module} first to unlock this!'**
  String unlockHint(String module);

  /// No description provided for @reviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get reviewTitle;

  /// No description provided for @dueForReview.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Nothing to review} =1{1 item to review} other{{count} items to review}}'**
  String dueForReview(int count);

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @progressTitle.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get progressTitle;

  /// No description provided for @karteikastenTitle.
  ///
  /// In en, this message translates to:
  /// **'Flashcard boxes'**
  String get karteikastenTitle;

  /// No description provided for @trickyNotesTitle.
  ///
  /// In en, this message translates to:
  /// **'Your tricky spots'**
  String get trickyNotesTitle;

  /// No description provided for @trickyNotesHint.
  ///
  /// In en, this message translates to:
  /// **'The skills you miss most — reading, rhythm, chords and more. Review practises these first.'**
  String get trickyNotesHint;

  /// No description provided for @trickyMissed.
  ///
  /// In en, this message translates to:
  /// **'missed {count}×'**
  String trickyMissed(int count);

  /// No description provided for @moduleProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Modules'**
  String get moduleProgressTitle;

  /// No description provided for @boxNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get boxNew;

  /// No description provided for @boxMastered.
  ///
  /// In en, this message translates to:
  /// **'Mastered'**
  String get boxMastered;

  /// No description provided for @masteredOfTracked.
  ///
  /// In en, this message translates to:
  /// **'{mastered} of {tracked} mastered'**
  String masteredOfTracked(int mastered, int tracked);

  /// No description provided for @languageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageLabel;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get systemDefault;

  /// No description provided for @workshopTitle.
  ///
  /// In en, this message translates to:
  /// **'Workshop'**
  String get workshopTitle;

  /// No description provided for @workshopComposeTitle.
  ///
  /// In en, this message translates to:
  /// **'Composition Workshop'**
  String get workshopComposeTitle;

  /// No description provided for @workshopTimeSignature.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get workshopTimeSignature;

  /// No description provided for @workshopHint.
  ///
  /// In en, this message translates to:
  /// **'Pick a note value, then tap the staff to write your tune.'**
  String get workshopHint;

  /// No description provided for @workshopEditHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the staff to move this note, or Delete it.'**
  String get workshopEditHint;

  /// No description provided for @workshopDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get workshopDelete;

  /// No description provided for @workshopRest.
  ///
  /// In en, this message translates to:
  /// **'Rest'**
  String get workshopRest;

  /// No description provided for @workshopRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get workshopRedo;

  /// No description provided for @workshopDot.
  ///
  /// In en, this message translates to:
  /// **'Dotted'**
  String get workshopDot;

  /// No description provided for @workshopAccidental.
  ///
  /// In en, this message translates to:
  /// **'Accidental'**
  String get workshopAccidental;

  /// No description provided for @workshopKey.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get workshopKey;

  /// No description provided for @workshopSelectPrev.
  ///
  /// In en, this message translates to:
  /// **'Select previous'**
  String get workshopSelectPrev;

  /// No description provided for @workshopSelectNext.
  ///
  /// In en, this message translates to:
  /// **'Select next'**
  String get workshopSelectNext;

  /// No description provided for @workshopUp.
  ///
  /// In en, this message translates to:
  /// **'Up a semitone'**
  String get workshopUp;

  /// No description provided for @workshopDown.
  ///
  /// In en, this message translates to:
  /// **'Down a semitone'**
  String get workshopDown;

  /// No description provided for @workshopReady.
  ///
  /// In en, this message translates to:
  /// **'Pick a value, then tap a note'**
  String get workshopReady;

  /// No description provided for @workshopTapStaff.
  ///
  /// In en, this message translates to:
  /// **'Tap the staff to place a note'**
  String get workshopTapStaff;

  /// No description provided for @workshopScoreSettings.
  ///
  /// In en, this message translates to:
  /// **'Score settings'**
  String get workshopScoreSettings;

  /// No description provided for @workshopClef.
  ///
  /// In en, this message translates to:
  /// **'Clef'**
  String get workshopClef;

  /// No description provided for @workshopZoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get workshopZoomIn;

  /// No description provided for @workshopZoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get workshopZoomOut;

  /// No description provided for @workshopExportXml.
  ///
  /// In en, this message translates to:
  /// **'Export MusicXML'**
  String get workshopExportXml;

  /// No description provided for @instrumentLabel.
  ///
  /// In en, this message translates to:
  /// **'Instrument sound'**
  String get instrumentLabel;

  /// No description provided for @instrumentPiano.
  ///
  /// In en, this message translates to:
  /// **'Piano'**
  String get instrumentPiano;

  /// No description provided for @instrumentCello.
  ///
  /// In en, this message translates to:
  /// **'Cello'**
  String get instrumentCello;

  /// No description provided for @instrumentFlute.
  ///
  /// In en, this message translates to:
  /// **'Flute'**
  String get instrumentFlute;

  /// No description provided for @instrumentMusicBox.
  ///
  /// In en, this message translates to:
  /// **'Music box'**
  String get instrumentMusicBox;

  /// No description provided for @noteNamingLabel.
  ///
  /// In en, this message translates to:
  /// **'Note names'**
  String get noteNamingLabel;

  /// No description provided for @noteNamingAuto.
  ///
  /// In en, this message translates to:
  /// **'Follow language'**
  String get noteNamingAuto;

  /// No description provided for @noteNamingGerman.
  ///
  /// In en, this message translates to:
  /// **'German (C D E F G A H)'**
  String get noteNamingGerman;

  /// No description provided for @noteNamingEnglish.
  ///
  /// In en, this message translates to:
  /// **'English (C D E F G A B)'**
  String get noteNamingEnglish;

  /// No description provided for @noteNamingSolfege.
  ///
  /// In en, this message translates to:
  /// **'Solfège (Do Re Mi Fa Sol La Si)'**
  String get noteNamingSolfege;

  /// No description provided for @streakDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1-day streak} other{{count}-day streak}}'**
  String streakDays(int count);

  /// No description provided for @statsTitle.
  ///
  /// In en, this message translates to:
  /// **'Learning statistics'**
  String get statsTitle;

  /// No description provided for @statsTracked.
  ///
  /// In en, this message translates to:
  /// **'Tracked items'**
  String get statsTracked;

  /// No description provided for @statsLearning.
  ///
  /// In en, this message translates to:
  /// **'Still learning'**
  String get statsLearning;

  /// No description provided for @gameNoteValueQuiz.
  ///
  /// In en, this message translates to:
  /// **'Symbol Quiz'**
  String get gameNoteValueQuiz;

  /// No description provided for @gameNoteValueQuizSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Which note or rest is this?'**
  String get gameNoteValueQuizSubtitle;

  /// No description provided for @gameDurationDuel.
  ///
  /// In en, this message translates to:
  /// **'Duration Duel'**
  String get gameDurationDuel;

  /// No description provided for @gameDurationDuelSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap the symbol that lasts longer'**
  String get gameDurationDuelSubtitle;

  /// No description provided for @whichLastsLonger.
  ///
  /// In en, this message translates to:
  /// **'Which one lasts longer?'**
  String get whichLastsLonger;

  /// No description provided for @gameNoteReadingTreble.
  ///
  /// In en, this message translates to:
  /// **'Treble Clef'**
  String get gameNoteReadingTreble;

  /// No description provided for @gameNoteReadingBass.
  ///
  /// In en, this message translates to:
  /// **'Bass Clef'**
  String get gameNoteReadingBass;

  /// No description provided for @gameNoteReadingTenor.
  ///
  /// In en, this message translates to:
  /// **'Tenor Clef'**
  String get gameNoteReadingTenor;

  /// No description provided for @gameNoteReadingAlto.
  ///
  /// In en, this message translates to:
  /// **'Alto Clef'**
  String get gameNoteReadingAlto;

  /// No description provided for @gameNoteReadingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Name the note on the staff'**
  String get gameNoteReadingSubtitle;

  /// No description provided for @moduleGuitar.
  ///
  /// In en, this message translates to:
  /// **'Guitar Corner'**
  String get moduleGuitar;

  /// No description provided for @moduleGuitarSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read tab and learn the strings'**
  String get moduleGuitarSubtitle;

  /// No description provided for @gameGuitarStringQuiz.
  ///
  /// In en, this message translates to:
  /// **'Open Strings'**
  String get gameGuitarStringQuiz;

  /// No description provided for @gameGuitarStringQuizSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Name the open string (E A D G B E)'**
  String get gameGuitarStringQuizSubtitle;

  /// No description provided for @guitarStringPrompt.
  ///
  /// In en, this message translates to:
  /// **'Which note is this open string?'**
  String get guitarStringPrompt;

  /// No description provided for @gameGuitarTabRead.
  ///
  /// In en, this message translates to:
  /// **'Read the Tab'**
  String get gameGuitarTabRead;

  /// No description provided for @gameGuitarTabReadSubtitle.
  ///
  /// In en, this message translates to:
  /// **'What note does this fret play?'**
  String get gameGuitarTabReadSubtitle;

  /// No description provided for @guitarTabReadPrompt.
  ///
  /// In en, this message translates to:
  /// **'Which note is this?'**
  String get guitarTabReadPrompt;

  /// No description provided for @moduleCello.
  ///
  /// In en, this message translates to:
  /// **'Cello Corner'**
  String get moduleCello;

  /// No description provided for @moduleCelloSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Strings, fingers and clefs for young cellists'**
  String get moduleCelloSubtitle;

  /// No description provided for @gameCelloStringQuiz.
  ///
  /// In en, this message translates to:
  /// **'Which String?'**
  String get gameCelloStringQuiz;

  /// No description provided for @gameCelloStringQuizSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Find the right cello string'**
  String get gameCelloStringQuizSubtitle;

  /// No description provided for @celloStringPrompt.
  ///
  /// In en, this message translates to:
  /// **'Which open string is this?'**
  String get celloStringPrompt;

  /// No description provided for @gameCelloFingerQuiz.
  ///
  /// In en, this message translates to:
  /// **'Finger Quiz'**
  String get gameCelloFingerQuiz;

  /// No description provided for @gameCelloFingerQuizSubtitle.
  ///
  /// In en, this message translates to:
  /// **'First position: which finger?'**
  String get gameCelloFingerQuizSubtitle;

  /// No description provided for @moduleComposition.
  ///
  /// In en, this message translates to:
  /// **'Composing'**
  String get moduleComposition;

  /// No description provided for @moduleCompositionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Endings, phrases — and your own melodies'**
  String get moduleCompositionSubtitle;

  /// No description provided for @gameEndingDetective.
  ///
  /// In en, this message translates to:
  /// **'Ending Detective'**
  String get gameEndingDetective;

  /// No description provided for @gameEndingDetectiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Does the melody sound finished?'**
  String get gameEndingDetectiveSubtitle;

  /// No description provided for @endingDetectivePrompt.
  ///
  /// In en, this message translates to:
  /// **'Listen! Does this melody sound finished?'**
  String get endingDetectivePrompt;

  /// No description provided for @soundsFinished.
  ///
  /// In en, this message translates to:
  /// **'Finished!'**
  String get soundsFinished;

  /// No description provided for @soundsOpen.
  ///
  /// In en, this message translates to:
  /// **'Not yet...'**
  String get soundsOpen;

  /// No description provided for @gameQuestionAnswer.
  ///
  /// In en, this message translates to:
  /// **'Question & Answer'**
  String get gameQuestionAnswer;

  /// No description provided for @gameQuestionAnswerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Find the answer phrase that fits'**
  String get gameQuestionAnswerSubtitle;

  /// No description provided for @questionAnswerPrompt.
  ///
  /// In en, this message translates to:
  /// **'The melody asks a question — which answer finishes it?'**
  String get questionAnswerPrompt;

  /// No description provided for @gameMyMelody.
  ///
  /// In en, this message translates to:
  /// **'My Melody'**
  String get gameMyMelody;

  /// No description provided for @gameMyMelodySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Compose and play your own tune'**
  String get gameMyMelodySubtitle;

  /// No description provided for @myMelodyPrompt.
  ///
  /// In en, this message translates to:
  /// **'Write your melody — tap the staff or an instrument!'**
  String get myMelodyPrompt;

  /// No description provided for @inputStaff.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get inputStaff;

  /// No description provided for @inputPiano.
  ///
  /// In en, this message translates to:
  /// **'Piano'**
  String get inputPiano;

  /// No description provided for @inputGuitar.
  ///
  /// In en, this message translates to:
  /// **'Guitar'**
  String get inputGuitar;

  /// No description provided for @inputCello.
  ///
  /// In en, this message translates to:
  /// **'Cello'**
  String get inputCello;

  /// No description provided for @myMelodyFull.
  ///
  /// In en, this message translates to:
  /// **'Your melody is full — play it!'**
  String get myMelodyFull;

  /// No description provided for @myMelodyPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get myMelodyPlay;

  /// No description provided for @myMelodyUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get myMelodyUndo;

  /// No description provided for @myMelodyClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get myMelodyClear;

  /// No description provided for @myMelodySave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get myMelodySave;

  /// No description provided for @myMelodySaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Name your melody'**
  String get myMelodySaveTitle;

  /// No description provided for @myMelodyDefaultName.
  ///
  /// In en, this message translates to:
  /// **'My melody'**
  String get myMelodyDefaultName;

  /// No description provided for @myMelodySaved.
  ///
  /// In en, this message translates to:
  /// **'Saved to the Song Book!'**
  String get myMelodySaved;

  /// No description provided for @moduleSongs.
  ///
  /// In en, this message translates to:
  /// **'Song Book'**
  String get moduleSongs;

  /// No description provided for @moduleSongsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Real songs — read, listen, sing along'**
  String get moduleSongsSubtitle;

  /// No description provided for @gameSongBook.
  ///
  /// In en, this message translates to:
  /// **'Song Book'**
  String get gameSongBook;

  /// No description provided for @gameSongBookSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Full songs with lyrics and a play-along cursor'**
  String get gameSongBookSubtitle;

  /// No description provided for @songStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get songStop;

  /// No description provided for @importTitle.
  ///
  /// In en, this message translates to:
  /// **'Import songs'**
  String get importTitle;

  /// No description provided for @importTitleField.
  ///
  /// In en, this message translates to:
  /// **'Title (optional)'**
  String get importTitleField;

  /// No description provided for @importHint.
  ///
  /// In en, this message translates to:
  /// **'Paste MusicXML (from MuseScore & co.) or ChordPro (lyrics with [C] chords) here — or pick a simple MIDI file below.'**
  String get importHint;

  /// No description provided for @importAsMusicXml.
  ///
  /// In en, this message translates to:
  /// **'Import as MusicXML'**
  String get importAsMusicXml;

  /// No description provided for @importAsAbc.
  ///
  /// In en, this message translates to:
  /// **'Import as ABC'**
  String get importAsAbc;

  /// No description provided for @importAsChordPro.
  ///
  /// In en, this message translates to:
  /// **'Import as ChordPro'**
  String get importAsChordPro;

  /// No description provided for @importMidiFile.
  ///
  /// In en, this message translates to:
  /// **'Pick a MIDI file…'**
  String get importMidiFile;

  /// No description provided for @importMusicXmlFile.
  ///
  /// In en, this message translates to:
  /// **'Pick a MusicXML file…'**
  String get importMusicXmlFile;

  /// No description provided for @importDone.
  ///
  /// In en, this message translates to:
  /// **'Imported!'**
  String get importDone;

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String importFailed(String error);

  /// No description provided for @importedSongs.
  ///
  /// In en, this message translates to:
  /// **'My imported songs'**
  String get importedSongs;

  /// No description provided for @chordSheets.
  ///
  /// In en, this message translates to:
  /// **'Chord sheets'**
  String get chordSheets;

  /// No description provided for @gameTuneQuiz.
  ///
  /// In en, this message translates to:
  /// **'Name That Tune'**
  String get gameTuneQuiz;

  /// No description provided for @gameTuneQuizSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Recognize the song from its opening'**
  String get gameTuneQuizSubtitle;

  /// No description provided for @tuneQuizPrompt.
  ///
  /// In en, this message translates to:
  /// **'Listen! Which song starts like this?'**
  String get tuneQuizPrompt;

  /// No description provided for @moduleKeyboard.
  ///
  /// In en, this message translates to:
  /// **'Piano Corner'**
  String get moduleKeyboard;

  /// No description provided for @moduleKeyboardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Find your way around the piano keys'**
  String get moduleKeyboardSubtitle;

  /// No description provided for @gameKeyFind.
  ///
  /// In en, this message translates to:
  /// **'Find the Key'**
  String get gameKeyFind;

  /// No description provided for @gameKeyFindSubtitle.
  ///
  /// In en, this message translates to:
  /// **'From the staff note to the piano key'**
  String get gameKeyFindSubtitle;

  /// No description provided for @keyFindPrompt.
  ///
  /// In en, this message translates to:
  /// **'Tap the key for this note!'**
  String get keyFindPrompt;

  /// No description provided for @gameKeyName.
  ///
  /// In en, this message translates to:
  /// **'Key Quiz'**
  String get gameKeyName;

  /// No description provided for @gameKeyNameSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Which key is marked?'**
  String get gameKeyNameSubtitle;

  /// No description provided for @keyNamePrompt.
  ///
  /// In en, this message translates to:
  /// **'What is the marked key called?'**
  String get keyNamePrompt;

  /// No description provided for @gameKeyEar.
  ///
  /// In en, this message translates to:
  /// **'Echo Keys'**
  String get gameKeyEar;

  /// No description provided for @gameKeyEarSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Play back what you hear'**
  String get gameKeyEarSubtitle;

  /// No description provided for @keyEarPrompt.
  ///
  /// In en, this message translates to:
  /// **'First you hear C, then the mystery note — tap it!'**
  String get keyEarPrompt;

  /// No description provided for @gameKeyMelody.
  ///
  /// In en, this message translates to:
  /// **'Play the Melody'**
  String get gameKeyMelody;

  /// No description provided for @gameKeyMelodySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read the staff, play the keys'**
  String get gameKeyMelodySubtitle;

  /// No description provided for @keyMelodyPrompt.
  ///
  /// In en, this message translates to:
  /// **'Play these notes in order!'**
  String get keyMelodyPrompt;

  /// No description provided for @gameKeyChord.
  ///
  /// In en, this message translates to:
  /// **'Chord Grip'**
  String get gameKeyChord;

  /// No description provided for @gameKeyChordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Grab all three chord notes'**
  String get gameKeyChordSubtitle;

  /// No description provided for @gameGrandStaffRead.
  ///
  /// In en, this message translates to:
  /// **'Grand Staff'**
  String get gameGrandStaffRead;

  /// No description provided for @gameGrandStaffReadSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read notes on both clefs at once'**
  String get gameGrandStaffReadSubtitle;

  /// No description provided for @keyChordPrompt.
  ///
  /// In en, this message translates to:
  /// **'Play the {name} major chord — tap all three keys!'**
  String keyChordPrompt(String name);

  /// No description provided for @celloFingerPrompt.
  ///
  /// In en, this message translates to:
  /// **'Which finger plays it on the {string} string?'**
  String celloFingerPrompt(String string);

  /// No description provided for @whatIsThisNote.
  ///
  /// In en, this message translates to:
  /// **'What is this note called?'**
  String get whatIsThisNote;

  /// No description provided for @hintButton.
  ///
  /// In en, this message translates to:
  /// **'Need a hint?'**
  String get hintButton;

  /// No description provided for @readingHintSame.
  ///
  /// In en, this message translates to:
  /// **'It\'s {name} — a landmark note!'**
  String readingHintSame(String name);

  /// No description provided for @readingHintStepUp.
  ///
  /// In en, this message translates to:
  /// **'One step up from {name}'**
  String readingHintStepUp(String name);

  /// No description provided for @readingHintStepDown.
  ///
  /// In en, this message translates to:
  /// **'One step down from {name}'**
  String readingHintStepDown(String name);

  /// No description provided for @readingHintSkipUp.
  ///
  /// In en, this message translates to:
  /// **'A skip up from {name}'**
  String readingHintSkipUp(String name);

  /// No description provided for @readingHintSkipDown.
  ///
  /// In en, this message translates to:
  /// **'A skip down from {name}'**
  String readingHintSkipDown(String name);

  /// No description provided for @readingHintFarUp.
  ///
  /// In en, this message translates to:
  /// **'{count} steps up from {name}'**
  String readingHintFarUp(int count, String name);

  /// No description provided for @readingHintFarDown.
  ///
  /// In en, this message translates to:
  /// **'{count} steps down from {name}'**
  String readingHintFarDown(int count, String name);

  /// No description provided for @noteNameC.
  ///
  /// In en, this message translates to:
  /// **'C'**
  String get noteNameC;

  /// No description provided for @noteNameD.
  ///
  /// In en, this message translates to:
  /// **'D'**
  String get noteNameD;

  /// No description provided for @noteNameE.
  ///
  /// In en, this message translates to:
  /// **'E'**
  String get noteNameE;

  /// No description provided for @noteNameF.
  ///
  /// In en, this message translates to:
  /// **'F'**
  String get noteNameF;

  /// No description provided for @noteNameG.
  ///
  /// In en, this message translates to:
  /// **'G'**
  String get noteNameG;

  /// No description provided for @noteNameA.
  ///
  /// In en, this message translates to:
  /// **'A'**
  String get noteNameA;

  /// No description provided for @noteNameB.
  ///
  /// In en, this message translates to:
  /// **'B'**
  String get noteNameB;

  /// No description provided for @gamePlaceNoteTreble.
  ///
  /// In en, this message translates to:
  /// **'Place the Note (Treble)'**
  String get gamePlaceNoteTreble;

  /// No description provided for @gamePlaceNoteBass.
  ///
  /// In en, this message translates to:
  /// **'Place the Note (Bass)'**
  String get gamePlaceNoteBass;

  /// No description provided for @gamePlaceNoteSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap the right line or space'**
  String get gamePlaceNoteSubtitle;

  /// No description provided for @placeNotePrompt.
  ///
  /// In en, this message translates to:
  /// **'Place the note {name}!'**
  String placeNotePrompt(String name);

  /// No description provided for @gameMeasureFill.
  ///
  /// In en, this message translates to:
  /// **'Measure Filler'**
  String get gameMeasureFill;

  /// No description provided for @gameMeasureFillSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Complete the measure so it adds up'**
  String get gameMeasureFillSubtitle;

  /// No description provided for @measureFillPrompt.
  ///
  /// In en, this message translates to:
  /// **'Which note completes the measure?'**
  String get measureFillPrompt;

  /// No description provided for @gameScaleDetective.
  ///
  /// In en, this message translates to:
  /// **'Scale Detective'**
  String get gameScaleDetective;

  /// No description provided for @gameScaleDetectiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Find the note that doesn\'t belong'**
  String get gameScaleDetectiveSubtitle;

  /// No description provided for @scaleDetectivePrompt.
  ///
  /// In en, this message translates to:
  /// **'Tap the wrong note in the {name} major scale!'**
  String scaleDetectivePrompt(String name);

  /// No description provided for @scaleDetectivePromptMinor.
  ///
  /// In en, this message translates to:
  /// **'Tap the wrong note in the {name} minor scale!'**
  String scaleDetectivePromptMinor(String name);

  /// No description provided for @gameChordQuiz.
  ///
  /// In en, this message translates to:
  /// **'Chord Quiz'**
  String get gameChordQuiz;

  /// No description provided for @gameChordQuizSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Name the chord on the staff'**
  String get gameChordQuizSubtitle;

  /// No description provided for @chordQuizPrompt.
  ///
  /// In en, this message translates to:
  /// **'What chord is this?'**
  String get chordQuizPrompt;

  /// No description provided for @majorChordName.
  ///
  /// In en, this message translates to:
  /// **'{name} major'**
  String majorChordName(String name);

  /// No description provided for @gameRomanNumeral.
  ///
  /// In en, this message translates to:
  /// **'Roman Numerals'**
  String get gameRomanNumeral;

  /// No description provided for @gameRomanNumeralSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Which scale-degree chord is this? (I, IV, V …)'**
  String get gameRomanNumeralSubtitle;

  /// No description provided for @romanNumeralPrompt.
  ///
  /// In en, this message translates to:
  /// **'In {key} major — which chord is this?'**
  String romanNumeralPrompt(String key);

  /// No description provided for @romanNumeralReplay.
  ///
  /// In en, this message translates to:
  /// **'Hear the chord again'**
  String get romanNumeralReplay;

  /// No description provided for @gameHarmonyQuiz.
  ///
  /// In en, this message translates to:
  /// **'Function Quiz'**
  String get gameHarmonyQuiz;

  /// No description provided for @gameHarmonyQuizSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tonic, subdominant or dominant?'**
  String get gameHarmonyQuizSubtitle;

  /// No description provided for @harmonyPrompt.
  ///
  /// In en, this message translates to:
  /// **'What is this chord\'s function in {key}?'**
  String harmonyPrompt(String key);

  /// No description provided for @keyMajorName.
  ///
  /// In en, this message translates to:
  /// **'{name} major'**
  String keyMajorName(String name);

  /// No description provided for @harmonicTonic.
  ///
  /// In en, this message translates to:
  /// **'Tonic'**
  String get harmonicTonic;

  /// No description provided for @harmonicSubdominant.
  ///
  /// In en, this message translates to:
  /// **'Subdominant'**
  String get harmonicSubdominant;

  /// No description provided for @harmonicDominant.
  ///
  /// In en, this message translates to:
  /// **'Dominant'**
  String get harmonicDominant;

  /// No description provided for @gameFunctionEar.
  ///
  /// In en, this message translates to:
  /// **'Hear the Function'**
  String get gameFunctionEar;

  /// No description provided for @gameFunctionEarSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Listen for tonic, subdominant or dominant'**
  String get gameFunctionEarSubtitle;

  /// No description provided for @functionEarPrompt.
  ///
  /// In en, this message translates to:
  /// **'Listen to the home chords in {key}, then name the last one'**
  String functionEarPrompt(String key);

  /// No description provided for @functionEarReplayHint.
  ///
  /// In en, this message translates to:
  /// **'Hear the key, then the chord again'**
  String get functionEarReplayHint;

  /// No description provided for @functionEarTargetAgain.
  ///
  /// In en, this message translates to:
  /// **'Just the chord'**
  String get functionEarTargetAgain;

  /// No description provided for @gameEchoSequence.
  ///
  /// In en, this message translates to:
  /// **'Sound Echo'**
  String get gameEchoSequence;

  /// No description provided for @gameEchoSequenceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Watch, listen, then repeat the tune'**
  String get gameEchoSequenceSubtitle;

  /// No description provided for @echoWatch.
  ///
  /// In en, this message translates to:
  /// **'Watch and listen…'**
  String get echoWatch;

  /// No description provided for @echoRepeat.
  ///
  /// In en, this message translates to:
  /// **'Your turn — repeat it!'**
  String get echoRepeat;

  /// No description provided for @echoLength.
  ///
  /// In en, this message translates to:
  /// **'Length: {count}'**
  String echoLength(int count);

  /// No description provided for @gameMajorMinorEar.
  ///
  /// In en, this message translates to:
  /// **'Major or Minor?'**
  String get gameMajorMinorEar;

  /// No description provided for @gameMajorMinorEarSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Listen closely and decide'**
  String get gameMajorMinorEarSubtitle;

  /// No description provided for @listenMajorMinorPrompt.
  ///
  /// In en, this message translates to:
  /// **'Listen! Does it sound major or minor?'**
  String get listenMajorMinorPrompt;

  /// No description provided for @listenAgain.
  ///
  /// In en, this message translates to:
  /// **'Hear it again'**
  String get listenAgain;

  /// No description provided for @majorLabel.
  ///
  /// In en, this message translates to:
  /// **'Major'**
  String get majorLabel;

  /// No description provided for @minorLabel.
  ///
  /// In en, this message translates to:
  /// **'Minor'**
  String get minorLabel;

  /// No description provided for @gameIntervalEar.
  ///
  /// In en, this message translates to:
  /// **'Interval Detective'**
  String get gameIntervalEar;

  /// No description provided for @gameIntervalEarSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How far apart are two notes?'**
  String get gameIntervalEarSubtitle;

  /// No description provided for @listenIntervalPrompt.
  ///
  /// In en, this message translates to:
  /// **'Listen! What interval is this?'**
  String get listenIntervalPrompt;

  /// No description provided for @intervalSecond.
  ///
  /// In en, this message translates to:
  /// **'Second'**
  String get intervalSecond;

  /// No description provided for @intervalThird.
  ///
  /// In en, this message translates to:
  /// **'Third'**
  String get intervalThird;

  /// No description provided for @intervalFifth.
  ///
  /// In en, this message translates to:
  /// **'Fifth'**
  String get intervalFifth;

  /// No description provided for @intervalOctave.
  ///
  /// In en, this message translates to:
  /// **'Octave'**
  String get intervalOctave;

  /// No description provided for @gameTriadBuilder.
  ///
  /// In en, this message translates to:
  /// **'Triad Builder'**
  String get gameTriadBuilder;

  /// No description provided for @gameTriadBuilderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Stack the chord on the staff'**
  String get gameTriadBuilderSubtitle;

  /// No description provided for @triadBuilderPrompt.
  ///
  /// In en, this message translates to:
  /// **'Build the {name} major triad!'**
  String triadBuilderPrompt(String name);

  /// No description provided for @gameScaleBuilder.
  ///
  /// In en, this message translates to:
  /// **'Scale Builder'**
  String get gameScaleBuilder;

  /// No description provided for @gameScaleBuilderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Build the scale step by step'**
  String get gameScaleBuilderSubtitle;

  /// No description provided for @scaleBuilderPromptMinor.
  ///
  /// In en, this message translates to:
  /// **'Build the {name} minor scale — tap the next note!'**
  String scaleBuilderPromptMinor(String name);

  /// No description provided for @scaleBuilderPrompt.
  ///
  /// In en, this message translates to:
  /// **'Build the {name} major scale — tap the next note!'**
  String scaleBuilderPrompt(String name);

  /// No description provided for @gameCadenceWorkshop.
  ///
  /// In en, this message translates to:
  /// **'Cadence Workshop'**
  String get gameCadenceWorkshop;

  /// No description provided for @gameCadenceWorkshopSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Build T–S–D–T cadences'**
  String get gameCadenceWorkshopSubtitle;

  /// No description provided for @cadencePrompt.
  ///
  /// In en, this message translates to:
  /// **'Tap the {function} in {key}!'**
  String cadencePrompt(String function, String key);

  /// No description provided for @gameRhythmTap.
  ///
  /// In en, this message translates to:
  /// **'Rhythm Echo'**
  String get gameRhythmTap;

  /// No description provided for @gameRhythmTapSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Listen and tap it back'**
  String get gameRhythmTapSubtitle;

  /// No description provided for @rhythmTapPrompt.
  ///
  /// In en, this message translates to:
  /// **'Tap the rhythm — hold the long notes!'**
  String get rhythmTapPrompt;

  /// No description provided for @tapHere.
  ///
  /// In en, this message translates to:
  /// **'Tap here!'**
  String get tapHere;

  /// No description provided for @rhythmTapHold.
  ///
  /// In en, this message translates to:
  /// **'Holding…'**
  String get rhythmTapHold;

  /// No description provided for @gameBeatCount.
  ///
  /// In en, this message translates to:
  /// **'Count the Beats'**
  String get gameBeatCount;

  /// No description provided for @gameBeatCountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Dots and ties add up — how long is it?'**
  String get gameBeatCountSubtitle;

  /// No description provided for @gameBeatSort.
  ///
  /// In en, this message translates to:
  /// **'Sort the Beats'**
  String get gameBeatSort;

  /// No description provided for @gameBeatSortSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Drag each note to its beat bucket'**
  String get gameBeatSortSubtitle;

  /// No description provided for @beatSortPrompt.
  ///
  /// In en, this message translates to:
  /// **'Drag each note into the right bucket!'**
  String get beatSortPrompt;

  /// No description provided for @beatCountPrompt.
  ///
  /// In en, this message translates to:
  /// **'How many beats does this last? (♩ = 1)'**
  String get beatCountPrompt;

  /// No description provided for @gameMeterDetective.
  ///
  /// In en, this message translates to:
  /// **'Meter Detective'**
  String get gameMeterDetective;

  /// No description provided for @gameMeterDetectiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'March or waltz? Feel the beat'**
  String get gameMeterDetectiveSubtitle;

  /// No description provided for @meterDetectivePrompt.
  ///
  /// In en, this message translates to:
  /// **'Listen! How many beats per measure?'**
  String get meterDetectivePrompt;

  /// No description provided for @gameMelodyEcho.
  ///
  /// In en, this message translates to:
  /// **'Melody Echo'**
  String get gameMelodyEcho;

  /// No description provided for @gameMelodyEchoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Find the melody you heard'**
  String get gameMelodyEchoSubtitle;

  /// No description provided for @melodyEchoPrompt.
  ///
  /// In en, this message translates to:
  /// **'Listen! Which melody did you hear?'**
  String get melodyEchoPrompt;

  /// No description provided for @gameMelodyDictation.
  ///
  /// In en, this message translates to:
  /// **'Melody Dictation'**
  String get gameMelodyDictation;

  /// No description provided for @gameMelodyDictationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hear it, then write it on the staff'**
  String get gameMelodyDictationSubtitle;

  /// No description provided for @gameNoteMemory.
  ///
  /// In en, this message translates to:
  /// **'Note Match'**
  String get gameNoteMemory;

  /// No description provided for @gameNoteMemorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Memory game: match notes to their names'**
  String get gameNoteMemorySubtitle;

  /// No description provided for @gameNoteOrder.
  ///
  /// In en, this message translates to:
  /// **'Note Order'**
  String get gameNoteOrder;

  /// No description provided for @gameNoteOrderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap the notes from lowest to highest'**
  String get gameNoteOrderSubtitle;

  /// No description provided for @gameOddOneOut.
  ///
  /// In en, this message translates to:
  /// **'Odd One Out'**
  String get gameOddOneOut;

  /// No description provided for @gameOddOneOutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Two notes share a name — tap the odd one'**
  String get gameOddOneOutSubtitle;

  /// No description provided for @oddOneOutPrompt.
  ///
  /// In en, this message translates to:
  /// **'Which note is the odd one out?'**
  String get oddOneOutPrompt;

  /// No description provided for @oddOneOutHint.
  ///
  /// In en, this message translates to:
  /// **'Two notes have the same letter name. Tap the different one!'**
  String get oddOneOutHint;

  /// No description provided for @gameNoteWhack.
  ///
  /// In en, this message translates to:
  /// **'Note Whack'**
  String get gameNoteWhack;

  /// No description provided for @gameNoteWhackSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Whack the notes with the called name'**
  String get gameNoteWhackSubtitle;

  /// No description provided for @noteWhackPrompt.
  ///
  /// In en, this message translates to:
  /// **'Whack:'**
  String get noteWhackPrompt;

  /// No description provided for @noteWhackHint.
  ///
  /// In en, this message translates to:
  /// **'Tap every note that matches — a wrong whack costs a heart!'**
  String get noteWhackHint;

  /// No description provided for @gameCharades.
  ///
  /// In en, this message translates to:
  /// **'Fast or Loud?'**
  String get gameCharades;

  /// No description provided for @gameCharadesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Name the tempo or the dynamics you hear'**
  String get gameCharadesSubtitle;

  /// No description provided for @charadesTempoPrompt.
  ///
  /// In en, this message translates to:
  /// **'How fast is it?'**
  String get charadesTempoPrompt;

  /// No description provided for @charadesDynamicsPrompt.
  ///
  /// In en, this message translates to:
  /// **'How loud is it?'**
  String get charadesDynamicsPrompt;

  /// No description provided for @gameIntervalLadder.
  ///
  /// In en, this message translates to:
  /// **'Interval Ladder'**
  String get gameIntervalLadder;

  /// No description provided for @gameIntervalLadderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Climb the interval from the base note'**
  String get gameIntervalLadderSubtitle;

  /// No description provided for @intervalLadderPrompt.
  ///
  /// In en, this message translates to:
  /// **'Tap the note the arrow points to!'**
  String get intervalLadderPrompt;

  /// No description provided for @intervalLadderHint.
  ///
  /// In en, this message translates to:
  /// **'▲ up, ▼ down. The number is the interval (3 = a third).'**
  String get intervalLadderHint;

  /// No description provided for @gameStaffRunner.
  ///
  /// In en, this message translates to:
  /// **'Staff Runner'**
  String get gameStaffRunner;

  /// No description provided for @gameStaffRunnerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Name notes before the timer runs out'**
  String get gameStaffRunnerSubtitle;

  /// No description provided for @gameChordGripHero.
  ///
  /// In en, this message translates to:
  /// **'Chord Grip Hero'**
  String get gameChordGripHero;

  /// No description provided for @gameChordGripHeroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Press all the chord keys before it lands'**
  String get gameChordGripHeroSubtitle;

  /// No description provided for @chordGripHint.
  ///
  /// In en, this message translates to:
  /// **'Press every glowing key!'**
  String get chordGripHint;

  /// No description provided for @gameNoteSnake.
  ///
  /// In en, this message translates to:
  /// **'Note Snake'**
  String get gameNoteSnake;

  /// No description provided for @gameNoteSnakeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Steer the snake to eat the matching note'**
  String get gameNoteSnakeSubtitle;

  /// No description provided for @noteSnakePrompt.
  ///
  /// In en, this message translates to:
  /// **'Eat this note:'**
  String get noteSnakePrompt;

  /// No description provided for @recitalTitle.
  ///
  /// In en, this message translates to:
  /// **'Recital'**
  String get recitalTitle;

  /// No description provided for @recitalTooltip.
  ///
  /// In en, this message translates to:
  /// **'Play a recital'**
  String get recitalTooltip;

  /// No description provided for @recitalProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} pieces performed'**
  String recitalProgress(int done, int total);

  /// No description provided for @recitalCurtainCall.
  ///
  /// In en, this message translates to:
  /// **'Bravo!'**
  String get recitalCurtainCall;

  /// No description provided for @recitalDone.
  ///
  /// In en, this message translates to:
  /// **'Take a bow'**
  String get recitalDone;

  /// No description provided for @gameStrumToy.
  ///
  /// In en, this message translates to:
  /// **'Strum Toy'**
  String get gameStrumToy;

  /// No description provided for @gameStrumToySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a chord and strum a free jam'**
  String get gameStrumToySubtitle;

  /// No description provided for @strumToyHint.
  ///
  /// In en, this message translates to:
  /// **'Swipe across the strings to strum, or tap one to pluck.'**
  String get strumToyHint;

  /// No description provided for @gameNameThatChord.
  ///
  /// In en, this message translates to:
  /// **'Name That Chord'**
  String get gameNameThatChord;

  /// No description provided for @gameNameThatChordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read or hear a chord, pick its symbol'**
  String get gameNameThatChordSubtitle;

  /// No description provided for @nameThatChordPrompt.
  ///
  /// In en, this message translates to:
  /// **'Which chord is this?'**
  String get nameThatChordPrompt;

  /// No description provided for @curriculumTitle.
  ///
  /// In en, this message translates to:
  /// **'Curriculum'**
  String get curriculumTitle;

  /// No description provided for @curriculumTooltip.
  ///
  /// In en, this message translates to:
  /// **'Curriculum by school year'**
  String get curriculumTooltip;

  /// No description provided for @curSchoolYears.
  ///
  /// In en, this message translates to:
  /// **'By school year'**
  String get curSchoolYears;

  /// No description provided for @curLevelGrades12.
  ///
  /// In en, this message translates to:
  /// **'Grades 1–2'**
  String get curLevelGrades12;

  /// No description provided for @curLevelGrades34.
  ///
  /// In en, this message translates to:
  /// **'Grades 3–4'**
  String get curLevelGrades34;

  /// No description provided for @curLevelGrades56.
  ///
  /// In en, this message translates to:
  /// **'Grades 5–6'**
  String get curLevelGrades56;

  /// No description provided for @curLevelGrades78.
  ///
  /// In en, this message translates to:
  /// **'Grades 7–8'**
  String get curLevelGrades78;

  /// No description provided for @curLevelGrades910.
  ///
  /// In en, this message translates to:
  /// **'Grades 9–10'**
  String get curLevelGrades910;

  /// No description provided for @curTopicNoteReading.
  ///
  /// In en, this message translates to:
  /// **'Note reading'**
  String get curTopicNoteReading;

  /// No description provided for @curTopicNoteValues.
  ///
  /// In en, this message translates to:
  /// **'Note values & rhythm'**
  String get curTopicNoteValues;

  /// No description provided for @curTopicMeter.
  ///
  /// In en, this message translates to:
  /// **'Time & metre'**
  String get curTopicMeter;

  /// No description provided for @curTopicDynamics.
  ///
  /// In en, this message translates to:
  /// **'Dynamics & tempo'**
  String get curTopicDynamics;

  /// No description provided for @curTopicScales.
  ///
  /// In en, this message translates to:
  /// **'Scales & keys'**
  String get curTopicScales;

  /// No description provided for @curTopicIntervals.
  ///
  /// In en, this message translates to:
  /// **'Intervals'**
  String get curTopicIntervals;

  /// No description provided for @curTopicChords.
  ///
  /// In en, this message translates to:
  /// **'Chords'**
  String get curTopicChords;

  /// No description provided for @curTopicHarmony.
  ///
  /// In en, this message translates to:
  /// **'Harmony & cadences'**
  String get curTopicHarmony;

  /// No description provided for @curTopicTransposition.
  ///
  /// In en, this message translates to:
  /// **'Transposition'**
  String get curTopicTransposition;

  /// No description provided for @curTopicEar.
  ///
  /// In en, this message translates to:
  /// **'Ear training'**
  String get curTopicEar;

  /// No description provided for @curTopicSightReading.
  ///
  /// In en, this message translates to:
  /// **'Sight-reading'**
  String get curTopicSightReading;

  /// No description provided for @curReadiness.
  ///
  /// In en, this message translates to:
  /// **'{pct}% ready'**
  String curReadiness(int pct);

  /// No description provided for @curPracticeLevel.
  ///
  /// In en, this message translates to:
  /// **'Practise this level'**
  String get curPracticeLevel;

  /// No description provided for @curContinueHere.
  ///
  /// In en, this message translates to:
  /// **'Continue here'**
  String get curContinueHere;

  /// No description provided for @curPractiseWeakest.
  ///
  /// In en, this message translates to:
  /// **'Practise your weakest topic'**
  String get curPractiseWeakest;

  /// No description provided for @curTopicsHeader.
  ///
  /// In en, this message translates to:
  /// **'Topics'**
  String get curTopicsHeader;

  /// No description provided for @curGuideNote.
  ///
  /// In en, this message translates to:
  /// **'A practice guide — topics arranged by school year, distilled from public school curricula.'**
  String get curGuideNote;

  /// No description provided for @curNoGames.
  ///
  /// In en, this message translates to:
  /// **'No games for this topic yet'**
  String get curNoGames;

  /// No description provided for @gameChordBuilder.
  ///
  /// In en, this message translates to:
  /// **'Chord Builder'**
  String get gameChordBuilder;

  /// No description provided for @gameChordBuilderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Build the named chord — any voicing counts'**
  String get gameChordBuilderSubtitle;

  /// No description provided for @chordBuilderPrompt.
  ///
  /// In en, this message translates to:
  /// **'Build a {chord} chord'**
  String chordBuilderPrompt(String chord);

  /// No description provided for @chordBuilderHint.
  ///
  /// In en, this message translates to:
  /// **'Tap three notes onto the staff. Any octave or inversion works.'**
  String get chordBuilderHint;

  /// No description provided for @chordBuilderClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get chordBuilderClear;

  /// No description provided for @chordBuilderCheck.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get chordBuilderCheck;

  /// No description provided for @moduleTranspose.
  ///
  /// In en, this message translates to:
  /// **'Transposing'**
  String get moduleTranspose;

  /// No description provided for @moduleTransposeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Written vs concert pitch'**
  String get moduleTransposeSubtitle;

  /// No description provided for @gameConcertPitch.
  ///
  /// In en, this message translates to:
  /// **'Concert Pitch'**
  String get gameConcertPitch;

  /// No description provided for @gameConcertPitchSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Name the note that really sounds'**
  String get gameConcertPitchSubtitle;

  /// No description provided for @concertPitchPrompt.
  ///
  /// In en, this message translates to:
  /// **'A {instrument} reads this note. What sounds?'**
  String concertPitchPrompt(String instrument);

  /// No description provided for @concertPitchHint.
  ///
  /// In en, this message translates to:
  /// **'A transposing instrument sounds a different note than written.'**
  String get concertPitchHint;

  /// No description provided for @concertInstrumentBb.
  ///
  /// In en, this message translates to:
  /// **'B♭ Trumpet'**
  String get concertInstrumentBb;

  /// No description provided for @concertInstrumentEb.
  ///
  /// In en, this message translates to:
  /// **'E♭ Alto Sax'**
  String get concertInstrumentEb;

  /// No description provided for @concertInstrumentF.
  ///
  /// In en, this message translates to:
  /// **'F Horn'**
  String get concertInstrumentF;

  /// No description provided for @gameBowing.
  ///
  /// In en, this message translates to:
  /// **'Bowing'**
  String get gameBowing;

  /// No description provided for @gameBowingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read the up-bow and down-bow marks'**
  String get gameBowingSubtitle;

  /// No description provided for @bowingPrompt.
  ///
  /// In en, this message translates to:
  /// **'Which bow stroke is marked?'**
  String get bowingPrompt;

  /// No description provided for @bowDown.
  ///
  /// In en, this message translates to:
  /// **'Down-bow'**
  String get bowDown;

  /// No description provided for @bowUp.
  ///
  /// In en, this message translates to:
  /// **'Up-bow'**
  String get bowUp;

  /// No description provided for @gameWhichBeat.
  ///
  /// In en, this message translates to:
  /// **'Which Beat?'**
  String get gameWhichBeat;

  /// No description provided for @gameWhichBeatSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap the beat the coloured note starts on'**
  String get gameWhichBeatSubtitle;

  /// No description provided for @whichBeatPrompt.
  ///
  /// In en, this message translates to:
  /// **'Which beat does the coloured note fall on?'**
  String get whichBeatPrompt;

  /// No description provided for @workshopExportAbc.
  ///
  /// In en, this message translates to:
  /// **'Export ABC'**
  String get workshopExportAbc;

  /// No description provided for @workshopCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get workshopCopy;

  /// No description provided for @workshopCopied.
  ///
  /// In en, this message translates to:
  /// **'ABC copied to clipboard'**
  String get workshopCopied;

  /// No description provided for @gameTimeSignature.
  ///
  /// In en, this message translates to:
  /// **'Time Signatures'**
  String get gameTimeSignature;

  /// No description provided for @gameTimeSignatureSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read the signature (incl. C and cut time)'**
  String get gameTimeSignatureSubtitle;

  /// No description provided for @timeSignaturePrompt.
  ///
  /// In en, this message translates to:
  /// **'How many beats are in one bar?'**
  String get timeSignaturePrompt;

  /// No description provided for @gameDuet.
  ///
  /// In en, this message translates to:
  /// **'Duet'**
  String get gameDuet;

  /// No description provided for @gameDuetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read the highlighted part in a two-staff score'**
  String get gameDuetSubtitle;

  /// No description provided for @duetPrompt.
  ///
  /// In en, this message translates to:
  /// **'Name the highlighted note'**
  String get duetPrompt;

  /// No description provided for @gamePerformIt.
  ///
  /// In en, this message translates to:
  /// **'Perform It'**
  String get gamePerformIt;

  /// No description provided for @gamePerformItSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Play or sing the note you see'**
  String get gamePerformItSubtitle;

  /// No description provided for @performItPrompt.
  ///
  /// In en, this message translates to:
  /// **'Play or sing this note!'**
  String get performItPrompt;

  /// No description provided for @performItOnTarget.
  ///
  /// In en, this message translates to:
  /// **'Got it!'**
  String get performItOnTarget;

  /// No description provided for @performItSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get performItSkip;

  /// No description provided for @gameSingBack.
  ///
  /// In en, this message translates to:
  /// **'Sing Back'**
  String get gameSingBack;

  /// No description provided for @gameSingBackSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hear a note, then sing it back'**
  String get gameSingBackSubtitle;

  /// No description provided for @singBackPrompt.
  ///
  /// In en, this message translates to:
  /// **'Sing the note you heard!'**
  String get singBackPrompt;

  /// No description provided for @singBackListen.
  ///
  /// In en, this message translates to:
  /// **'Hear it again'**
  String get singBackListen;

  /// No description provided for @gameCelloPlayIt.
  ///
  /// In en, this message translates to:
  /// **'Play It'**
  String get gameCelloPlayIt;

  /// No description provided for @gameCelloPlayItSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Play the note on your real cello — the mic listens'**
  String get gameCelloPlayItSubtitle;

  /// No description provided for @celloPlayItPrompt.
  ///
  /// In en, this message translates to:
  /// **'Play this note on your cello!'**
  String get celloPlayItPrompt;

  /// No description provided for @celloPlayItOpenString.
  ///
  /// In en, this message translates to:
  /// **'{string} string — open'**
  String celloPlayItOpenString(String string);

  /// No description provided for @celloPlayItFingered.
  ///
  /// In en, this message translates to:
  /// **'{string} string — finger {finger}'**
  String celloPlayItFingered(String string, int finger);

  /// No description provided for @moduleDrums.
  ///
  /// In en, this message translates to:
  /// **'Drums'**
  String get moduleDrums;

  /// No description provided for @moduleDrumsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read and play rhythms'**
  String get moduleDrumsSubtitle;

  /// No description provided for @gameDrumRead.
  ///
  /// In en, this message translates to:
  /// **'Drum Read'**
  String get gameDrumRead;

  /// No description provided for @gameDrumReadSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read the rhythm and tap it on the drum'**
  String get gameDrumReadSubtitle;

  /// No description provided for @drumReadHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the drum on each note, in time with the click.'**
  String get drumReadHint;

  /// No description provided for @drumReadGo.
  ///
  /// In en, this message translates to:
  /// **'Play!'**
  String get drumReadGo;

  /// No description provided for @beatsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 beat} other{{count} beats}}'**
  String beatsCount(int count);

  /// No description provided for @clefBass.
  ///
  /// In en, this message translates to:
  /// **'Bass clef'**
  String get clefBass;

  /// No description provided for @gameLineSpace.
  ///
  /// In en, this message translates to:
  /// **'Line or Space?'**
  String get gameLineSpace;

  /// No description provided for @gameLineSpaceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Swipe: is the note on a line or in a space?'**
  String get gameLineSpaceSubtitle;

  /// No description provided for @gameFallingNotes.
  ///
  /// In en, this message translates to:
  /// **'Falling Notes'**
  String get gameFallingNotes;

  /// No description provided for @gameFallingNotesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Name the notes before they land!'**
  String get gameFallingNotesSubtitle;

  /// No description provided for @gameConnectLine.
  ///
  /// In en, this message translates to:
  /// **'Connect the Notes'**
  String get gameConnectLine;

  /// No description provided for @gameConnectLineSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Draw a line from each note to its name'**
  String get gameConnectLineSubtitle;

  /// No description provided for @connectLinePrompt.
  ///
  /// In en, this message translates to:
  /// **'Connect each note to its name!'**
  String get connectLinePrompt;

  /// No description provided for @gameLedgerLeap.
  ///
  /// In en, this message translates to:
  /// **'Ledger Leap'**
  String get gameLedgerLeap;

  /// No description provided for @gameLedgerLeapSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Count the little helper lines above or below the staff'**
  String get gameLedgerLeapSubtitle;

  /// No description provided for @ledgerLeapPrompt.
  ///
  /// In en, this message translates to:
  /// **'How many ledger lines?'**
  String get ledgerLeapPrompt;

  /// No description provided for @gameFallingKeys.
  ///
  /// In en, this message translates to:
  /// **'Falling Keys'**
  String get gameFallingKeys;

  /// No description provided for @gameFallingKeysSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Play each falling note on the piano before it lands!'**
  String get gameFallingKeysSubtitle;

  /// No description provided for @gameConnectSymbols.
  ///
  /// In en, this message translates to:
  /// **'Connect the Symbols'**
  String get gameConnectSymbols;

  /// No description provided for @gameConnectSymbolsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Draw a line from each note value to its name'**
  String get gameConnectSymbolsSubtitle;

  /// No description provided for @connectSymbolsPrompt.
  ///
  /// In en, this message translates to:
  /// **'Connect each symbol to its name!'**
  String get connectSymbolsPrompt;

  /// No description provided for @gameCommandCaller.
  ///
  /// In en, this message translates to:
  /// **'Follow the Conductor'**
  String get gameCommandCaller;

  /// No description provided for @gameCommandCallerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Do the move the conductor calls!'**
  String get gameCommandCallerSubtitle;

  /// No description provided for @commandCallerHint.
  ///
  /// In en, this message translates to:
  /// **'Tap, hold, or swipe — before the bar runs out!'**
  String get commandCallerHint;

  /// No description provided for @conductorPrompt.
  ///
  /// In en, this message translates to:
  /// **'Follow the conductor\'s beat!'**
  String get conductorPrompt;

  /// No description provided for @commandTap.
  ///
  /// In en, this message translates to:
  /// **'Tap!'**
  String get commandTap;

  /// No description provided for @commandHold.
  ///
  /// In en, this message translates to:
  /// **'Hold!'**
  String get commandHold;

  /// No description provided for @commandSwipeLeft.
  ///
  /// In en, this message translates to:
  /// **'Swipe left!'**
  String get commandSwipeLeft;

  /// No description provided for @commandSwipeRight.
  ///
  /// In en, this message translates to:
  /// **'Swipe right!'**
  String get commandSwipeRight;

  /// No description provided for @commandSwipeUp.
  ///
  /// In en, this message translates to:
  /// **'Swipe up!'**
  String get commandSwipeUp;

  /// No description provided for @commandSwipeDown.
  ///
  /// In en, this message translates to:
  /// **'Swipe down!'**
  String get commandSwipeDown;

  /// No description provided for @gameKeySignature.
  ///
  /// In en, this message translates to:
  /// **'Key Detective'**
  String get gameKeySignature;

  /// No description provided for @gameKeySignatureSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read the sharps or flats — name the key'**
  String get gameKeySignatureSubtitle;

  /// No description provided for @keySignaturePrompt.
  ///
  /// In en, this message translates to:
  /// **'Which major key is this?'**
  String get keySignaturePrompt;

  /// No description provided for @keyMajorLabel.
  ///
  /// In en, this message translates to:
  /// **'{name} major'**
  String keyMajorLabel(String name);

  /// No description provided for @gameBeatRunner.
  ///
  /// In en, this message translates to:
  /// **'Beat Runner'**
  String get gameBeatRunner;

  /// No description provided for @gameBeatRunnerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap in time as the beats reach the line!'**
  String get gameBeatRunnerSubtitle;

  /// No description provided for @beatRunnerHint.
  ///
  /// In en, this message translates to:
  /// **'Tap on the beat!'**
  String get beatRunnerHint;

  /// No description provided for @beatPerfect.
  ///
  /// In en, this message translates to:
  /// **'Perfect!'**
  String get beatPerfect;

  /// No description provided for @beatGood.
  ///
  /// In en, this message translates to:
  /// **'Good!'**
  String get beatGood;

  /// No description provided for @beatMiss.
  ///
  /// In en, this message translates to:
  /// **'Miss'**
  String get beatMiss;

  /// No description provided for @fallingSpeedUp.
  ///
  /// In en, this message translates to:
  /// **'Speed up!'**
  String get fallingSpeedUp;

  /// No description provided for @fallingMultiplier.
  ///
  /// In en, this message translates to:
  /// **'×{mult}'**
  String fallingMultiplier(int mult);

  /// No description provided for @lineSpacePrompt.
  ///
  /// In en, this message translates to:
  /// **'Swipe ← Line   or   Space →'**
  String get lineSpacePrompt;

  /// No description provided for @lineLabel.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get lineLabel;

  /// No description provided for @spaceLabel.
  ///
  /// In en, this message translates to:
  /// **'Space'**
  String get spaceLabel;

  /// No description provided for @noteOrderPrompt.
  ///
  /// In en, this message translates to:
  /// **'Tap the notes from lowest to highest!'**
  String get noteOrderPrompt;

  /// No description provided for @noteOrderHint.
  ///
  /// In en, this message translates to:
  /// **'Each note plays when you tap it.'**
  String get noteOrderHint;

  /// No description provided for @noteMemoryPrompt.
  ///
  /// In en, this message translates to:
  /// **'Find the pairs: a note and its name!'**
  String get noteMemoryPrompt;

  /// No description provided for @noteMemoryMoves.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 move} other{{count} moves}}'**
  String noteMemoryMoves(int count);

  /// No description provided for @melodyDictationPrompt.
  ///
  /// In en, this message translates to:
  /// **'The first note is given — add the ones you hear'**
  String get melodyDictationPrompt;

  /// No description provided for @dictationUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get dictationUndo;

  /// No description provided for @whatIsThisSymbol.
  ///
  /// In en, this message translates to:
  /// **'What is this symbol called?'**
  String get whatIsThisSymbol;

  /// No description provided for @hearLength.
  ///
  /// In en, this message translates to:
  /// **'Hear the length'**
  String get hearLength;

  /// No description provided for @countAlong.
  ///
  /// In en, this message translates to:
  /// **'Count along'**
  String get countAlong;

  /// No description provided for @halfBeat.
  ///
  /// In en, this message translates to:
  /// **'½ beat'**
  String get halfBeat;

  /// No description provided for @quarterBeat.
  ///
  /// In en, this message translates to:
  /// **'¼ beat'**
  String get quarterBeat;

  /// No description provided for @symbolLength.
  ///
  /// In en, this message translates to:
  /// **'{name} lasts {length}'**
  String symbolLength(String name, String length);

  /// No description provided for @symbolLengthRest.
  ///
  /// In en, this message translates to:
  /// **'{name}: {length} of silence'**
  String symbolLengthRest(String name, String length);

  /// No description provided for @roundOf.
  ///
  /// In en, this message translates to:
  /// **'Round {current} of {total}'**
  String roundOf(int current, int total);

  /// No description provided for @feedbackCorrect.
  ///
  /// In en, this message translates to:
  /// **'Correct!'**
  String get feedbackCorrect;

  /// No description provided for @feedbackTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Oops — try again!'**
  String get feedbackTryAgain;

  /// No description provided for @resultScore.
  ///
  /// In en, this message translates to:
  /// **'Score: {score}'**
  String resultScore(int score);

  /// No description provided for @resultTime.
  ///
  /// In en, this message translates to:
  /// **'Your time: {time}'**
  String resultTime(String time);

  /// No description provided for @resultBest.
  ///
  /// In en, this message translates to:
  /// **'Best: {time}'**
  String resultBest(String time);

  /// No description provided for @resultNewBest.
  ///
  /// In en, this message translates to:
  /// **'New best time! 🎉'**
  String get resultNewBest;

  /// No description provided for @showTimerLabel.
  ///
  /// In en, this message translates to:
  /// **'Show your time'**
  String get showTimerLabel;

  /// No description provided for @colorScaffoldLabel.
  ///
  /// In en, this message translates to:
  /// **'Colour helper for beginners'**
  String get colorScaffoldLabel;

  /// No description provided for @colorScaffoldSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tint notes by their letter — turn it off once the staff is familiar'**
  String get colorScaffoldSubtitle;

  /// No description provided for @debugModeEnabled.
  ///
  /// In en, this message translates to:
  /// **'Debug settings unlocked!'**
  String get debugModeEnabled;

  /// No description provided for @debugSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Debug'**
  String get debugSectionTitle;

  /// No description provided for @debugUnlockLabel.
  ///
  /// In en, this message translates to:
  /// **'Unlock all games'**
  String get debugUnlockLabel;

  /// No description provided for @playAgain.
  ///
  /// In en, this message translates to:
  /// **'Play again'**
  String get playAgain;

  /// No description provided for @backButton.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get backButton;

  /// No description provided for @wholeNote.
  ///
  /// In en, this message translates to:
  /// **'Whole note'**
  String get wholeNote;

  /// No description provided for @halfNote.
  ///
  /// In en, this message translates to:
  /// **'Half note'**
  String get halfNote;

  /// No description provided for @quarterNote.
  ///
  /// In en, this message translates to:
  /// **'Quarter note'**
  String get quarterNote;

  /// No description provided for @eighthNote.
  ///
  /// In en, this message translates to:
  /// **'Eighth note'**
  String get eighthNote;

  /// No description provided for @sixteenthNote.
  ///
  /// In en, this message translates to:
  /// **'Sixteenth note'**
  String get sixteenthNote;

  /// No description provided for @wholeRest.
  ///
  /// In en, this message translates to:
  /// **'Whole rest'**
  String get wholeRest;

  /// No description provided for @halfRest.
  ///
  /// In en, this message translates to:
  /// **'Half rest'**
  String get halfRest;

  /// No description provided for @quarterRest.
  ///
  /// In en, this message translates to:
  /// **'Quarter rest'**
  String get quarterRest;

  /// No description provided for @eighthRest.
  ///
  /// In en, this message translates to:
  /// **'Eighth rest'**
  String get eighthRest;

  /// No description provided for @sixteenthRest.
  ///
  /// In en, this message translates to:
  /// **'Sixteenth rest'**
  String get sixteenthRest;

  /// No description provided for @gameTuner.
  ///
  /// In en, this message translates to:
  /// **'Tuner'**
  String get gameTuner;

  /// No description provided for @gameTunerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Live intonation — play or sing a note'**
  String get gameTunerSubtitle;

  /// No description provided for @gamePlayAlong.
  ///
  /// In en, this message translates to:
  /// **'Play along'**
  String get gamePlayAlong;

  /// No description provided for @gamePlayAlongSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Follow the moving score in first position'**
  String get gamePlayAlongSubtitle;

  /// No description provided for @gamePlayAlongGuitarSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Follow the moving score on the guitar'**
  String get gamePlayAlongGuitarSubtitle;

  /// No description provided for @gamePlayAlongKeyboardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Play the moving score on the keys'**
  String get gamePlayAlongKeyboardSubtitle;

  /// No description provided for @gameSingAlong.
  ///
  /// In en, this message translates to:
  /// **'Sing along'**
  String get gameSingAlong;

  /// No description provided for @gameSingAlongSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Match the moving score with your voice'**
  String get gameSingAlongSubtitle;

  /// No description provided for @gameOdeToJoy.
  ///
  /// In en, this message translates to:
  /// **'Ode to Joy'**
  String get gameOdeToJoy;

  /// No description provided for @gameMaryLamb.
  ///
  /// In en, this message translates to:
  /// **'Mary\'s Lamb'**
  String get gameMaryLamb;

  /// No description provided for @gameChordListener.
  ///
  /// In en, this message translates to:
  /// **'Chord listener'**
  String get gameChordListener;

  /// No description provided for @gameChordListenerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Name the chord you strum or play'**
  String get gameChordListenerSubtitle;

  /// No description provided for @gameChordProgression.
  ///
  /// In en, this message translates to:
  /// **'Chord play-along'**
  String get gameChordProgression;

  /// No description provided for @gameChordProgressionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Strum the progression as it scrolls by'**
  String get gameChordProgressionSubtitle;

  /// No description provided for @micStart.
  ///
  /// In en, this message translates to:
  /// **'Start listening'**
  String get micStart;

  /// No description provided for @micStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get micStop;

  /// No description provided for @micPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission denied. Enable it in system settings.'**
  String get micPermissionDenied;

  /// No description provided for @micUnsupported.
  ///
  /// In en, this message translates to:
  /// **'PCM capture is not supported on this device.'**
  String get micUnsupported;

  /// No description provided for @micStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not start the microphone: {detail}'**
  String micStartFailed(String detail);

  /// No description provided for @tunerPrompt.
  ///
  /// In en, this message translates to:
  /// **'Play or sing a note'**
  String get tunerPrompt;

  /// No description provided for @tunerCents.
  ///
  /// In en, this message translates to:
  /// **'{cents} cents'**
  String tunerCents(String cents);

  /// No description provided for @playAlongScore.
  ///
  /// In en, this message translates to:
  /// **'Score'**
  String get playAlongScore;

  /// No description provided for @playAlongNow.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get playAlongNow;

  /// No description provided for @playAlongYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get playAlongYou;

  /// No description provided for @playAlongCountIn.
  ///
  /// In en, this message translates to:
  /// **'count-in'**
  String get playAlongCountIn;

  /// No description provided for @playAlongPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get playAlongPreview;

  /// No description provided for @playAlongViewLabel.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get playAlongViewLabel;

  /// No description provided for @playAlongViewHighway.
  ///
  /// In en, this message translates to:
  /// **'Highway'**
  String get playAlongViewHighway;

  /// No description provided for @playAlongViewNotation.
  ///
  /// In en, this message translates to:
  /// **'Notation'**
  String get playAlongViewNotation;

  /// No description provided for @playAlongViewFalling.
  ///
  /// In en, this message translates to:
  /// **'Falling'**
  String get playAlongViewFalling;

  /// No description provided for @playAlongViewCoach.
  ///
  /// In en, this message translates to:
  /// **'Coach'**
  String get playAlongViewCoach;

  /// No description provided for @playAlongNext.
  ///
  /// In en, this message translates to:
  /// **'next'**
  String get playAlongNext;

  /// No description provided for @playAlongBacking.
  ///
  /// In en, this message translates to:
  /// **'Backing (use headphones)'**
  String get playAlongBacking;

  /// No description provided for @playAlongTempo.
  ///
  /// In en, this message translates to:
  /// **'Tempo'**
  String get playAlongTempo;

  /// No description provided for @chordListenerPrompt.
  ///
  /// In en, this message translates to:
  /// **'Strum or play a chord'**
  String get chordListenerPrompt;

  /// No description provided for @chordListenerMatch.
  ///
  /// In en, this message translates to:
  /// **'{percent}% match'**
  String chordListenerMatch(int percent);

  /// No description provided for @chordListenerHeard.
  ///
  /// In en, this message translates to:
  /// **'Heard pitch classes'**
  String get chordListenerHeard;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutTitle;

  /// No description provided for @aboutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Version, licenses and credits'**
  String get aboutSubtitle;

  /// No description provided for @appLegalese.
  ///
  /// In en, this message translates to:
  /// **'© 2026 Christian Ströbele'**
  String get appLegalese;

  /// No description provided for @aboutTagline.
  ///
  /// In en, this message translates to:
  /// **'Music notation & harmony — from primary school onward'**
  String get aboutTagline;

  /// No description provided for @aboutVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String aboutVersionLabel(String version);

  /// No description provided for @aboutProvider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get aboutProvider;

  /// No description provided for @aboutContact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get aboutContact;

  /// No description provided for @aboutPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get aboutPrivacy;

  /// No description provided for @aboutPrivacyText.
  ///
  /// In en, this message translates to:
  /// **'KlangUniversum works entirely on your device. Microphone audio (for the tuner and play-along) is analysed locally in real time — never recorded, stored, or sent anywhere. There are no accounts, no ads, and no tracking.'**
  String get aboutPrivacyText;

  /// No description provided for @aboutDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Disclaimer'**
  String get aboutDisclaimer;

  /// No description provided for @aboutDisclaimerText.
  ///
  /// In en, this message translates to:
  /// **'KlangUniversum is a learning aid, provided as is and without warranty. Curriculum levels are generic guidance, not an official syllabus.'**
  String get aboutDisclaimerText;

  /// No description provided for @aboutCredits.
  ///
  /// In en, this message translates to:
  /// **'Credits'**
  String get aboutCredits;

  /// No description provided for @aboutCreditsText.
  ///
  /// In en, this message translates to:
  /// **'Music engraving uses the Bravura font (SIL Open Font License).'**
  String get aboutCreditsText;

  /// No description provided for @aboutOpenSourceLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open-source licenses'**
  String get aboutOpenSourceLicenses;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
