// The answer-explanation glossary: every term has a meaning + an explanation
// in BOTH UI languages, the ladders are in the right musical order, and the
// key German wordings are the conventional ones.

import 'package:comet_beat/features/games/explain/music_terms.dart';
import 'package:comet_beat/features/games/note_values/dynamics_duel_screen.dart';
import 'package:comet_beat/features/games/note_values/tempo_duel_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final de = lookupAppLocalizations(const Locale('de'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('every term has a non-empty name, meaning and info in de + en', () {
    for (final l10n in [de, en]) {
      for (final t in MusicTerm.values) {
        expect(termName(l10n, t), isNotEmpty, reason: t.name);
        expect(termMeaning(l10n, t), isNotEmpty, reason: t.name);
        expect(termInfo(l10n, t), isNotEmpty, reason: t.name);
      }
    }
  });

  test('German and English wording actually differ (both are translated)', () {
    for (final t in MusicTerm.values) {
      expect(termMeaning(de, t), isNot(termMeaning(en, t)), reason: t.name);
      expect(termInfo(de, t), isNot(termInfo(en, t)), reason: t.name);
    }
  });

  test('the dynamics ladder runs pp < p < mp < mf < f < ff', () {
    expect(
      MusicTerm.dynamicsLadder.map((t) => t.mark),
      ['pp', 'p', 'mp', 'mf', 'f', 'ff'],
    );
    final ladder = MusicTerm.dynamicsLadder;
    for (var i = 1; i < ladder.length; i++) {
      expect(ladder[i].rank, greaterThan(ladder[i - 1].rank));
      expect(ladder[i].gain, greaterThan(ladder[i - 1].gain));
    }
    expect(
      MusicTerm.dynamicsLadder.map((t) => t.italian),
      [
        'pianissimo',
        'piano',
        'mezzopiano',
        'mezzoforte',
        'forte',
        'fortissimo',
      ],
    );
  });

  test('the tempo ladder runs Largo … Presto with rising BPM', () {
    final ladder = MusicTerm.tempoLadder;
    expect(
      ladder.map((t) => t.mark),
      ['Largo', 'Adagio', 'Andante', 'Moderato', 'Allegro', 'Vivace', 'Presto'],
    );
    for (var i = 1; i < ladder.length; i++) {
      expect(ladder[i].bpm, greaterThan(ladder[i - 1].bpm));
    }
  });

  test('glossary order agrees with the games that use it', () {
    for (final m in kDynamicMarks) {
      expect(MusicTerm.dynamicFromMark(m.name)!.rank, m.rank);
      expect(MusicTerm.dynamicFromMark(m.name)!.glyph, m.code);
    }
    for (final t in kTempoTerms) {
      expect(MusicTerm.tempoFromMark(t.name)!.rank, t.rank);
    }
  });

  test('conventional German meanings for the key terms', () {
    expect(termMeaning(de, MusicTerm.pp), 'sehr leise');
    expect(termMeaning(de, MusicTerm.p), 'leise');
    expect(termMeaning(de, MusicTerm.mp), contains('halbleise'));
    expect(termMeaning(de, MusicTerm.mf), contains('halblaut'));
    expect(termMeaning(de, MusicTerm.f), 'laut');
    expect(termMeaning(de, MusicTerm.ff), 'sehr laut');
    expect(termMeaning(de, MusicTerm.crescendo), 'lauter werden');
    expect(termMeaning(de, MusicTerm.diminuendo), 'leiser werden');
    expect(termMeaning(de, MusicTerm.andante), 'gehend');
    expect(termMeaning(de, MusicTerm.staccato), contains('kurz'));
    expect(termMeaning(de, MusicTerm.legato), 'gebunden');
  });

  test('gradual changes point the right way', () {
    expect(MusicTerm.crescendo.rank, greaterThan(0));
    expect(MusicTerm.diminuendo.rank, lessThan(0));
    expect(MusicTerm.accelerando.rank, greaterThan(0));
    expect(MusicTerm.ritardando.rank, lessThan(0));
  });
}
