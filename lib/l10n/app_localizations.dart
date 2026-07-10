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
  /// **'Which string plays this note?'**
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
  /// **'Listen, then tap the rhythm!'**
  String get rhythmTapPrompt;

  /// No description provided for @tapHere.
  ///
  /// In en, this message translates to:
  /// **'Tap here!'**
  String get tapHere;

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

  /// No description provided for @whatIsThisSymbol.
  ///
  /// In en, this message translates to:
  /// **'What is this symbol called?'**
  String get whatIsThisSymbol;

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
