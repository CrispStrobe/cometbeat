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

  /// No description provided for @gameNoteReadingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Name the note on the staff'**
  String get gameNoteReadingSubtitle;

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
