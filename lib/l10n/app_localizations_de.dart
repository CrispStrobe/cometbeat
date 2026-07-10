// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'KlangUniversum';

  @override
  String get homeTagline => 'Entdecke das Universum der Musik!';

  @override
  String get moduleNoteValues => 'Notenwerte';

  @override
  String get moduleNoteValuesSubtitle =>
      'Ganze, halbe, Viertel — wie lange klingt eine Note?';

  @override
  String get moduleNoteReading => 'Noten lesen';

  @override
  String get moduleNoteReadingSubtitle =>
      'Violin- und Bassschlüssel — welche Note ist das?';

  @override
  String get moduleMeasures => 'Takte';

  @override
  String get moduleMeasuresSubtitle => 'Fülle den Takt, bis alles aufgeht';

  @override
  String get moduleScales => 'Tonleitern';

  @override
  String get moduleScalesSubtitle => 'Dur und Moll, Schritt für Schritt';

  @override
  String get moduleChords => 'Akkorde & Intervalle';

  @override
  String get moduleChordsSubtitle => 'Baue Dreiklänge und trainiere dein Gehör';

  @override
  String get moduleHarmony => 'Harmonik';

  @override
  String get moduleHarmonySubtitle => 'Tonika, Subdominante, Dominante';

  @override
  String get comingSoon => 'Kommt bald!';

  @override
  String get locked => 'Gesperrt';

  @override
  String get reviewTitle => 'Wiederholen';

  @override
  String dueForReview(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Aufgaben zum Wiederholen',
      one: '1 Aufgabe zum Wiederholen',
      zero: 'Nichts zu wiederholen',
    );
    return '$_temp0';
  }

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get progressTitle => 'Fortschritt';

  @override
  String get karteikastenTitle => 'Karteikasten';

  @override
  String get moduleProgressTitle => 'Module';

  @override
  String get boxNew => 'Neu';

  @override
  String get boxMastered => 'Gemeistert';

  @override
  String masteredOfTracked(int mastered, int tracked) {
    return '$mastered von $tracked gemeistert';
  }

  @override
  String get languageLabel => 'Sprache';

  @override
  String get systemDefault => 'Systemstandard';

  @override
  String get statsTitle => 'Lernstatistik';

  @override
  String get statsTracked => 'Erfasste Aufgaben';

  @override
  String get statsLearning => 'Noch am Lernen';

  @override
  String get gameNoteValueQuiz => 'Zeichen-Quiz';

  @override
  String get gameNoteValueQuizSubtitle => 'Welche Note oder Pause ist das?';

  @override
  String get gameDurationDuel => 'Dauer-Duell';

  @override
  String get gameDurationDuelSubtitle =>
      'Tippe auf das Zeichen, das länger dauert';

  @override
  String get whichLastsLonger => 'Was dauert länger?';

  @override
  String get gameNoteReadingTreble => 'Violinschlüssel';

  @override
  String get gameNoteReadingBass => 'Bassschlüssel';

  @override
  String get gameNoteReadingSubtitle => 'Wie heißt die Note auf den Linien?';

  @override
  String get whatIsThisNote => 'Wie heißt diese Note?';

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
  String get noteNameB => 'H';

  @override
  String get gamePlaceNoteTreble => 'Setz die Note (Violinschlüssel)';

  @override
  String get gamePlaceNoteBass => 'Setz die Note (Bassschlüssel)';

  @override
  String get gamePlaceNoteSubtitle =>
      'Tippe auf die richtige Linie oder den Zwischenraum';

  @override
  String placeNotePrompt(String name) {
    return 'Setze die Note $name!';
  }

  @override
  String get gameMeasureFill => 'Takt-Füller';

  @override
  String get gameMeasureFillSubtitle => 'Fülle den Takt, bis alles aufgeht';

  @override
  String get measureFillPrompt => 'Welche Note macht den Takt voll?';

  @override
  String get gameScaleDetective => 'Tonleiter-Detektiv';

  @override
  String get gameScaleDetectiveSubtitle => 'Finde den Ton, der nicht passt';

  @override
  String scaleDetectivePrompt(String name) {
    return 'Tippe auf den falschen Ton in der $name-Dur-Tonleiter!';
  }

  @override
  String get gameChordQuiz => 'Akkord-Quiz';

  @override
  String get gameChordQuizSubtitle => 'Wie heißt der Akkord auf den Linien?';

  @override
  String get chordQuizPrompt => 'Welcher Akkord ist das?';

  @override
  String majorChordName(String name) {
    return '$name-Dur';
  }

  @override
  String get gameHarmonyQuiz => 'Funktions-Quiz';

  @override
  String get gameHarmonyQuizSubtitle => 'Tonika, Subdominante oder Dominante?';

  @override
  String harmonyPrompt(String key) {
    return 'Welche Funktion hat dieser Akkord in $key?';
  }

  @override
  String keyMajorName(String name) {
    return '$name-Dur';
  }

  @override
  String get harmonicTonic => 'Tonika';

  @override
  String get harmonicSubdominant => 'Subdominante';

  @override
  String get harmonicDominant => 'Dominante';

  @override
  String get whatIsThisSymbol => 'Wie heißt dieses Zeichen?';

  @override
  String roundOf(int current, int total) {
    return 'Runde $current von $total';
  }

  @override
  String get feedbackCorrect => 'Richtig!';

  @override
  String get feedbackTryAgain => 'Ups — versuch es nochmal!';

  @override
  String resultScore(int score) {
    return 'Punkte: $score';
  }

  @override
  String get playAgain => 'Nochmal spielen';

  @override
  String get backButton => 'Zurück';

  @override
  String get wholeNote => 'Ganze Note';

  @override
  String get halfNote => 'Halbe Note';

  @override
  String get quarterNote => 'Viertelnote';

  @override
  String get eighthNote => 'Achtelnote';

  @override
  String get sixteenthNote => 'Sechzehntelnote';

  @override
  String get wholeRest => 'Ganze Pause';

  @override
  String get halfRest => 'Halbe Pause';

  @override
  String get quarterRest => 'Viertelpause';

  @override
  String get eighthRest => 'Achtelpause';

  @override
  String get sixteenthRest => 'Sechzehntelpause';
}
