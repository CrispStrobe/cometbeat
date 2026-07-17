// lib/features/games/note_reading/note_names.dart
//
// Note letter names in the learner's chosen convention. `auto` goes through the
// ARB files (German uses H for the natural B); the explicit conventions use the
// maps below so a German-UI child can still drill English/solfège names.

import 'package:comet_beat/core/note_naming.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/midi_pitch.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

const _english = <Step, String>{
  Step.c: 'C',
  Step.d: 'D',
  Step.e: 'E',
  Step.f: 'F',
  Step.g: 'G',
  Step.a: 'A',
  Step.b: 'B',
};
const _germanH = <Step, String>{
  Step.c: 'C',
  Step.d: 'D',
  Step.e: 'E',
  Step.f: 'F',
  Step.g: 'G',
  Step.a: 'A',
  Step.b: 'H',
};
const _solfege = <Step, String>{
  Step.c: 'Do',
  Step.d: 'Re',
  Step.e: 'Mi',
  Step.f: 'Fa',
  Step.g: 'Sol',
  Step.a: 'La',
  Step.b: 'Si',
};

String noteName(
  AppLocalizations l10n,
  Step step, {
  NoteNaming naming = NoteNaming.auto,
}) =>
    switch (naming) {
      NoteNaming.auto => _localized(l10n, step),
      NoteNaming.english => _english[step]!,
      NoteNaming.germanH => _germanH[step]!,
      NoteNaming.solfege => _solfege[step]!,
    };

String _localized(AppLocalizations l10n, Step step) => switch (step) {
      Step.c => l10n.noteNameC,
      Step.d => l10n.noteNameD,
      Step.e => l10n.noteNameE,
      Step.f => l10n.noteNameF,
      Step.g => l10n.noteNameG,
      Step.a => l10n.noteNameA,
      Step.b => l10n.noteNameB,
    };

/// [step] spelled in the learner's chosen convention (from [SettingsService]).
/// Use this from widget builds; falls back to `auto` where the app language wins.
String noteNameFor(BuildContext context, Step step) => noteName(
      AppLocalizations.of(context)!,
      step,
      naming: context.watch<SettingsService>().noteNaming,
    );

/// A full MIDI note spelled in [naming], e.g. "A3", "F♯4", or "H4" in German.
/// Accidentals are shown as ♯/♭ appended to the localized letter (the app
/// spells black keys as sharps). Pure — testable without a widget tree.
String spelledMidiNameWith(
  AppLocalizations l10n,
  NoteNaming naming,
  int midi, {
  bool withOctave = true,
}) {
  final p = pitchFromMidi(midi);
  final letter = noteName(l10n, p.step, naming: naming);
  final acc =
      p.alter > 0 ? '♯' * p.alter : (p.alter < 0 ? '♭' * (-p.alter) : '');
  return withOctave ? '$letter$acc${p.octave}' : '$letter$acc';
}

/// [spelledMidiNameWith] resolved from the current [SettingsService]/locale.
/// Call from a widget build. Pass [withOctave] = false for a pitch-class name
/// (chord roots).
String spelledMidiName(
  BuildContext context,
  int midi, {
  bool withOctave = true,
}) =>
    spelledMidiNameWith(
      AppLocalizations.of(context)!,
      context.watch<SettingsService>().noteNaming,
      midi,
      withOctave: withOctave,
    );
