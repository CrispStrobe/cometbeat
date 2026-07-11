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
  String unlockHint(String module) {
    return 'Spiele zuerst $module, um das freizuschalten!';
  }

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
  String get trickyNotesTitle => 'Deine kniffligen Stellen';

  @override
  String get trickyNotesHint =>
      'Was du am häufigsten verpasst — die Wiederholung übt das zuerst.';

  @override
  String trickyMissed(int count) {
    return '$count× verpasst';
  }

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
  String get noteNamingLabel => 'Notennamen';

  @override
  String get noteNamingAuto => 'Der Sprache folgen';

  @override
  String get noteNamingGerman => 'Deutsch (C D E F G A H)';

  @override
  String get noteNamingEnglish => 'Englisch (C D E F G A B)';

  @override
  String get noteNamingSolfege => 'Solfège (Do Re Mi Fa Sol La Si)';

  @override
  String streakDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage in Folge',
      one: '1 Tag in Folge',
    );
    return '$_temp0';
  }

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
  String get gameNoteReadingTenor => 'Tenorschlüssel';

  @override
  String get gameNoteReadingAlto => 'Altschlüssel';

  @override
  String get gameNoteReadingSubtitle => 'Wie heißt die Note auf den Linien?';

  @override
  String get moduleGuitar => 'Gitarren-Ecke';

  @override
  String get moduleGuitarSubtitle => 'Tabulatur lesen und die Saiten lernen';

  @override
  String get gameGuitarStringQuiz => 'Leere Saiten';

  @override
  String get gameGuitarStringQuizSubtitle =>
      'Benenne die leere Saite (E A D G H E)';

  @override
  String get guitarStringPrompt => 'Welche Note ist diese leere Saite?';

  @override
  String get gameGuitarTabRead => 'Tabulatur lesen';

  @override
  String get gameGuitarTabReadSubtitle => 'Welche Note spielt dieser Bund?';

  @override
  String get guitarTabReadPrompt => 'Welche Note ist das?';

  @override
  String get moduleCello => 'Cello-Ecke';

  @override
  String get moduleCelloSubtitle =>
      'Saiten, Finger und Schlüssel für junge Cellisten';

  @override
  String get gameCelloStringQuiz => 'Welche Saite?';

  @override
  String get gameCelloStringQuizSubtitle => 'Finde die richtige Cello-Saite';

  @override
  String get celloStringPrompt => 'Auf welcher Saite spielst du diese Note?';

  @override
  String get gameCelloFingerQuiz => 'Finger-Quiz';

  @override
  String get gameCelloFingerQuizSubtitle => 'Erste Lage: welcher Finger?';

  @override
  String get moduleComposition => 'Komponieren';

  @override
  String get moduleCompositionSubtitle =>
      'Schlüsse, Phrasen — und eigene Melodien';

  @override
  String get gameEndingDetective => 'Schluss-Detektiv';

  @override
  String get gameEndingDetectiveSubtitle => 'Klingt die Melodie fertig?';

  @override
  String get endingDetectivePrompt => 'Hör zu! Klingt diese Melodie fertig?';

  @override
  String get soundsFinished => 'Fertig!';

  @override
  String get soundsOpen => 'Noch nicht...';

  @override
  String get gameQuestionAnswer => 'Frage & Antwort';

  @override
  String get gameQuestionAnswerSubtitle => 'Finde die passende Antwort-Phrase';

  @override
  String get questionAnswerPrompt =>
      'Die Melodie stellt eine Frage — welche Antwort macht sie fertig?';

  @override
  String get gameMyMelody => 'Meine Melodie';

  @override
  String get gameMyMelodySubtitle =>
      'Komponiere und spiele deine eigene Melodie';

  @override
  String get myMelodyPrompt =>
      'Tippe auf die Linien und schreibe deine Melodie!';

  @override
  String get myMelodyFull => 'Deine Melodie ist voll — spiel sie ab!';

  @override
  String get myMelodyPlay => 'Abspielen';

  @override
  String get myMelodyUndo => 'Rückgängig';

  @override
  String get myMelodyClear => 'Löschen';

  @override
  String get myMelodySave => 'Speichern';

  @override
  String get myMelodySaveTitle => 'Benenne deine Melodie';

  @override
  String get myMelodyDefaultName => 'Meine Melodie';

  @override
  String get myMelodySaved => 'Im Liederbuch gespeichert!';

  @override
  String get moduleSongs => 'Liederbuch';

  @override
  String get moduleSongsSubtitle => 'Echte Lieder — lesen, hören, mitsingen';

  @override
  String get gameSongBook => 'Liederbuch';

  @override
  String get gameSongBookSubtitle => 'Ganze Lieder mit Text und Mitlese-Cursor';

  @override
  String get songStop => 'Stopp';

  @override
  String get importTitle => 'Lieder importieren';

  @override
  String get importTitleField => 'Titel (optional)';

  @override
  String get importHint =>
      'Füge hier MusicXML (aus MuseScore & Co.) oder ChordPro (Text mit [C]-Akkorden) ein — oder wähle unten eine einfache MIDI-Datei.';

  @override
  String get importAsMusicXml => 'Als MusicXML importieren';

  @override
  String get importAsChordPro => 'Als ChordPro importieren';

  @override
  String get importMidiFile => 'MIDI-Datei wählen…';

  @override
  String get importMusicXmlFile => 'MusicXML-Datei wählen…';

  @override
  String get importDone => 'Importiert!';

  @override
  String importFailed(String error) {
    return 'Import fehlgeschlagen: $error';
  }

  @override
  String get importedSongs => 'Meine importierten Lieder';

  @override
  String get chordSheets => 'Akkord-Blätter';

  @override
  String get gameTuneQuiz => 'Lieder-Quiz';

  @override
  String get gameTuneQuizSubtitle => 'Erkenne das Lied am Anfang';

  @override
  String get tuneQuizPrompt => 'Hör zu! Welches Lied fängt so an?';

  @override
  String get moduleKeyboard => 'Tasten-Ecke';

  @override
  String get moduleKeyboardSubtitle =>
      'Finde dich auf den Klaviertasten zurecht';

  @override
  String get gameKeyFind => 'Taste finden';

  @override
  String get gameKeyFindSubtitle => 'Von der Note zur Taste';

  @override
  String get keyFindPrompt => 'Tippe auf die Taste für diese Note!';

  @override
  String get gameKeyName => 'Tasten-Quiz';

  @override
  String get gameKeyNameSubtitle => 'Welche Taste ist markiert?';

  @override
  String get keyNamePrompt => 'Wie heißt die markierte Taste?';

  @override
  String get gameKeyEar => 'Echo-Tasten';

  @override
  String get gameKeyEarSubtitle => 'Spiel nach, was du hörst';

  @override
  String get keyEarPrompt =>
      'Zuerst hörst du C, dann den Rätselton — tippe ihn!';

  @override
  String get gameKeyMelody => 'Melodie spielen';

  @override
  String get gameKeyMelodySubtitle => 'Lies die Noten, spiel die Tasten';

  @override
  String get keyMelodyPrompt => 'Spiele diese Noten der Reihe nach!';

  @override
  String get gameKeyChord => 'Akkord-Griff';

  @override
  String get gameKeyChordSubtitle => 'Greife alle drei Töne des Akkords';

  @override
  String get gameGrandStaffRead => 'Klaviersystem';

  @override
  String get gameGrandStaffReadSubtitle => 'Noten in beiden Schlüsseln lesen';

  @override
  String keyChordPrompt(String name) {
    return 'Spiele den $name-Dur-Akkord — tippe alle drei Tasten!';
  }

  @override
  String celloFingerPrompt(String string) {
    return 'Welcher Finger spielt sie auf der $string-Saite?';
  }

  @override
  String get whatIsThisNote => 'Wie heißt diese Note?';

  @override
  String get hintButton => 'Brauchst du einen Tipp?';

  @override
  String readingHintSame(String name) {
    return 'Das ist $name — eine Merknote!';
  }

  @override
  String readingHintStepUp(String name) {
    return 'Einen Schritt über $name';
  }

  @override
  String readingHintStepDown(String name) {
    return 'Einen Schritt unter $name';
  }

  @override
  String readingHintSkipUp(String name) {
    return 'Einen Sprung über $name';
  }

  @override
  String readingHintSkipDown(String name) {
    return 'Einen Sprung unter $name';
  }

  @override
  String readingHintFarUp(int count, String name) {
    return '$count Schritte über $name';
  }

  @override
  String readingHintFarDown(int count, String name) {
    return '$count Schritte unter $name';
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
  String get gameFunctionEar => 'Funktion hören';

  @override
  String get gameFunctionEarSubtitle =>
      'Tonika, Subdominante oder Dominante heraushören';

  @override
  String functionEarPrompt(String key) {
    return 'Höre die Grundakkorde in $key, dann benenne den letzten';
  }

  @override
  String get functionEarReplayHint =>
      'Erst die Tonart, dann den Akkord nochmal hören';

  @override
  String get functionEarTargetAgain => 'Nur der Akkord';

  @override
  String get gameMajorMinorEar => 'Dur oder Moll?';

  @override
  String get gameMajorMinorEarSubtitle => 'Hör genau hin und entscheide';

  @override
  String get listenMajorMinorPrompt => 'Hör zu! Klingt das nach Dur oder Moll?';

  @override
  String get listenAgain => 'Nochmal anhören';

  @override
  String get majorLabel => 'Dur';

  @override
  String get minorLabel => 'Moll';

  @override
  String get gameIntervalEar => 'Intervall-Detektiv';

  @override
  String get gameIntervalEarSubtitle =>
      'Wie weit liegen zwei Töne auseinander?';

  @override
  String get listenIntervalPrompt => 'Hör zu! Welches Intervall ist das?';

  @override
  String get intervalSecond => 'Sekunde';

  @override
  String get intervalThird => 'Terz';

  @override
  String get intervalFifth => 'Quinte';

  @override
  String get intervalOctave => 'Oktave';

  @override
  String get gameTriadBuilder => 'Dreiklang-Baumeister';

  @override
  String get gameTriadBuilderSubtitle => 'Baue den Akkord auf den Linien';

  @override
  String triadBuilderPrompt(String name) {
    return 'Baue den $name-Dur-Dreiklang!';
  }

  @override
  String get gameScaleBuilder => 'Tonleiter-Baumeister';

  @override
  String get gameScaleBuilderSubtitle =>
      'Baue die Tonleiter Schritt für Schritt';

  @override
  String scaleBuilderPrompt(String name) {
    return 'Baue die $name-Dur-Tonleiter — tippe auf den nächsten Ton!';
  }

  @override
  String get gameCadenceWorkshop => 'Kadenzen-Werkstatt';

  @override
  String get gameCadenceWorkshopSubtitle => 'Baue Kadenzen: T–S–D–T';

  @override
  String cadencePrompt(String function, String key) {
    return 'Tippe auf die $function in $key!';
  }

  @override
  String get gameRhythmTap => 'Rhythmus-Echo';

  @override
  String get gameRhythmTapSubtitle => 'Hör zu und klopfe nach';

  @override
  String get rhythmTapPrompt => 'Hör zu und klopfe den Rhythmus nach!';

  @override
  String get tapHere => 'Klopf hier!';

  @override
  String get gameBeatCount => 'Schläge zählen';

  @override
  String get gameBeatCountSubtitle =>
      'Punkte und Bögen zählen mit — wie lang ist das?';

  @override
  String get beatCountPrompt => 'Wie viele Schläge dauert das? (♩ = 1)';

  @override
  String get gameMeterDetective => 'Takt-Detektiv';

  @override
  String get gameMeterDetectiveSubtitle => 'Marsch oder Walzer? Spür den Takt';

  @override
  String get meterDetectivePrompt =>
      'Hör zu! Wie viele Schläge hat jeder Takt?';

  @override
  String get gameMelodyEcho => 'Melodie-Echo';

  @override
  String get gameMelodyEchoSubtitle => 'Finde die Melodie, die du gehört hast';

  @override
  String get melodyEchoPrompt => 'Hör zu! Welche Melodie war das?';

  @override
  String get gameMelodyDictation => 'Melodie-Diktat';

  @override
  String get gameMelodyDictationSubtitle =>
      'Hören, dann ins Notensystem schreiben';

  @override
  String get melodyDictationPrompt =>
      'Die erste Note ist da — ergänze die, die du hörst';

  @override
  String get dictationUndo => 'Zurück';

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
  String resultTime(String time) {
    return 'Deine Zeit: $time';
  }

  @override
  String resultBest(String time) {
    return 'Bestzeit: $time';
  }

  @override
  String get resultNewBest => 'Neue Bestzeit! 🎉';

  @override
  String get showTimerLabel => 'Zeit anzeigen';

  @override
  String get colorScaffoldLabel => 'Farbhilfe für Anfänger';

  @override
  String get colorScaffoldSubtitle =>
      'Noten nach ihrem Buchstaben einfärben — später einfach ausschalten';

  @override
  String get debugModeEnabled => 'Debug-Einstellungen freigeschaltet!';

  @override
  String get debugSectionTitle => 'Debug';

  @override
  String get debugUnlockLabel => 'Alle Spiele freischalten';

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
