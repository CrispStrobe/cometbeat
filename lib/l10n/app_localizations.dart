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

  /// No description provided for @workshopClefMidBar.
  ///
  /// In en, this message translates to:
  /// **'Clef (mid-bar)'**
  String get workshopClefMidBar;

  /// No description provided for @workshopVoice1.
  ///
  /// In en, this message translates to:
  /// **'V1'**
  String get workshopVoice1;

  /// No description provided for @workshopVoice2.
  ///
  /// In en, this message translates to:
  /// **'V2'**
  String get workshopVoice2;

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

  /// No description provided for @workshopOpen.
  ///
  /// In en, this message translates to:
  /// **'Open a file…'**
  String get workshopOpen;

  /// No description provided for @workshopExport.
  ///
  /// In en, this message translates to:
  /// **'Export…'**
  String get workshopExport;

  /// No description provided for @workshopExportChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose a format'**
  String get workshopExportChoose;

  /// Export sheet: this format writes every instrument part.
  ///
  /// In en, this message translates to:
  /// **'All {count} parts'**
  String workshopExportAllParts(int count);

  /// Export sheet: warns that the format drops all but the active part.
  ///
  /// In en, this message translates to:
  /// **'Only “{part}” — this format cannot hold several parts'**
  String workshopExportActivePartOnly(String part);

  /// No description provided for @workshopSavedTo.
  ///
  /// In en, this message translates to:
  /// **'Saved: {path}'**
  String workshopSavedTo(String path);

  /// No description provided for @workshopExportXml.
  ///
  /// In en, this message translates to:
  /// **'Export MusicXML'**
  String get workshopExportXml;

  /// No description provided for @workshopExportSvg.
  ///
  /// In en, this message translates to:
  /// **'Export SVG (print)'**
  String get workshopExportSvg;

  /// No description provided for @workshopExportImage.
  ///
  /// In en, this message translates to:
  /// **'Export image (PNG)'**
  String get workshopExportImage;

  /// No description provided for @workshopExportedImage.
  ///
  /// In en, this message translates to:
  /// **'Image saved'**
  String get workshopExportedImage;

  /// No description provided for @workshopMarquee.
  ///
  /// In en, this message translates to:
  /// **'Select notes (rubber-band)'**
  String get workshopMarquee;

  /// No description provided for @workshopCut.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get workshopCut;

  /// No description provided for @workshopPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get workshopPaste;

  /// No description provided for @workshopMoveLeft.
  ///
  /// In en, this message translates to:
  /// **'Move left'**
  String get workshopMoveLeft;

  /// No description provided for @workshopMoveRight.
  ///
  /// In en, this message translates to:
  /// **'Move right'**
  String get workshopMoveRight;

  /// No description provided for @workshopExtendLeft.
  ///
  /// In en, this message translates to:
  /// **'Extend selection left'**
  String get workshopExtendLeft;

  /// No description provided for @workshopExtendRight.
  ///
  /// In en, this message translates to:
  /// **'Extend selection right'**
  String get workshopExtendRight;

  /// No description provided for @workshopSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 selected} other{{count} selected}}'**
  String workshopSelectedCount(int count);

  /// No description provided for @workshopRepeatStart.
  ///
  /// In en, this message translates to:
  /// **'Repeat starts here'**
  String get workshopRepeatStart;

  /// No description provided for @workshopRepeatEnd.
  ///
  /// In en, this message translates to:
  /// **'Repeat ends here'**
  String get workshopRepeatEnd;

  /// No description provided for @workshopChangeHere.
  ///
  /// In en, this message translates to:
  /// **'Change from here…'**
  String get workshopChangeHere;

  /// No description provided for @workshopChangeHereTitle.
  ///
  /// In en, this message translates to:
  /// **'Change from this note'**
  String get workshopChangeHereTitle;

  /// No description provided for @workshopNoChange.
  ///
  /// In en, this message translates to:
  /// **'No change'**
  String get workshopNoChange;

  /// No description provided for @workshopVolta.
  ///
  /// In en, this message translates to:
  /// **'Ending'**
  String get workshopVolta;

  /// No description provided for @workshopNavigation.
  ///
  /// In en, this message translates to:
  /// **'Navigation'**
  String get workshopNavigation;

  /// No description provided for @workshopTempo.
  ///
  /// In en, this message translates to:
  /// **'Tempo'**
  String get workshopTempo;

  /// No description provided for @workshopInitialTempo.
  ///
  /// In en, this message translates to:
  /// **'Initial tempo…'**
  String get workshopInitialTempo;

  /// No description provided for @workshopTempoNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get workshopTempoNone;

  /// No description provided for @workshopGraceNotes.
  ///
  /// In en, this message translates to:
  /// **'Grace notes…'**
  String get workshopGraceNotes;

  /// No description provided for @workshopGraceEmpty.
  ///
  /// In en, this message translates to:
  /// **'No grace notes yet — tap a note to add one.'**
  String get workshopGraceEmpty;

  /// No description provided for @workshopGraceAcciaccatura.
  ///
  /// In en, this message translates to:
  /// **'Acciaccatura'**
  String get workshopGraceAcciaccatura;

  /// No description provided for @workshopGraceAppoggiatura.
  ///
  /// In en, this message translates to:
  /// **'Appoggiatura'**
  String get workshopGraceAppoggiatura;

  /// No description provided for @workshopStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get workshopStop;

  /// No description provided for @workshopMutePart.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get workshopMutePart;

  /// No description provided for @workshopPlaybackSpeed.
  ///
  /// In en, this message translates to:
  /// **'Playback speed'**
  String get workshopPlaybackSpeed;

  /// No description provided for @workshopCountIn.
  ///
  /// In en, this message translates to:
  /// **'Count-in'**
  String get workshopCountIn;

  /// No description provided for @workshopLoopSelection.
  ///
  /// In en, this message translates to:
  /// **'Loop selection'**
  String get workshopLoopSelection;

  /// No description provided for @workshopArticulations.
  ///
  /// In en, this message translates to:
  /// **'Articulations & ties'**
  String get workshopArticulations;

  /// No description provided for @workshopOrnament.
  ///
  /// In en, this message translates to:
  /// **'Ornament'**
  String get workshopOrnament;

  /// No description provided for @workshopStaccato.
  ///
  /// In en, this message translates to:
  /// **'Staccato'**
  String get workshopStaccato;

  /// No description provided for @workshopTenuto.
  ///
  /// In en, this message translates to:
  /// **'Tenuto'**
  String get workshopTenuto;

  /// No description provided for @workshopAccent.
  ///
  /// In en, this message translates to:
  /// **'Accent'**
  String get workshopAccent;

  /// No description provided for @workshopMarcato.
  ///
  /// In en, this message translates to:
  /// **'Marcato'**
  String get workshopMarcato;

  /// No description provided for @workshopFermata.
  ///
  /// In en, this message translates to:
  /// **'Fermata'**
  String get workshopFermata;

  /// No description provided for @workshopBarNumbers.
  ///
  /// In en, this message translates to:
  /// **'Bar numbers'**
  String get workshopBarNumbers;

  /// No description provided for @workshopNoteNames.
  ///
  /// In en, this message translates to:
  /// **'Note names'**
  String get workshopNoteNames;

  /// No description provided for @workshopInspector.
  ///
  /// In en, this message translates to:
  /// **'Inspector'**
  String get workshopInspector;

  /// No description provided for @workshopInspectorEmpty.
  ///
  /// In en, this message translates to:
  /// **'Select a note to see its properties.'**
  String get workshopInspectorEmpty;

  /// No description provided for @workshopStructure.
  ///
  /// In en, this message translates to:
  /// **'Structure'**
  String get workshopStructure;

  /// No description provided for @workshopInsertMode.
  ///
  /// In en, this message translates to:
  /// **'Insert'**
  String get workshopInsertMode;

  /// No description provided for @workshopSelectMode.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get workshopSelectMode;

  /// No description provided for @workshopStudioMode.
  ///
  /// In en, this message translates to:
  /// **'Studio mode'**
  String get workshopStudioMode;

  /// No description provided for @workshopSplitNotes.
  ///
  /// In en, this message translates to:
  /// **'Split notes across barlines'**
  String get workshopSplitNotes;

  /// No description provided for @workshopPasteTokens.
  ///
  /// In en, this message translates to:
  /// **'Paste notation tokens…'**
  String get workshopPasteTokens;

  /// No description provided for @workshopPasteTokensHint.
  ///
  /// In en, this message translates to:
  /// **'Paste bekern / kern tokens (e.g. **kern <b> 4 c <b> *-)'**
  String get workshopPasteTokensHint;

  /// No description provided for @workshopPasteTokensLoad.
  ///
  /// In en, this message translates to:
  /// **'Load'**
  String get workshopPasteTokensLoad;

  /// No description provided for @workshopAddInstrument.
  ///
  /// In en, this message translates to:
  /// **'Add instrument'**
  String get workshopAddInstrument;

  /// No description provided for @workshopRemoveInstrument.
  ///
  /// In en, this message translates to:
  /// **'Remove this part'**
  String get workshopRemoveInstrument;

  /// No description provided for @workshopPartClef.
  ///
  /// In en, this message translates to:
  /// **'Clef'**
  String get workshopPartClef;

  /// No description provided for @workshopPartTransposition.
  ///
  /// In en, this message translates to:
  /// **'Transposition'**
  String get workshopPartTransposition;

  /// No description provided for @workshopConcertPitch.
  ///
  /// In en, this message translates to:
  /// **'Concert pitch (C)'**
  String get workshopConcertPitch;

  /// No description provided for @workshopBraceBelow.
  ///
  /// In en, this message translates to:
  /// **'Brace with part below'**
  String get workshopBraceBelow;

  /// No description provided for @workshopBreakBarlineBelow.
  ///
  /// In en, this message translates to:
  /// **'Break barline below'**
  String get workshopBreakBarlineBelow;

  /// No description provided for @workshopTuplet.
  ///
  /// In en, this message translates to:
  /// **'Triplet (3 in the time of 2)'**
  String get workshopTuplet;

  /// No description provided for @workshopTie.
  ///
  /// In en, this message translates to:
  /// **'Tie'**
  String get workshopTie;

  /// No description provided for @workshopDynamics.
  ///
  /// In en, this message translates to:
  /// **'Dynamics'**
  String get workshopDynamics;

  /// No description provided for @workshopDynamicNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get workshopDynamicNone;

  /// No description provided for @workshopChord.
  ///
  /// In en, this message translates to:
  /// **'Chord (stack notes)'**
  String get workshopChord;

  /// No description provided for @workshopSlur.
  ///
  /// In en, this message translates to:
  /// **'Slur (phrase the selected notes)'**
  String get workshopSlur;

  /// No description provided for @workshopCrescendo.
  ///
  /// In en, this message translates to:
  /// **'Crescendo (getting louder)'**
  String get workshopCrescendo;

  /// No description provided for @workshopDiminuendo.
  ///
  /// In en, this message translates to:
  /// **'Diminuendo (getting softer)'**
  String get workshopDiminuendo;

  /// No description provided for @workshopPickup.
  ///
  /// In en, this message translates to:
  /// **'Pickup (upbeat)'**
  String get workshopPickup;

  /// No description provided for @workshopPickupNone.
  ///
  /// In en, this message translates to:
  /// **'No pickup'**
  String get workshopPickupNone;

  /// No description provided for @workshopLyric.
  ///
  /// In en, this message translates to:
  /// **'Lyric'**
  String get workshopLyric;

  /// No description provided for @workshopLyricHint.
  ///
  /// In en, this message translates to:
  /// **'Syllable…'**
  String get workshopLyricHint;

  /// No description provided for @workshopLyricVerse.
  ///
  /// In en, this message translates to:
  /// **'Verse'**
  String get workshopLyricVerse;

  /// No description provided for @workshopShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get workshopShortcuts;

  /// No description provided for @workshopShortcutPlaceNote.
  ///
  /// In en, this message translates to:
  /// **'Place a note (its pitch)'**
  String get workshopShortcutPlaceNote;

  /// No description provided for @workshopShortcutNoteValue.
  ///
  /// In en, this message translates to:
  /// **'Note value (whole … sixteenth)'**
  String get workshopShortcutNoteValue;

  /// No description provided for @workshopShortcutSelect.
  ///
  /// In en, this message translates to:
  /// **'Select previous / next'**
  String get workshopShortcutSelect;

  /// No description provided for @workshopShortcutTranspose.
  ///
  /// In en, this message translates to:
  /// **'Move pitch up / down'**
  String get workshopShortcutTranspose;

  /// No description provided for @workshopShortcutUndoRedo.
  ///
  /// In en, this message translates to:
  /// **'Undo / redo'**
  String get workshopShortcutUndoRedo;

  /// No description provided for @workshopShortcutCopyPaste.
  ///
  /// In en, this message translates to:
  /// **'Copy / cut / paste'**
  String get workshopShortcutCopyPaste;

  /// No description provided for @workshopExitTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave the workshop?'**
  String get workshopExitTitle;

  /// No description provided for @workshopExitMessage.
  ///
  /// In en, this message translates to:
  /// **'Your score has unsaved changes.'**
  String get workshopExitMessage;

  /// No description provided for @workshopKeepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get workshopKeepEditing;

  /// No description provided for @workshopDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get workshopDiscard;

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

  /// No description provided for @gameTempoDuel.
  ///
  /// In en, this message translates to:
  /// **'Faster or Slower?'**
  String get gameTempoDuel;

  /// No description provided for @gameTempoDuelSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read two tempo words and tap the faster one'**
  String get gameTempoDuelSubtitle;

  /// No description provided for @whichIsFaster.
  ///
  /// In en, this message translates to:
  /// **'Which tempo is faster?'**
  String get whichIsFaster;

  /// No description provided for @gameDynamicsDuel.
  ///
  /// In en, this message translates to:
  /// **'Louder or Softer?'**
  String get gameDynamicsDuel;

  /// No description provided for @gameDynamicsDuelSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read two dynamic marks and tap the louder one'**
  String get gameDynamicsDuelSubtitle;

  /// No description provided for @whichIsLouder.
  ///
  /// In en, this message translates to:
  /// **'Which mark is louder?'**
  String get whichIsLouder;

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

  /// No description provided for @gamePitchSort.
  ///
  /// In en, this message translates to:
  /// **'High or Low?'**
  String get gamePitchSort;

  /// No description provided for @gamePitchSortBass.
  ///
  /// In en, this message translates to:
  /// **'High or Low? (bass)'**
  String get gamePitchSortBass;

  /// No description provided for @gamePitchSortSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Drag each note into the high or low basket'**
  String get gamePitchSortSubtitle;

  /// No description provided for @pitchSortPrompt.
  ///
  /// In en, this message translates to:
  /// **'Is each note high or low? Drop it in the right basket!'**
  String get pitchSortPrompt;

  /// No description provided for @pitchHighLabel.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get pitchHighLabel;

  /// No description provided for @pitchLowLabel.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get pitchLowLabel;

  /// No description provided for @gameAccidentalSort.
  ///
  /// In en, this message translates to:
  /// **'Sharp or Flat?'**
  String get gameAccidentalSort;

  /// No description provided for @gameAccidentalSortBass.
  ///
  /// In en, this message translates to:
  /// **'Sharp or Flat? (bass)'**
  String get gameAccidentalSortBass;

  /// No description provided for @gameAccidentalSortSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Drag each note into the sharp or flat basket'**
  String get gameAccidentalSortSubtitle;

  /// No description provided for @accidentalSortPrompt.
  ///
  /// In en, this message translates to:
  /// **'Does the note have a sharp or a flat? Drop it in the right basket!'**
  String get accidentalSortPrompt;

  /// No description provided for @accidentalSharpLabel.
  ///
  /// In en, this message translates to:
  /// **'Sharp'**
  String get accidentalSharpLabel;

  /// No description provided for @accidentalFlatLabel.
  ///
  /// In en, this message translates to:
  /// **'Flat'**
  String get accidentalFlatLabel;

  /// No description provided for @accidentalNaturalLabel.
  ///
  /// In en, this message translates to:
  /// **'Natural'**
  String get accidentalNaturalLabel;

  /// No description provided for @gameDirectionEar.
  ///
  /// In en, this message translates to:
  /// **'Higher or Lower?'**
  String get gameDirectionEar;

  /// No description provided for @gameDirectionEarSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Listen: does the second note go up or down?'**
  String get gameDirectionEarSubtitle;

  /// No description provided for @directionEarPrompt.
  ///
  /// In en, this message translates to:
  /// **'Two notes play. Is the second one higher or lower?'**
  String get directionEarPrompt;

  /// No description provided for @directionUpLabel.
  ///
  /// In en, this message translates to:
  /// **'Higher'**
  String get directionUpLabel;

  /// No description provided for @directionDownLabel.
  ///
  /// In en, this message translates to:
  /// **'Lower'**
  String get directionDownLabel;

  /// No description provided for @gameStepSkip.
  ///
  /// In en, this message translates to:
  /// **'Step or Skip?'**
  String get gameStepSkip;

  /// No description provided for @gameStepSkipBass.
  ///
  /// In en, this message translates to:
  /// **'Step or Skip? (bass)'**
  String get gameStepSkipBass;

  /// No description provided for @gameStepSkipSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Do the two notes step to a neighbour or skip a gap?'**
  String get gameStepSkipSubtitle;

  /// No description provided for @stepSkipPrompt.
  ///
  /// In en, this message translates to:
  /// **'Does the second note step next door, or skip over a gap?'**
  String get stepSkipPrompt;

  /// No description provided for @stepLabel.
  ///
  /// In en, this message translates to:
  /// **'Step'**
  String get stepLabel;

  /// No description provided for @skipLabel.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skipLabel;

  /// No description provided for @leapLabel.
  ///
  /// In en, this message translates to:
  /// **'Leap'**
  String get leapLabel;

  /// No description provided for @gameArticulation.
  ///
  /// In en, this message translates to:
  /// **'Read the Mark'**
  String get gameArticulation;

  /// No description provided for @gameArticulationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Match the articulation mark on the note to its name'**
  String get gameArticulationSubtitle;

  /// No description provided for @articulationPrompt.
  ///
  /// In en, this message translates to:
  /// **'Which mark is on the note?'**
  String get articulationPrompt;

  /// No description provided for @articulationStaccato.
  ///
  /// In en, this message translates to:
  /// **'Staccato'**
  String get articulationStaccato;

  /// No description provided for @articulationTenuto.
  ///
  /// In en, this message translates to:
  /// **'Tenuto'**
  String get articulationTenuto;

  /// No description provided for @articulationAccent.
  ///
  /// In en, this message translates to:
  /// **'Accent'**
  String get articulationAccent;

  /// No description provided for @articulationMarcato.
  ///
  /// In en, this message translates to:
  /// **'Marcato'**
  String get articulationMarcato;

  /// No description provided for @gameTieSlur.
  ///
  /// In en, this message translates to:
  /// **'Tie or Slur?'**
  String get gameTieSlur;

  /// No description provided for @gameTieSlurSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Same pitch = a tie; different pitches = a slur'**
  String get gameTieSlurSubtitle;

  /// No description provided for @tieSlurPrompt.
  ///
  /// In en, this message translates to:
  /// **'Is the curve a tie or a slur?'**
  String get tieSlurPrompt;

  /// No description provided for @tieLabel.
  ///
  /// In en, this message translates to:
  /// **'Tie'**
  String get tieLabel;

  /// No description provided for @slurLabel.
  ///
  /// In en, this message translates to:
  /// **'Slur'**
  String get slurLabel;

  /// No description provided for @gameBeamFlag.
  ///
  /// In en, this message translates to:
  /// **'Beam or Flag?'**
  String get gameBeamFlag;

  /// No description provided for @gameBeamFlagSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Eighths joined by a beam, or each with its own flag?'**
  String get gameBeamFlagSubtitle;

  /// No description provided for @beamFlagPrompt.
  ///
  /// In en, this message translates to:
  /// **'Are the eighth notes beamed or flagged?'**
  String get beamFlagPrompt;

  /// No description provided for @beamLabel.
  ///
  /// In en, this message translates to:
  /// **'Beam'**
  String get beamLabel;

  /// No description provided for @flagLabel.
  ///
  /// In en, this message translates to:
  /// **'Flag'**
  String get flagLabel;

  /// No description provided for @gameSpotUpbeat.
  ///
  /// In en, this message translates to:
  /// **'Spot the Upbeat'**
  String get gameSpotUpbeat;

  /// No description provided for @gameSpotUpbeatSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Does the tune start on the beat, or with a pickup?'**
  String get gameSpotUpbeatSubtitle;

  /// No description provided for @spotUpbeatPrompt.
  ///
  /// In en, this message translates to:
  /// **'Where does the melody begin?'**
  String get spotUpbeatPrompt;

  /// No description provided for @spotUpbeatUpbeat.
  ///
  /// In en, this message translates to:
  /// **'Upbeat'**
  String get spotUpbeatUpbeat;

  /// No description provided for @spotUpbeatOnBeat.
  ///
  /// In en, this message translates to:
  /// **'On the beat'**
  String get spotUpbeatOnBeat;

  /// No description provided for @gameWhichClef.
  ///
  /// In en, this message translates to:
  /// **'Which Clef?'**
  String get gameWhichClef;

  /// No description provided for @gameWhichClefSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Is it the treble clef or the bass clef? (Alto & tenor at 2★.)'**
  String get gameWhichClefSubtitle;

  /// No description provided for @whichClefPrompt.
  ///
  /// In en, this message translates to:
  /// **'Which clef is this?'**
  String get whichClefPrompt;

  /// No description provided for @trebleClefLabel.
  ///
  /// In en, this message translates to:
  /// **'Treble'**
  String get trebleClefLabel;

  /// No description provided for @bassClefLabel.
  ///
  /// In en, this message translates to:
  /// **'Bass'**
  String get bassClefLabel;

  /// No description provided for @altoClefLabel.
  ///
  /// In en, this message translates to:
  /// **'Alto'**
  String get altoClefLabel;

  /// No description provided for @tenorClefLabel.
  ///
  /// In en, this message translates to:
  /// **'Tenor'**
  String get tenorClefLabel;

  /// No description provided for @gameWholeHalf.
  ///
  /// In en, this message translates to:
  /// **'Whole or Half Step?'**
  String get gameWholeHalf;

  /// No description provided for @gameWholeHalfSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Two neighbour notes — a whole step (tone) or a half step (semitone)?'**
  String get gameWholeHalfSubtitle;

  /// No description provided for @wholeHalfPrompt.
  ///
  /// In en, this message translates to:
  /// **'Is the gap a whole step or a half step?'**
  String get wholeHalfPrompt;

  /// No description provided for @wholeStepLabel.
  ///
  /// In en, this message translates to:
  /// **'Whole step'**
  String get wholeStepLabel;

  /// No description provided for @halfStepLabel.
  ///
  /// In en, this message translates to:
  /// **'Half step'**
  String get halfStepLabel;

  /// No description provided for @gameSameDiff.
  ///
  /// In en, this message translates to:
  /// **'Same or Different?'**
  String get gameSameDiff;

  /// No description provided for @gameSameDiffSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Two notes play — are they the same pitch or different?'**
  String get gameSameDiffSubtitle;

  /// No description provided for @sameDiffPrompt.
  ///
  /// In en, this message translates to:
  /// **'Are the two notes the same, or different?'**
  String get sameDiffPrompt;

  /// No description provided for @sameLabel.
  ///
  /// In en, this message translates to:
  /// **'Same'**
  String get sameLabel;

  /// No description provided for @differentLabel.
  ///
  /// In en, this message translates to:
  /// **'Different'**
  String get differentLabel;

  /// No description provided for @gameDottedSort.
  ///
  /// In en, this message translates to:
  /// **'Dotted or Not?'**
  String get gameDottedSort;

  /// No description provided for @gameDottedSortSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sort the notes — does it carry a dot (half again as long)?'**
  String get gameDottedSortSubtitle;

  /// No description provided for @dottedSortPrompt.
  ///
  /// In en, this message translates to:
  /// **'Drag each note: does it have a dot?'**
  String get dottedSortPrompt;

  /// No description provided for @dottedLabel.
  ///
  /// In en, this message translates to:
  /// **'Dotted'**
  String get dottedLabel;

  /// No description provided for @plainLabel.
  ///
  /// In en, this message translates to:
  /// **'Plain'**
  String get plainLabel;

  /// No description provided for @gameRunDirection.
  ///
  /// In en, this message translates to:
  /// **'Ascending or Descending?'**
  String get gameRunDirection;

  /// No description provided for @gameRunDirectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A little run of notes plays — does it climb up or step down?'**
  String get gameRunDirectionSubtitle;

  /// No description provided for @runDirectionPrompt.
  ///
  /// In en, this message translates to:
  /// **'Does the run go up or down?'**
  String get runDirectionPrompt;

  /// No description provided for @gameCountNotes.
  ///
  /// In en, this message translates to:
  /// **'Count the Notes'**
  String get gameCountNotes;

  /// No description provided for @gameCountNotesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Listen closely — how many notes did you hear?'**
  String get gameCountNotesSubtitle;

  /// No description provided for @countNotesPrompt.
  ///
  /// In en, this message translates to:
  /// **'How many notes did you hear?'**
  String get countNotesPrompt;

  /// No description provided for @ascendingLabel.
  ///
  /// In en, this message translates to:
  /// **'Ascending'**
  String get ascendingLabel;

  /// No description provided for @descendingLabel.
  ///
  /// In en, this message translates to:
  /// **'Descending'**
  String get descendingLabel;

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

  /// No description provided for @gameGridComposer.
  ///
  /// In en, this message translates to:
  /// **'Colour Melody'**
  String get gameGridComposer;

  /// No description provided for @gameGridComposerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap colours to build a tune — no reading needed'**
  String get gameGridComposerSubtitle;

  /// No description provided for @gridComposerPrompt.
  ///
  /// In en, this message translates to:
  /// **'Tap the colours to make a tune!'**
  String get gridComposerPrompt;

  /// No description provided for @gameMelodyDoodle.
  ///
  /// In en, this message translates to:
  /// **'Melody doodle'**
  String get gameMelodyDoodle;

  /// No description provided for @gameMelodyDoodleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Draw a line and hear it as a tune'**
  String get gameMelodyDoodleSubtitle;

  /// No description provided for @melodyDoodlePrompt.
  ///
  /// In en, this message translates to:
  /// **'Drag a line across the box — higher is higher!'**
  String get melodyDoodlePrompt;

  /// No description provided for @gridComposerPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get gridComposerPlay;

  /// No description provided for @gridComposerClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get gridComposerClear;

  /// No description provided for @gameLoopMixer.
  ///
  /// In en, this message translates to:
  /// **'Loop Mixer'**
  String get gameLoopMixer;

  /// No description provided for @gameLoopMixerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Layer looping grooves — you are the band'**
  String get gameLoopMixerSubtitle;

  /// No description provided for @loopMixerPrompt.
  ///
  /// In en, this message translates to:
  /// **'Tap the cards to start your band!'**
  String get loopMixerPrompt;

  /// No description provided for @loopMixerStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get loopMixerStop;

  /// No description provided for @loopMixerSwing.
  ///
  /// In en, this message translates to:
  /// **'Swing'**
  String get loopMixerSwing;

  /// No description provided for @loopMixerHarmony.
  ///
  /// In en, this message translates to:
  /// **'Harmony'**
  String get loopMixerHarmony;

  /// No description provided for @loopMixerHarmonyOff.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get loopMixerHarmonyOff;

  /// No description provided for @loopMixerScore.
  ///
  /// In en, this message translates to:
  /// **'Show as sheet music'**
  String get loopMixerScore;

  /// No description provided for @loopMixerShare.
  ///
  /// In en, this message translates to:
  /// **'Share your groove'**
  String get loopMixerShare;

  /// No description provided for @loopMixerCopyCode.
  ///
  /// In en, this message translates to:
  /// **'Copy groove code'**
  String get loopMixerCopyCode;

  /// No description provided for @loopMixerPasteCode.
  ///
  /// In en, this message translates to:
  /// **'Paste a groove code'**
  String get loopMixerPasteCode;

  /// No description provided for @loopMixerCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Groove code copied — paste it anywhere!'**
  String get loopMixerCodeCopied;

  /// No description provided for @loopMixerCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'That groove code didn\'t work'**
  String get loopMixerCodeInvalid;

  /// No description provided for @loopMixerSaveAudio.
  ///
  /// In en, this message translates to:
  /// **'Save as audio (WAV)'**
  String get loopMixerSaveAudio;

  /// No description provided for @loopMixerSaveSongBook.
  ///
  /// In en, this message translates to:
  /// **'Save to Song Book'**
  String get loopMixerSaveSongBook;

  /// No description provided for @loopMixerExportMusicXml.
  ///
  /// In en, this message translates to:
  /// **'Export sheet music (MusicXML)'**
  String get loopMixerExportMusicXml;

  /// No description provided for @loopMixerSaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Name your groove'**
  String get loopMixerSaveTitle;

  /// No description provided for @loopMixerSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Saving audio isn\'t available here'**
  String get loopMixerSaveFailed;

  /// No description provided for @loopMixerLoad.
  ///
  /// In en, this message translates to:
  /// **'Load'**
  String get loopMixerLoad;

  /// No description provided for @loopMixerInfinite.
  ///
  /// In en, this message translates to:
  /// **'Infinite mode — every loop a little different'**
  String get loopMixerInfinite;

  /// No description provided for @loopMixerSing.
  ///
  /// In en, this message translates to:
  /// **'Sing a track!'**
  String get loopMixerSing;

  /// No description provided for @loopMixerSingAgain.
  ///
  /// In en, this message translates to:
  /// **'Sing your track again'**
  String get loopMixerSingAgain;

  /// No description provided for @loopMixerSingNow.
  ///
  /// In en, this message translates to:
  /// **'Sing now!'**
  String get loopMixerSingNow;

  /// No description provided for @loopMixerSingNothing.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t hear a tune — try again!'**
  String get loopMixerSingNothing;

  /// No description provided for @loopMixerTrackVoice.
  ///
  /// In en, this message translates to:
  /// **'My voice'**
  String get loopMixerTrackVoice;

  /// No description provided for @loopMixerBeatbox.
  ///
  /// In en, this message translates to:
  /// **'Beatbox a beat!'**
  String get loopMixerBeatbox;

  /// No description provided for @loopMixerBeatboxAgain.
  ///
  /// In en, this message translates to:
  /// **'Beatbox again'**
  String get loopMixerBeatboxAgain;

  /// No description provided for @loopMixerBeatNow.
  ///
  /// In en, this message translates to:
  /// **'Beatbox now!'**
  String get loopMixerBeatNow;

  /// No description provided for @loopMixerTrackBeat.
  ///
  /// In en, this message translates to:
  /// **'My beat'**
  String get loopMixerTrackBeat;

  /// No description provided for @loopMixerJam.
  ///
  /// In en, this message translates to:
  /// **'Jam along — best with headphones'**
  String get loopMixerJam;

  /// No description provided for @loopMixerJamHint.
  ///
  /// In en, this message translates to:
  /// **'Play or sing along — green fits the chord! Headphones help the mic hear only you.'**
  String get loopMixerJamHint;

  /// No description provided for @loopMixerJamHintAec.
  ///
  /// In en, this message translates to:
  /// **'Play or sing along — the band listens back! Green fits the chord.'**
  String get loopMixerJamHintAec;

  /// No description provided for @loopMixerJamGraded.
  ///
  /// In en, this message translates to:
  /// **'🎧 Band cancelled — this grades you'**
  String get loopMixerJamGraded;

  /// No description provided for @loopMixerJamHeadphones.
  ///
  /// In en, this message translates to:
  /// **'Headphones help the mic hear only you'**
  String get loopMixerJamHeadphones;

  /// No description provided for @loopMixerFollow.
  ///
  /// In en, this message translates to:
  /// **'Follow the melody'**
  String get loopMixerFollow;

  /// No description provided for @loopMixerFollowScore.
  ///
  /// In en, this message translates to:
  /// **'🎯 Melody match: {pct}%'**
  String loopMixerFollowScore(int pct);

  /// No description provided for @loopMixerTempoChill.
  ///
  /// In en, this message translates to:
  /// **'Chill'**
  String get loopMixerTempoChill;

  /// No description provided for @loopMixerTempoGroove.
  ///
  /// In en, this message translates to:
  /// **'Groove'**
  String get loopMixerTempoGroove;

  /// No description provided for @loopMixerTempoFast.
  ///
  /// In en, this message translates to:
  /// **'Fast'**
  String get loopMixerTempoFast;

  /// No description provided for @loopMixerTrackDrums.
  ///
  /// In en, this message translates to:
  /// **'Drums'**
  String get loopMixerTrackDrums;

  /// No description provided for @loopMixerTrackBass.
  ///
  /// In en, this message translates to:
  /// **'Bass'**
  String get loopMixerTrackBass;

  /// No description provided for @loopMixerTrackChords.
  ///
  /// In en, this message translates to:
  /// **'Chords'**
  String get loopMixerTrackChords;

  /// No description provided for @loopMixerTrackMelody.
  ///
  /// In en, this message translates to:
  /// **'Melody'**
  String get loopMixerTrackMelody;

  /// No description provided for @loopMixerTrackSparkle.
  ///
  /// In en, this message translates to:
  /// **'Sparkle'**
  String get loopMixerTrackSparkle;

  /// No description provided for @gameTracker.
  ///
  /// In en, this message translates to:
  /// **'Tracker'**
  String get gameTracker;

  /// No description provided for @gameTrackerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Build a looping beat, track by track'**
  String get gameTrackerSubtitle;

  /// No description provided for @trackerPrompt.
  ///
  /// In en, this message translates to:
  /// **'Pick an instrument, then tap to build your loop!'**
  String get trackerPrompt;

  /// No description provided for @trackerClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get trackerClear;

  /// No description provided for @trackerChannelMelody.
  ///
  /// In en, this message translates to:
  /// **'Melody'**
  String get trackerChannelMelody;

  /// No description provided for @trackerChannelSparkle.
  ///
  /// In en, this message translates to:
  /// **'Sparkle'**
  String get trackerChannelSparkle;

  /// No description provided for @trackerChannelZap.
  ///
  /// In en, this message translates to:
  /// **'Zap'**
  String get trackerChannelZap;

  /// No description provided for @trackerChannelBass.
  ///
  /// In en, this message translates to:
  /// **'Bass'**
  String get trackerChannelBass;

  /// No description provided for @trackerChannelDrums.
  ///
  /// In en, this message translates to:
  /// **'Drums'**
  String get trackerChannelDrums;

  /// No description provided for @trackerChannelVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get trackerChannelVoice;

  /// No description provided for @trackerToggleNotation.
  ///
  /// In en, this message translates to:
  /// **'Show notation'**
  String get trackerToggleNotation;

  /// No description provided for @trackerImportTune.
  ///
  /// In en, this message translates to:
  /// **'Load a tune'**
  String get trackerImportTune;

  /// No description provided for @trackerDemoTune.
  ///
  /// In en, this message translates to:
  /// **'Simple tune (C D E G)'**
  String get trackerDemoTune;

  /// No description provided for @trackerChangeInstrument.
  ///
  /// In en, this message translates to:
  /// **'Change instrument'**
  String get trackerChangeInstrument;

  /// No description provided for @trackerPattern.
  ///
  /// In en, this message translates to:
  /// **'Pattern'**
  String get trackerPattern;

  /// No description provided for @trackerSong.
  ///
  /// In en, this message translates to:
  /// **'Song'**
  String get trackerSong;

  /// No description provided for @trackerPlaySong.
  ///
  /// In en, this message translates to:
  /// **'Play song'**
  String get trackerPlaySong;

  /// No description provided for @trackerSoftNote.
  ///
  /// In en, this message translates to:
  /// **'Soft note'**
  String get trackerSoftNote;

  /// No description provided for @trackerEffect.
  ///
  /// In en, this message translates to:
  /// **'Effect'**
  String get trackerEffect;

  /// No description provided for @trackerEffectNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get trackerEffectNone;

  /// No description provided for @trackerEffectArp.
  ///
  /// In en, this message translates to:
  /// **'Arpeggio'**
  String get trackerEffectArp;

  /// No description provided for @trackerEffectVibrato.
  ///
  /// In en, this message translates to:
  /// **'Vibrato'**
  String get trackerEffectVibrato;

  /// No description provided for @trackerEffectSlideUp.
  ///
  /// In en, this message translates to:
  /// **'Slide up'**
  String get trackerEffectSlideUp;

  /// No description provided for @trackerEffectSlideDown.
  ///
  /// In en, this message translates to:
  /// **'Slide down'**
  String get trackerEffectSlideDown;

  /// No description provided for @trackerImportMod.
  ///
  /// In en, this message translates to:
  /// **'Import .mod…'**
  String get trackerImportMod;

  /// No description provided for @trackerExportMod.
  ///
  /// In en, this message translates to:
  /// **'Export .mod…'**
  String get trackerExportMod;

  /// No description provided for @trackerImportMidi.
  ///
  /// In en, this message translates to:
  /// **'Import MIDI…'**
  String get trackerImportMidi;

  /// No description provided for @trackerExportMidi.
  ///
  /// In en, this message translates to:
  /// **'Export MIDI…'**
  String get trackerExportMidi;

  /// No description provided for @trackerModFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read/write that .mod.'**
  String get trackerModFailed;

  /// No description provided for @trackerBorrowSample.
  ///
  /// In en, this message translates to:
  /// **'Borrow instrument…'**
  String get trackerBorrowSample;

  /// No description provided for @trackerBorrowEmpty.
  ///
  /// In en, this message translates to:
  /// **'That module has no samples to borrow.'**
  String get trackerBorrowEmpty;

  /// No description provided for @trackerSfxrZap.
  ///
  /// In en, this message translates to:
  /// **'Zap'**
  String get trackerSfxrZap;

  /// No description provided for @trackerSfxrBlip.
  ///
  /// In en, this message translates to:
  /// **'Blip'**
  String get trackerSfxrBlip;

  /// No description provided for @trackerSfxrLaser.
  ///
  /// In en, this message translates to:
  /// **'Laser'**
  String get trackerSfxrLaser;

  /// No description provided for @trackerSfxrCoin.
  ///
  /// In en, this message translates to:
  /// **'Coin'**
  String get trackerSfxrCoin;

  /// No description provided for @trackerSfxrExplosion.
  ///
  /// In en, this message translates to:
  /// **'Boom'**
  String get trackerSfxrExplosion;

  /// No description provided for @trackerRecord.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get trackerRecord;

  /// No description provided for @trackerRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording…'**
  String get trackerRecording;

  /// No description provided for @trackerRecordFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t use the microphone.'**
  String get trackerRecordFailed;

  /// No description provided for @trackerRecordPrompt.
  ///
  /// In en, this message translates to:
  /// **'Pick a voice, then record 2 seconds!'**
  String get trackerRecordPrompt;

  /// No description provided for @trackerVoiceNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get trackerVoiceNormal;

  /// No description provided for @trackerVoiceChipmunk.
  ///
  /// In en, this message translates to:
  /// **'Chipmunk'**
  String get trackerVoiceChipmunk;

  /// No description provided for @trackerVoiceMonster.
  ///
  /// In en, this message translates to:
  /// **'Monster'**
  String get trackerVoiceMonster;

  /// No description provided for @trackerVoiceDeep.
  ///
  /// In en, this message translates to:
  /// **'Deep'**
  String get trackerVoiceDeep;

  /// No description provided for @trackerVoiceRobot.
  ///
  /// In en, this message translates to:
  /// **'Robot'**
  String get trackerVoiceRobot;

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

  /// No description provided for @songbooksTitle.
  ///
  /// In en, this message translates to:
  /// **'My songbooks'**
  String get songbooksTitle;

  /// No description provided for @songbookNew.
  ///
  /// In en, this message translates to:
  /// **'New songbook'**
  String get songbookNew;

  /// No description provided for @songbookNameTitle.
  ///
  /// In en, this message translates to:
  /// **'Name the songbook'**
  String get songbookNameTitle;

  /// No description provided for @songbookDefaultName.
  ///
  /// In en, this message translates to:
  /// **'My songbook'**
  String get songbookDefaultName;

  /// No description provided for @songbookRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get songbookRename;

  /// No description provided for @songbookDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete songbook'**
  String get songbookDelete;

  /// No description provided for @songbookAddSongs.
  ///
  /// In en, this message translates to:
  /// **'Add songs'**
  String get songbookAddSongs;

  /// No description provided for @songbookEmpty.
  ///
  /// In en, this message translates to:
  /// **'No songs yet — tap Add songs.'**
  String get songbookEmpty;

  /// No description provided for @songbookNoImports.
  ///
  /// In en, this message translates to:
  /// **'Import or compose a song first, then add it here.'**
  String get songbookNoImports;

  /// No description provided for @songbookRemoveFromBook.
  ///
  /// In en, this message translates to:
  /// **'Remove from songbook'**
  String get songbookRemoveFromBook;

  /// No description provided for @songbookSongCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{empty} =1{1 song} other{{count} songs}}'**
  String songbookSongCount(int count);

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

  /// No description provided for @gameKeyFindBass.
  ///
  /// In en, this message translates to:
  /// **'Find the Key (Bass)'**
  String get gameKeyFindBass;

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

  /// No description provided for @gameInScale.
  ///
  /// In en, this message translates to:
  /// **'In the Scale?'**
  String get gameInScale;

  /// No description provided for @gameInScaleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Does the note belong to C major? Swipe or tap'**
  String get gameInScaleSubtitle;

  /// No description provided for @inScalePrompt.
  ///
  /// In en, this message translates to:
  /// **'Is this note in the C major scale?'**
  String get inScalePrompt;

  /// No description provided for @inScaleLabel.
  ///
  /// In en, this message translates to:
  /// **'In'**
  String get inScaleLabel;

  /// No description provided for @notInScaleLabel.
  ///
  /// In en, this message translates to:
  /// **'Out'**
  String get notInScaleLabel;

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
  /// **'In {key} — which chord is this?'**
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

  /// No description provided for @diminishedLabel.
  ///
  /// In en, this message translates to:
  /// **'Diminished'**
  String get diminishedLabel;

  /// No description provided for @augmentedLabel.
  ///
  /// In en, this message translates to:
  /// **'Augmented'**
  String get augmentedLabel;

  /// No description provided for @listenChordQualityPrompt.
  ///
  /// In en, this message translates to:
  /// **'Listen! Which chord quality is it?'**
  String get listenChordQualityPrompt;

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

  /// No description provided for @intervalFourth.
  ///
  /// In en, this message translates to:
  /// **'Fourth'**
  String get intervalFourth;

  /// No description provided for @intervalFifth.
  ///
  /// In en, this message translates to:
  /// **'Fifth'**
  String get intervalFifth;

  /// No description provided for @intervalSixth.
  ///
  /// In en, this message translates to:
  /// **'Sixth'**
  String get intervalSixth;

  /// No description provided for @intervalOctave.
  ///
  /// In en, this message translates to:
  /// **'Octave'**
  String get intervalOctave;

  /// No description provided for @gameTriadSeventh.
  ///
  /// In en, this message translates to:
  /// **'Triad or Seventh?'**
  String get gameTriadSeventh;

  /// No description provided for @gameTriadSeventhSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hear a chord — three notes, or four with a seventh?'**
  String get gameTriadSeventhSubtitle;

  /// No description provided for @triadSeventhPrompt.
  ///
  /// In en, this message translates to:
  /// **'Triad or seventh chord?'**
  String get triadSeventhPrompt;

  /// No description provided for @triadLabel.
  ///
  /// In en, this message translates to:
  /// **'Triad'**
  String get triadLabel;

  /// No description provided for @seventhLabel.
  ///
  /// In en, this message translates to:
  /// **'Seventh'**
  String get seventhLabel;

  /// No description provided for @gameSingInterval.
  ///
  /// In en, this message translates to:
  /// **'Sing the Interval'**
  String get gameSingInterval;

  /// No description provided for @gameSingIntervalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hear an interval, sing the top note back'**
  String get gameSingIntervalSubtitle;

  /// No description provided for @singIntervalPrompt.
  ///
  /// In en, this message translates to:
  /// **'Sing the top note — a {interval} up!'**
  String singIntervalPrompt(String interval);

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

  /// No description provided for @gameValueOrder.
  ///
  /// In en, this message translates to:
  /// **'Longest First'**
  String get gameValueOrder;

  /// No description provided for @gameValueOrderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Order the note values by length'**
  String get gameValueOrderSubtitle;

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

  /// No description provided for @gameChordChart.
  ///
  /// In en, this message translates to:
  /// **'Chord Chart'**
  String get gameChordChart;

  /// No description provided for @gameChordChartSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read the chord symbol, find its notation'**
  String get gameChordChartSubtitle;

  /// No description provided for @chordChartPrompt.
  ///
  /// In en, this message translates to:
  /// **'Which notation is this chord symbol?'**
  String get chordChartPrompt;

  /// No description provided for @curriculumTitle.
  ///
  /// In en, this message translates to:
  /// **'Topics by grade'**
  String get curriculumTitle;

  /// No description provided for @curriculumTooltip.
  ///
  /// In en, this message translates to:
  /// **'Topics by grade'**
  String get curriculumTooltip;

  /// No description provided for @curSchoolYears.
  ///
  /// In en, this message translates to:
  /// **'By grade'**
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
  /// **'A practice guide — topics arranged by grade, distilled from public school curricula.'**
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

  /// No description provided for @gameStrongBeat.
  ///
  /// In en, this message translates to:
  /// **'Strong Beat?'**
  String get gameStrongBeat;

  /// No description provided for @gameStrongBeatSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Is the marked beat strong or weak?'**
  String get gameStrongBeatSubtitle;

  /// No description provided for @strongBeatPrompt.
  ///
  /// In en, this message translates to:
  /// **'Beat {beat}: is it a strong or a weak beat?'**
  String strongBeatPrompt(int beat);

  /// No description provided for @strongBeatStrong.
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get strongBeatStrong;

  /// No description provided for @strongBeatWeak.
  ///
  /// In en, this message translates to:
  /// **'Weak'**
  String get strongBeatWeak;

  /// No description provided for @strongBeatReplay.
  ///
  /// In en, this message translates to:
  /// **'Hear the beats again'**
  String get strongBeatReplay;

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

  /// No description provided for @gameReadVoice.
  ///
  /// In en, this message translates to:
  /// **'Read the Voice'**
  String get gameReadVoice;

  /// No description provided for @gameReadVoiceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Follow one voice in a chord (Soprano to Bass)'**
  String get gameReadVoiceSubtitle;

  /// No description provided for @readVoicePrompt.
  ///
  /// In en, this message translates to:
  /// **'Which note does the {voice} sing?'**
  String readVoicePrompt(String voice);

  /// No description provided for @readVoiceHear.
  ///
  /// In en, this message translates to:
  /// **'Hear this voice'**
  String get readVoiceHear;

  /// No description provided for @voiceSoprano.
  ///
  /// In en, this message translates to:
  /// **'Soprano'**
  String get voiceSoprano;

  /// No description provided for @voiceAlto.
  ///
  /// In en, this message translates to:
  /// **'Alto'**
  String get voiceAlto;

  /// No description provided for @voiceTenor.
  ///
  /// In en, this message translates to:
  /// **'Tenor'**
  String get voiceTenor;

  /// No description provided for @voiceBass.
  ///
  /// In en, this message translates to:
  /// **'Bass'**
  String get voiceBass;

  /// No description provided for @gameWhichVoice.
  ///
  /// In en, this message translates to:
  /// **'Which Voice?'**
  String get gameWhichVoice;

  /// No description provided for @gameWhichVoiceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The highlighted note — Soprano, Alto, Tenor or Bass?'**
  String get gameWhichVoiceSubtitle;

  /// No description provided for @whichVoicePrompt.
  ///
  /// In en, this message translates to:
  /// **'Which voice sings the highlighted note?'**
  String get whichVoicePrompt;

  /// No description provided for @gameHearVoice.
  ///
  /// In en, this message translates to:
  /// **'Hear the Voice'**
  String get gameHearVoice;

  /// No description provided for @gameHearVoiceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Listen — which voice do you hear alone?'**
  String get gameHearVoiceSubtitle;

  /// No description provided for @hearVoicePrompt.
  ///
  /// In en, this message translates to:
  /// **'The chord plays, then one voice. Which voice was it?'**
  String get hearVoicePrompt;

  /// No description provided for @hearVoiceReplay.
  ///
  /// In en, this message translates to:
  /// **'Play again'**
  String get hearVoiceReplay;

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

  /// No description provided for @gameConnectIntervals.
  ///
  /// In en, this message translates to:
  /// **'Connect the Steps'**
  String get gameConnectIntervals;

  /// No description provided for @gameConnectIntervalsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Count the note-names in each interval and match it to its number'**
  String get gameConnectIntervalsSubtitle;

  /// No description provided for @connectIntervalsPrompt.
  ///
  /// In en, this message translates to:
  /// **'How far apart? Connect each interval to its number!'**
  String get connectIntervalsPrompt;

  /// No description provided for @gameConnectDynamics.
  ///
  /// In en, this message translates to:
  /// **'Connect the Dynamics'**
  String get gameConnectDynamics;

  /// No description provided for @gameConnectDynamicsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Match each dynamic mark to how loud it means (pp = very soft)'**
  String get gameConnectDynamicsSubtitle;

  /// No description provided for @connectDynamicsPrompt.
  ///
  /// In en, this message translates to:
  /// **'How loud? Connect each mark to its meaning!'**
  String get connectDynamicsPrompt;

  /// No description provided for @dynVerySoft.
  ///
  /// In en, this message translates to:
  /// **'very soft'**
  String get dynVerySoft;

  /// No description provided for @dynSoft.
  ///
  /// In en, this message translates to:
  /// **'soft'**
  String get dynSoft;

  /// No description provided for @dynMediumSoft.
  ///
  /// In en, this message translates to:
  /// **'medium soft'**
  String get dynMediumSoft;

  /// No description provided for @dynMediumLoud.
  ///
  /// In en, this message translates to:
  /// **'medium loud'**
  String get dynMediumLoud;

  /// No description provided for @dynLoud.
  ///
  /// In en, this message translates to:
  /// **'loud'**
  String get dynLoud;

  /// No description provided for @dynVeryLoud.
  ///
  /// In en, this message translates to:
  /// **'very loud'**
  String get dynVeryLoud;

  /// No description provided for @gameConnectRests.
  ///
  /// In en, this message translates to:
  /// **'Connect the Rests'**
  String get gameConnectRests;

  /// No description provided for @gameConnectRestsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Match each rest to the note it lasts as long as'**
  String get gameConnectRestsSubtitle;

  /// No description provided for @connectRestsPrompt.
  ///
  /// In en, this message translates to:
  /// **'How long is the silence? Connect each rest to its note!'**
  String get connectRestsPrompt;

  /// No description provided for @gameConnectTempo.
  ///
  /// In en, this message translates to:
  /// **'Connect the Tempo Words'**
  String get gameConnectTempo;

  /// No description provided for @gameConnectTempoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Match each Italian tempo word to its meaning (Largo = very slow)'**
  String get gameConnectTempoSubtitle;

  /// No description provided for @connectTempoPrompt.
  ///
  /// In en, this message translates to:
  /// **'How fast? Connect each tempo word to its meaning!'**
  String get connectTempoPrompt;

  /// No description provided for @tempoVerySlow.
  ///
  /// In en, this message translates to:
  /// **'very slow'**
  String get tempoVerySlow;

  /// No description provided for @tempoSlow.
  ///
  /// In en, this message translates to:
  /// **'slow'**
  String get tempoSlow;

  /// No description provided for @tempoWalking.
  ///
  /// In en, this message translates to:
  /// **'walking pace'**
  String get tempoWalking;

  /// No description provided for @tempoModerate.
  ///
  /// In en, this message translates to:
  /// **'moderate'**
  String get tempoModerate;

  /// No description provided for @tempoFast.
  ///
  /// In en, this message translates to:
  /// **'fast'**
  String get tempoFast;

  /// No description provided for @tempoLively.
  ///
  /// In en, this message translates to:
  /// **'lively'**
  String get tempoLively;

  /// No description provided for @tempoVeryFast.
  ///
  /// In en, this message translates to:
  /// **'very fast'**
  String get tempoVeryFast;

  /// No description provided for @gameConnectBeats.
  ///
  /// In en, this message translates to:
  /// **'Connect the Beats'**
  String get gameConnectBeats;

  /// No description provided for @gameConnectBeatsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Match each note to how many beats it lasts in 4/4 time'**
  String get gameConnectBeatsSubtitle;

  /// No description provided for @connectBeatsPrompt.
  ///
  /// In en, this message translates to:
  /// **'How many beats? Connect each note to its count (in 4/4)!'**
  String get connectBeatsPrompt;

  /// No description provided for @beatCount4.
  ///
  /// In en, this message translates to:
  /// **'4 beats'**
  String get beatCount4;

  /// No description provided for @beatCount2.
  ///
  /// In en, this message translates to:
  /// **'2 beats'**
  String get beatCount2;

  /// No description provided for @beatCount1.
  ///
  /// In en, this message translates to:
  /// **'1 beat'**
  String get beatCount1;

  /// No description provided for @beatCountHalf.
  ///
  /// In en, this message translates to:
  /// **'½ beat'**
  String get beatCountHalf;

  /// No description provided for @beatCountQuarter.
  ///
  /// In en, this message translates to:
  /// **'¼ beat'**
  String get beatCountQuarter;

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

  /// No description provided for @valueOrderPrompt.
  ///
  /// In en, this message translates to:
  /// **'Tap the notes from longest to shortest!'**
  String get valueOrderPrompt;

  /// No description provided for @valueOrderHint.
  ///
  /// In en, this message translates to:
  /// **'Each value plays its length when you tap it.'**
  String get valueOrderHint;

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

  /// No description provided for @soundOnLabel.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get soundOnLabel;

  /// No description provided for @soundOnSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Notes, chords and sound effects (the microphone still works)'**
  String get soundOnSubtitle;

  /// No description provided for @muteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Mute sound'**
  String get muteTooltip;

  /// No description provided for @unmuteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Turn sound on'**
  String get unmuteTooltip;

  /// No description provided for @howToPlayTooltip.
  ///
  /// In en, this message translates to:
  /// **'How to play'**
  String get howToPlayTooltip;

  /// No description provided for @tutorialNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get tutorialNext;

  /// No description provided for @tutorialGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it!'**
  String get tutorialGotIt;

  /// No description provided for @tutorialListen.
  ///
  /// In en, this message translates to:
  /// **'Listen'**
  String get tutorialListen;

  /// No description provided for @primerReadingTitle.
  ///
  /// In en, this message translates to:
  /// **'Reading notes'**
  String get primerReadingTitle;

  /// No description provided for @primerReadingStaff.
  ///
  /// In en, this message translates to:
  /// **'Music is written on five lines called a staff. Notes sit on the lines and in the spaces between them.'**
  String get primerReadingStaff;

  /// No description provided for @primerReadingHigher.
  ///
  /// In en, this message translates to:
  /// **'The higher a note sits on the staff, the higher it sounds. Tap Listen and hear these notes climb!'**
  String get primerReadingHigher;

  /// No description provided for @primerReadingNames.
  ///
  /// In en, this message translates to:
  /// **'Every note has a letter name: A B C D E F G. This one is E — tap Listen to hear it.'**
  String get primerReadingNames;

  /// No description provided for @primerValuesTitle.
  ///
  /// In en, this message translates to:
  /// **'How long is a note?'**
  String get primerValuesTitle;

  /// No description provided for @primerValuesWhole.
  ///
  /// In en, this message translates to:
  /// **'A note\'s shape shows how LONG to hold it. This open oval with no stem is a whole note — a long sound (4 beats).'**
  String get primerValuesWhole;

  /// No description provided for @primerValuesQuarter.
  ///
  /// In en, this message translates to:
  /// **'A filled note with a stem is a quarter note — one short beat. Four quarter notes last as long as one whole note.'**
  String get primerValuesQuarter;

  /// No description provided for @primerValuesRest.
  ///
  /// In en, this message translates to:
  /// **'A rest is a beat of SILENCE. Count it in your head, but don\'t play. Tap Listen to hear a beat of rest.'**
  String get primerValuesRest;

  /// No description provided for @primerMeasuresTitle.
  ///
  /// In en, this message translates to:
  /// **'Filling a measure'**
  String get primerMeasuresTitle;

  /// No description provided for @primerMeasuresBars.
  ///
  /// In en, this message translates to:
  /// **'Music is split into measures (bars) by barlines. A time signature like 4/4 means each measure holds 4 beats.'**
  String get primerMeasuresBars;

  /// No description provided for @primerMeasuresFill.
  ///
  /// In en, this message translates to:
  /// **'Fill each measure so the beats add up. Four quarter notes make 4 beats — one full 4/4 measure.'**
  String get primerMeasuresFill;

  /// No description provided for @primerMeasuresHalf.
  ///
  /// In en, this message translates to:
  /// **'A half note lasts 2 beats, so two half notes also fill a 4/4 measure.'**
  String get primerMeasuresHalf;

  /// No description provided for @primerScalesTitle.
  ///
  /// In en, this message translates to:
  /// **'What is a scale?'**
  String get primerScalesTitle;

  /// No description provided for @primerScalesLadder.
  ///
  /// In en, this message translates to:
  /// **'A scale is a ladder of notes climbing step by step. This is C major: C D E F G A B C.'**
  String get primerScalesLadder;

  /// No description provided for @primerScalesMajor.
  ///
  /// In en, this message translates to:
  /// **'A major scale sounds bright and cheerful. Listen to C major climb up.'**
  String get primerScalesMajor;

  /// No description provided for @primerScalesMinor.
  ///
  /// In en, this message translates to:
  /// **'A minor scale sounds darker, a little sad. Listen to A minor.'**
  String get primerScalesMinor;

  /// No description provided for @primerChordsTitle.
  ///
  /// In en, this message translates to:
  /// **'Building a chord'**
  String get primerChordsTitle;

  /// No description provided for @primerChordsStack.
  ///
  /// In en, this message translates to:
  /// **'A chord is notes played at the SAME time. Stack three notes a gap apart and you get a triad — here, C E G.'**
  String get primerChordsStack;

  /// No description provided for @primerChordsColour.
  ///
  /// In en, this message translates to:
  /// **'A major triad sounds bright; a minor triad sounds softer and sadder. Listen to both.'**
  String get primerChordsColour;

  /// No description provided for @primerChordsArpeggio.
  ///
  /// In en, this message translates to:
  /// **'You can also play a chord one note at a time, bottom to top — that\'s an arpeggio.'**
  String get primerChordsArpeggio;

  /// No description provided for @primerHarmonyTitle.
  ///
  /// In en, this message translates to:
  /// **'Chords have jobs'**
  String get primerHarmonyTitle;

  /// No description provided for @primerHarmonyHome.
  ///
  /// In en, this message translates to:
  /// **'One chord feels like HOME — settled and finished. We call it the Tonic. Listen: this is C major, home base.'**
  String get primerHarmonyHome;

  /// No description provided for @primerHarmonyPull.
  ///
  /// In en, this message translates to:
  /// **'Other chords pull AWAY and want to return home. The Dominant tugs the hardest — hear how it leans right back to home.'**
  String get primerHarmonyPull;

  /// No description provided for @primerHarmonyCadence.
  ///
  /// In en, this message translates to:
  /// **'When chords travel home → away → home, that little journey to a resting point is a cadence. Listen to the whole trip.'**
  String get primerHarmonyCadence;

  /// No description provided for @primerCompositionTitle.
  ///
  /// In en, this message translates to:
  /// **'Make a melody'**
  String get primerCompositionTitle;

  /// No description provided for @primerCompositionJourney.
  ///
  /// In en, this message translates to:
  /// **'A melody is a little journey of notes — some step up, some come down. Hum along as it rises and falls!'**
  String get primerCompositionJourney;

  /// No description provided for @primerCompositionQuestion.
  ///
  /// In en, this message translates to:
  /// **'A tune can ask a QUESTION — it stops high up in the air, sounding unfinished, as if it\'s waiting.'**
  String get primerCompositionQuestion;

  /// No description provided for @primerCompositionAnswer.
  ///
  /// In en, this message translates to:
  /// **'…then it gives an ANSWER, coming back down to rest at home. A question and its answer make a phrase.'**
  String get primerCompositionAnswer;

  /// No description provided for @primerCelloTitle.
  ///
  /// In en, this message translates to:
  /// **'Your four strings'**
  String get primerCelloTitle;

  /// No description provided for @primerCelloStrings.
  ///
  /// In en, this message translates to:
  /// **'The cello has four strings. From low to high they are C, G, D, A — the lowest string is the thickest.'**
  String get primerCelloStrings;

  /// No description provided for @primerCelloBass.
  ///
  /// In en, this message translates to:
  /// **'Cello notes live on the bass clef, the staff for low sounds. This deep note is C, your thickest string.'**
  String get primerCelloBass;

  /// No description provided for @primerCelloFinger.
  ///
  /// In en, this message translates to:
  /// **'Press a finger onto a string to shorten it and the note gets higher. The tuner listens and shows if you\'re spot on.'**
  String get primerCelloFinger;

  /// No description provided for @primerGuitarTitle.
  ///
  /// In en, this message translates to:
  /// **'Six strings and tab'**
  String get primerGuitarTitle;

  /// No description provided for @primerGuitarStrings.
  ///
  /// In en, this message translates to:
  /// **'A guitar has six strings. From low (thick) to high (thin): E, A, D, G, B, E — yes, an E at each end!'**
  String get primerGuitarStrings;

  /// No description provided for @primerGuitarTab.
  ///
  /// In en, this message translates to:
  /// **'Guitar can be written as tab: six lines, one per string. A number is the fret to press; 0 means play the open string.'**
  String get primerGuitarTab;

  /// No description provided for @primerGuitarPlay.
  ///
  /// In en, this message translates to:
  /// **'Play the note shown, or strum along. The thinner the string, the higher it sings — from low E up to high E.'**
  String get primerGuitarPlay;

  /// No description provided for @primerSongsTitle.
  ///
  /// In en, this message translates to:
  /// **'Follow the tune'**
  String get primerSongsTitle;

  /// No description provided for @primerSongsPick.
  ///
  /// In en, this message translates to:
  /// **'Pick a song you know. The screen shows its tune as a line of notes, read left to right.'**
  String get primerSongsPick;

  /// No description provided for @primerSongsMarker.
  ///
  /// In en, this message translates to:
  /// **'A marker slides along the tune. Sing or play each note as it reaches the line — like following a bouncing ball.'**
  String get primerSongsMarker;

  /// No description provided for @primerKeyboardTitle.
  ///
  /// In en, this message translates to:
  /// **'The piano keys'**
  String get primerKeyboardTitle;

  /// No description provided for @primerKeyboardWhite.
  ///
  /// In en, this message translates to:
  /// **'The white keys are named A B C D E F G, repeating up the whole piano. The black keys sit in little groups of two and three.'**
  String get primerKeyboardWhite;

  /// No description provided for @primerKeyboardFindC.
  ///
  /// In en, this message translates to:
  /// **'Find C: it\'s the white key just to the LEFT of every group of TWO black keys. From C, climb up C D E F G A B C.'**
  String get primerKeyboardFindC;

  /// No description provided for @primerKeyboardHands.
  ///
  /// In en, this message translates to:
  /// **'Piano music uses two staves at once: the top staff for your right hand, the bottom staff for your left. Hear both together.'**
  String get primerKeyboardHands;

  /// No description provided for @primerTransposeTitle.
  ///
  /// In en, this message translates to:
  /// **'Read one note, hear another'**
  String get primerTransposeTitle;

  /// No description provided for @primerTransposeSame.
  ///
  /// In en, this message translates to:
  /// **'Most instruments sound the note they read. Read a C, hear a C — simple.'**
  String get primerTransposeSame;

  /// No description provided for @primerTransposeShift.
  ///
  /// In en, this message translates to:
  /// **'But some are ‘transposing’: a trumpet in B♭ reads a C yet a B♭ comes out — a little lower. This game does that swap for you.'**
  String get primerTransposeShift;

  /// No description provided for @primerDrumsTitle.
  ///
  /// In en, this message translates to:
  /// **'Reading drums'**
  String get primerDrumsTitle;

  /// No description provided for @primerDrumsWhat.
  ///
  /// In en, this message translates to:
  /// **'Drums don\'t play high and low tunes — a drum just goes THUMP or TSS. So drum music shows WHICH drum and WHEN, not a pitch.'**
  String get primerDrumsWhat;

  /// No description provided for @primerDrumsLines.
  ///
  /// In en, this message translates to:
  /// **'Each line and space is a different drum: low down is the bass drum you kick, higher up are the snare and cymbals. Read left to right and play the beat.'**
  String get primerDrumsLines;

  /// No description provided for @primerBassTitle.
  ///
  /// In en, this message translates to:
  /// **'The bass clef'**
  String get primerBassTitle;

  /// No description provided for @primerBassClef.
  ///
  /// In en, this message translates to:
  /// **'This low staff is the bass clef (the F-clef). A cello or a left hand reads here. Its lines and spaces spell different notes than the treble clef.'**
  String get primerBassClef;

  /// No description provided for @primerBassMiddleC.
  ///
  /// In en, this message translates to:
  /// **'Middle C — the note in the middle of the piano — sits just above the bass staff, on its own little ledger line.'**
  String get primerBassMiddleC;

  /// No description provided for @primerLedgerTitle.
  ///
  /// In en, this message translates to:
  /// **'Ledger lines'**
  String get primerLedgerTitle;

  /// No description provided for @primerLedgerMiddleC.
  ///
  /// In en, this message translates to:
  /// **'When a note won\'t fit on the five lines, we add a tiny extra line just for it — a ledger line. Middle C hangs on one, right below the treble staff.'**
  String get primerLedgerMiddleC;

  /// No description provided for @primerLedgerHigh.
  ///
  /// In en, this message translates to:
  /// **'The higher a note climbs above the staff, the more ledger lines it needs. Count them like the rungs of a ladder.'**
  String get primerLedgerHigh;

  /// No description provided for @primerAccidentalsTitle.
  ///
  /// In en, this message translates to:
  /// **'Sharps and flats'**
  String get primerAccidentalsTitle;

  /// No description provided for @primerAccidentalsSharp.
  ///
  /// In en, this message translates to:
  /// **'A sharp ♯ in front of a note lifts it up by the smallest step, a semitone. C♯ is a hair higher than C.'**
  String get primerAccidentalsSharp;

  /// No description provided for @primerAccidentalsFlat.
  ///
  /// In en, this message translates to:
  /// **'A flat ♭ lowers a note by a semitone. D♭ is the very same key as C♯ — it just leans down from D.'**
  String get primerAccidentalsFlat;

  /// No description provided for @primerStepSkipTitle.
  ///
  /// In en, this message translates to:
  /// **'Steps and skips'**
  String get primerStepSkipTitle;

  /// No description provided for @primerStepSkipStep.
  ///
  /// In en, this message translates to:
  /// **'A STEP moves to the next-door note — a line to the space touching it, one letter along: C to D.'**
  String get primerStepSkipStep;

  /// No description provided for @primerStepSkipSkip.
  ///
  /// In en, this message translates to:
  /// **'A SKIP jumps over one — a line straight to the next line: C to E. Skips sound bouncier than steps.'**
  String get primerStepSkipSkip;

  /// No description provided for @primerIntervalsTitle.
  ///
  /// In en, this message translates to:
  /// **'How far apart?'**
  String get primerIntervalsTitle;

  /// No description provided for @primerIntervalsCount.
  ///
  /// In en, this message translates to:
  /// **'The distance between two notes is an interval. Count the letters including both ends: C to E is C-D-E — a 3rd.'**
  String get primerIntervalsCount;

  /// No description provided for @primerIntervalsWide.
  ///
  /// In en, this message translates to:
  /// **'The wider the gap, the bigger the number. C up to G is a 5th: C-D-E-F-G.'**
  String get primerIntervalsWide;

  /// No description provided for @primerIntervalsEar.
  ///
  /// In en, this message translates to:
  /// **'Narrow intervals sound close and gentle; wide ones sound open and bold. Listen to a small gap, then a big one.'**
  String get primerIntervalsEar;

  /// No description provided for @primerKeySigTitle.
  ///
  /// In en, this message translates to:
  /// **'Key signatures'**
  String get primerKeySigTitle;

  /// No description provided for @primerKeySigWhat.
  ///
  /// In en, this message translates to:
  /// **'Instead of marking every sharp, we write them once at the very start — a key signature. It applies to the whole piece. This is G major: one sharp, F♯.'**
  String get primerKeySigWhat;

  /// No description provided for @primerKeySigCompare.
  ///
  /// In en, this message translates to:
  /// **'C major has no sharps or flats at all. Listen to C major — every note is a plain white key.'**
  String get primerKeySigCompare;

  /// No description provided for @primerTimeSigTitle.
  ///
  /// In en, this message translates to:
  /// **'Time signatures'**
  String get primerTimeSigTitle;

  /// No description provided for @primerTimeSigFour.
  ///
  /// In en, this message translates to:
  /// **'The two numbers at the start are the time signature. The top number is how many beats fill each measure — 4 means a steady four.'**
  String get primerTimeSigFour;

  /// No description provided for @primerTimeSigThree.
  ///
  /// In en, this message translates to:
  /// **'Change the top number to 3 and each measure has three beats — the gentle swing of a waltz. Count 1-2-3, 1-2-3.'**
  String get primerTimeSigThree;

  /// No description provided for @primerChartTitle.
  ///
  /// In en, this message translates to:
  /// **'Chord symbols'**
  String get primerChartTitle;

  /// No description provided for @primerChartMajor.
  ///
  /// In en, this message translates to:
  /// **'Above a tune you\'ll see chord symbols. A plain letter means a major chord: ‘C’ tells you to play a C major chord.'**
  String get primerChartMajor;

  /// No description provided for @primerChartMinor.
  ///
  /// In en, this message translates to:
  /// **'A small ‘m’ after the letter means minor: ‘Am’ is A minor — the same family, but a softer, sadder colour.'**
  String get primerChartMinor;

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

  /// No description provided for @handwrittenNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Handwritten notes'**
  String get handwrittenNotesLabel;

  /// No description provided for @handwrittenNotesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Draw notation in a hand-written jazz style (Petaluma)'**
  String get handwrittenNotesSubtitle;

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

  /// No description provided for @gameFreeSing.
  ///
  /// In en, this message translates to:
  /// **'Free Sing'**
  String get gameFreeSing;

  /// No description provided for @gameFreeSingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sing a tune and hear it back'**
  String get gameFreeSingSubtitle;

  /// No description provided for @freeSingPrompt.
  ///
  /// In en, this message translates to:
  /// **'Sing a tune…'**
  String get freeSingPrompt;

  /// No description provided for @freeSingRecord.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get freeSingRecord;

  /// No description provided for @freeSingCaptured.
  ///
  /// In en, this message translates to:
  /// **'{count} notes captured'**
  String freeSingCaptured(int count);

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

  /// No description provided for @tunerReference.
  ///
  /// In en, this message translates to:
  /// **'Reference pitch'**
  String get tunerReference;

  /// No description provided for @tunerInstrument.
  ///
  /// In en, this message translates to:
  /// **'Instrument'**
  String get tunerInstrument;

  /// No description provided for @tunerInstrumentChromatic.
  ///
  /// In en, this message translates to:
  /// **'Chromatic'**
  String get tunerInstrumentChromatic;

  /// No description provided for @tunerInstrumentCello.
  ///
  /// In en, this message translates to:
  /// **'Cello'**
  String get tunerInstrumentCello;

  /// No description provided for @tunerInstrumentGuitar.
  ///
  /// In en, this message translates to:
  /// **'Guitar'**
  String get tunerInstrumentGuitar;

  /// No description provided for @tunerInstrumentViolin.
  ///
  /// In en, this message translates to:
  /// **'Violin'**
  String get tunerInstrumentViolin;

  /// No description provided for @tunerPickString.
  ///
  /// In en, this message translates to:
  /// **'Tap a string to tune it'**
  String get tunerPickString;

  /// No description provided for @tunerTuneString.
  ///
  /// In en, this message translates to:
  /// **'Tune the {string} string'**
  String tunerTuneString(String string);

  /// No description provided for @tunerStringInTune.
  ///
  /// In en, this message translates to:
  /// **'In tune!'**
  String get tunerStringInTune;

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

  /// No description provided for @playAlongLoopHint.
  ///
  /// In en, this message translates to:
  /// **'Tap two notes to loop that section'**
  String get playAlongLoopHint;

  /// No description provided for @playAlongLoopEnd.
  ///
  /// In en, this message translates to:
  /// **'Now tap the last note of the loop'**
  String get playAlongLoopEnd;

  /// No description provided for @playAlongLooping.
  ///
  /// In en, this message translates to:
  /// **'Looping this section — tap a note to clear'**
  String get playAlongLooping;

  /// No description provided for @playAlongMarkFlat.
  ///
  /// In en, this message translates to:
  /// **'flat'**
  String get playAlongMarkFlat;

  /// No description provided for @playAlongMarkSharp.
  ///
  /// In en, this message translates to:
  /// **'sharp'**
  String get playAlongMarkSharp;

  /// No description provided for @playAlongMarkMiss.
  ///
  /// In en, this message translates to:
  /// **'missed'**
  String get playAlongMarkMiss;

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

  /// No description provided for @playAlongDifficulty.
  ///
  /// In en, this message translates to:
  /// **'Difficulty'**
  String get playAlongDifficulty;

  /// No description provided for @playAlongDifficultyEasy.
  ///
  /// In en, this message translates to:
  /// **'Easy'**
  String get playAlongDifficultyEasy;

  /// No description provided for @playAlongDifficultyMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get playAlongDifficultyMedium;

  /// No description provided for @playAlongDifficultyHard.
  ///
  /// In en, this message translates to:
  /// **'Hard'**
  String get playAlongDifficultyHard;

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
