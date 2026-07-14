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
  String get workshopRest => 'Pause';

  @override
  String get workshopRedo => 'Wiederherstellen';

  @override
  String get workshopDot => 'Punktiert';

  @override
  String get workshopAccidental => 'Vorzeichen';

  @override
  String get workshopKey => 'Tonart';

  @override
  String get workshopSelectPrev => 'Vorherige auswählen';

  @override
  String get workshopSelectNext => 'Nächste auswählen';

  @override
  String get workshopUp => 'Einen Halbton höher';

  @override
  String get workshopDown => 'Einen Halbton tiefer';

  @override
  String get workshopReady => 'Wähle einen Wert und tippe eine Note';

  @override
  String get workshopTapStaff => 'Tippe ins System, um eine Note zu setzen';

  @override
  String get workshopScoreSettings => 'Noteneinstellungen';

  @override
  String get workshopClef => 'Schlüssel';

  @override
  String get workshopZoomIn => 'Vergrößern';

  @override
  String get workshopZoomOut => 'Verkleinern';

  @override
  String get workshopExportXml => 'MusicXML exportieren';

  @override
  String get workshopExportSvg => 'SVG exportieren (Druck)';

  @override
  String get workshopExportImage => 'Bild exportieren (PNG)';

  @override
  String get workshopExportedImage => 'Bild gespeichert';

  @override
  String get workshopMarquee => 'Noten auswählen (Gummiband)';

  @override
  String get workshopCut => 'Ausschneiden';

  @override
  String get workshopPaste => 'Einfügen';

  @override
  String get workshopMoveLeft => 'Nach links';

  @override
  String get workshopMoveRight => 'Nach rechts';

  @override
  String get workshopExtendLeft => 'Auswahl nach links';

  @override
  String get workshopExtendRight => 'Auswahl nach rechts';

  @override
  String workshopSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ausgewählt',
      one: '1 ausgewählt',
    );
    return '$_temp0';
  }

  @override
  String get workshopArticulations => 'Artikulation & Bindebögen';

  @override
  String get workshopStaccato => 'Staccato';

  @override
  String get workshopTenuto => 'Tenuto';

  @override
  String get workshopAccent => 'Akzent';

  @override
  String get workshopMarcato => 'Marcato';

  @override
  String get workshopFermata => 'Fermate';

  @override
  String get workshopTie => 'Bindebogen';

  @override
  String get workshopDynamics => 'Dynamik';

  @override
  String get workshopDynamicNone => 'Keine';

  @override
  String get workshopChord => 'Akkord (Töne stapeln)';

  @override
  String get workshopSlur => 'Legatobogen (Auswahl phrasieren)';

  @override
  String get workshopCrescendo => 'Crescendo (lauter werden)';

  @override
  String get workshopDiminuendo => 'Diminuendo (leiser werden)';

  @override
  String get workshopPickup => 'Auftakt';

  @override
  String get workshopPickupNone => 'Kein Auftakt';

  @override
  String get workshopLyric => 'Liedtext';

  @override
  String get workshopLyricHint => 'Silbe…';

  @override
  String get workshopLyricVerse => 'Strophe';

  @override
  String get workshopShortcuts => 'Tastenkürzel';

  @override
  String get workshopShortcutPlaceNote => 'Note setzen (ihre Tonhöhe)';

  @override
  String get workshopShortcutNoteValue => 'Notenwert (ganze … Sechzehntel)';

  @override
  String get workshopShortcutSelect => 'Vorherige / nächste auswählen';

  @override
  String get workshopShortcutTranspose => 'Tonhöhe hoch / runter';

  @override
  String get workshopShortcutUndoRedo => 'Rückgängig / Wiederholen';

  @override
  String get workshopShortcutCopyPaste => 'Kopieren / ausschneiden / einfügen';

  @override
  String get workshopExitTitle => 'Werkstatt verlassen?';

  @override
  String get workshopExitMessage =>
      'Deine Partitur hat ungespeicherte Änderungen.';

  @override
  String get workshopKeepEditing => 'Weiter bearbeiten';

  @override
  String get workshopDiscard => 'Verwerfen';

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
  String get gamePitchSort => 'Hoch oder tief?';

  @override
  String get gamePitchSortSubtitle =>
      'Zieh jede Note in den hohen oder tiefen Korb';

  @override
  String get pitchSortPrompt =>
      'Ist jede Note hoch oder tief? Zieh sie in den richtigen Korb!';

  @override
  String get pitchHighLabel => 'Hoch';

  @override
  String get pitchLowLabel => 'Tief';

  @override
  String get gameAccidentalSort => 'Kreuz oder B?';

  @override
  String get gameAccidentalSortSubtitle =>
      'Zieh jede Note in den Kreuz- oder B-Korb';

  @override
  String get accidentalSortPrompt =>
      'Hat die Note ein Kreuz oder ein B? Zieh sie in den richtigen Korb!';

  @override
  String get accidentalSharpLabel => 'Kreuz';

  @override
  String get accidentalFlatLabel => 'B';

  @override
  String get gameDirectionEar => 'Höher oder tiefer?';

  @override
  String get gameDirectionEarSubtitle =>
      'Hör hin: geht die zweite Note hoch oder runter?';

  @override
  String get directionEarPrompt =>
      'Zwei Töne erklingen. Ist der zweite höher oder tiefer?';

  @override
  String get directionUpLabel => 'Höher';

  @override
  String get directionDownLabel => 'Tiefer';

  @override
  String get gameStepSkip => 'Schritt oder Sprung?';

  @override
  String get gameStepSkipSubtitle =>
      'Gehen die zwei Noten zum Nachbarn oder springen sie?';

  @override
  String get stepSkipPrompt =>
      'Geht die zweite Note zum Nachbarn, oder springt sie über eine Lücke?';

  @override
  String get stepLabel => 'Schritt';

  @override
  String get skipLabel => 'Sprung';

  @override
  String get gameWhichClef => 'Welcher Schlüssel?';

  @override
  String get gameWhichClefSubtitle =>
      'Violin- oder Bassschlüssel? (Alt & Tenor ab 2★.)';

  @override
  String get whichClefPrompt => 'Welcher Notenschlüssel ist das?';

  @override
  String get trebleClefLabel => 'Violin';

  @override
  String get bassClefLabel => 'Bass';

  @override
  String get altoClefLabel => 'Alt';

  @override
  String get tenorClefLabel => 'Tenor';

  @override
  String get gameWholeHalf => 'Ganz- oder Halbton?';

  @override
  String get gameWholeHalfSubtitle =>
      'Zwei Nachbarnoten — ein Ganzton oder ein Halbton?';

  @override
  String get wholeHalfPrompt => 'Ist der Abstand ein Ganzton oder ein Halbton?';

  @override
  String get wholeStepLabel => 'Ganzton';

  @override
  String get halfStepLabel => 'Halbton';

  @override
  String get gameSameDiff => 'Gleich oder anders?';

  @override
  String get gameSameDiffSubtitle =>
      'Zwei Töne erklingen — gleicher Ton oder verschieden?';

  @override
  String get sameDiffPrompt => 'Sind die zwei Töne gleich oder verschieden?';

  @override
  String get sameLabel => 'Gleich';

  @override
  String get differentLabel => 'Anders';

  @override
  String get gameDottedSort => 'Mit oder ohne Punkt?';

  @override
  String get gameDottedSortSubtitle =>
      'Sortiere die Noten — trägt sie einen Punkt (halb so lang dazu)?';

  @override
  String get dottedSortPrompt => 'Zieh jede Note: hat sie einen Punkt?';

  @override
  String get dottedLabel => 'Punktiert';

  @override
  String get plainLabel => 'Ohne Punkt';

  @override
  String get gameRunDirection => 'Aufsteigend oder absteigend?';

  @override
  String get gameRunDirectionSubtitle =>
      'Eine kleine Tonfolge erklingt — steigt sie auf oder ab?';

  @override
  String get runDirectionPrompt => 'Geht die Tonfolge aufwärts oder abwärts?';

  @override
  String get ascendingLabel => 'Aufsteigend';

  @override
  String get descendingLabel => 'Absteigend';

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
  String get importAsAbc => 'Als ABC importieren';

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
  String get songbooksTitle => 'Meine Liederbücher';

  @override
  String get songbookNew => 'Neues Liederbuch';

  @override
  String get songbookNameTitle => 'Benenne das Liederbuch';

  @override
  String get songbookDefaultName => 'Mein Liederbuch';

  @override
  String get songbookRename => 'Umbenennen';

  @override
  String get songbookDelete => 'Liederbuch löschen';

  @override
  String get songbookAddSongs => 'Lieder hinzufügen';

  @override
  String get songbookEmpty =>
      'Noch keine Lieder — tippe auf „Lieder hinzufügen“.';

  @override
  String get songbookNoImports =>
      'Importiere oder komponiere zuerst ein Lied, dann füge es hier hinzu.';

  @override
  String get songbookRemoveFromBook => 'Aus dem Liederbuch entfernen';

  @override
  String songbookSongCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Lieder',
      one: '1 Lied',
      zero: 'leer',
    );
    return '$_temp0';
  }

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
  String get gameInScale => 'In der Tonleiter?';

  @override
  String get gameInScaleSubtitle =>
      'Gehört der Ton zu C-Dur? Wische oder tippe';

  @override
  String get inScalePrompt => 'Ist dieser Ton in der C-Dur-Tonleiter?';

  @override
  String get inScaleLabel => 'Drin';

  @override
  String get notInScaleLabel => 'Raus';

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
  String get gameRomanNumeral => 'Stufen-Quiz';

  @override
  String get gameRomanNumeralSubtitle =>
      'Welche Akkordstufe ist das? (I, IV, V …)';

  @override
  String romanNumeralPrompt(String key) {
    return 'In $key — welcher Akkord ist das?';
  }

  @override
  String get romanNumeralReplay => 'Akkord nochmal hören';

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
  String get gameValueOrder => 'Von lang nach kurz';

  @override
  String get gameValueOrderSubtitle => 'Ordne die Notenwerte nach ihrer Länge';

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
  String get gameCharades => 'Schnell oder laut?';

  @override
  String get gameCharadesSubtitle => 'Benenne Tempo oder Dynamik, die du hörst';

  @override
  String get charadesTempoPrompt => 'Wie schnell ist es?';

  @override
  String get charadesDynamicsPrompt => 'Wie laut ist es?';

  @override
  String get gameIntervalLadder => 'Intervall-Leiter';

  @override
  String get gameIntervalLadderSubtitle =>
      'Steige das Intervall von der Basisnote';

  @override
  String get intervalLadderPrompt => 'Tippe die Note, auf die der Pfeil zeigt!';

  @override
  String get intervalLadderHint =>
      '▲ hoch, ▼ runter. Die Zahl ist das Intervall (3 = Terz).';

  @override
  String get gameStaffRunner => 'Noten-Sprint';

  @override
  String get gameStaffRunnerSubtitle => 'Benenne Noten, bevor die Zeit abläuft';

  @override
  String get gameChordGripHero => 'Akkord-Griff-Held';

  @override
  String get gameChordGripHeroSubtitle =>
      'Drücke alle Akkordtasten, bevor er landet';

  @override
  String get chordGripHint => 'Drücke jede leuchtende Taste!';

  @override
  String get gameNoteSnake => 'Noten-Schlange';

  @override
  String get gameNoteSnakeSubtitle => 'Lenke die Schlange zur passenden Note';

  @override
  String get noteSnakePrompt => 'Friss diese Note:';

  @override
  String get recitalTitle => 'Vorspiel';

  @override
  String get recitalTooltip => 'Ein Vorspiel spielen';

  @override
  String recitalProgress(int done, int total) {
    return '$done von $total Stücken gespielt';
  }

  @override
  String get recitalCurtainCall => 'Bravo!';

  @override
  String get recitalDone => 'Verbeugen';

  @override
  String get gameStrumToy => 'Zupf-Spaß';

  @override
  String get gameStrumToySubtitle => 'Wähle einen Akkord und jamme frei';

  @override
  String get strumToyHint =>
      'Wische über die Saiten zum Schrammeln oder tippe eine zum Zupfen.';

  @override
  String get gameNameThatChord => 'Akkord benennen';

  @override
  String get gameNameThatChordSubtitle =>
      'Lies oder höre einen Akkord, wähle sein Symbol';

  @override
  String get nameThatChordPrompt => 'Welcher Akkord ist das?';

  @override
  String get gameChordChart => 'Akkord-Symbole';

  @override
  String get gameChordChartSubtitle => 'Lies das Akkordsymbol, finde die Noten';

  @override
  String get chordChartPrompt => 'Welche Noten gehören zu diesem Akkordsymbol?';

  @override
  String get curriculumTitle => 'Themen nach Klasse';

  @override
  String get curriculumTooltip => 'Themen nach Klasse';

  @override
  String get curSchoolYears => 'Nach Klasse';

  @override
  String get curLevelGrades12 => 'Klasse 1–2';

  @override
  String get curLevelGrades34 => 'Klasse 3–4';

  @override
  String get curLevelGrades56 => 'Klasse 5–6';

  @override
  String get curLevelGrades78 => 'Klasse 7–8';

  @override
  String get curLevelGrades910 => 'Klasse 9–10';

  @override
  String get curTopicNoteReading => 'Noten lesen';

  @override
  String get curTopicNoteValues => 'Notenwerte & Rhythmus';

  @override
  String get curTopicMeter => 'Takt & Taktarten';

  @override
  String get curTopicDynamics => 'Dynamik & Tempo';

  @override
  String get curTopicScales => 'Tonleitern & Tonarten';

  @override
  String get curTopicIntervals => 'Intervalle';

  @override
  String get curTopicChords => 'Akkorde';

  @override
  String get curTopicHarmony => 'Harmonik & Kadenzen';

  @override
  String get curTopicTransposition => 'Transposition';

  @override
  String get curTopicEar => 'Gehörbildung';

  @override
  String get curTopicSightReading => 'Blattlesen';

  @override
  String curReadiness(int pct) {
    return '$pct% bereit';
  }

  @override
  String get curPracticeLevel => 'Diese Stufe üben';

  @override
  String get curContinueHere => 'Hier weiter';

  @override
  String get curPractiseWeakest => 'Schwächstes Thema üben';

  @override
  String get curTopicsHeader => 'Themen';

  @override
  String get curGuideNote =>
      'Ein Übungsleitfaden — Themen nach Klasse, zusammengestellt aus öffentlichen Lehrplänen.';

  @override
  String get curNoGames => 'Noch keine Spiele für dieses Thema';

  @override
  String get gameChordBuilder => 'Akkord bauen';

  @override
  String get gameChordBuilderSubtitle => 'Baue den Akkord — jede Lage zählt';

  @override
  String chordBuilderPrompt(String chord) {
    return 'Baue einen $chord-Akkord';
  }

  @override
  String get chordBuilderHint =>
      'Tippe drei Noten auf das System. Jede Oktave oder Umkehrung zählt.';

  @override
  String get chordBuilderClear => 'Löschen';

  @override
  String get chordBuilderCheck => 'Prüfen';

  @override
  String get moduleTranspose => 'Transponieren';

  @override
  String get moduleTransposeSubtitle => 'Notiert vs. klingend';

  @override
  String get gameConcertPitch => 'Klingende Note';

  @override
  String get gameConcertPitchSubtitle =>
      'Benenne die Note, die wirklich klingt';

  @override
  String concertPitchPrompt(String instrument) {
    return 'Eine $instrument liest diese Note. Was klingt?';
  }

  @override
  String get concertPitchHint =>
      'Ein transponierendes Instrument klingt anders als notiert.';

  @override
  String get concertInstrumentBb => 'B-Trompete';

  @override
  String get concertInstrumentEb => 'Es-Altsax';

  @override
  String get concertInstrumentF => 'F-Horn';

  @override
  String get gameBowing => 'Bogenstrich';

  @override
  String get gameBowingSubtitle => 'Lies Auf- und Abstrich-Zeichen';

  @override
  String get bowingPrompt => 'Welcher Bogenstrich ist markiert?';

  @override
  String get bowDown => 'Abstrich';

  @override
  String get bowUp => 'Aufstrich';

  @override
  String get gameWhichBeat => 'Welche Zählzeit?';

  @override
  String get gameWhichBeatSubtitle => 'Tippe die Zählzeit der farbigen Note';

  @override
  String get whichBeatPrompt => 'Auf welche Zählzeit fällt die farbige Note?';

  @override
  String get gameStrongBeat => 'Starke Zählzeit?';

  @override
  String get gameStrongBeatSubtitle =>
      'Ist die markierte Zählzeit betont oder unbetont?';

  @override
  String strongBeatPrompt(int beat) {
    return 'Zählzeit $beat: betont oder unbetont?';
  }

  @override
  String get strongBeatStrong => 'Betont';

  @override
  String get strongBeatWeak => 'Unbetont';

  @override
  String get strongBeatReplay => 'Zählzeiten nochmal hören';

  @override
  String get workshopExportAbc => 'ABC exportieren';

  @override
  String get workshopCopy => 'Kopieren';

  @override
  String get workshopCopied => 'ABC in die Zwischenablage kopiert';

  @override
  String get gameTimeSignature => 'Taktarten';

  @override
  String get gameTimeSignatureSubtitle =>
      'Lies die Taktart (auch C und Alla breve)';

  @override
  String get timeSignaturePrompt => 'Wie viele Zählzeiten hat ein Takt?';

  @override
  String get gameDuet => 'Duett';

  @override
  String get gameDuetSubtitle => 'Lies die markierte Stimme im Zweiersystem';

  @override
  String get duetPrompt => 'Benenne die markierte Note';

  @override
  String get gameReadVoice => 'Stimmen lesen';

  @override
  String get gameReadVoiceSubtitle =>
      'Verfolge eine Stimme im Akkord (Sopran bis Bass)';

  @override
  String readVoicePrompt(String voice) {
    return 'Welche Note singt der $voice?';
  }

  @override
  String get readVoiceHear => 'Diese Stimme hören';

  @override
  String get voiceSoprano => 'Sopran';

  @override
  String get voiceAlto => 'Alt';

  @override
  String get voiceTenor => 'Tenor';

  @override
  String get voiceBass => 'Bass';

  @override
  String get gameWhichVoice => 'Welche Stimme?';

  @override
  String get gameWhichVoiceSubtitle =>
      'Die markierte Note — Sopran, Alt, Tenor oder Bass?';

  @override
  String get whichVoicePrompt => 'Welche Stimme singt die markierte Note?';

  @override
  String get gameHearVoice => 'Stimme hören';

  @override
  String get gameHearVoiceSubtitle => 'Hör zu — welche Stimme hörst du allein?';

  @override
  String get hearVoicePrompt =>
      'Der Akkord klingt, dann eine Stimme. Welche war es?';

  @override
  String get hearVoiceReplay => 'Nochmal abspielen';

  @override
  String get gamePerformIt => 'Spiel es!';

  @override
  String get gamePerformItSubtitle =>
      'Spiele oder singe die Note, die du siehst';

  @override
  String get performItPrompt => 'Spiele oder singe diese Note!';

  @override
  String get performItOnTarget => 'Getroffen!';

  @override
  String get performItSkip => 'Überspringen';

  @override
  String get gameSingBack => 'Sing nach';

  @override
  String get gameSingBackSubtitle => 'Höre eine Note und singe sie nach';

  @override
  String get singBackPrompt => 'Singe die Note, die du gehört hast!';

  @override
  String get singBackListen => 'Nochmal hören';

  @override
  String get gameCelloPlayIt => 'Spiel es!';

  @override
  String get gameCelloPlayItSubtitle =>
      'Spiele die Note auf deinem echten Cello — das Mikro hört zu';

  @override
  String get celloPlayItPrompt => 'Spiele diese Note auf deinem Cello!';

  @override
  String celloPlayItOpenString(String string) {
    return '$string-Saite — leer';
  }

  @override
  String celloPlayItFingered(String string, int finger) {
    return '$string-Saite — Finger $finger';
  }

  @override
  String get moduleDrums => 'Schlagzeug';

  @override
  String get moduleDrumsSubtitle => 'Rhythmen lesen und spielen';

  @override
  String get gameDrumRead => 'Trommeln lesen';

  @override
  String get gameDrumReadSubtitle =>
      'Lies den Rhythmus und tippe ihn auf der Trommel';

  @override
  String get drumReadHint =>
      'Tippe die Trommel bei jeder Note, im Takt des Klicks.';

  @override
  String get drumReadGo => 'Los!';

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
  String get gameConnectIntervals => 'Schritte verbinden';

  @override
  String get gameConnectIntervalsSubtitle =>
      'Zähle die Notennamen in jedem Intervall und verbinde es mit seiner Zahl';

  @override
  String get connectIntervalsPrompt =>
      'Wie weit? Verbinde jedes Intervall mit seiner Zahl!';

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
  String get valueOrderPrompt => 'Tippe die Noten von lang nach kurz!';

  @override
  String get valueOrderHint =>
      'Jeder Wert klingt in seiner Länge, wenn du ihn antippst.';

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
  String get soundOnLabel => 'Ton';

  @override
  String get soundOnSubtitle =>
      'Noten, Akkorde und Klangeffekte (das Mikrofon bleibt an)';

  @override
  String get muteTooltip => 'Ton aus';

  @override
  String get unmuteTooltip => 'Ton an';

  @override
  String get howToPlayTooltip => 'Spielhilfe';

  @override
  String get tutorialNext => 'Weiter';

  @override
  String get tutorialGotIt => 'Verstanden!';

  @override
  String get tutorialListen => 'Anhören';

  @override
  String get primerReadingTitle => 'Noten lesen';

  @override
  String get primerReadingStaff =>
      'Musik steht auf fünf Linien, dem Notensystem. Noten sitzen auf den Linien und in den Zwischenräumen.';

  @override
  String get primerReadingHigher =>
      'Je höher eine Note im System sitzt, desto höher klingt sie. Tippe auf Anhören und hör, wie sie nach oben steigt!';

  @override
  String get primerReadingNames =>
      'Jede Note hat einen Buchstabennamen: A H C D E F G. Diese hier ist E — tippe auf Anhören.';

  @override
  String get primerValuesTitle => 'Wie lang ist eine Note?';

  @override
  String get primerValuesWhole =>
      'Die Form einer Note zeigt, wie LANG du sie hältst. Dieser offene Kopf ohne Hals ist eine ganze Note — ein langer Klang (4 Schläge).';

  @override
  String get primerValuesQuarter =>
      'Eine ausgefüllte Note mit Hals ist eine Viertelnote — ein kurzer Schlag. Vier Viertel dauern so lang wie eine ganze Note.';

  @override
  String get primerValuesRest =>
      'Eine Pause ist ein Schlag STILLE. Zähl sie mit, aber spiel nicht. Tippe auf Anhören und hör eine Pause.';

  @override
  String get primerMeasuresTitle => 'Einen Takt füllen';

  @override
  String get primerMeasuresBars =>
      'Musik wird durch Taktstriche in Takte geteilt. Eine Taktangabe wie 4/4 heißt: jeder Takt hat 4 Schläge.';

  @override
  String get primerMeasuresFill =>
      'Füll jeden Takt, bis die Schläge aufgehen. Vier Viertelnoten ergeben 4 Schläge — ein voller 4/4-Takt.';

  @override
  String get primerMeasuresHalf =>
      'Eine halbe Note dauert 2 Schläge, also füllen auch zwei Halbe einen 4/4-Takt.';

  @override
  String get primerScalesTitle => 'Was ist eine Tonleiter?';

  @override
  String get primerScalesLadder =>
      'Eine Tonleiter ist eine Leiter aus Tönen, Stufe für Stufe nach oben. Das ist C-Dur: C D E F G A H C.';

  @override
  String get primerScalesMajor =>
      'Eine Dur-Tonleiter klingt hell und fröhlich. Hör, wie C-Dur nach oben steigt.';

  @override
  String get primerScalesMinor =>
      'Eine Moll-Tonleiter klingt dunkler, etwas traurig. Hör a-Moll.';

  @override
  String get primerChordsTitle => 'Einen Akkord bauen';

  @override
  String get primerChordsStack =>
      'Ein Akkord sind Töne, die GLEICHZEITIG klingen. Stapel drei Töne im Abstand und du hast einen Dreiklang — hier C E G.';

  @override
  String get primerChordsColour =>
      'Ein Dur-Dreiklang klingt hell, ein Moll-Dreiklang weicher und trauriger. Hör dir beide an.';

  @override
  String get primerChordsArpeggio =>
      'Du kannst einen Akkord auch Ton für Ton von unten nach oben spielen — das ist ein Arpeggio.';

  @override
  String get primerHarmonyTitle => 'Akkorde haben Aufgaben';

  @override
  String get primerHarmonyHome =>
      'Ein Akkord fühlt sich wie ZUHAUSE an — ruhig und fertig. Wir nennen ihn Tonika. Hör hin: Das ist C-Dur, das Zuhause.';

  @override
  String get primerHarmonyPull =>
      'Andere Akkorde ziehen WEG und wollen zurück nach Hause. Die Dominante zieht am stärksten — hör, wie sie gleich zum Zuhause zurücklehnt.';

  @override
  String get primerHarmonyCadence =>
      'Wenn Akkorde nach Hause → weg → nach Hause wandern, heißt diese kleine Reise zum Ruhepunkt eine Kadenz. Hör dir die ganze Reise an.';

  @override
  String get primerCompositionTitle => 'Eine Melodie erfinden';

  @override
  String get primerCompositionJourney =>
      'Eine Melodie ist eine kleine Reise aus Tönen — mal geht es aufwärts, mal wieder herunter. Summ mit, wenn sie steigt und fällt!';

  @override
  String get primerCompositionQuestion =>
      'Eine Melodie kann eine FRAGE stellen — sie bleibt oben in der Luft stehen, klingt noch nicht fertig, wie wartend.';

  @override
  String get primerCompositionAnswer =>
      '…dann gibt sie eine ANTWORT und kommt zum Zuhause herunter, zur Ruhe. Frage und Antwort ergeben einen Satz.';

  @override
  String get primerCelloTitle => 'Deine vier Saiten';

  @override
  String get primerCelloStrings =>
      'Das Cello hat vier Saiten. Von tief nach hoch heißen sie C, G, D, A — die tiefste Saite ist die dickste.';

  @override
  String get primerCelloBass =>
      'Cello-Töne stehen im Bassschlüssel, dem System für tiefe Klänge. Dieser tiefe Ton ist C, deine dickste Saite.';

  @override
  String get primerCelloFinger =>
      'Drück einen Finger auf eine Saite, um sie zu verkürzen, dann wird der Ton höher. Das Stimmgerät hört zu und zeigt, ob du genau triffst.';

  @override
  String get primerGuitarTitle => 'Sechs Saiten und Tabulatur';

  @override
  String get primerGuitarStrings =>
      'Eine Gitarre hat sechs Saiten. Von tief (dick) nach hoch (dünn): E, A, D, G, H, E — ja, an beiden Enden ein E!';

  @override
  String get primerGuitarTab =>
      'Gitarre kann man als Tabulatur (Tab) schreiben: sechs Linien, eine pro Saite. Eine Zahl ist der Bund zum Greifen; 0 heißt leere Saite.';

  @override
  String get primerGuitarPlay =>
      'Spiel den gezeigten Ton oder schrumme mit. Je dünner die Saite, desto höher klingt sie — vom tiefen E bis zum hohen E.';

  @override
  String get primerSongsTitle => 'Der Melodie folgen';

  @override
  String get primerSongsPick =>
      'Wähl ein Lied, das du kennst. Der Bildschirm zeigt seine Melodie als Notenreihe, von links nach rechts zu lesen.';

  @override
  String get primerSongsMarker =>
      'Eine Marke gleitet über die Melodie. Sing oder spiel jeden Ton, wenn er die Linie erreicht — wie einem hüpfenden Ball folgen.';

  @override
  String get primerKeyboardTitle => 'Die Klaviertasten';

  @override
  String get primerKeyboardWhite =>
      'Die weißen Tasten heißen A H C D E F G und wiederholen sich das ganze Klavier hinauf. Die schwarzen Tasten stehen in kleinen Gruppen aus zwei und drei.';

  @override
  String get primerKeyboardFindC =>
      'Finde das C: die weiße Taste direkt LINKS von jeder ZWEIER-Gruppe schwarzer Tasten. Von C aus hinauf: C D E F G A H C.';

  @override
  String get primerKeyboardHands =>
      'Klaviernoten nutzen zwei Systeme zugleich: das obere für die rechte Hand, das untere für die linke. Hör dir beide zusammen an.';

  @override
  String get primerTransposeTitle => 'Einen Ton lesen, einen anderen hören';

  @override
  String get primerTransposeSame =>
      'Die meisten Instrumente klingen so, wie sie notiert sind. Lies ein C, hör ein C — ganz einfach.';

  @override
  String get primerTransposeShift =>
      'Manche aber sind „transponierend“: eine Trompete in B liest ein C, doch heraus kommt ein B — etwas tiefer. Dieses Spiel rechnet das für dich um.';

  @override
  String get primerDrumsTitle => 'Schlagzeug lesen';

  @override
  String get primerDrumsWhat =>
      'Trommeln spielen keine hohen und tiefen Melodien — eine Trommel macht einfach BUMM oder TSS. Drum-Noten zeigen also WELCHE Trommel und WANN, keine Tonhöhe.';

  @override
  String get primerDrumsLines =>
      'Jede Linie und jeder Zwischenraum ist eine andere Trommel: ganz unten die große Trommel (Fußtritt), oben Snare und Becken. Von links nach rechts lesen und den Beat spielen.';

  @override
  String get primerBassTitle => 'Der Bassschlüssel';

  @override
  String get primerBassClef =>
      'Dieses tiefe System ist der Bassschlüssel (der F-Schlüssel). Ein Cello oder die linke Hand liest hier. Seine Linien und Zwischenräume bedeuten andere Töne als der Violinschlüssel.';

  @override
  String get primerBassMiddleC =>
      'Das eingestrichene C — das C in der Mitte des Klaviers — sitzt knapp über dem Bass-System, auf einer eigenen kleinen Hilfslinie.';

  @override
  String get primerLedgerTitle => 'Hilfslinien';

  @override
  String get primerLedgerMiddleC =>
      'Passt eine Note nicht auf die fünf Linien, malen wir eine kleine Extra-Linie nur für sie — eine Hilfslinie. Das eingestrichene C hängt an einer, direkt unter dem Violinsystem.';

  @override
  String get primerLedgerHigh =>
      'Je höher eine Note über das System steigt, desto mehr Hilfslinien braucht sie. Zähl sie wie die Sprossen einer Leiter.';

  @override
  String get primerAccidentalsTitle => 'Kreuz und B';

  @override
  String get primerAccidentalsSharp =>
      'Ein Kreuz ♯ vor einer Note hebt sie um den kleinsten Schritt, einen Halbton. Cis liegt einen Hauch höher als C.';

  @override
  String get primerAccidentalsFlat =>
      'Ein B ♭ senkt eine Note um einen Halbton. Des ist genau dieselbe Taste wie Cis — es lehnt sich nur von D herunter.';

  @override
  String get primerStepSkipTitle => 'Schritt und Sprung';

  @override
  String get primerStepSkipStep =>
      'Ein SCHRITT geht zur Nachbar-Note — von einer Linie zum berührenden Zwischenraum, einen Buchstaben weiter: C zu D.';

  @override
  String get primerStepSkipSkip =>
      'Ein SPRUNG überspringt eine — von einer Linie gleich zur nächsten Linie: C zu E. Sprünge klingen hüpfender als Schritte.';

  @override
  String get primerIntervalsTitle => 'Wie weit auseinander?';

  @override
  String get primerIntervalsCount =>
      'Der Abstand zwischen zwei Tönen ist ein Intervall. Zähl die Buchstaben mit beiden Enden: C bis E ist C-D-E — eine Terz (3).';

  @override
  String get primerIntervalsWide =>
      'Je größer der Abstand, desto größer die Zahl. C hinauf bis G ist eine Quinte (5): C-D-E-F-G.';

  @override
  String get primerIntervalsEar =>
      'Enge Intervalle klingen nah und sanft, weite offen und kräftig. Hör einen kleinen Abstand, dann einen großen.';

  @override
  String get primerKeySigTitle => 'Vorzeichen (Tonart)';

  @override
  String get primerKeySigWhat =>
      'Statt jedes Kreuz einzeln zu schreiben, setzen wir sie einmal ganz an den Anfang — die Vorzeichen der Tonart. Sie gelten fürs ganze Stück. Das hier ist G-Dur: ein Kreuz, Fis.';

  @override
  String get primerKeySigCompare =>
      'C-Dur hat gar keine Vorzeichen. Hör dir C-Dur an — lauter weiße Tasten.';

  @override
  String get primerTimeSigTitle => 'Taktarten';

  @override
  String get primerTimeSigFour =>
      'Die zwei Zahlen am Anfang sind die Taktart. Die obere Zahl sagt, wie viele Schläge in einen Takt passen — 4 heißt ein gleichmäßiger Vierer.';

  @override
  String get primerTimeSigThree =>
      'Setz oben eine 3 und jeder Takt hat drei Schläge — der sanfte Schwung eines Walzers. Zähl 1-2-3, 1-2-3.';

  @override
  String get primerChartTitle => 'Akkordsymbole';

  @override
  String get primerChartMajor =>
      'Über einer Melodie stehen oft Akkordsymbole. Ein einfacher Buchstabe meint einen Dur-Akkord: „C“ sagt dir, spiel einen C-Dur-Akkord.';

  @override
  String get primerChartMinor =>
      'Ein kleines „m“ hinter dem Buchstaben heißt Moll: „Am“ ist a-Moll — dieselbe Familie, aber weicher und trauriger.';

  @override
  String get colorScaffoldLabel => 'Farbhilfe für Anfänger';

  @override
  String get colorScaffoldSubtitle =>
      'Noten nach ihrem Buchstaben einfärben — später einfach ausschalten';

  @override
  String get handwrittenNotesLabel => 'Handgeschriebene Noten';

  @override
  String get handwrittenNotesSubtitle =>
      'Notenschrift im handgeschriebenen Jazz-Stil (Petaluma)';

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

  @override
  String get gameTuner => 'Stimmgerät';

  @override
  String get gameTunerSubtitle =>
      'Live-Intonation – spiele oder singe einen Ton';

  @override
  String get gamePlayAlong => 'Mitspielen';

  @override
  String get gamePlayAlongSubtitle =>
      'Folge der laufenden Partitur in der ersten Lage';

  @override
  String get gamePlayAlongGuitarSubtitle =>
      'Folge der laufenden Partitur auf der Gitarre';

  @override
  String get gamePlayAlongKeyboardSubtitle =>
      'Spiele die laufende Partitur auf den Tasten';

  @override
  String get gameSingAlong => 'Mitsingen';

  @override
  String get gameSingAlongSubtitle =>
      'Triff die laufende Partitur mit deiner Stimme';

  @override
  String get gameOdeToJoy => 'An die Freude';

  @override
  String get gameMaryLamb => 'Marys Lämmchen';

  @override
  String get gameFreeSing => 'Frei singen';

  @override
  String get gameFreeSingSubtitle => 'Sing eine Melodie und hör sie zurück';

  @override
  String get freeSingPrompt => 'Sing eine Melodie…';

  @override
  String get freeSingRecord => 'Aufnehmen';

  @override
  String freeSingCaptured(int count) {
    return '$count Noten aufgenommen';
  }

  @override
  String get gameChordListener => 'Akkord-Erkennung';

  @override
  String get gameChordListenerSubtitle => 'Erkenne den Akkord, den du spielst';

  @override
  String get gameChordProgression => 'Akkorde mitspielen';

  @override
  String get gameChordProgressionSubtitle =>
      'Spiele die Akkordfolge, während sie vorbeizieht';

  @override
  String get micStart => 'Zuhören starten';

  @override
  String get micStop => 'Stopp';

  @override
  String get micPermissionDenied =>
      'Mikrofonzugriff verweigert. Aktiviere ihn in den Systemeinstellungen.';

  @override
  String get micUnsupported =>
      'PCM-Aufnahme wird auf diesem Gerät nicht unterstützt.';

  @override
  String micStartFailed(String detail) {
    return 'Mikrofon konnte nicht gestartet werden: $detail';
  }

  @override
  String get tunerPrompt => 'Spiele oder singe einen Ton';

  @override
  String tunerCents(String cents) {
    return '$cents Cent';
  }

  @override
  String get tunerReference => 'Referenzton';

  @override
  String get tunerInstrument => 'Instrument';

  @override
  String get tunerInstrumentChromatic => 'Chromatisch';

  @override
  String get tunerInstrumentCello => 'Cello';

  @override
  String get tunerInstrumentGuitar => 'Gitarre';

  @override
  String get tunerInstrumentViolin => 'Geige';

  @override
  String get tunerPickString => 'Tippe eine Saite zum Stimmen an';

  @override
  String tunerTuneString(String string) {
    return 'Stimme die $string-Saite';
  }

  @override
  String get tunerStringInTune => 'Sauber gestimmt!';

  @override
  String get playAlongScore => 'Punkte';

  @override
  String get playAlongNow => 'Jetzt';

  @override
  String get playAlongYou => 'Du';

  @override
  String get playAlongCountIn => 'Einzähler';

  @override
  String get playAlongPreview => 'Vorhören';

  @override
  String get playAlongViewLabel => 'Ansicht';

  @override
  String get playAlongViewHighway => 'Notenband';

  @override
  String get playAlongViewNotation => 'Noten';

  @override
  String get playAlongViewFalling => 'Fallend';

  @override
  String get playAlongViewCoach => 'Coach';

  @override
  String get playAlongNext => 'als Nächstes';

  @override
  String get playAlongLoopHint =>
      'Tippe zwei Noten an, um den Abschnitt zu wiederholen';

  @override
  String get playAlongLoopEnd => 'Tippe jetzt die letzte Note der Schleife an';

  @override
  String get playAlongLooping =>
      'Abschnitt läuft in Schleife — tippe eine Note zum Beenden';

  @override
  String get playAlongMarkFlat => 'zu tief';

  @override
  String get playAlongMarkSharp => 'zu hoch';

  @override
  String get playAlongMarkMiss => 'verpasst';

  @override
  String get playAlongBacking => 'Begleitung (Kopfhörer nutzen)';

  @override
  String get playAlongTempo => 'Tempo';

  @override
  String get playAlongDifficulty => 'Schwierigkeit';

  @override
  String get playAlongDifficultyEasy => 'Leicht';

  @override
  String get playAlongDifficultyMedium => 'Mittel';

  @override
  String get playAlongDifficultyHard => 'Schwer';

  @override
  String get chordListenerPrompt => 'Spiele oder zupfe einen Akkord';

  @override
  String chordListenerMatch(int percent) {
    return '$percent% Übereinstimmung';
  }

  @override
  String get chordListenerHeard => 'Gehörte Tonklassen';

  @override
  String get aboutTitle => 'Über';

  @override
  String get aboutSubtitle => 'Version, Lizenzen und Danksagungen';

  @override
  String get appLegalese => '© 2026 Christian Ströbele';

  @override
  String get aboutTagline =>
      'Notenschrift & Harmonielehre – ab der Grundschule';

  @override
  String aboutVersionLabel(String version) {
    return 'Version $version';
  }

  @override
  String get aboutProvider => 'Anbieter';

  @override
  String get aboutContact => 'Kontakt';

  @override
  String get aboutPrivacy => 'Datenschutz';

  @override
  String get aboutPrivacyText =>
      'KlangUniversum läuft vollständig auf deinem Gerät. Mikrofon-Audio (für Stimmgerät und Mitspielen) wird lokal in Echtzeit analysiert – niemals aufgezeichnet, gespeichert oder übertragen. Es gibt keine Konten, keine Werbung und kein Tracking.';

  @override
  String get aboutDisclaimer => 'Haftungsausschluss';

  @override
  String get aboutDisclaimerText =>
      'KlangUniversum ist eine Lernhilfe und wird ohne Gewähr bereitgestellt. Die Lehrplan-Stufen sind allgemeine Orientierung, kein offizieller Lehrplan.';

  @override
  String get aboutCredits => 'Danksagungen';

  @override
  String get aboutCreditsText =>
      'Der Notensatz verwendet die Schriftart Bravura (SIL Open Font License).';

  @override
  String get aboutOpenSourceLicenses => 'Open-Source-Lizenzen';
}
