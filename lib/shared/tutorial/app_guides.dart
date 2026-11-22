// lib/shared/tutorial/app_guides.dart
//
// Per-surface help for the tools that are not minigames. Each factory returns a
// one-page [Tutorial] so the existing tutorial sheet (and its "?" button) can
// explain a complex editor without a second help system.
//
// One bullet per line: [TutorialStep.text] is rendered as text, so `\n• ` keeps
// the guides short, scannable and easy to translate.

import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/tutorial/tutorial.dart';

Tutorial _guide(String title, String body) =>
    Tutorial(title: title, steps: [TutorialStep(text: body)]);

Tutorial homeGuide(AppLocalizations l) =>
    _guide(l.helpHomeTitle, l.helpHomeBody);

Tutorial tabWorkshopGuide(AppLocalizations l) =>
    _guide(l.helpTabTitle, l.helpTabBody);

Tutorial transcribeGuide(AppLocalizations l) =>
    _guide(l.helpTranscribeTitle, l.helpTranscribeBody);

Tutorial practiceGuide(AppLocalizations l) =>
    _guide(l.helpPracticeTitle, l.helpPracticeBody);

Tutorial trackerGuide(AppLocalizations l) =>
    _guide(l.helpTrackerTitle, l.helpTrackerBody);

Tutorial performGuide(AppLocalizations l) =>
    _guide(l.helpPerformTitle, l.helpPerformBody);

Tutorial chartGuide(AppLocalizations l) =>
    _guide(l.helpChartTitle, l.helpChartBody);

Tutorial soundLabGuide(AppLocalizations l) =>
    _guide(l.helpSoundLabTitle, l.helpSoundLabBody);

Tutorial voiceLabGuide(AppLocalizations l) =>
    _guide(l.helpVoiceLabTitle, l.helpVoiceLabBody);

Tutorial songBookGuide(AppLocalizations l) =>
    _guide(l.helpSongBookTitle, l.helpSongBookBody);

Tutorial libraryGuide(AppLocalizations l) =>
    _guide(l.helpLibraryTitle, l.helpLibraryBody);

Tutorial mixerGuide(AppLocalizations l) =>
    _guide(l.helpMixerTitle, l.helpMixerBody);

Tutorial setlistGuide(AppLocalizations l) =>
    _guide(l.helpSetlistTitle, l.helpSetlistBody);

Tutorial gigGuide(AppLocalizations l) => _guide(l.helpGigTitle, l.helpGigBody);

Tutorial tunerGuide(AppLocalizations l) =>
    _guide(l.helpTunerTitle, l.helpTunerBody);

Tutorial sampleExtractorGuide(AppLocalizations l) =>
    _guide(l.helpSampleTitle, l.helpSampleBody);

Tutorial importGuide(AppLocalizations l) =>
    _guide(l.helpImportTitle, l.helpImportBody);
