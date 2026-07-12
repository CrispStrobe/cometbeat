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
  String get advancedGameHint =>
      'Für Fortgeschrittene! Hol dir zuerst 2 Sterne in den anderen Cello-Ecke-Spielen.';

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
      'Was du am häufigsten verpasst — Lesen, Rhythmus, Akkorde und mehr. Die Wiederholung übt das zuerst.';

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
  String get workshopTitle => 'Werkstatt';

  @override
  String get workshopComposeTitle => 'Kompositions-Werkstatt';

  @override
  String get workshopTimeSignature => 'Takt';

  @override
  String get workshopHint =>
      'Wähle einen Notenwert und tippe ins System, um deine Melodie zu schreiben.';

  @override
  String get workshopEditHint =>
      'Tippe ins System, um die Note zu verschieben, oder lösche sie.';

  @override
  String get workshopDelete => 'Löschen';

  @override
  String get instrumentLabel => 'Instrumentenklang';

  @override
  String get instrumentPiano => 'Klavier';

  @override
  String get instrumentCello => 'Cello';

  @override
  String get instrumentFlute => 'Flöte';

  @override
  String get instrumentMusicBox => 'Spieluhr';

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
  String get celloStringPrompt => 'Welche leere Saite ist das?';

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
      'Schreibe deine Melodie — tippe die Linien oder ein Instrument!';

  @override
  String get inputStaff => 'Noten';

  @override
  String get inputPiano => 'Klavier';

  @override
  String get inputGuitar => 'Gitarre';

  @override
  String get inputCello => 'Cello';

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
  String scaleDetectivePromptMinor(String name) {
    return 'Tippe auf den falschen Ton in der $name-Moll-Tonleiter!';
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
  String get gameEchoSequence => 'Ton-Echo';

  @override
  String get gameEchoSequenceSubtitle => 'Zusehen, zuhören, dann nachspielen';

  @override
  String get echoWatch => 'Schau und hör zu…';

  @override
  String get echoRepeat => 'Du bist dran — spiel es nach!';

  @override
  String echoLength(int count) {
    return 'Länge: $count';
  }

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
  String scaleBuilderPromptMinor(String name) {
    return 'Baue die $name-Moll-Tonleiter — tippe auf den nächsten Ton!';
  }

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
  String get rhythmTapPrompt => 'Klopfe den Rhythmus — halte die langen Noten!';

  @override
  String get tapHere => 'Klopf hier!';

  @override
  String get rhythmTapHold => 'Halten…';

  @override
  String get gameBeatCount => 'Schläge zählen';

  @override
  String get gameBeatCountSubtitle =>
      'Punkte und Bögen zählen mit — wie lang ist das?';

  @override
  String get gameBeatSort => 'Schläge sortieren';

  @override
  String get gameBeatSortSubtitle => 'Ziehe jede Note in ihren Schläge-Korb';

  @override
  String get beatSortPrompt => 'Ziehe jede Note in den richtigen Korb!';

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
  String get gameNoteMemory => 'Noten-Memory';

  @override
  String get gameNoteMemorySubtitle => 'Memory: Noten und ihre Namen zuordnen';

  @override
  String get gameNoteOrder => 'Der Reihe nach';

  @override
  String get gameNoteOrderSubtitle => 'Tippe die Noten von tief nach hoch';

  @override
  String get gameOddOneOut => 'Wer passt nicht?';

  @override
  String get gameOddOneOutSubtitle =>
      'Zwei Noten heißen gleich — tippe die andere';

  @override
  String get oddOneOutPrompt => 'Welche Note passt nicht dazu?';

  @override
  String get oddOneOutHint =>
      'Zwei Noten haben denselben Notennamen. Tippe die andere!';

  @override
  String get gameNoteWhack => 'Noten klopfen';

  @override
  String get gameNoteWhackSubtitle =>
      'Klopfe die Noten mit dem genannten Namen';

  @override
  String get noteWhackPrompt => 'Klopfe:';

  @override
  String get noteWhackHint =>
      'Tippe jede passende Note — ein falscher Schlag kostet ein Herz!';

  @override
  String get clefBass => 'Bassschlüssel';

  @override
  String get gameLineSpace => 'Linie oder Zwischenraum?';

  @override
  String get gameLineSpaceSubtitle => 'Wische: Linie oder Zwischenraum?';

  @override
  String get gameFallingNotes => 'Notenregen';

  @override
  String get gameFallingNotesSubtitle => 'Benenne die Noten, bevor sie landen!';

  @override
  String get gameConnectLine => 'Noten verbinden';

  @override
  String get gameConnectLineSubtitle =>
      'Ziehe eine Linie von jeder Note zu ihrem Namen';

  @override
  String get connectLinePrompt => 'Verbinde jede Note mit ihrem Namen!';

  @override
  String get gameLedgerLeap => 'Hilfslinien zählen';

  @override
  String get gameLedgerLeapSubtitle =>
      'Zähle die kleinen Hilfslinien über oder unter dem Notensystem';

  @override
  String get ledgerLeapPrompt => 'Wie viele Hilfslinien?';

  @override
  String get gameFallingKeys => 'Fallende Tasten';

  @override
  String get gameFallingKeysSubtitle =>
      'Spiele jede fallende Note auf dem Klavier, bevor sie landet!';

  @override
  String get gameConnectSymbols => 'Symbole verbinden';

  @override
  String get gameConnectSymbolsSubtitle =>
      'Ziehe eine Linie von jedem Notenwert zu seinem Namen';

  @override
  String get connectSymbolsPrompt => 'Verbinde jedes Symbol mit seinem Namen!';

  @override
  String get gameCommandCaller => 'Der Dirigent';

  @override
  String get gameCommandCallerSubtitle =>
      'Mach die Bewegung, die der Dirigent ansagt!';

  @override
  String get commandCallerHint =>
      'Tippen, halten oder wischen — bevor der Balken leer ist!';

  @override
  String get conductorPrompt => 'Folge dem Takt des Dirigenten!';

  @override
  String get commandTap => 'Tippen!';

  @override
  String get commandHold => 'Halten!';

  @override
  String get commandSwipeLeft => 'Nach links wischen!';

  @override
  String get commandSwipeRight => 'Nach rechts wischen!';

  @override
  String get commandSwipeUp => 'Nach oben wischen!';

  @override
  String get commandSwipeDown => 'Nach unten wischen!';

  @override
  String get gameKeySignature => 'Tonart-Detektiv';

  @override
  String get gameKeySignatureSubtitle => 'Lies die Vorzeichen — welche Tonart?';

  @override
  String get keySignaturePrompt => 'Welche Dur-Tonart ist das?';

  @override
  String keyMajorLabel(String name) {
    return '$name-Dur';
  }

  @override
  String get gameBeatRunner => 'Im Takt';

  @override
  String get gameBeatRunnerSubtitle =>
      'Tippe im Takt, wenn die Schläge die Linie erreichen!';

  @override
  String get beatRunnerHint => 'Tippe auf den Schlag!';

  @override
  String get beatPerfect => 'Perfekt!';

  @override
  String get beatGood => 'Gut!';

  @override
  String get beatMiss => 'Daneben';

  @override
  String get fallingSpeedUp => 'Schneller!';

  @override
  String fallingMultiplier(int mult) {
    return '×$mult';
  }

  @override
  String get lineSpacePrompt => 'Wische ← Linie   oder   Zwischenraum →';

  @override
  String get lineLabel => 'Linie';

  @override
  String get spaceLabel => 'Zwischenr.';

  @override
  String get noteOrderPrompt => 'Tippe die Noten von tief nach hoch!';

  @override
  String get noteOrderHint => 'Jede Note klingt, wenn du sie antippst.';

  @override
  String get noteMemoryPrompt => 'Finde die Paare: eine Note und ihr Name!';

  @override
  String noteMemoryMoves(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Züge',
      one: '1 Zug',
    );
    return '$_temp0';
  }

  @override
  String get melodyDictationPrompt =>
      'Die erste Note ist da — ergänze die, die du hörst';

  @override
  String get dictationUndo => 'Zurück';

  @override
  String get whatIsThisSymbol => 'Wie heißt dieses Zeichen?';

  @override
  String get hearLength => 'Länge anhören';

  @override
  String get countAlong => 'Mitzählen';

  @override
  String get halfBeat => '½ Schlag';

  @override
  String get quarterBeat => '¼ Schlag';

  @override
  String beatsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Schläge',
      one: '1 Schlag',
    );
    return '$_temp0';
  }

  @override
  String symbolLength(String name, String length) {
    return '$name dauert $length';
  }

  @override
  String symbolLengthRest(String name, String length) {
    return '$name: $length Pause';
  }

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
