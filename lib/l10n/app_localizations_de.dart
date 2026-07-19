// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'CometBeat';

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
  String get workshopClefMidBar => 'Schlüssel (im Takt)';

  @override
  String get workshopVoice1 => 'St.1';

  @override
  String get workshopVoice2 => 'St.2';

  @override
  String get workshopZoomIn => 'Vergrößern';

  @override
  String get workshopZoomOut => 'Verkleinern';

  @override
  String get workshopOpen => 'Datei öffnen…';

  @override
  String get workshopExport => 'Exportieren…';

  @override
  String get workshopExportChoose => 'Format wählen';

  @override
  String workshopExportAllParts(int count) {
    return 'Alle $count Stimmen';
  }

  @override
  String workshopExportActivePartOnly(String part) {
    return 'Nur „$part“ — dieses Format kann nicht mehrere Stimmen speichern';
  }

  @override
  String workshopSavedTo(String path) {
    return 'Gespeichert: $path';
  }

  @override
  String get musicExportTitle => 'Exportieren als…';

  @override
  String get musicExportEmpty => 'Noch nichts zu exportieren';

  @override
  String get musicExportFailed => 'Export fehlgeschlagen';

  @override
  String get audioExportTitle => 'Klang exportieren';

  @override
  String get audioExportWav => 'WAV (unkomprimiert)';

  @override
  String get audioExportMp3 => 'MP3 (kleiner)';

  @override
  String get audioExportEmpty => 'Noch nichts zu exportieren';

  @override
  String get audioExportFailed => 'Export fehlgeschlagen';

  @override
  String audioExportSavedTo(String path) {
    return 'Gespeichert unter $path';
  }

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
  String get workshopRepeatStart => 'Wiederholung beginnt hier';

  @override
  String get workshopRepeatEnd => 'Wiederholung endet hier';

  @override
  String get workshopChangeHere => 'Ab hier ändern…';

  @override
  String get workshopChangeHereTitle => 'Ab dieser Note ändern';

  @override
  String get workshopNoChange => 'Keine Änderung';

  @override
  String get workshopVolta => 'Klammer';

  @override
  String get workshopNavigation => 'Navigation';

  @override
  String get workshopTempo => 'Tempo';

  @override
  String get workshopInitialTempo => 'Anfangstempo…';

  @override
  String get workshopTempoNone => 'Ohne';

  @override
  String get workshopGraceNotes => 'Vorschlagsnoten…';

  @override
  String get workshopGraceEmpty =>
      'Noch keine Vorschlagsnoten — tippe eine Note zum Hinzufügen.';

  @override
  String get workshopGraceAcciaccatura => 'Acciaccatura';

  @override
  String get workshopGraceAppoggiatura => 'Appoggiatura';

  @override
  String get workshopStop => 'Stopp';

  @override
  String get workshopMutePart => 'Stumm';

  @override
  String get workshopPlaybackSpeed => 'Wiedergabetempo';

  @override
  String get workshopCountIn => 'Einzähler';

  @override
  String get workshopLoopSelection => 'Auswahl wiederholen';

  @override
  String get workshopArticulations => 'Artikulation & Bindebögen';

  @override
  String get workshopOrnament => 'Verzierung';

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
  String get workshopBarNumbers => 'Taktzahlen';

  @override
  String get workshopNoteNames => 'Notennamen';

  @override
  String get workshopAnalysis => 'Analyse (nach Harmonie einfärben)';

  @override
  String get workshopInspector => 'Inspektor';

  @override
  String get workshopInspectorEmpty =>
      'Wähle eine Note, um ihre Eigenschaften zu sehen.';

  @override
  String get workshopStructure => 'Struktur';

  @override
  String get workshopInsertMode => 'Einfügen';

  @override
  String get workshopSelectMode => 'Auswählen';

  @override
  String get workshopStudioMode => 'Studio-Modus';

  @override
  String get workshopSplitNotes => 'Noten über Taktstriche binden';

  @override
  String get workshopPasteTokens => 'Noten-Tokens einfügen…';

  @override
  String get workshopPasteTokensHint =>
      'bekern-/kern-Tokens einfügen (z. B. **kern <b> 4 c <b> *-)';

  @override
  String get workshopPasteTokensLoad => 'Laden';

  @override
  String get workshopAddInstrument => 'Instrument hinzufügen';

  @override
  String get workshopRemoveInstrument => 'Diese Stimme entfernen';

  @override
  String get workshopPartClef => 'Schlüssel';

  @override
  String get workshopPartTransposition => 'Transposition';

  @override
  String get workshopConcertPitch => 'Klingend (C)';

  @override
  String get workshopBraceBelow => 'Klammer mit Stimme darunter';

  @override
  String get workshopBreakBarlineBelow => 'Taktstrich darunter trennen';

  @override
  String get workshopTuplet => 'Triole (3 statt 2)';

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
  String get gameTempoDuel => 'Schneller oder langsamer?';

  @override
  String get gameTempoDuelSubtitle =>
      'Lies zwei Tempo-Wörter und tippe das schnellere';

  @override
  String get whichIsFaster => 'Welches Tempo ist schneller?';

  @override
  String get gameDynamicsDuel => 'Lauter oder leiser?';

  @override
  String get gameDynamicsDuelSubtitle =>
      'Lies zwei Dynamik-Zeichen und tippe das lautere';

  @override
  String get whichIsLouder => 'Welches Zeichen ist lauter?';

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
  String get gamePitchSortBass => 'Hoch oder tief? (Bass)';

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
  String get gameAccidentalSortBass => 'Kreuz oder B? (Bass)';

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
  String get accidentalNaturalLabel => 'Auflösung';

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
  String get gameStepSkipBass => 'Schritt oder Sprung? (Bass)';

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
  String get leapLabel => 'Großer Sprung';

  @override
  String get gameArticulation => 'Lies das Zeichen';

  @override
  String get gameArticulationSubtitle =>
      'Ordne das Artikulationszeichen an der Note seinem Namen zu';

  @override
  String get articulationPrompt => 'Welches Zeichen steht an der Note?';

  @override
  String get articulationStaccato => 'Staccato';

  @override
  String get articulationTenuto => 'Tenuto';

  @override
  String get articulationAccent => 'Akzent';

  @override
  String get articulationMarcato => 'Marcato';

  @override
  String get gameTieSlur => 'Haltebogen oder Bindebogen?';

  @override
  String get gameTieSlurSubtitle =>
      'Gleiche Tonhöhe = Haltebogen; verschiedene = Bindebogen';

  @override
  String get tieSlurPrompt => 'Ist der Bogen ein Halte- oder ein Bindebogen?';

  @override
  String get tieLabel => 'Haltebogen';

  @override
  String get slurLabel => 'Bindebogen';

  @override
  String get gameEnharmonic => 'Enharmonische Zwillinge';

  @override
  String get gameEnharmonicSubtitle =>
      'Gleicher Klang, zwei Schreibweisen – oder verschiedene Töne?';

  @override
  String get enharmonicPrompt => 'Klingen diese beiden Noten gleich?';

  @override
  String get enharmonicSame => 'Gleicher Klang';

  @override
  String get enharmonicDifferent => 'Verschieden';

  @override
  String get gameBeamFlag => 'Balken oder Fähnchen?';

  @override
  String get gameBeamFlagSubtitle =>
      'Achtel mit Balken verbunden oder jede mit eigenem Fähnchen?';

  @override
  String get beamFlagPrompt =>
      'Sind die Achtel mit Balken verbunden oder haben sie Fähnchen?';

  @override
  String get beamLabel => 'Balken';

  @override
  String get flagLabel => 'Fähnchen';

  @override
  String get gameSpotUpbeat => 'Auftakt finden';

  @override
  String get gameSpotUpbeatSubtitle =>
      'Beginnt das Stück auf der Zählzeit oder mit einem Auftakt?';

  @override
  String get spotUpbeatPrompt => 'Wo beginnt die Melodie?';

  @override
  String get spotUpbeatUpbeat => 'Auftakt';

  @override
  String get spotUpbeatOnBeat => 'Volltakt';

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
  String get gameCountNotes => 'Töne zählen';

  @override
  String get gameCountNotesSubtitle =>
      'Hör genau hin — wie viele Töne hast du gehört?';

  @override
  String get countNotesPrompt => 'Wie viele Töne hast du gehört?';

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
  String get gameGridComposer => 'Farb-Melodie';

  @override
  String get gameGridComposerSubtitle =>
      'Tippe Farben und bau eine Melodie — ohne Lesen';

  @override
  String get gridComposerPrompt => 'Tippe die Farben und mach eine Melodie!';

  @override
  String get gameMelodyDoodle => 'Melodie malen';

  @override
  String get gameMelodyDoodleSubtitle =>
      'Mal eine Linie und hör sie als Melodie';

  @override
  String get melodyDoodlePrompt =>
      'Zieh eine Linie durch das Feld — oben ist höher!';

  @override
  String get gridComposerPlay => 'Abspielen';

  @override
  String get gridComposerClear => 'Löschen';

  @override
  String get gameLoopMixer => 'Loop-Mixer';

  @override
  String get gameLoopMixerSubtitle =>
      'Staple Grooves übereinander — du bist die Band';

  @override
  String get loopMixerPrompt => 'Tippe die Karten und starte deine Band!';

  @override
  String get loopMixerStop => 'Stopp';

  @override
  String get loopMixerSwing => 'Swing';

  @override
  String get loopMixerHarmony => 'Harmonie';

  @override
  String get loopMixerKey => 'Tonart';

  @override
  String get loopMixerScale => 'Tongeschlecht';

  @override
  String get loopMixerScaleMajor => 'Dur';

  @override
  String get loopMixerScaleMinor => 'Moll';

  @override
  String get loopMixerKit => 'Set';

  @override
  String get loopMixerKitClean => 'Klar';

  @override
  String get loopMixerKitDeep => 'Tief';

  @override
  String get loopMixerKitWarm => 'Warm';

  @override
  String get loopMixerKitLofi => 'Lo-fi';

  @override
  String get loopMixerFilter => 'Filter';

  @override
  String get loopMixerQuantize => 'Quantisiert starten (im Takt einsetzen)';

  @override
  String get loopMixerSolo => 'Solo-Pad (ziehen für Töne in der Tonart)';

  @override
  String get loopMixerSoloKeep => 'Behalten';

  @override
  String get loopMixerScenes => 'Teile';

  @override
  String get loopMixerScenesHint =>
      'Tippen zum Starten, halten zum Speichern der Schichten';

  @override
  String get loopMixerChain => 'Teile verketten (automatisch weiter)';

  @override
  String get loopMixerExportArrangement => 'Teile als einen Track exportieren';

  @override
  String get loopMixerChallengeSparkle =>
      'Versuch: etwas Hohes und Glitzerndes ✨';

  @override
  String get loopMixerChallengeBass => 'Versuch: eine tiefe Basslinie';

  @override
  String get loopMixerChallengeMelody => 'Versuch: eine Melodie obendrauf';

  @override
  String get loopMixerChallengeLayers => 'Versuch: drei Schichten gleichzeitig';

  @override
  String get loopMixerChallengeFullBand => 'Versuch: die ganze Band zusammen';

  @override
  String get loopMixerChallengeDone => 'Super! Tippe für eine neue Idee →';

  @override
  String get loopMixerStyle => 'Stil';

  @override
  String get loopMixerStyleClassic => 'Klassisch';

  @override
  String get loopMixerStyleFour => 'Four-on-Floor';

  @override
  String get loopMixerStyleChill => 'Lounge';

  @override
  String get loopMixerHarmonyOff => 'Frei';

  @override
  String get loopMixerRoll => 'Überrasch mich — neuen Groove würfeln';

  @override
  String get loopMixerSaveSlot => 'In meinen Grooves speichern';

  @override
  String get loopMixerMySlots => 'Meine Grooves';

  @override
  String get loopMixerSlotNameHint => 'Benenne deinen Groove';

  @override
  String get loopMixerSave => 'Speichern';

  @override
  String loopMixerSlotSaved(String name) {
    return '„$name“ gespeichert';
  }

  @override
  String get loopMixerNoSlots => 'Noch keine gespeicherten Grooves';

  @override
  String loopMixerComboFound(String name) {
    return 'Combo entdeckt: $name!';
  }

  @override
  String get loopMixerCombosTip => 'Gefundene Geheim-Combos';

  @override
  String get loopMixerComboRhythmSection => 'Rhythmusgruppe';

  @override
  String get loopMixerComboDuo => 'Duo';

  @override
  String get loopMixerComboDreamy => 'Verträumt';

  @override
  String get loopMixerComboMarching => 'Blaskapelle';

  @override
  String get loopMixerComboFullBand => 'Ganze Band';

  @override
  String get loopMixerScore => 'Als Noten zeigen';

  @override
  String get loopMixerScoreEmpty =>
      'Schalte eine Spur ein, um sie als Noten zu sehen.';

  @override
  String get loopMixerShare => 'Teile deinen Groove';

  @override
  String get loopMixerCopyCode => 'Groove-Code kopieren';

  @override
  String get loopMixerPasteCode => 'Groove-Code einfügen';

  @override
  String get loopMixerCodeCopied =>
      'Groove-Code kopiert — füge ihn irgendwo ein!';

  @override
  String get loopMixerCodeInvalid => 'Dieser Groove-Code hat nicht geklappt';

  @override
  String get loopMixerSaveAudio => 'Als Audio speichern (WAV)';

  @override
  String get loopMixerSaveSongBook => 'Ins Liederbuch speichern';

  @override
  String get loopMixerExportMusicXml => 'Als Noten exportieren (MusicXML)';

  @override
  String get loopMixerOpenTracker => 'Im Tracker öffnen';

  @override
  String get loopMixerOpenWorkshop => 'In der Noten-Werkstatt öffnen';

  @override
  String get loopMixerSaveTitle => 'Benenne deinen Groove';

  @override
  String get loopMixerSaveFailed => 'Audio speichern geht hier nicht';

  @override
  String get loopMixerLoad => 'Laden';

  @override
  String get loopMixerInfinite =>
      'Endlos-Modus — jeder Loop ein bisschen anders';

  @override
  String get loopMixerSend => 'Raum-Effekt (Hall / Echo)';

  @override
  String get loopMixerSing => 'Sing eine Spur!';

  @override
  String get loopMixerSingAgain => 'Sing deine Spur neu';

  @override
  String get loopMixerSingNow => 'Jetzt singen!';

  @override
  String get loopMixerSingNothing =>
      'Wir haben keine Melodie gehört — probier\'s nochmal!';

  @override
  String get loopMixerTrackVoice => 'Meine Stimme';

  @override
  String get loopMixerBeatbox => 'Beatbox einen Beat!';

  @override
  String get loopMixerBeatboxAgain => 'Nochmal beatboxen';

  @override
  String get loopMixerBeatNow => 'Jetzt beatboxen!';

  @override
  String get loopMixerTrackBeat => 'Mein Beat';

  @override
  String get loopMixerJam => 'Mitspielen — am besten mit Kopfhörern';

  @override
  String get loopMixerJamHint =>
      'Spiel oder sing mit — grün passt zum Akkord! Mit Kopfhörern hört das Mikro nur dich.';

  @override
  String get loopMixerJamHintAec =>
      'Spiel oder sing mit — die Band hört zu! Grün passt zum Akkord.';

  @override
  String get loopMixerJamGraded => '🎧 Band rausgerechnet — das bewertet dich';

  @override
  String get loopMixerJamHeadphones => 'Mit Kopfhörern hört das Mikro nur dich';

  @override
  String get loopMixerFollow => 'Der Melodie folgen';

  @override
  String loopMixerFollowScore(int pct) {
    return '🎯 Melodie-Treffer: $pct%';
  }

  @override
  String get loopMixerTempoChill => 'Gemütlich';

  @override
  String get loopMixerTempoGroove => 'Groove';

  @override
  String get loopMixerTempoFast => 'Schnell';

  @override
  String get loopMixerTrackDrums => 'Schlagzeug';

  @override
  String get loopMixerTrackBass => 'Bass';

  @override
  String get loopMixerTrackChords => 'Akkorde';

  @override
  String get loopMixerTrackMelody => 'Melodie';

  @override
  String get loopMixerTrackSparkle => 'Glitzer';

  @override
  String get gameTracker => 'Tracker';

  @override
  String get gameTrackerSubtitle => 'Bau dir einen Loop — Spur für Spur';

  @override
  String get gameTrackerAdvanced => 'Profi-Tracker';

  @override
  String get workshopModeScore => 'Noten-Werkstatt';

  @override
  String get workshopModeTracker => 'Tracker';

  @override
  String get workshopModeTab => 'Gitarren-Tabulatur';

  @override
  String get workshopModeLoop => 'Loop-Mixer';

  @override
  String get workshopModeDrums => 'Schlagzeug';

  @override
  String get dawTitle => 'Mehrspur';

  @override
  String get dawAddBeat => 'Beat hinzufügen';

  @override
  String get dawAddSample => 'Sample hinzufügen';

  @override
  String get dawAddTune => 'Melodie hinzufügen';

  @override
  String get dawEmpty =>
      'Füge einen Beat oder eine Melodie hinzu und drücke Play — sie überlagern sich.';

  @override
  String get dawSend => 'Zur Mehrspur';

  @override
  String get dawSent => 'Zur Mehrspur hinzugefügt';

  @override
  String dawBpm(int n) {
    return '$n BPM';
  }

  @override
  String get dawTempoUp => 'Schneller';

  @override
  String get dawTempoDown => 'Langsamer';

  @override
  String get dawAddTrack => 'Spur hinzufügen';

  @override
  String get dawTrackTitle => 'Spur';

  @override
  String get dawTrackName => 'Name';

  @override
  String get dawRenameTrack => 'Umbenennen';

  @override
  String get dawRemoveTrack => 'Spur entfernen';

  @override
  String get dawRename => 'Umbenennen';

  @override
  String get dawCancel => 'Abbrechen';

  @override
  String get dawSaveProject => 'Projekt speichern';

  @override
  String get dawOpenProject => 'Projekt öffnen';

  @override
  String get dawProjectSaved => 'Projekt gespeichert';

  @override
  String get dawProjectSaveFailed => 'Projekt konnte nicht gespeichert werden';

  @override
  String get dawProjectOpenFailed => 'Projekt konnte nicht geöffnet werden';

  @override
  String get dawMergeAll => 'Alles zusammenführen';

  @override
  String get dawMerged => 'Zu einer Audiospur zusammengeführt';

  @override
  String get dawDuplicate => 'Duplizieren';

  @override
  String get dawFreeze => 'In Audio umwandeln';

  @override
  String get dawFrozen => 'In eine Audiospur umgewandelt';

  @override
  String get dawUndo => 'Rückgängig';

  @override
  String get dawRedo => 'Wiederholen';

  @override
  String get dawGain => 'Lautstärke';

  @override
  String get dawFadeIn => 'Einblenden';

  @override
  String get dawTrimStart => 'Anfang beschneiden';

  @override
  String get dawTrimEnd => 'Ende beschneiden';

  @override
  String get dawFadeOut => 'Ausblenden';

  @override
  String get dawRemoveClip => 'Entfernen';

  @override
  String get dawLoop => 'Schleife';

  @override
  String get dawSnap => 'Am Raster ausrichten';

  @override
  String get drumkitTitle => 'Schlagzeug';

  @override
  String get drumkitRecord => 'Aufnehmen';

  @override
  String get drumkitStopRecording => 'Aufnahme stoppen';

  @override
  String get drumkitBeatbox => 'Beatbox';

  @override
  String get drumkitStopListening => 'Stopp';

  @override
  String get drumkitBeatboxNothing => 'Nichts gehört — beatboxe lauter.';

  @override
  String get drumkitSave => 'Ins Liederbuch';

  @override
  String get drumkitExport => 'Exportieren';

  @override
  String get drumkitSaveTitle => 'Benenne deinen Beat';

  @override
  String get drumkitDefaultName => 'Mein Beat';

  @override
  String get drumkitSaved => 'Im Liederbuch gespeichert';

  @override
  String get drumkitStraight => 'Gerade';

  @override
  String get drumkitSwing => 'Swing';

  @override
  String get drumkitKick => 'Bass';

  @override
  String get drumkitSnare => 'Snare';

  @override
  String get drumkitHat => 'Hi-Hat';

  @override
  String get tabWorkshopTitle => 'Gitarren-Tabulatur';

  @override
  String get tabImport => 'Datei öffnen';

  @override
  String get tabDemo => 'Demo-Riff';

  @override
  String get tabTuning => 'Stimmung';

  @override
  String get tabCapo => 'Kapodaster';

  @override
  String get tabShowStandard => 'Notenschrift';

  @override
  String get tabTempo => 'Tempo';

  @override
  String get tabMic => 'Einspielen (Mikrofon)';

  @override
  String get tabMicDenied => 'Mikrofon-Berechtigung wird benötigt';

  @override
  String get tabMicFailed => 'Mikrofon konnte nicht gestartet werden';

  @override
  String get tabTracks => 'Spuren';

  @override
  String get tabAddTrack => 'Spur hinzufügen';

  @override
  String get tabRemoveTrack => 'Spur entfernen';

  @override
  String get tabOpenSongBook => 'Aus Liederbuch öffnen';

  @override
  String get tabOpenWorkshop => 'In Noten-Werkstatt öffnen';

  @override
  String get soundLabTitle => 'Klanglabor';

  @override
  String get soundLabPlay => 'Abspielen';

  @override
  String get soundLabExport => 'WAV exportieren';

  @override
  String get soundLabShare => 'Teilen-Code kopieren';

  @override
  String get soundLabRandomize => 'Zufall';

  @override
  String get soundLabMutate => 'Verändern';

  @override
  String get soundLabSetA => 'Schnappschuss A';

  @override
  String get soundLabSetB => 'Schnappschuss B';

  @override
  String get soundLabMorphHint =>
      'Zwei Klänge in A und B ablegen, dann dazwischen überblenden.';

  @override
  String get soundLabCopied => 'Teilen-Code kopiert';

  @override
  String get soundLabExportFailed => 'Export fehlgeschlagen';

  @override
  String soundLabSavedTo(String path) {
    return 'Gespeichert unter $path';
  }

  @override
  String get soundLabSaveTitle => 'Speichern…';

  @override
  String get soundLabSaveRecipe => 'Rezept speichern (Meine Klänge)';

  @override
  String get soundLabToSamples => 'Als Sample speichern (Meine Samples)';

  @override
  String get soundLabSfxName => 'Sample-Name';

  @override
  String get soundLabMyTitle => 'Meine Klänge';

  @override
  String get soundLabSaveName => 'Name';

  @override
  String get soundLabCancel => 'Abbrechen';

  @override
  String get soundLabSave => 'Speichern';

  @override
  String get soundLabDelete => 'Löschen';

  @override
  String soundLabDefaultName(int n) {
    return 'Klang $n';
  }

  @override
  String soundLabSaved(String name) {
    return '„$name“ gespeichert';
  }

  @override
  String get soundLabMyEmpty =>
      'Noch keine gespeicherten Klänge. Erstelle einen und tippe auf das Lesezeichen.';

  @override
  String get soundLabSquare => 'Rechteck';

  @override
  String get soundLabSaw => 'Säge';

  @override
  String get soundLabSine => 'Sinus';

  @override
  String get soundLabNoise => 'Rauschen';

  @override
  String get soundLabPitch => 'Tonhöhe';

  @override
  String get soundLabSlide => 'Gleiten';

  @override
  String get soundLabAttack => 'Anschlag';

  @override
  String get soundLabHold => 'Halten';

  @override
  String get soundLabFade => 'Ausklang';

  @override
  String get soundLabPunch => 'Wucht';

  @override
  String get soundLabBuzz => 'Schnarren';

  @override
  String get soundLabWobble => 'Wobbeln';

  @override
  String get soundLabBright => 'Hell';

  @override
  String get soundLabCrunch => 'Verzerrung';

  @override
  String get soundLabEcho => 'Echo';

  @override
  String get voiceLabTitle => 'Stimmlabor';

  @override
  String get voiceLabPlay => 'Abspielen';

  @override
  String get voiceLabExport => 'WAV exportieren';

  @override
  String get voiceLabRecord => 'Aufnehmen';

  @override
  String get voiceLabLoad => 'Audio laden';

  @override
  String get voiceLabHint =>
      'Nimm deine Stimme auf oder lade einen Klang, dann verwandle ihn.';

  @override
  String get voiceLabCharacter => 'Charakter';

  @override
  String get voiceLabPitch => 'Tonhöhe';

  @override
  String get voiceLabSpeed => 'Tempo';

  @override
  String get voiceLabTremolo => 'Wobbeln';

  @override
  String get voiceLabGate => 'Gate';

  @override
  String get voiceLabReverb => 'Hall';

  @override
  String get voiceLabNoMic => 'Mikrofon-Berechtigung wird benötigt';

  @override
  String get voiceLabRecordFailed => 'Aufnahme fehlgeschlagen';

  @override
  String get voiceLabExportFailed => 'Export fehlgeschlagen';

  @override
  String voiceLabSavedTo(String path) {
    return 'Gespeichert unter $path';
  }

  @override
  String get voiceLabSaveTitle => 'In Meine Samples speichern';

  @override
  String get voiceLabMyTitle => 'Meine Samples';

  @override
  String get voiceLabSaveName => 'Name';

  @override
  String get voiceLabCancel => 'Abbrechen';

  @override
  String get voiceLabSave => 'Speichern';

  @override
  String get voiceLabDelete => 'Löschen';

  @override
  String voiceLabDefaultName(int n) {
    return 'Stimme $n';
  }

  @override
  String get voiceLabMyEmpty =>
      'Noch keine gespeicherten Samples. Bearbeite eine Stimme und tippe auf das Lesezeichen.';

  @override
  String get sampleExtractTitle => 'Sample-Extraktor';

  @override
  String get sampleExtractOpen => 'Module öffnen…';

  @override
  String get sampleExtractHint =>
      'Öffne eine oder mehrere Tracker-Module (.mod, .xm, .s3m, .it), um ihre Samples zu extrahieren. Du kannst jedes vorhören, als WAV exportieren oder zu Meine Samples hinzufügen.\n\nVerwende nur Dateien, für die du die Rechte hast — die App macht keine Lizenzaussage über die Samples eines Moduls.';

  @override
  String sampleExtractCount(int n) {
    return '$n Samples';
  }

  @override
  String sampleExtractLibrary(int n) {
    return 'Meine Samples: $n';
  }

  @override
  String sampleExtractMeta(String module, String secs) {
    return '$module · ${secs}s';
  }

  @override
  String get sampleExtractBrowsePacks => 'Freie Pakete durchsuchen';

  @override
  String get samplePackSearch => 'Instrumente suchen…';

  @override
  String get samplePackHint =>
      'Freie Instrument-Sample-Pakete. Es werden nur Pakete mit eindeutig freier Lizenz gelistet — Unklares wird ausgeblendet.';

  @override
  String get samplePackEmpty => 'Keine Pakete gefunden';

  @override
  String get mySamplesTitle => 'Meine Samples';

  @override
  String get mySamplesEmpty =>
      'Noch keine Samples. Extrahiere welche aus einem Modul oder Paket, oder speichere eine Stimme.';

  @override
  String get mySamplesCredits => 'Credits';

  @override
  String get mySamplesClose => 'Schließen';

  @override
  String get mySamplesImport => 'Datei importieren';

  @override
  String get mySamplesImportFailed => 'Audiodatei konnte nicht gelesen werden.';

  @override
  String get mySamplesPreview => 'Vorhören';

  @override
  String get mySamplesDelete => 'Löschen';

  @override
  String get sampleExtractPreview => 'Vorhören';

  @override
  String get sampleExtractExport => 'WAV exportieren';

  @override
  String get sampleExtractExportFolder => 'Alle in einen Ordner exportieren';

  @override
  String sampleExtractSavedFolder(int n, String dir) {
    return '$n WAVs gespeichert in $dir';
  }

  @override
  String get sampleExtractAdd => 'Zu Meine Samples';

  @override
  String get sampleExtractAddAll => 'Alle zu Meine Samples';

  @override
  String sampleExtractAdded(String name) {
    return '„$name“ hinzugefügt';
  }

  @override
  String sampleExtractAddedAll(int n) {
    return '$n Samples hinzugefügt';
  }

  @override
  String sampleExtractFailed(String files) {
    return 'Konnte nicht gelesen werden: $files';
  }

  @override
  String get tabPasteAscii => 'ASCII-Tab einfügen';

  @override
  String get tabPasteAsciiHint => 'e|--0--3--|\nB|--1-----|\n...';

  @override
  String get tabSongBookEmpty => 'Dein Liederbuch ist leer';

  @override
  String get tabSaveSongBook => 'Ins Liederbuch speichern';

  @override
  String tabSaved(String title) {
    return '„$title“ gespeichert';
  }

  @override
  String get tabPlay => 'Abspielen';

  @override
  String get tabClear => 'Leeren';

  @override
  String get tabDuration => 'Notenlänge';

  @override
  String get tabClearCell => 'Löschen';

  @override
  String get tabAddColumn => 'Schritt hinzufügen';

  @override
  String get tabRemoveColumn => 'Schritt entfernen';

  @override
  String get tabTechnique => 'Technik';

  @override
  String get tabTechHammer => 'H/P';

  @override
  String get tabTechSlide => 'Slide';

  @override
  String get tabTechBend => 'Bending';

  @override
  String get tabTechVibrato => 'Vibrato';

  @override
  String get tabTechDead => 'Dead ✕';

  @override
  String get tabTechGhost => 'Ghost';

  @override
  String get tabTechHarmonic => 'Flageolett';

  @override
  String get tabChord => 'Akkord';

  @override
  String get tabChordPick => 'Akkord wählen';

  @override
  String get tabChordNone => 'Kein Akkord';

  @override
  String get tabExport => 'Exportieren';

  @override
  String get tabExportGp => 'Guitar Pro (.gp)';

  @override
  String get tabExportMusicXml => 'MusicXML';

  @override
  String get tabExportMidi => 'MIDI';

  @override
  String get tabExportFailed => 'Export fehlgeschlagen';

  @override
  String tabSavedTo(String path) {
    return 'Gespeichert unter $path';
  }

  @override
  String get tabImportFailed => 'Datei konnte nicht geöffnet werden';

  @override
  String get libraryTitle => 'Freie Musik-Bibliotheken';

  @override
  String get librarySaveToMy => 'In Meine Samples speichern';

  @override
  String librarySavedToMy(String name) {
    return '„$name“ in Meine Samples gespeichert';
  }

  @override
  String get librarySearchHint => 'Nach Titel oder Komponist suchen';

  @override
  String get libraryImport => 'Importieren';

  @override
  String libraryImported(String title) {
    return '„$title“ importiert';
  }

  @override
  String get libraryAlreadyImported => 'Schon in deinem Liederbuch';

  @override
  String get libraryLicenseBlocked =>
      'Dieses Werk ist nicht frei lizenziert – übersprungen';

  @override
  String get libraryImportFailed => 'Import fehlgeschlagen';

  @override
  String get libraryLoadFailed => 'Bibliothek konnte nicht geladen werden';

  @override
  String get libraryRetry => 'Erneut versuchen';

  @override
  String get libraryNoResults => 'Keine Treffer';

  @override
  String get librarySourcesCredits => 'Quellen & Nachweise';

  @override
  String get libraryNoCredits => 'Noch nichts aus einer Bibliothek importiert';

  @override
  String get libraryCreditsSongs => 'Noten & Lieder';

  @override
  String get libraryCreditsSamples => 'Samples';

  @override
  String get libraryCreditsIntro =>
      'Aus freien Musik-Bibliotheken importierte Werke mit ihren Lizenzen.';

  @override
  String get librarySupportDev => 'Entwickler unterstützen';

  @override
  String get trackerPrompt => 'Wähle ein Instrument und tippe deinen Loop!';

  @override
  String get trackerClear => 'Leeren';

  @override
  String get trackerChannelMelody => 'Melodie';

  @override
  String get trackerChannelSparkle => 'Glitzer';

  @override
  String get trackerChannelZap => 'Zap';

  @override
  String get trackerChannelBass => 'Bass';

  @override
  String get trackerChannelDrums => 'Schlagzeug';

  @override
  String get trackerChannelVoice => 'Stimme';

  @override
  String get trackerToggleNotation => 'Noten zeigen';

  @override
  String get trackerWideRange => 'Großer Tonumfang (mehr Oktaven)';

  @override
  String get trackerSimplified =>
      'Für den Anfänger-Modus vereinfacht (Töne aufs Raster gerundet; Schlagzeug entfällt)';

  @override
  String get trackerImportTune => 'Melodie laden';

  @override
  String get trackerSwing => 'Swing';

  @override
  String get trackerDemoTune => 'Kurze Melodie (C D E G)';

  @override
  String get trackerChangeInstrument => 'Instrument wechseln';

  @override
  String get trackerPattern => 'Muster';

  @override
  String get trackerSong => 'Song';

  @override
  String get trackerPlaySong => 'Song spielen';

  @override
  String get trackerSoftNote => 'Leise Note';

  @override
  String get trackerEffect => 'Effekt';

  @override
  String get trackerEffectNone => 'Keiner';

  @override
  String get trackerEffectArp => 'Arpeggio';

  @override
  String get trackerEffectVibrato => 'Vibrato';

  @override
  String get trackerEffectSlideUp => 'Rauf gleiten';

  @override
  String get trackerEffectSlideDown => 'Runter gleiten';

  @override
  String get trackerImportMod => 'Melodie importieren (MOD/XM/S3M/IT)…';

  @override
  String get trackerExportMod => '.mod exportieren…';

  @override
  String get trackerImportMidi => 'MIDI importieren…';

  @override
  String get trackerImportAbc => 'ABC importieren…';

  @override
  String get trackerExportMidi => 'MIDI exportieren…';

  @override
  String get trackerModFailed => 'Diese .mod ließ sich nicht lesen/schreiben.';

  @override
  String get trackerBorrowSample => 'Instrument leihen…';

  @override
  String get trackerSaveSong => 'Ins Liederbuch';

  @override
  String get trackerImportScore =>
      'Noten importieren (MusicXML/ABC/MEI/kern/MIDI)…';

  @override
  String get trackerExportXml => 'MusicXML exportieren…';

  @override
  String get trackerExportAbc => 'ABC exportieren…';

  @override
  String get trackerExportModule => 'Modul exportieren (.mod/.xm/.s3m/.it)…';

  @override
  String get trackerOpenWorkshop => 'In der Notenwerkstatt öffnen';

  @override
  String get trackerSavedSong => 'Im Liederbuch gespeichert';

  @override
  String get trackerSaveEmpty => 'Erst ein paar Noten setzen';

  @override
  String get trackerBorrowEmpty => 'Dieses Modul hat keine Samples zum Leihen.';

  @override
  String get trackerChangeEffect => 'Kanal-Effekt';

  @override
  String get trackerFxNone => 'Kein';

  @override
  String get trackerFxDelay => 'Echo';

  @override
  String get trackerFxChorus => 'Chorus';

  @override
  String get trackerFxFlanger => 'Flanger';

  @override
  String get trackerFxReverb => 'Hall';

  @override
  String get trackerFxRingMod => 'Roboter';

  @override
  String get trackerFxCrunch => 'Verzerrung';

  @override
  String get trackerSfxrZap => 'Zap';

  @override
  String get trackerSfxrBlip => 'Blip';

  @override
  String get trackerSfxrLaser => 'Laser';

  @override
  String get trackerSfxrCoin => 'Münze';

  @override
  String get trackerSfxrBell => 'Glocke';

  @override
  String get trackerSfxrExplosion => 'Bumm';

  @override
  String get trackerRecord => 'Aufnehmen';

  @override
  String get trackerRecording => 'Nimmt auf…';

  @override
  String get trackerRecordFailed => 'Mikrofon nicht verfügbar.';

  @override
  String get trackerRecordPrompt =>
      'Wähle eine Stimme und nimm 2 Sekunden auf!';

  @override
  String get trackerVoiceNormal => 'Normal';

  @override
  String get trackerVoiceChipmunk => 'Eichhörnchen';

  @override
  String get trackerVoiceMonster => 'Monster';

  @override
  String get trackerVoiceDeep => 'Tief';

  @override
  String get trackerVoiceRobot => 'Roboter';

  @override
  String get trackerVoiceAlien => 'Alien';

  @override
  String get trackerVoiceCyborg => 'Cyborg';

  @override
  String get trackerVoiceRadio => 'Radio';

  @override
  String get trackerVoiceDemon => 'Dämon';

  @override
  String get trackerSpeedSlow => 'Langsam';

  @override
  String get trackerSpeedNormal => 'Normal';

  @override
  String get trackerSpeedFast => 'Schnell';

  @override
  String get trackerAdvancedTitle => 'Tracker · Fortgeschritten';

  @override
  String get trackerOpenAdvanced => 'Tracker (Fortgeschritten)';

  @override
  String get trackerModeToAdvanced => 'Fortgeschritten-Modus';

  @override
  String get trackerModeToBeginner => 'Einsteiger-Modus';

  @override
  String get trackerLength => 'Länge';

  @override
  String get trackerAddTrack => 'Spur hinzufügen';

  @override
  String get trackerRemoveTrack => 'Diese Spur entfernen';

  @override
  String get trackerPlay => 'Abspielen';

  @override
  String get trackerPause => 'Pause';

  @override
  String get trackerStop => 'Stopp';

  @override
  String get trackerBack => 'Zurück';

  @override
  String get trackerForward => 'Vor';

  @override
  String get trackerLoop => 'Schleife';

  @override
  String get trackerPickNote => 'Note wählen';

  @override
  String get trackerOctave => 'Oktave';

  @override
  String get trackerEditStep => 'Schritt';

  @override
  String get trackerPatternNew => 'Neues Pattern';

  @override
  String get trackerPatternClone => 'Pattern klonen';

  @override
  String get trackerTempo => 'Tempo';

  @override
  String get trackerCustomLength => 'Eigene…';

  @override
  String get trackerCustomLengthPrompt => 'Zeilen (z. B. 64, 128, 256)';

  @override
  String get trackerEditStepHelp =>
      'Zeilen, die der Cursor nach jeder Note nach unten springt';

  @override
  String get trackerCancel => 'Abbrechen';

  @override
  String get trackerOk => 'OK';

  @override
  String get trackerEntryPiano => 'Klaviertasten';

  @override
  String get trackerEntryNames => 'Notennamen';

  @override
  String get trackerKeyHelp => 'Tastatur';

  @override
  String get trackerShowKeys => 'Tastenhinweise zeigen';

  @override
  String get trackerRecordLive => 'Live-Aufnahme (ins Pattern jammen)';

  @override
  String get trackerInterpolate => 'Lautstärken interpolieren';

  @override
  String get trackerField => 'Spalte (Note / Lautst. / FX)';

  @override
  String get trackerPlayFromCursor => 'Ab Cursor abspielen';

  @override
  String get trackerMetronome => 'Metronom';

  @override
  String get trackerFollow => 'Abspielposition folgen';

  @override
  String get trackerScope => 'Oszilloskop ein/aus';

  @override
  String get trackerLoadDemo => 'Demo-Song laden';

  @override
  String get trackerZoomIn => 'Vergrößern';

  @override
  String get trackerZoomOut => 'Verkleinern';

  @override
  String get trackerClassicSkin => 'Klassischer Tracker-Look';

  @override
  String get trackerInsertRow => 'Zeile einfügen (am Cursor)';

  @override
  String get trackerDeleteRow => 'Zeile löschen (am Cursor)';

  @override
  String get trackerFxHelp => 'In der FX-Spalte tippen: Befehl + 2 Hex-Ziffern';

  @override
  String get trackerFxPitch =>
      'Arpeggio · Porta rauf/runter · Ton-Porta · Vibrato';

  @override
  String get trackerFxTremVolSet =>
      'Tremolo · Lautstärke-Slide · Lautstärke setzen';

  @override
  String get trackerFxFlow =>
      'Sprung · Pattern-Break · Speed/Tempo · Erweitert';

  @override
  String get trackerOrderMoveLeft => 'Platz nach links';

  @override
  String get trackerOrderMoveRight => 'Platz nach rechts';

  @override
  String get trackerOrderInsert => 'Kopie einfügen';

  @override
  String get trackerOrderPrevPat => 'Platz → vorheriges Pattern';

  @override
  String get trackerOrderNextPat => 'Platz → nächstes Pattern';

  @override
  String get trackerClearCell => 'Zelle löschen';

  @override
  String get trackerClearConfirm =>
      'Das ganze Pattern löschen? Das kann nicht rückgängig gemacht werden.';

  @override
  String get trackerCursor => 'Cursor bewegen';

  @override
  String get trackerFxColumn => 'Effekt-Spalte (MOD)';

  @override
  String get trackerMixer => 'Spuren & Mixer';

  @override
  String get trackerGain => 'Lautstärke';

  @override
  String get trackerPan => 'Panorama (links ↔ rechts)';

  @override
  String get trackerEnvelope => 'Lautstärkeverlauf (Hüllkurve)';

  @override
  String get trackerEnvFlat => 'Gleichbleibend';

  @override
  String get trackerEnvFadeIn => 'Einblenden';

  @override
  String get trackerEnvFadeOut => 'Ausblenden';

  @override
  String get trackerEnvPluck => 'Zupfen (schnell abklingend)';

  @override
  String get trackerEnvSwell => 'Anschwellen';

  @override
  String get trackerAutoPan => 'Auto-Panorama';

  @override
  String get trackerPanOff => 'Aus (fest)';

  @override
  String get trackerPanLR => 'Links → rechts';

  @override
  String get trackerPanRL => 'Rechts → links';

  @override
  String get trackerPanPingPong => 'Ping-Pong';

  @override
  String get trackerInstruments => 'Instrument für neue Noten';

  @override
  String get trackerInstrumentDefault => 'Spur-Standard';

  @override
  String get trackerRecordSample => 'Sample aufnehmen';

  @override
  String get trackerSampleTrim => 'Stille kürzen';

  @override
  String get trackerSampleTrimDrag => 'Zum Kürzen die Griffe ziehen';

  @override
  String get trackerSampleNormalize => 'Normalisieren';

  @override
  String get trackerSampleReverse => 'Umkehren';

  @override
  String get trackerSampleSustain => 'Halten';

  @override
  String get trackerAssignSample => 'Für diese Spur verwenden';

  @override
  String get trackerLoadWav => 'WAV-Datei laden…';

  @override
  String get trackerMySamples => 'Aus Meine Samples';

  @override
  String get trackerFreeSounds => 'Freie Klänge durchsuchen…';

  @override
  String get trackerStarterBeat => 'Starter-Beat hinzufügen';

  @override
  String get trackerLoadSoundFont => 'SoundFont laden…';

  @override
  String get trackerSoundLibrary => 'Klangbibliothek';

  @override
  String get trackerAddFromLibrary => 'Aus Bibliothek hinzufügen…';

  @override
  String get trackerLibTonal => 'Tonal';

  @override
  String get trackerLibPlucked => 'Gezupft';

  @override
  String get trackerLibChiptune => 'Chiptune';

  @override
  String get trackerLibDrum => 'Schlagzeug';

  @override
  String get trackerLibRecorded => 'Aufgenommen';

  @override
  String get trackerLibPercussion => 'Perkussion (CC0)';

  @override
  String get trackerRemove => 'Entfernen';

  @override
  String get trackerShareSong => 'Song teilen (Token)';

  @override
  String get trackerLoadSong => 'Song laden (Token)';

  @override
  String get trackerSongCopied => 'Song-Token in die Zwischenablage kopiert';

  @override
  String get trackerCopy => 'Kopieren';

  @override
  String get trackerClose => 'Schließen';

  @override
  String get trackerPasteToken => 'Song-Token einfügen (CBS1.…)';

  @override
  String get trackerLoad => 'Laden';

  @override
  String get trackerTokenInvalid => 'Das ist kein gültiges Song-Token.';

  @override
  String get trackerModArchive => 'The Mod Archive durchsuchen…';

  @override
  String get modArchiveTitle => 'The Mod Archive';

  @override
  String get modArchiveKeyPrompt =>
      'Durchsucht nur CC0-/Public-Domain-Module und benötigt deinen eigenen kostenlosen API-Schlüssel von modarchive.org.';

  @override
  String get modArchiveKeyLabel => 'API-Schlüssel';

  @override
  String get modArchiveGetKey => 'Schlüssel holen';

  @override
  String get modArchiveSaveKey => 'Speichern';

  @override
  String get trackerPreview => 'Vorhören';

  @override
  String get trackerCopyInstrument => 'Instrument kopieren nach…';

  @override
  String get trackerBlock => 'Block';

  @override
  String get trackerBlockMark => 'Markieren (Zellen antippen)';

  @override
  String get trackerBlockTrack => 'Spur auswählen';

  @override
  String get trackerBlockPattern => 'Pattern auswählen';

  @override
  String get trackerBlockCopy => 'Kopieren';

  @override
  String get trackerBlockCut => 'Ausschneiden';

  @override
  String get trackerBlockPaste => 'Einfügen (überschreiben)';

  @override
  String get trackerBlockPasteMix => 'Misch-Einfügen (Lücken füllen)';

  @override
  String get trackerBlockTransUp => 'Transponieren +1';

  @override
  String get trackerBlockTransDown => 'Transponieren −1';

  @override
  String get trackerBlockOctUp => 'Transponieren +Oktave';

  @override
  String get trackerBlockOctDown => 'Transponieren −Oktave';

  @override
  String get trackerBlockClear => 'Block löschen';

  @override
  String get trackerBlockUnmark => 'Markierung aufheben';

  @override
  String get trackerTutGrid =>
      'Das ist ein Pattern-Raster: Die Zeit läuft von oben nach unten in Zeilen, jede Spalte ist eine Spur. Tippe eine Zelle an, um den Cursor zu setzen, und spiele dann eine Note hinein.';

  @override
  String get trackerTutKeys =>
      'Gib Noten über die Computertastatur ein. „Klaviertasten“ nutzt das klassische Tracker-Layout (Z–M ist eine Oktave, Q–I die nächste). „Notennamen“ erlaubt Buchstabe + Oktavziffer, z. B. F dann 2 = F2. Der ⓘ-Knopf zeigt alle Tastenkürzel. Auf dem Touchscreen nutzt du das Klavier unten.';

  @override
  String get trackerTutStep =>
      '„Schritt“ ist, wie viele Zeilen der Cursor nach jeder Note nach unten springt — stell ihn auf deinen Takt (z. B. 4), um schnell Noten zu setzen, oder auf 0, um auf einer Zeile zu bleiben.';

  @override
  String get trackerTutTransport =>
      'Die Transportleiste spielt und pausiert, stoppt und springt vor/zurück. „Länge“ legt fest, wie viele Zeilen ein Pattern hat (keine 2–3 Takte mehr!), und „Tempo“ die Geschwindigkeit.';

  @override
  String get trackerTutArrange =>
      'Baue mehrere Patterns und reihe sie zu einem Song: Füge jedes zur Reihenfolge hinzu und drücke „Song abspielen“.';

  @override
  String get trackerTutTracks =>
      'Füge beliebig viele Spuren hinzu, gib jeder ein eigenes Instrument und schalte sie stumm (M) oder solo (S). Du kannst sogar ein echtes .mod/.xm/.s3m/.it-Modul importieren und bearbeiten.';

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
  String get importMusicFile =>
      'Datei importieren (MusicXML/MXL/ABC/MEI/kern/MIDI)…';

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
  String get gameKeyFindBass => 'Taste finden (Bass)';

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
  String get gameSpotParallels => 'Parallelen finden';

  @override
  String get gameSpotParallelsSubtitle =>
      'Saubere Stimmführung oder verbotene Parallelen?';

  @override
  String get spotParallelsPrompt =>
      'Zwischen diesen beiden Akkorden — ist die Stimmführung sauber oder rutscht sie in Parallelen?';

  @override
  String get spotParallelsListen => 'Anhören';

  @override
  String get spotParallelsClean => 'Sauber';

  @override
  String get spotParallelsParallel => 'Parallelen!';

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
  String get gameModulation => 'Tonartwechsel?';

  @override
  String get gameModulationSubtitle => 'Wechselt die Melodie die Tonart?';

  @override
  String get modulationPrompt => 'Bleibt es in einer Tonart oder wechselt es?';

  @override
  String get modulationSame => 'Gleiche Tonart';

  @override
  String get modulationChanged => 'Tonart gewechselt';

  @override
  String get primerModulationTitle => 'Gleiche Tonart oder eine neue?';

  @override
  String get primerModulationStay =>
      'Eine Melodie hat einen Grundton. Hier steigt sie auf und kehrt beide Male zum selben Grundton zurück — sie bleibt in einer Tonart.';

  @override
  String get primerModulationMove =>
      'Diesmal ist die zweite Hälfte höher und landet auf einem neuen Grundton. Die Musik hat die Tonart gewechselt — das ist eine Modulation.';

  @override
  String get listenMajorMinorPrompt => 'Hör zu! Klingt das nach Dur oder Moll?';

  @override
  String get listenAgain => 'Nochmal anhören';

  @override
  String get majorLabel => 'Dur';

  @override
  String get minorLabel => 'Moll';

  @override
  String get diminishedLabel => 'Vermindert';

  @override
  String get augmentedLabel => 'Übermäßig';

  @override
  String get gameMajorMinorSort => 'Dur oder Moll?';

  @override
  String get gameMajorMinorSortSubtitle =>
      'Lies jeden Dreiklang und sortiere ihn nach Geschlecht';

  @override
  String get majorMinorSortPrompt => 'Ziehe jeden Akkord in seinen Korb';

  @override
  String get listenChordQualityPrompt => 'Hör zu! Welche Akkordart ist das?';

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
  String get intervalFourth => 'Quarte';

  @override
  String get intervalFifth => 'Quinte';

  @override
  String get intervalSixth => 'Sexte';

  @override
  String get intervalOctave => 'Oktave';

  @override
  String get gameTriadSeventh => 'Dreiklang oder Septakkord?';

  @override
  String get gameTriadSeventhSubtitle =>
      'Höre einen Akkord — drei Töne oder vier mit Septime?';

  @override
  String get triadSeventhPrompt => 'Dreiklang oder Septakkord?';

  @override
  String get triadLabel => 'Dreiklang';

  @override
  String get seventhLabel => 'Septakkord';

  @override
  String get gameSingInterval => 'Intervall singen';

  @override
  String get gameSingIntervalSubtitle =>
      'Höre ein Intervall und singe den oberen Ton nach';

  @override
  String singIntervalPrompt(String interval) {
    return 'Singe den oberen Ton — eine $interval höher!';
  }

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
  String get gameTransposeWrite => 'Für das Instrument notieren';

  @override
  String get gameTransposeWriteSubtitle =>
      'Nenne die Note, die das Instrument lesen muss';

  @override
  String transposeWritePrompt(String instrument) {
    return 'Welche Note liest ein $instrument, damit dies klingt?';
  }

  @override
  String get transposeWriteHint =>
      'Ein transponierendes Instrument liest eine andere Note als die, die klingt.';

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
  String get gameSpacingRead => 'Eng oder weit?';

  @override
  String get gameSpacingReadSubtitle =>
      'Lies die SATB-Lage — gedrängt oder gespreizt?';

  @override
  String get spacingReadPrompt => 'Stehen die Oberstimmen eng oder weit?';

  @override
  String get spacingClose => 'Eng';

  @override
  String get spacingOpen => 'Weit';

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
  String get clefTenor => 'Tenorschlüssel';

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
  String get gameConnectDynamics => 'Dynamik verbinden';

  @override
  String get gameConnectDynamicsSubtitle =>
      'Verbinde jedes Dynamikzeichen mit seiner Lautstärke (pp = sehr leise)';

  @override
  String get connectDynamicsPrompt =>
      'Wie laut? Verbinde jedes Zeichen mit seiner Bedeutung!';

  @override
  String get dynVerySoft => 'sehr leise';

  @override
  String get dynSoft => 'leise';

  @override
  String get dynMediumSoft => 'etwas leise';

  @override
  String get dynMediumLoud => 'etwas laut';

  @override
  String get dynLoud => 'laut';

  @override
  String get dynVeryLoud => 'sehr laut';

  @override
  String get gameConnectRests => 'Pausen verbinden';

  @override
  String get gameConnectRestsSubtitle =>
      'Verbinde jede Pause mit der Note, so lang wie sie dauert';

  @override
  String get connectRestsPrompt =>
      'Wie lang ist die Stille? Verbinde jede Pause mit ihrer Note!';

  @override
  String get gameConnectTempo => 'Tempo-Wörter verbinden';

  @override
  String get gameConnectTempoSubtitle =>
      'Verbinde jedes italienische Tempo-Wort mit seiner Bedeutung (Largo = sehr langsam)';

  @override
  String get connectTempoPrompt =>
      'Wie schnell? Verbinde jedes Tempo-Wort mit seiner Bedeutung!';

  @override
  String get tempoVerySlow => 'sehr langsam';

  @override
  String get tempoSlow => 'langsam';

  @override
  String get tempoWalking => 'Schritttempo';

  @override
  String get tempoModerate => 'mäßig';

  @override
  String get tempoFast => 'schnell';

  @override
  String get tempoLively => 'lebhaft';

  @override
  String get tempoVeryFast => 'sehr schnell';

  @override
  String get gameConnectBeats => 'Schläge verbinden';

  @override
  String get gameConnectBeatsSubtitle =>
      'Verbinde jede Note damit, wie viele Schläge sie im 4/4-Takt dauert';

  @override
  String get connectBeatsPrompt =>
      'Wie viele Schläge? Verbinde jede Note mit ihrer Zahl (im 4/4-Takt)!';

  @override
  String get gameConnectDegrees => 'Tonstufen verbinden';

  @override
  String get gameConnectDegreesSubtitle =>
      'Ordne jeder Stufennummer ihren Namen zu (1 = Tonika, 5 = Dominante)';

  @override
  String get connectDegreesPrompt =>
      'Ordne jede Tonstufen-Nummer ihrem Namen zu — tippe zum Hören!';

  @override
  String get degreeTonic => 'Tonika';

  @override
  String get degreeSupertonic => 'Supertonika';

  @override
  String get degreeMediant => 'Mediante';

  @override
  String get degreeSubdominant => 'Subdominante';

  @override
  String get degreeDominant => 'Dominante';

  @override
  String get degreeSubmediant => 'Submediante';

  @override
  String get degreeLeadingTone => 'Leitton';

  @override
  String get gameConnectTime => 'Taktarten verbinden';

  @override
  String get gameConnectTimeSubtitle =>
      'Ordne jeder Taktart zu, was ihre Zahlen bedeuten';

  @override
  String get connectTimePrompt =>
      'Was bedeuten die Zahlen? Verbinde jede Taktart mit ihren Schlägen!';

  @override
  String get timeSigMeaning44 => 'Vier Viertel-Schläge';

  @override
  String get timeSigMeaning34 => 'Drei Viertel-Schläge';

  @override
  String get timeSigMeaning24 => 'Zwei Viertel-Schläge';

  @override
  String get timeSigMeaning68 => 'Sechs Achtel-Schläge';

  @override
  String get timeSigMeaning22 => 'Zwei Halbe-Schläge';

  @override
  String get timeSigMeaning98 => 'Neun Achtel-Schläge';

  @override
  String get timeSigMeaning128 => 'Zwölf Achtel-Schläge';

  @override
  String get timeSigMeaning54 => 'Fünf Viertel-Schläge';

  @override
  String get gameConnectKeysig => 'Vorzeichen verbinden';

  @override
  String get gameConnectKeysigSubtitle =>
      'Ordne jeder Tonart zu, wie viele Kreuze oder Be sie hat';

  @override
  String get connectKeysigPrompt =>
      'Wie viele Kreuze oder Be? Verbinde jede Tonart mit ihrer Anzahl!';

  @override
  String get keySigNone => 'Keine Vorzeichen';

  @override
  String keySigSharps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Kreuze',
      one: '1 Kreuz',
    );
    return '$_temp0';
  }

  @override
  String keySigFlats(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ♭',
      one: '1 ♭',
    );
    return '$_temp0';
  }

  @override
  String get gameConnectRoadmap => 'Wegweiser verbinden';

  @override
  String get gameConnectRoadmapSubtitle =>
      'Ordne jedem Navigationszeichen zu, was es dir sagt';

  @override
  String get connectRoadmapPrompt =>
      'Lies die Landkarte! Verbinde jeden Wegweiser mit seiner Bedeutung.';

  @override
  String get roadmapDaCapo => 'Zurück zum Anfang';

  @override
  String get roadmapDalSegno => 'Zurück zum Segno-Zeichen';

  @override
  String get roadmapFine => 'Das Ende — hier aufhören';

  @override
  String get roadmapCoda => 'Zum Schlussteil springen';

  @override
  String get roadmapSegno => 'Das Zeichen, zu dem du zurückspringst';

  @override
  String get roadmapAlFine => '…weiter bis Fine';

  @override
  String get roadmapAlCoda => '…dann zur Coda springen';

  @override
  String get beatCount4 => '4 Schläge';

  @override
  String get beatCount2 => '2 Schläge';

  @override
  String get beatCount1 => '1 Schlag';

  @override
  String get beatCountHalf => '½ Schlag';

  @override
  String get beatCountQuarter => '¼ Schlag';

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
  String get primerSpacingTitle => 'Eng und weit';

  @override
  String get primerSpacingClose =>
      'In der ENGEN Lage stehen die oberen drei Stimmen dicht beieinander — die höchste Stimme und der Tenor liegen innerhalb einer Oktave.';

  @override
  String get primerSpacingOpen =>
      'In der WEITEN Lage sind die Oberstimmen gespreizt — die höchste Note liegt mehr als eine Oktave über dem Tenor.';

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
  String get primerIntervalsSong =>
      'Intervalle kennst du schon aus Liedern! Der Ruf des Kuckucks — „Kuck-uck“ — ist eine fallende kleine Terz. „Alle meine Entchen“ beginnt mit einer großen Sekunde aufwärts.';

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
  String get primerUpbeatTitle => 'Mit dem Auftakt beginnen';

  @override
  String get primerUpbeatDownbeat =>
      'Die meisten Stücke beginnen auf Zählzeit 1 — dem betonten Taktanfang. Zähl „1-2-3-4“ und fang auf der 1 an.';

  @override
  String get primerUpbeatUpbeat =>
      'Ein Auftakt beginnt mit einer oder zwei Noten VOR dem ersten Taktstrich, die zur 1 hinführen. Hör hin — die Melodie holt Schwung.';

  @override
  String get primerEnharmonicTitle => 'Derselbe Ton, zwei Namen';

  @override
  String get primerEnharmonicSame =>
      'Diese Klaviertaste kann Fis oder Ges heißen — genau derselbe Klang, zwei Schreibweisen. Das sind „enharmonische“ Zwillinge.';

  @override
  String get primerEnharmonicTwins =>
      'Fis und Ges klingen also gleich. Weitere Zwillinge: Cis=Des, Dis=Es, Gis=As, Ais=B.';

  @override
  String get primerExpressionTitle => 'Schnell oder langsam, laut oder leise';

  @override
  String get primerExpressionTempo =>
      'Ausdruck ist das WIE des Spielens. Ein Teil ist das Tempo: hör diese Phrase erst langsam, dann schnell.';

  @override
  String get primerExpressionDynamics =>
      'Der andere Teil ist die Lautstärke (Dynamik): dieselbe Phrase leise (p), dann laut (f). Bei Charade nennst du, was du gehört hast.';

  @override
  String get primerTempoTitle => 'Wie schnell? Tempo-Wörter';

  @override
  String get primerTempoSlow =>
      'Über einem Stück steht ein italienisches Wort für das Tempo. Largo ist sehr langsam, Adagio langsam. Hör hin — diese vier Noten sind Adagio.';

  @override
  String get primerTempoFast =>
      'Allegro ist schnell, Presto sehr schnell. Dieselben vier Noten, nur schneller — hör den Unterschied.';

  @override
  String get primerDynamicsTitle => 'Wie laut? p und f';

  @override
  String get primerDynamicsSoft =>
      'Die Dynamik sagt dir, wie laut du spielst. p (piano) heißt leise — und pp (pianissimo) sehr leise. Hör hin: das ist piano.';

  @override
  String get primerDynamicsLoud =>
      'f (forte) heißt laut, ff (fortissimo) sehr laut. Dieselben Noten noch einmal — jetzt forte.';

  @override
  String get primerDottedTitle => 'Der Punkt, der die Hälfte dazugibt';

  @override
  String get primerDottedPlain =>
      'Eine halbe Note dauert 2 Schläge. Zähl „1-2“, solange sie klingt.';

  @override
  String get primerDottedDotted =>
      'Ein Punkt hinter der Note gibt die HÄLFTE ihres Wertes dazu: 2 Schläge + 1 = eine punktierte Halbe mit 3 Schlägen. Zähl „1-2-3“.';

  @override
  String get primerRestsTitle => 'Auch Stille hat eine Länge';

  @override
  String get primerRestsSilence =>
      'Eine Pause ist Stille — und sie wird mitgezählt wie eine Note. Hier heißt es: spielen, Pause, spielen, Pause — je ein Schlag.';

  @override
  String get primerRestsMatch =>
      'Zu jedem Notenwert gibt es eine passende Pause. Eine halbe Note klingt 2 Schläge; eine halbe Pause ist 2 Schläge Stille.';

  @override
  String get primerCurveTitle => 'Haltebogen und Bindebogen';

  @override
  String get primerCurveTie =>
      'Ein HALTEBOGEN verbindet zwei Noten mit DERSELBEN Tonhöhe. Spiel die zweite nicht neu an — halte die erste durch beide hindurch. C mit C verbunden ist ein langes C.';

  @override
  String get primerCurveSlur =>
      'Ein BINDEBOGEN spannt sich über VERSCHIEDENE Tonhöhen. Spiel sie weich und ohne Lücke verbunden — das heißt legato.';

  @override
  String get primerArticulationTitle => 'Wie du die Note spielst';

  @override
  String get primerArticulationStaccato =>
      'Ein Punkt über oder unter dem Notenkopf ist Staccato: kurz und abgesetzt spielen, mit Luft danach. (Achtung — ein Punkt NEBEN der Note macht sie stattdessen länger!)';

  @override
  String get primerArticulationAccent =>
      'Ein Keil > ist ein Akzent: gib dieser Note einen extra Schubs, damit sie hervorsticht.';

  @override
  String get primerBeamTitle => 'Fähnchen und Balken';

  @override
  String get primerBeamFlag =>
      'Eine einzelne Achtelnote trägt ein Fähnchen am Hals. Hier trennt je eine Pause die Achtel, darum behält jede ihr eigenes Fähnchen.';

  @override
  String get primerBeamBeam =>
      'Liegen Achtel auf demselben Schlag, verbindet sie ein BALKEN statt der Fähnchen — derselbe Klang, nur übersichtlicher zu lesen.';

  @override
  String get primerToneTitle => 'Halbtöne und Ganztöne';

  @override
  String get primerToneHalf =>
      'Ein Halbton ist der kleinste Schritt auf der Klaviatur — direkte Nachbarn, nichts dazwischen. E zu F ist ein Halbton: keine schwarze Taste dazwischen.';

  @override
  String get primerToneWhole =>
      'Ein Ganzton sind zwei Halbtöne. C zu D ist ein Ganzton — dazwischen LIEGT eine schwarze Taste.';

  @override
  String get primerClefTitle => 'Welcher Schlüssel?';

  @override
  String get primerClefTreble =>
      'Der Violinschlüssel (G-Schlüssel) windet sich um die Linie, die G bedeutet. Er steht für hohe Töne — rechte Hand, Flöte, Geige.';

  @override
  String get primerClefBass =>
      'Der Bassschlüssel (F-Schlüssel) setzt zwei Punkte um die Linie, die F bedeutet. Er steht für tiefe Töne — linke Hand, Cello, Bass.';

  @override
  String get primerVoicesTitle => 'Vier Stimmen gleichzeitig';

  @override
  String get primerVoicesChord =>
      'Ein Chor singt vier Linien zusammen: Sopran (am höchsten), Alt, Tenor, Bass (am tiefsten). Gleichzeitig erklingen sie als Akkord.';

  @override
  String get primerVoicesFollow =>
      'Um eine Stimme zu lesen, folge nur ihrer Linie: der Sopran ist die oberste Note, der Bass die unterste. Hör hin — erst oben, dann unten.';

  @override
  String get primerDirectionTitle => 'Aufwärts oder abwärts?';

  @override
  String get primerDirectionUp =>
      'Wenn eine Melodie steigt, ist jede Note höher als die davor — im Notenbild wandern die Noten nach oben, und der Klang geht hinauf.';

  @override
  String get primerDirectionDown =>
      'Wenn sie fällt, ist jede Note tiefer als die davor — die Noten wandern nach unten, und der Klang sinkt.';

  @override
  String get primerSameDiffTitle => 'Gleich oder verschieden?';

  @override
  String get primerSameDiffSame =>
      'Zwei Noten mit DERSELBEN Tonhöhe klingen genau gleich — wie ein Echo. Im Notenbild stehen sie an genau derselben Stelle.';

  @override
  String get primerSameDiffDifferent =>
      'Ist die zweite Note auch nur einen Schritt höher oder tiefer, ist sie verschieden — und steht woanders. Hör hin: C, dann D.';

  @override
  String get primerCountTitle => 'Wie viele Noten?';

  @override
  String get primerCountThree =>
      'Hör hin und zähl, wie viele einzelne Noten vorbeikommen. Hier sind es drei — zähl bei jedem neuen Klang eins weiter.';

  @override
  String get primerCountFour =>
      'Jetzt vier. Sie kommen schnell, also zähl jede sofort mit, wenn sie erklingt.';

  @override
  String get primerAccentTitle => 'Betonte und unbetonte Schläge';

  @override
  String get primerAccentCount =>
      'Im 4/4-Takt zählst du immer 1-2-3-4. Die 1 ist der BETONTE Schlag — der, den du am stärksten klopfst. Die 2, 3 und 4 sind leichter.';

  @override
  String get primerAccentThree =>
      'Die Taktart bestimmt, welcher Schlag betont ist. Im 3/4-Takt zählst du 1-2-3, und wieder ist die 1 betont — der Schwung eines Walzers.';

  @override
  String get primerSeventhTitle => 'Die Septime dazu';

  @override
  String get primerSeventhTriad =>
      'Ein Dreiklang sind drei Töne — nimm einen, überspring einen, nimm den nächsten: C, E, G. Das ist C-Dur und klingt in sich ruhend.';

  @override
  String get primerSeventhAdd =>
      'Nimm auf dieselbe Weise NOCH einen Ton dazu (überspring einen, nimm den nächsten): C E G B. Das ist ein Septakkord — er klingt unruhig, als wollte er weiter.';

  @override
  String get primerRomanTitle => 'Akkorde nummerieren';

  @override
  String get primerRomanDegree =>
      'Nummeriere die Töne der Tonleiter von 1 bis 7. Auf jeder Stufe baust du einen Akkord und benennst ihn mit einer römischen Ziffer. Auf Stufe 1 von C-Dur steht C E G — Akkord I.';

  @override
  String get primerRomanCase =>
      'GROSSBUCHSTABEN meinen einen Dur-Akkord (I, IV, V); kleine Ziffern meinen Moll (ii, iii, vi). Auf Stufe 2 von C-Dur steht D F A — Akkord ii, d-Moll.';

  @override
  String get primerCadenceTitle => 'Wie eine Phrase endet';

  @override
  String get primerCadenceFull =>
      'Eine Kadenz ist, wie eine Phrase endet — wie das Ende eines Satzes. Auf dem HEIMAT-Akkord zu enden klingt fertig, wie ein Punkt. Hör hin: weg, dann heim.';

  @override
  String get primerCadenceHalf =>
      'Endest du auf einem anderen Akkord, hängt es in der Luft — wie ein Fragezeichen. Dein Ohr erwartet, dass mehr kommt. Hör hin: heim, dann weg.';

  @override
  String get primerPhraseTitle => 'Frage und Antwort';

  @override
  String get primerPhraseQuestion =>
      'Musik kommt in Phrasen, wie Sätze. Diese hier steigt weg und bleibt in der Luft stehen — sie klingt wie eine FRAGE.';

  @override
  String get primerPhraseAnswer =>
      'Die antwortende Phrase kehrt zu dem Ton zurück, mit dem die Melodie begann — ihrem Heimatton. Darum klingt sie abgeschlossen.';

  @override
  String get primerBowTitle => 'Wohin der Bogen geht';

  @override
  String get primerBowDown =>
      '⊓ heißt ABSTRICH: Zieh den Bogen vom Frosch (deiner Hand) zur Spitze. Das ist die schwerere Richtung — sie passt zu betonten Schlägen.';

  @override
  String get primerBowUp =>
      '∨ heißt AUFSTRICH: Schieb von der Spitze zurück zum Frosch. Der ist leichter — gut für Auftakte und Anläufe.';

  @override
  String get primerTenorTitle => 'Der Tenorschlüssel';

  @override
  String get primerTenorC =>
      'Der Tenorschlüssel ist ein C-Schlüssel: die Mitte des Zeichens zeigt genau auf das eingestrichene C. Auf welcher Linie das Zeichen sitzt, DIESE Linie ist das c′.';

  @override
  String get primerTenorWhy =>
      'Celli und Posaunen nutzen ihn für ihre hohen Töne — so bleiben sie im Notensystem, statt über dem Bassschlüssel Hilfslinien zu stapeln.';

  @override
  String get primerGrandTitle => 'Zwei Systeme, zwei Hände';

  @override
  String get primerGrandTop =>
      'Klavier schreibt man im SYSTEM aus zwei Notenzeilen, verbunden durch eine Klammer. Die obere ist der Violinschlüssel — meist deine rechte Hand.';

  @override
  String get primerGrandBottom =>
      'Die untere ist der Bassschlüssel — meist deine linke Hand. Das eingestrichene C liegt in der Lücke dazwischen, auf einer eigenen kleinen Hilfslinie.';

  @override
  String get colorScaffoldLabel => 'Farbhilfe für Anfänger';

  @override
  String get colorScaffoldSubtitle =>
      'Noten nach ihrem Buchstaben einfärben — später einfach ausschalten';

  @override
  String get notationFontLabel => 'Notenschriftart';

  @override
  String get notationFontSubtitle =>
      'Die Schrift, mit der Noten und Symbole gezeichnet werden.';

  @override
  String get scoreFontBravura => 'Bravura';

  @override
  String get scoreFontPetaluma => 'Petaluma (handgeschrieben)';

  @override
  String get scoreFontLeland => 'Leland';

  @override
  String get scoreFontLeipzig => 'Leipzig';

  @override
  String get showNoteNamesLabel => 'Notennamen unter dem System';

  @override
  String get showNoteNamesSubtitle =>
      'Den Buchstaben jeder Note als Lesehilfe anzeigen — versteckt in Spielen, in denen das Benennen die Aufgabe ist';

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
      'CometBeat läuft vollständig auf deinem Gerät. Mikrofon-Audio (für Stimmgerät und Mitspielen) wird lokal in Echtzeit analysiert – niemals aufgezeichnet, gespeichert oder übertragen. Es gibt keine Konten, keine Werbung und kein Tracking.';

  @override
  String get aboutDisclaimer => 'Haftungsausschluss';

  @override
  String get aboutDisclaimerText =>
      'CometBeat ist eine Lernhilfe und wird ohne Gewähr bereitgestellt. Die Lehrplan-Stufen sind allgemeine Orientierung, kein offizieller Lehrplan.';

  @override
  String get aboutCredits => 'Danksagungen';

  @override
  String get aboutCreditsText =>
      'Der Notensatz verwendet die Schriftart Bravura (SIL Open Font License).';

  @override
  String get aboutOpenSourceLicenses => 'Open-Source-Lizenzen';

  @override
  String get gameSyncRead => 'Auf dem Schlag oder daneben?';

  @override
  String get gameSyncReadSubtitle => 'Gerader Rhythmus oder synkopiert?';

  @override
  String get syncReadPrompt =>
      'Ist dieser Rhythmus auf dem Schlag oder synkopiert?';

  @override
  String get syncReadStraight => 'Auf dem Schlag';

  @override
  String get syncReadSyncopated => 'Synkopiert';

  @override
  String get gameTripletRead => 'Gerade oder Triole?';

  @override
  String get gameTripletReadSubtitle =>
      'Wird der Schlag in zwei oder in drei geteilt?';

  @override
  String get tripletReadPrompt => 'Wie wird der Schlag geteilt?';

  @override
  String get tripletReadEven => 'Gerade (2)';

  @override
  String get tripletReadTriplet => 'Triole (3)';

  @override
  String get gameOrnamentRead => 'Welche Verzierung?';

  @override
  String get gameOrnamentReadSubtitle =>
      'Lies Triller, Mordent oder Doppelschlag';

  @override
  String get ornamentReadPrompt => 'Welche Verzierung steht über der Note?';

  @override
  String get ornamentTrill => 'Triller';

  @override
  String get ornamentMordent => 'Mordent';

  @override
  String get ornamentTurn => 'Doppelschlag';

  @override
  String get primerSyncTitle => 'Auf dem Schlag oder daneben?';

  @override
  String get primerSyncStraight =>
      'Meist landen die Noten genau AUF den Schlägen — zähl 1-2-3-4, und jede Note fällt auf eine Zahl. Ruhig und gerade.';

  @override
  String get primerSyncOff =>
      'Die Synkope schiebt Noten NEBEN den Schlag, auf das „und“ dazwischen. Die Betonung kommt, wo dein Ohr sie nicht erwartet — das ist der Groove in Pop und Jazz.';

  @override
  String get primerTripletTitle => 'Zwei oder drei im Schlag';

  @override
  String get primerTripletEven =>
      'Normalerweise teilt sich ein Schlag in ZWEI gleiche Hälften: „1-und“. Zwei Achtelnoten.';

  @override
  String get primerTripletThree =>
      'Eine Triole quetscht DREI gleiche Noten in denselben Schlag: „tri-o-le“. Darüber steht eine kleine 3.';

  @override
  String get primerOrnamentTitle => 'Eine Note verzieren';

  @override
  String get primerOrnamentTrill =>
      'Verzierungen sind kleine Zeichen, die eine Note schmücken. Ein Triller (tr) wechselt schnell zwischen der Note und der direkt darüber.';

  @override
  String get primerOrnamentTurn =>
      'Ein Doppelschlag (ein liegendes S) windet sich UM die Note: die Note darüber, die Note, die darunter, dann zurück. Ein Mordent ist nur ein kurzer Schlenker hinauf und zurück.';

  @override
  String get gameFormRead => 'Die Form benennen';

  @override
  String get gameFormReadSubtitle => 'Hör die Teile; benenne die Form (ABA …)';

  @override
  String get formReadPrompt =>
      'Welche Form ist das? (gleiche Farbe = gleiche Melodie)';

  @override
  String get formReadListen => 'Anhören';

  @override
  String get primerFormTitle => 'Die Form eines Stücks';

  @override
  String get primerFormSection =>
      'Musik besteht aus Teilen. Hier ist eine kleine Melodie — nenn sie Teil A. Immer wenn sie wiederkommt, ist es wieder A.';

  @override
  String get primerFormAba =>
      'Eine andere Melodie ist ein neuer Buchstabe — Teil B. Melodie, andere Melodie, dann wieder die erste ergibt die Form A-B-A. Ganz viele Lieder sind so gebaut!';

  @override
  String get gameMode => 'Welcher Modus?';

  @override
  String get gameModeSubtitle => 'Dur, Moll oder Dorisch?';

  @override
  String get modePrompt => 'Hör hin! Welcher Modus ist das?';

  @override
  String get modeMajor => 'Dur';

  @override
  String get modeMinor => 'Moll';

  @override
  String get modeDorian => 'Dorisch';

  @override
  String get primerModeTitle => 'Drei Farben einer Tonleiter';

  @override
  String get primerModeMajor =>
      'Eine Dur-Tonleiter klingt hell und fröhlich. Hör, wie sie nach oben steigt.';

  @override
  String get primerModeMinor =>
      'Eine Moll-Tonleiter klingt dunkler — ihre 3., 6. und 7. Stufe liegen etwas tiefer.';

  @override
  String get primerModeDorian =>
      'Dorisch ist wie Moll, aber die 6. Stufe ist erhöht — es klingt nach Moll mit einem helleren Schimmer. Diese eine Note ist das ganze Geheimnis!';

  @override
  String get textbookTitle => 'Lehrbuch';

  @override
  String get textbookIntro =>
      'Arbeite dich von ganz vorne durch die Musik. Zu jedem Thema gibt es eine kurze Lektion (sehen, hören) und Spiele zum Üben.';

  @override
  String get textbookComingSoon => 'Lektion folgt bald';

  @override
  String get textbookReadLesson => 'Lektion lesen';

  @override
  String get textbookPractise => 'Üben';

  @override
  String get formAnalysisTitle => 'Die Form sehen';

  @override
  String get formAnalysisPlayWhole => 'Ganzes Stück abspielen';

  @override
  String get formAnalysisHint =>
      'Tippe einen Block an, um diesen Teil zu hören.';

  @override
  String get harmonyAnalysisTitle => 'Die Harmonie sehen';

  @override
  String get harmonyAnalysisHint => 'Tippe einen Akkord an, um ihn zu hören.';

  @override
  String get funcTonic => 'Zuhause (Tonika)';

  @override
  String get funcSubdominant => 'Weg (Subdominante)';

  @override
  String get funcDominant => 'Spannung (Dominante)';

  @override
  String get funcTonicKid => 'Zuhause';

  @override
  String get funcSubdominantKid => 'Weg';

  @override
  String get funcDominantKid => 'Spannung';

  @override
  String get analysisHarmonyHeading => 'Harmonie';

  @override
  String get analyzeAction => 'Harmonie analysieren';

  @override
  String get inspectMode => 'Untersuchen (Note antippen)';

  @override
  String get analysisFormLabel => 'Form';

  @override
  String get analysisCircleOfFifths => 'Quintenzirkel';

  @override
  String get analysisTension => 'Spannung';

  @override
  String get analysisVoiceLeading => 'Stimmführung';

  @override
  String get analysisVoiceLeadingClean => 'Keine Quint-/Oktavparallelen ✓';

  @override
  String get analysisParallelFifths => 'Quintparallelen';

  @override
  String get analysisParallelOctaves => 'Oktavparallelen';

  @override
  String get analysisNonChordTones => 'Akkordfremde Töne';

  @override
  String get cadenceAuthentic => 'authentische Kadenz';

  @override
  String get cadenceHalf => 'Halbkadenz';

  @override
  String get cadencePlagal => 'plagale Kadenz';

  @override
  String get cadenceDeceptive => 'Trugschluss';

  @override
  String get analysisDepthKids => 'Kinder';

  @override
  String get analysisDepthLearner => 'Lernend';

  @override
  String get analysisDepthExpert => 'Profi';

  @override
  String get harmonyExampleAuthentic =>
      'Zuhause → weg → Spannung → zuhause (I–IV–V–I)';

  @override
  String get harmonyExampleAuthenticCaption =>
      'Die Geschichte hinter fast jeder Musik: die Tonika (I) ist zuhause, die Subdominante (IV) tritt weg, die Dominante (V) baut Spannung auf, und I bringt dich wieder nach Hause.';

  @override
  String get harmonyExampleTwoFive => 'ii – V – I';

  @override
  String get harmonyExampleTwoFiveCaption =>
      'Der häufigste Weg nach Hause: eine Subdominante (ii) bereitet die Dominante (V) vor, die stark in die Tonika (I) zieht.';

  @override
  String get harmonyExamplePerfect => 'Authentische Kadenz (… V → I)';

  @override
  String get harmonyExamplePerfectCaption =>
      'Auf der Tonika nach der Dominante zu enden klingt fertig und beruhigt — ein Punkt. Hör, wie der letzte Akkord zur Ruhe kommt.';

  @override
  String get harmonyExampleHalf => 'Halbkadenz (… → V)';

  @override
  String get harmonyExampleHalfCaption =>
      'Stattdessen auf der Dominante zu halten klingt unfertig, wie eine offene Frage — die Musik will noch nach Hause.';

  @override
  String get cadenceMarkPerfect => 'kommt zur Ruhe';

  @override
  String get cadenceMarkHalf => 'bleibt offen';

  @override
  String get gameAnalysisView => 'Die Musik sehen';

  @override
  String get gameAnalysisViewSubtitle =>
      'Form und Harmonie eines Stücks betrachten';

  @override
  String get analysisHubTitle => 'Die Musik sehen';

  @override
  String get analysisHubIntro =>
      'Musik hat Formen, die man sehen kann. Betrachte die Form eines Stücks als farbige Teile und eine Akkordfolge nach ihrer Aufgabe eingefärbt — tippe dann, um jeden Teil zu hören.';

  @override
  String get analysisHubForm => 'Form';

  @override
  String get analysisHubHarmony => 'Harmonie & Funktion';

  @override
  String get analysisHubComputed => 'Aus den Noten gelesen (Auto-Analyse)';

  @override
  String get formExampleTernary => 'Dreiteilige Form (A–B–A)';

  @override
  String get formExampleTernaryCaption =>
      'Eine Melodie, eine andere in der Mitte, dann wieder die erste. Zwei der drei Teile sind gleich — darum haben A und A dieselbe Farbe.';

  @override
  String get formExampleRondo => 'Rondo (A–B–A–C–A)';

  @override
  String get formExampleRondoCaption =>
      'Eine Melodie kehrt immer wieder (A), dazwischen jedes Mal eine neue (B, dann C). Wie ein Refrain, zu dem man immer wieder zurückkommt.';

  @override
  String get formExampleVerseChorus => 'Strophe und Refrain (A–B–A–B)';

  @override
  String get formExampleVerseChorusCaption =>
      'A ist die Strophe (der Text ändert sich), B ist der Refrain (er bleibt gleich). Die meisten Popsongs wechseln zwischen beiden.';

  @override
  String get formExampleAaba => 'Liedform (A–A–B–A)';

  @override
  String get formExampleAabaCaption =>
      'Die Hauptmelodie zweimal (A, A), dann ein anderer Mittelteil (B, die „Bridge“), dann noch einmal die Hauptmelodie. Eine sehr häufige Liedform.';

  @override
  String get proseIntervals =>
      'Ein Intervall ist der Abstand zwischen zwei Tönen — wie groß der Sprung ist. Kleine Sprünge (eine Sekunde, eine Terz) klingen eng und weich; große Sprünge (eine Sexte, eine Oktave) klingen weit und offen. Jedes erkennst du am Anfang eines bekannten Lieds: eine fallende kleine Terz ist der „Kuck-uck“-Ruf.';

  @override
  String get proseTriads =>
      'Ein Dreiklang ist ein Akkord aus drei Tönen, gebaut aus zwei übereinandergestapelten Terzen — ein Grundton, der Ton zwei Schritte höher und noch zwei Schritte höher. Dur-Dreiklänge klingen hell und fröhlich, Moll-Dreiklänge weicher und trauriger. Fast alle Akkorde beginnen als Dreiklang.';

  @override
  String get proseKeySignatures =>
      'Die Kreuze oder Bs ganz am Anfang einer Zeile sind die Vorzeichen: Sie sagen dir, welche Töne im ganzen Stück erhöht oder erniedrigt bleiben, damit du nicht jedes Mal ein Vorzeichen schreiben musst. Zähle sie, um die Tonart zu bestimmen.';

  @override
  String get proseEnharmonics =>
      'Ein Klang kann zwei Namen haben. Fis und Ges sind genau dieselbe Taste am Klavier, nur je nach Tonart anders geschrieben. Solche Töne nennt man enharmonisch — gleiche Tonhöhe, zwei Schreibweisen.';

  @override
  String get proseCircleOfFifths =>
      'Gehe jedes Mal eine Quinte hinauf — C, G, D, A … — und du wanderst um einen Kreis, der durch alle Tonarten führt und wieder nach Hause kommt. Jeder Schritt fügt ein Kreuz hinzu (in die eine Richtung) oder ein B (in die andere) — darum ist er die Landkarte der Vorzeichen.';

  @override
  String get proseMinorScales =>
      'Moll-Tonleitern klingen dunkler als Dur. Natürliches Moll benutzt die einfachen Töne seiner Tonart; harmonisches Moll erhöht die 7. Stufe, damit sich die Tonleiter stark zum Grundton zurückzieht. Dieser eine erhöhte Ton gibt harmonischem Moll seinen besonderen, ziehenden Klang.';

  @override
  String get proseSeventhChords =>
      'Setze noch eine Terz oben auf einen Dreiklang und du bekommst einen Septakkord — vier Töne statt drei. Der zusätzliche Ton klingt unruhig und will weiter, darum zieht ein Dominantseptakkord (V7) so stark zum Grundakkord zurück.';

  @override
  String get proseCadences =>
      'Eine Kadenz ist, wie eine musikalische Phrase endet — ihr Satzzeichen. Eine authentische Kadenz (V→I) klingt wie ein Punkt, fertig und zur Ruhe gekommen. Eine Halbkadenz endet auf der Dominante und klingt wie eine Frage, die noch offen bleibt.';

  @override
  String get proseHarmonicFunction =>
      'Akkorde haben Aufgaben. Die Tonika (I) ist Zuhause — ruhig und entspannt. Die Dominante (V) ist Spannung, die nach Hause zieht. Die Subdominante (IV) ist der Schritt weg von zu Hause, bevor die Dominante zurückzieht. Zuhause → weg → Spannung → Zuhause ist die Geschichte hinter fast jeder Musik.';

  @override
  String get proseRomanNumerals =>
      'Römische Zahlen benennen einen Akkord nach seiner Stufe in der Tonleiter, nicht nach seinem Buchstaben — so gelten dieselben Zahlen in jeder Tonart. GROSSBUCHSTABEN bedeuten Dur (I, IV, V), kleine Buchstaben Moll (ii, iii, vi). So beschreibt „V–I“ einen Schluss in jeder Tonart auf einmal.';

  @override
  String get proseModulation =>
      'Modulation ist, wenn ein Stück mittendrin die Tonart wechselt — es hebt sich zu einem neuen Grundton und bleibt eine Weile dort. Oft macht das die Musik heller oder frischer, wie ein Fenster in einen neuen Raum, bevor sie vielleicht wieder zurückfindet.';

  @override
  String get proseModes =>
      'Modi sind Tonleitern, die auf verschiedenen Stufen beginnen, jede mit eigener Farbe. Dur (Ionisch) ist hell, natürliches Moll (Äolisch) ist dunkel, und Dorisch ist Moll mit erhöhter 6. Stufe — Moll, aber mit einem hoffnungsvollen Dreh. Ändere einen Ton und die ganze Farbe ändert sich.';

  @override
  String get proseSyncopation =>
      'Normalerweise liegen die betonten Schläge auf der Zählzeit — 1, 2, 3, 4. Synkopen setzen die Betonung stattdessen neben den Schlag, in die Lücken dazwischen. Dieses Ziehen und Schieben lässt Musik tanzen oder swingen, statt zu marschieren.';

  @override
  String get proseTriplets =>
      'Eine Triole quetscht drei gleiche Noten in den Platz, wo du sonst zwei spielst. Statt „ta-ta“ zählst du „ta-ta-ta“ in derselben Zeit. Ein Dreier-Gefühl mitten in einem Zweier-Schlag — ein sanftes Wiegen.';

  @override
  String get proseSongForm =>
      'Lieder bestehen aus Teilen, die sich wiederholen und abwechseln. Eine Strophe erzählt die Geschichte mit wechselndem Text; ein Refrain kommt jedes Mal gleich wieder als einprägsamer Ohrwurm. Die Teile mit Buchstaben (A, B …) zu benennen zeigt die Form auf einen Blick.';

  @override
  String get proseMusicalForm =>
      'Die Form ist der Bauplan eines Stücks — wie seine Teile angeordnet sind. Kehrt eine Melodie wieder, behält sie ihren Buchstaben; eine neue Melodie bekommt einen neuen. A–B–A (dreiteilig) und A–B–A–C–A (Rondo) sind zwei der ältesten, klarsten Formen. Die Buchstaben machen ein langes Stück leicht verständlich.';

  @override
  String get proseTransposingInstruments =>
      'Manche Instrumente klingen anders als der Ton, den sie lesen. Eine B-Klarinette klingt ein B, wenn sie ein geschriebenes C spielt. Darum wird dieselbe Melodie für verschiedene Instrumente unterschiedlich notiert, damit sie in der richtigen Tonhöhe klingt — das ist Transposition.';

  @override
  String get prosePulse =>
      'Jedes Stück hat einen Herzschlag — einen gleichmäßigen Puls, zu dem du klatschen oder marschieren kannst. Er wird nicht schneller oder langsamer; er ist die tickende Uhr, über der die übrige Musik tanzt.';

  @override
  String get proseHighLow =>
      'Manche Klänge sind hoch und hell wie ein Vogel, andere tief wie eine große Trommel. Zu hören, was höher ist, ist der allererste Schritt zum Notenlesen — hohe Töne stehen oben im System, tiefe unten.';

  @override
  String get proseMelodyDirection =>
      'Eine Melodie kann steigen, fallen oder gleich bleiben — diese Linie ist ihr Verlauf. Zu verfolgen, ob die Melodie aufwärts oder abwärts geht, spürt dein Ohr die Melodie nach, lange bevor du die Töne benennen kannst.';

  @override
  String get proseSameDifferent =>
      'Zwei Klänge können genau gleich sein oder verschieden. „Das ist wieder derselbe Ton“ oder „der hat sich geändert“ zu bemerken übt das genaue Hören, auf dem alle anderen musikalischen Fähigkeiten aufbauen.';

  @override
  String get proseLoudSoft =>
      'Musik kann flüstern oder rufen. Laut und leise (italienisch forte und piano) gehören zu den stärksten Werkzeugen — dieselbe Melodie wirkt leise sanft und laut aufregend.';

  @override
  String get proseFastSlow =>
      'Wie schnell die Schläge kommen, ist das Tempo. Ein langsames Tempo wirkt ruhig oder traurig, ein schnelles geschäftig oder fröhlich. Gleiche Töne, anderes Tempo, ganz andere Stimmung.';

  @override
  String get proseLongShort =>
      'Manche Töne werden lang gehalten, andere huschen kurz vorbei. Diese Notenlängen (Dauern) sind der Rohstoff des Rhythmus — Muster aus langen und kurzen Klängen.';

  @override
  String get proseCountSounds =>
      'Genau genug hinzuhören, um zu zählen, wie viele Töne du gehört hast — zwei, drei, vier — schärft deine musikalische Aufmerksamkeit. Wenn du sie zählen kannst, kannst du sie dir merken und wiederholen.';

  @override
  String get proseAuralMemory =>
      'Musik lebt in deinem Gedächtnis. Ein kurzes Muster zu hören und zurückzugeben — klatschen oder singen — baut das Gehörgedächtnis auf, das jeder Musiker beim Lernen nach Gehör benutzt.';

  @override
  String get proseLearnSongs =>
      'Der schönste Weg in die Musik sind echte Lieder zum Mitsingen. Bekannte Melodien zu lernen und wiederzuerkennen gibt jeder abstrakten Idee — Puls, Tonhöhe, Form — eine Melodie, die du schon kennst.';

  @override
  String get proseTrebleStaff =>
      'Das Violinsystem hat fünf Linien und vier Zwischenräume, in denen die höheren Töne wohnen. Jede Linie und jeder Zwischenraum ist ein Buchstabe, und wenn du sie kennst, kannst du die Melodie der meisten Lieder lesen.';

  @override
  String get proseLedgerMiddleC =>
      'Ist ein Ton zu hoch oder zu tief für das System, bekommt er seine eigene kleine Hilfslinie. Das eingestrichene C sitzt auf einer knapp unter dem Violinsystem — die Tür zwischen den hohen und tiefen Noten.';

  @override
  String get proseNoteValues =>
      'Die Form einer Note sagt, wie lang du sie hältst: die ganze Note am längsten, dann halbe, Viertel- und Achtelnoten, jede halb so lang wie die davor. So wird Rhythmus aufgeschrieben.';

  @override
  String get proseRests =>
      'Auch Stille gehört zur Musik. Eine Pause ist ein geschriebenes Schweigen — zu jeder Notenlänge gibt es eine gleich lange Pause, damit die Musik atmet und die Lücken so genau sind wie die Töne.';

  @override
  String get proseDottedNotes =>
      'Ein kleiner Punkt hinter einer Note macht sie länger — er fügt die Hälfte ihres Wertes hinzu. Eine punktierte halbe Note dauert drei Schläge statt zwei, denn die Hälfte von zwei ist eins, und zwei plus eins ist drei.';

  @override
  String get proseBeatsPerBar =>
      'Musik wird in gleiche Kästchen gepackt, die Takte heißen. Die Schläge in jedem Takt ergeben immer dieselbe Summe, damit der Puls geordnet und leicht zu zählen bleibt.';

  @override
  String get proseTimeSignature =>
      'Die zwei Zahlen am Anfang sagen, wie der Takt gezählt wird: die obere, wie viele Schläge pro Takt, die untere, welche Note einen Schlag bekommt. 4/4 heißt vier Viertelschläge in jedem Takt.';

  @override
  String get proseStrongWeakBeat =>
      'In jedem Takt fühlen sich manche Schläge stärker an als andere — der erste ist der stärkste. Dieses Muster aus starken und schwachen Schlägen lässt einen Walzer anders klingen als einen Marsch.';

  @override
  String get proseDynamicsMarks =>
      'Komponisten schreiben mit Buchstaben, wie laut zu spielen ist: p für piano (leise), f für forte (laut) und sanftere Stufen dazwischen (mp, mf). Diese Dynamik formt das Gefühl der Musik.';

  @override
  String get proseTempoTerms =>
      'Das Tempo hat Namen, meist italienische: Largo sehr langsam, Adagio langsam, Andante Schritttempo, Allegro schnell, Presto sehr schnell. Ein Wort ganz oben setzt die ganze Stimmung.';

  @override
  String get proseRhythmEcho =>
      'Höre einen Rhythmus und klatsche ihn gleich zurück. Dieses Ruf-und-Antwort bringt den Rhythmus in deinen Körper — du spürst das Muster aus lang und kurz, bevor du es liest.';

  @override
  String get proseStepsSkips =>
      'Von einem Ton zum nächsten kannst du schreiten (zum nächsten Buchstaben) oder springen (über einen oder mehr hinweg). Melodien sind meist sanfte Schritte mit gelegentlichen Sprüngen zur Überraschung.';

  @override
  String get proseCMajorScale =>
      'Die C-Dur-Tonleiter sind die weißen Tasten von C bis C — die einfachste, hellste Tonleiter, ohne Kreuze und Bs. Sie ist die Heimat, von der aus jede andere Tonleiter gemessen wird.';

  @override
  String get proseMajorMinorEar =>
      'Dieselben Töne können fröhlich oder traurig wirken, je nachdem, welche wenigen erniedrigt sind. Dur klingt hell und heiter, Moll dunkler und ernster — dein Ohr lernt schnell, sie zu unterscheiden.';

  @override
  String get proseReadingFluency =>
      'Noten lesen wird wie Wörterlesen mit Übung schneller, bis du nicht mehr jede Note ausrechnen musst. Flüssiges Lesen in beiden Schlüsseln lässt dich ein neues Stück fast vom Blatt spielen.';

  @override
  String get proseSingWhatYouHear =>
      'Einen Ton oder eine kurze Melodie zurückzusingen verbindet dein Ohr mit deiner Stimme. Wenn du singen kannst, was du hörst, hast du die Tonhöhe wirklich verstanden — das Herz der Gehörbildung.';

  @override
  String get prosePlayKeyboard =>
      'Auf der Tastatur laufen die Töne von links (tief) nach rechts (hoch), die schwarzen Tasten in Zweier- und Dreiergruppen als Wegweiser. Die richtigen Tasten zu finden macht aus den Noten auf dem Papier Klang unter deinen Fingern.';

  @override
  String get prosePlayCello =>
      'Das Cello spielt man mit dem Bogen über vier Saiten, die linke Hand drückt, um die Tonhöhe zu ändern. Seine Saiten, Fingerplätze und Bogenstriche (Abstrich und Aufstrich) zu lernen führt zu einem warmen, singenden Ton.';

  @override
  String get prosePlayGuitar =>
      'Die Gitarre hat sechs Saiten, die du hinter Bünden drückst und zupfst oder anschlägst. Ihre Saiten und einfache Tabulatur zu lesen und im Takt zu schlagen bringt dich erstaunlich schnell zum Spielen.';

  @override
  String get prosePlayPercussion =>
      'Schlagwerk ist Rhythmus zum Schlagen. Ein Trommelmuster zu lesen und zu spielen — zu wissen, welcher Klang auf welchen Schlag fällt — ist purer Rhythmus, das Rückgrat, das eine ganze Band zusammenhält.';

  @override
  String get proseCompose =>
      'Eine eigene Melodie zu erfinden ist, wo alle Regeln zum Spiel werden. Ein paar Töne zu wählen, sie zu einer Form zu ordnen, die dir gefällt, und sie zu hören ist Komponieren — der schönste Weg zu verstehen, wie Musik funktioniert.';

  @override
  String get proseBassClef =>
      'Der Bassschlüssel liest die tieferen Töne — die linke Hand am Klavier, das Cello, den Bass. Seine Linien und Zwischenräume ergeben andere Buchstaben als der Violinschlüssel, also öffnet er die ganze tiefe Hälfte der Musik.';

  @override
  String get proseGrandStaff =>
      'Verbinde Violin- und Bassschlüssel mit einer Klammer und du bekommst das große System — zwei Systeme auf einmal, eins pro Hand. Das eingestrichene C sitzt in der Lücke dazwischen, beiden gemeinsam.';

  @override
  String get proseClefSigns =>
      'Ein Schlüssel ist das Zeichen am Anfang, das festlegt, welche Linien welche Töne bedeuten. Der Violinschlüssel (G) umkringelt die G-Linie, die zwei Punkte des Bassschlüssels (F) umschließen die F-Linie. Gleiches System, anderer Schlüssel, andere Töne.';

  @override
  String get proseAccidentals =>
      'Ein Kreuz (♯) erhöht einen Ton um einen Halbton, ein B (♭) erniedrigt ihn, ein Auflösungszeichen (♮) hebt beides auf. Mit diesen Vorzeichen erreichen wir die schwarzen Tasten und die Töne zwischen den Buchstaben.';

  @override
  String get proseWholeHalfStep =>
      'Der kleinste Schritt auf der Tastatur ist ein Halbton (zur direkt nächsten Taste). Zwei davon ergeben einen Ganzton. Tonleitern sind nur bestimmte Leitern aus Ganz- und Halbtönen — das Muster macht ihren Klang aus.';

  @override
  String get proseMajorScales =>
      'Jede Dur-Tonleiter folgt demselben Rezept aus Ganz- und Halbtönen, von jedem beliebigen Ton aus. Stimmt das Muster, klingen C-Dur, G-Dur und alle anderen gleich hell und vertraut.';

  @override
  String get proseTiesSlurs =>
      'Ein Bogen kann zweierlei bedeuten. Ein Haltebogen verbindet zwei GLEICHE Töne zu einem längeren Klang; ein Bindebogen über VERSCHIEDENEN Tönen heißt, sie weich verbunden zu spielen. Gleicher Bogen, gegensätzliche Aufgaben.';

  @override
  String get proseArticulation =>
      'Artikulation ist, wie eine Note gespielt wird — kurz und abgesetzt (staccato, ein Punkt über der Note) oder betont (ein Akzent). Es ist der Unterschied, jedes Wort knapp oder weich zu sprechen.';

  @override
  String get proseBeams =>
      'Kurze Noten tragen einzelne Fähnchen oder werden durch einen dicken Balken verbunden. Balken gruppieren die Noten innerhalb eines Schlags, sodass ein Takt schneller Noten viel leichter zu lesen ist als eine Reihe loser Fähnchen.';

  @override
  String get proseAnacrusis =>
      'Nicht jede Melodie beginnt auf Schlag eins. Ein Auftakt ist ein Ton oder zwei vor dem ersten vollen Takt — denk an das „Hap-“ vor „Happy Birthday“. Die Musik lehnt sich hinein, bevor sie landet.';

  @override
  String get proseCompoundMeter =>
      'Im zusammengesetzten Takt wie 6/8 teilt sich der Schlag in Dreier statt Zweier und bekommt ein rollendes, wiegendes Gefühl. Man zählt in zwei großen Dreierschlägen — eins-und-a, zwei-und-a — wie ein Boot auf sanften Wellen.';

  @override
  String get proseArrangeLoops =>
      'Du musst nicht jede Note schreiben, um Musik zu machen. Fertige Loops zu schichten und anzuordnen — ein Schlagzeug-Groove, eine Basslinie, ein Akkordteppich — lehrt, wie Teile zu einem vollen, ausgewogenen Track zusammenpassen.';

  @override
  String get proseChordQualities =>
      'Neben Dur und Moll gibt es zwei weitere Dreiklang-Arten: vermindert (beide Terzen klein, gespannt und unruhig) und übermäßig (beide Terzen weit, seltsam und traumhaft). Die Art bestimmt sich durch die genauen Größen der gestapelten Terzen.';

  @override
  String get proseChordSymbols =>
      'Leadsheets benennen Akkorde mit kurzen Symbolen über der Melodie — C, Am, G7, Dm. Lernst du sie zu lesen, kannst du die Harmonie eines ganzen Lieds aus einer einzigen Akkordzeile spielen, so wie eine Band.';

  @override
  String get proseMelodicDictation =>
      'Eine kurze Melodie zu hören und aufzuschreiben ist Diktat — die härteste Prüfung fürs Ohr. Es verbindet Tonhöhe, Rhythmus und Gedächtnis: Du entschlüsselst die Melodie, wie du ein eben gehörtes Wort schreibst.';

  @override
  String get prosePhrasingQa =>
      'Melodien kommen oft paarweise, wie ein Gespräch. Die erste Phrase stellt eine Frage und bleibt offen, die zweite antwortet und kommt zur Ruhe. Diese Frage-und-Antwort-Form zu hören zeigt dir, wohin eine Melodie will.';

  @override
  String get proseInversions =>
      'Die Töne eines Akkords können in verschiedener Reihenfolge gestapelt werden. Sitzt ein anderer Ton als der Grundton unten, ist der Akkord umgekehrt (Umkehrung) — gleicher Akkord, andere Farbe und ein weicherer Weg von Akkord zu Akkord.';

  @override
  String get proseTenorClef =>
      'Der Tenorschlüssel ist ein C-Schlüssel, der weiter oben im System auf das eingestrichene C zeigt. Er dient für die höheren Töne von Instrumenten wie Cello und Fagott, damit sie keinen Wald aus Hilfslinien über dem Bass brauchen.';

  @override
  String get proseSatbVoices =>
      'Chormusik steht in vier Stimmen — Sopran, Alt, Tenor und Bass, von hoch nach tief. Alle vier zugleich zu lesen, jede mit eigener Linie, ist die Art, einem Choral zu folgen.';

  @override
  String get proseScoreReading =>
      'Eine Partitur stapelt jede Instrumentenstimme zugleich auf der Seite. Ihr zu folgen — über mehrere Systeme hinweg die Stelle zu halten, während die Musik läuft — ist die Fähigkeit, mit der ein Dirigent das ganze Ensemble vom Papier hört.';

  @override
  String get proseOrnaments =>
      'Verzierungen sind kleine Ausschmückungen an einer Note — ein Triller (schnelles Wechseln mit dem Ton darüber), ein Mordent (ein rascher Schlenker) oder ein Doppelschlag (eine Kringel um die Note). Sie geben Glanz, ohne die Melodie darunter zu ändern.';

  @override
  String get proseInstrumentFamilies =>
      'Das Orchester ordnet seine Instrumente nach der Art, wie sie Klang erzeugen, in Familien: Streicher (gestrichen oder gezupft), Holzbläser, Blechbläser, Schlagwerk und Tasten. Die Familien zu kennen hilft dir, beim Hören herauszufinden, wer was spielt.';

  @override
  String get proseVoiceLeading =>
      'Stimmführung beschreibt, wie jeder Ton eines Akkords zum nächsten weiterschreitet — möglichst glatt, wobei jede Stimme so wenig wie möglich springt, damit die Teile wie eigenständige singende Linien klingen. Die klassische Regel lautet, Parallelen in Quinten und Oktaven zu vermeiden: Bewegen sich zwei Stimmen im gleichen Abstand in dieselbe Richtung, verlieren sie ihre Eigenständigkeit und verschmelzen zu einer. Solche Stellen zu erkennen und zu glätten macht vier Stimmen erst lebendig.';

  @override
  String get gameInstrumentFamily => 'Welche Familie?';

  @override
  String get gameInstrumentFamilySubtitle =>
      'Ordne ein Instrument seiner Familie zu: Streicher, Holzbläser, Blechbläser, Schlagwerk oder Tasten.';

  @override
  String get instrumentFamilyPrompt => 'Zu welcher Familie gehört es?';

  @override
  String get familyStrings => 'Streicher';

  @override
  String get familyWoodwind => 'Holzbläser';

  @override
  String get familyBrass => 'Blechbläser';

  @override
  String get familyPercussion => 'Schlagwerk';

  @override
  String get familyKeyboard => 'Tasten';

  @override
  String get instrViolin => 'Geige';

  @override
  String get instrCello => 'Cello';

  @override
  String get instrGuitar => 'Gitarre';

  @override
  String get instrHarp => 'Harfe';

  @override
  String get instrFlute => 'Flöte';

  @override
  String get instrClarinet => 'Klarinette';

  @override
  String get instrOboe => 'Oboe';

  @override
  String get instrSaxophone => 'Saxofon';

  @override
  String get instrRecorder => 'Blockflöte';

  @override
  String get instrTrumpet => 'Trompete';

  @override
  String get instrTrombone => 'Posaune';

  @override
  String get instrHorn => 'Horn';

  @override
  String get instrTuba => 'Tuba';

  @override
  String get instrDrums => 'Schlagzeug';

  @override
  String get instrXylophone => 'Xylophon';

  @override
  String get instrTimpani => 'Pauke';

  @override
  String get instrTriangle => 'Triangel';

  @override
  String get instrPiano => 'Klavier';

  @override
  String get instrOrgan => 'Orgel';

  @override
  String get primerFamilyTitle => 'Instrumentenfamilien';

  @override
  String get primerFamilyStrings =>
      'Streicher klingen, wenn man sie streicht oder zupft: Geige, Cello, Gitarre und Harfe.';

  @override
  String get primerFamilyWinds =>
      'Bläser brauchen deinen Atem. Holzbläser wie Flöte, Klarinette und Saxofon; Blechbläser wie Trompete, Posaune und Tuba.';

  @override
  String get primerFamilyPercKeys =>
      'Schlagwerk wird geschlagen — Trommeln, Xylophon und Triangel. Tasteninstrumente wie Klavier und Orgel spielen viele Töne zugleich.';

  @override
  String get conceptPulse => 'Ein gleichmäßiger Puls (Grundschlag)';

  @override
  String get conceptHighLow => 'Höher und tiefer';

  @override
  String get conceptMelodyDirection => 'Eine Melodie steigt oder fällt';

  @override
  String get conceptSameDifferent => 'Gleich oder verschieden';

  @override
  String get conceptLoudSoft => 'Laut und leise';

  @override
  String get conceptFastSlow => 'Schnell und langsam';

  @override
  String get conceptLongShort => 'Lange und kurze Noten';

  @override
  String get conceptCountSounds => 'Zähle die Töne, die du hörst';

  @override
  String get conceptTrebleStaff => 'Noten im Violinschlüssel';

  @override
  String get conceptLedgerMiddleC => 'Hilfslinien und das eingestrichene C';

  @override
  String get conceptNoteValues => 'Ganze, halbe, Viertel- und Achtelnoten';

  @override
  String get conceptRests => 'Pausen sind Stille';

  @override
  String get conceptDottedNotes => 'Der Punkt gibt die Hälfte dazu';

  @override
  String get conceptBeatsPerBar => 'Schläge füllen einen Takt';

  @override
  String get conceptTimeSignature => 'Die Taktangabe lesen';

  @override
  String get conceptStrongWeakBeat => 'Betonte und unbetonte Schläge';

  @override
  String get conceptDynamicsMarks => 'p und f (piano/forte)';

  @override
  String get conceptTempoTerms => 'Italienische Tempo-Wörter';

  @override
  String get conceptRhythmEcho => 'Einen gehörten Rhythmus nachklatschen';

  @override
  String get conceptStepsSkips => 'Schritte und Sprünge';

  @override
  String get conceptCMajorScale => 'Die C-Dur-Tonleiter';

  @override
  String get conceptMajorMinorEar => 'Dur klingt hell, Moll dunkler';

  @override
  String get conceptSongForm => 'Strophe und Refrain; Wiederholungen';

  @override
  String get conceptBassClef => 'Noten im Bassschlüssel';

  @override
  String get conceptGrandStaff => 'Zwei Systeme, zwei Hände';

  @override
  String get conceptClefSigns => 'Violin- oder Bassschlüssel';

  @override
  String get conceptAccidentals => 'Kreuze und Be (Vorzeichen)';

  @override
  String get conceptEnharmonics => 'Eine Taste, zwei Namen (Fis = Ges)';

  @override
  String get conceptWholeHalfStep => 'Ganztöne und Halbtöne';

  @override
  String get conceptKeySignatures => 'Vorzeichen am Anfang (Tonarten)';

  @override
  String get conceptMajorScales => 'Dur-Tonleitern bauen';

  @override
  String get conceptIntervals => 'Intervalle: der Abstand zwischen Tönen';

  @override
  String get conceptTriads => 'Dur- und Moll-Dreiklänge';

  @override
  String get conceptTiesSlurs => 'Halte- und Bindebögen';

  @override
  String get conceptArticulation => 'Staccato und Akzente';

  @override
  String get conceptBeams => 'Balken und Fähnchen';

  @override
  String get conceptAnacrusis => 'Der Auftakt';

  @override
  String get conceptCompoundMeter => 'Zusammengesetzter Takt (6/8)';

  @override
  String get conceptSyncopation => 'Betonungen neben dem Schlag (Synkope)';

  @override
  String get conceptTriplets => 'Triolen und andere Tuolen';

  @override
  String get conceptCircleOfFifths => 'Der Quintenzirkel';

  @override
  String get conceptMinorScales => 'Natürliches und harmonisches Moll';

  @override
  String get conceptChordQualities => 'Vermindert und übermäßig';

  @override
  String get conceptSeventhChords => 'Septakkorde';

  @override
  String get conceptChordSymbols => 'Akkordsymbole (Leadsheet)';

  @override
  String get conceptCadences => 'Wie Phrasen enden (Kadenzen)';

  @override
  String get conceptHarmonicFunction => 'Tonika, Subdominante, Dominante';

  @override
  String get conceptRomanNumerals => 'Römische Stufen (Ziffern)';

  @override
  String get conceptMelodicDictation => 'Eine gehörte Melodie aufschreiben';

  @override
  String get conceptPhrasingQa => 'Frage-und-Antwort-Phrasen';

  @override
  String get conceptMusicalForm => 'Form: ABA, Rondo, Thema mit Variationen';

  @override
  String get conceptModulation => 'Die Tonart wechseln (Modulation)';

  @override
  String get conceptInversions => 'Akkord-Umkehrungen';

  @override
  String get conceptTransposingInstruments => 'Transponierende Instrumente';

  @override
  String get conceptTenorClef => 'Der Tenorschlüssel';

  @override
  String get conceptSatbVoices => 'Vierstimmig (SATB) lesen';

  @override
  String get conceptScoreReading => 'Eine mehrsystemige Partitur lesen';

  @override
  String get conceptOrnaments =>
      'Verzierungen (Triller, Mordent, Doppelschlag)';

  @override
  String get conceptModes => 'Kirchentonarten (Dorisch usw.)';

  @override
  String get conceptInstrumentFamilies =>
      'Instrumentenfamilien / das Orchester';

  @override
  String get conceptReadingFluency => 'Noten flüssig lesen (beide Schlüssel)';

  @override
  String get conceptAuralMemory => 'Höre und merke dir, was erklingt';

  @override
  String get conceptSingWhatYouHear =>
      'Einen Ton oder ein Intervall nachsingen';

  @override
  String get conceptPlayKeyboard => 'Tasten finden und spielen';

  @override
  String get conceptPlayCello => 'Cello spielen: Saiten, Finger, Bogen';

  @override
  String get conceptPlayGuitar =>
      'Gitarre spielen: Saiten, Tabulatur, Anschlag';

  @override
  String get conceptPlayPercussion => 'Einen Trommelrhythmus lesen und spielen';

  @override
  String get conceptCompose => 'Eine eigene Melodie erfinden';

  @override
  String get conceptArrangeLoops => 'Loops schichten und arrangieren';

  @override
  String get conceptLearnSongs => 'Echte Lieder lernen und erkennen';

  @override
  String get areaPulse => 'Puls';

  @override
  String get areaReading => 'Notenlesen';

  @override
  String get areaDuration => 'Notenwerte';

  @override
  String get areaMeter => 'Takt';

  @override
  String get areaDynamics => 'Dynamik';

  @override
  String get areaTempo => 'Tempo';

  @override
  String get areaPitch => 'Tonhöhe';

  @override
  String get areaScales => 'Tonleitern';

  @override
  String get areaIntervals => 'Intervalle';

  @override
  String get areaChords => 'Akkorde';

  @override
  String get areaHarmony => 'Harmonik';

  @override
  String get areaArticulation => 'Artikulation';

  @override
  String get areaTranspose => 'Transposition';

  @override
  String get areaForm => 'Form';

  @override
  String get areaTimbre => 'Klangfarbe';

  @override
  String get areaTechnique => 'Musizieren';

  @override
  String get areaAural => 'Gehörbildung';

  @override
  String get areaCreating => 'Gestalten';

  @override
  String get areaRepertoire => 'Repertoire';

  @override
  String get textbookBandG12 =>
      'Musik beginnt mit deinem Körper: den gleichmäßigen Puls spüren, hoch und tief, laut und leise, schnell und langsam hören. Noten liest du noch nicht — du hörst und bewegst dich.';

  @override
  String get textbookBandG34 =>
      'Jetzt bekommen Noten Namen und Plätze im System. Du lernst, wie lange jede dauert, wie sie einen Takt füllen und wie man eine einfache Melodie in C-Dur liest.';

  @override
  String get textbookBandG56 =>
      'Beide Hände, beide Schlüssel. Kreuze und Be geben den Noten neue Farben; du misst den Abstand zwischen Tönen (Intervalle) und stapelst sie zu deinen ersten Akkorden.';

  @override
  String get textbookBandG78 =>
      'Die Musik wird reicher: Moll-Tonarten, der Quintenzirkel, Akkorde mit einer besonderen Septime und wie Phrasen zur Ruhe kommen (Kadenzen). Du beginnst zu hören, WARUM sich Akkorde bewegen.';

  @override
  String get textbookBandG910 =>
      'Das fortgeschrittene Werkzeug: Akkord-Umkehrungen, transponierende Instrumente, das Lesen einer ganzen Partitur und die Formen und Farben (Form, Kirchentonarten), mit denen Komponisten ganze Stücke bauen.';

  @override
  String get textbookGradesG12 => 'Klasse 1–2';

  @override
  String get textbookGradesG34 => 'Klasse 3–4';

  @override
  String get textbookGradesG56 => 'Klasse 5–6';

  @override
  String get textbookGradesG78 => 'Klasse 7–8';

  @override
  String get textbookGradesG910 => 'Klasse 9–10';

  @override
  String get tutorialReadAloud => 'Vorlesen';

  @override
  String get ttsHdVoiceTitle => 'Natürliche Stimme (HD)';

  @override
  String get ttsHdVoiceSubtitle =>
      'Eine wärmere, natürlichere Vorlesestimme für die Lektionen';

  @override
  String get ttsHdVoiceReady => 'An — Vorlesen nutzt die natürliche Stimme';

  @override
  String get ttsHdVoiceDownload => 'Herunterladen (~135 MB)';

  @override
  String get ttsHdVoiceDownloading => 'Wird heruntergeladen …';

  @override
  String get ttsHdVoiceFailed =>
      'Download fehlgeschlagen – zum Wiederholen tippen';
}
