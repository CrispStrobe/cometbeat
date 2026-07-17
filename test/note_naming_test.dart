// The note-naming convention decouples how note letters are spelled from the
// UI language: a German-UI child can drill English or solfège names, and vice
// versa. `auto` keeps today's behaviour (follow the app language).

import 'package:comet_beat/core/note_naming.dart';
import 'package:comet_beat/features/games/note_reading/note_names.dart';
import 'package:comet_beat/l10n/app_localizations_de.dart';
import 'package:comet_beat/l10n/app_localizations_en.dart';
import 'package:crisp_notation/crisp_notation.dart' show Step;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final en = AppLocalizationsEn();
  final de = AppLocalizationsDe();

  test('auto follows the UI language for the natural B', () {
    expect(noteName(en, Step.b), 'B');
    expect(noteName(de, Step.b), 'H');
  });

  test('an explicit convention overrides the UI language', () {
    // German UI, English naming -> B, not H.
    expect(noteName(de, Step.b, naming: NoteNaming.english), 'B');
    // English UI, German naming -> H.
    expect(noteName(en, Step.b, naming: NoteNaming.germanH), 'H');
  });

  test('solfège spells the whole scale', () {
    String s(Step step) => noteName(en, step, naming: NoteNaming.solfege);
    expect(
      [Step.c, Step.d, Step.e, Step.f, Step.g, Step.a, Step.b].map(s).toList(),
      ['Do', 'Re', 'Mi', 'Fa', 'Sol', 'La', 'Si'],
    );
  });

  test('spelledMidiName: octave, sharps, and German H', () {
    // English: A3, C#4, B4.
    expect(spelledMidiNameWith(en, NoteNaming.auto, 57), 'A3');
    expect(spelledMidiNameWith(en, NoteNaming.auto, 61), 'C♯4');
    expect(spelledMidiNameWith(en, NoteNaming.auto, 71), 'B4');
    // German auto: the natural B becomes H.
    expect(spelledMidiNameWith(de, NoteNaming.auto, 71), 'H4');
    // Pitch-class form (chord roots): no octave.
    expect(
      spelledMidiNameWith(en, NoteNaming.auto, 60 + 9, withOctave: false),
      'A',
    );
    expect(
      spelledMidiNameWith(de, NoteNaming.auto, 60 + 11, withOctave: false),
      'H',
    );
  });

  test('the non-B letters are identical across letter conventions', () {
    for (final step in [Step.c, Step.d, Step.e, Step.f, Step.g, Step.a]) {
      final letter = noteName(en, step, naming: NoteNaming.english);
      expect(noteName(en, step, naming: NoteNaming.germanH), letter);
    }
  });
}
