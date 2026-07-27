// symbol_catalog.dart — the note-value symbol catalog (id · glyph · beats ·
// label · SRI id). Pure data + a lookup, so its invariants are exactly
// testable. (label needs an AppLocalizations at call time and is not exercised
// here.)
import 'package:comet_beat/features/games/note_values/symbol_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('symbolById returns the entry, or null for an unknown id', () {
    expect(symbolById('whole_note')?.beats, 1.0);
    expect(symbolById('quarter_note')?.beats, 0.25);
    expect(symbolById('sixteenth_rest')?.beats, 0.0625);
    expect(symbolById('nope'), isNull);
    expect(symbolById(''), isNull);
  });

  test('every catalog id is unique', () {
    final ids = kNoteSymbols.map((s) => s.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('the durations are exact fractions of a whole note, halving each step',
      () {
    const expected = {
      'whole_note': 1.0,
      'half_note': 0.5,
      'quarter_note': 0.25,
      'eighth_note': 0.125,
      'sixteenth_note': 0.0625,
    };
    for (final e in expected.entries) {
      expect(symbolById(e.key)?.beats, e.value, reason: e.key);
    }
  });

  test('every note value has a matching rest of the same duration', () {
    for (final base in ['whole', 'half', 'quarter', 'eighth', 'sixteenth']) {
      final note = symbolById('${base}_note');
      final rest = symbolById('${base}_rest');
      expect(note, isNotNull, reason: '$base note');
      expect(rest, isNotNull, reason: '$base rest');
      expect(rest!.beats, note!.beats, reason: '$base note/rest duration');
    }
  });

  test('the SRI id namespaces the catalog id', () {
    expect(symbolById('whole_note')!.sriId, 'note_values.symbol.whole_note');
  });

  test('every entry carries a non-empty glyph', () {
    for (final s in kNoteSymbols) {
      expect(s.glyph, isNotEmpty, reason: s.id);
    }
  });
}
