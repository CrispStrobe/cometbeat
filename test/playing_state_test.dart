// test/playing_state_test.dart
//
// SE-C1. pizz./arco is a STATE with change points, so the claims worth pinning
// are about what happens BETWEEN the marks, and about surviving a round trip
// through MusicXML — which is the only reason riding on Annotation is worth it.

import 'package:comet_beat/core/notation/playing_state.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter_test/flutter_test.dart';

Score _notes(int count) {
  var i = 0;
  return Score(
    clef: Clef.bass,
    measures: [
      Measure([
        for (var k = 0; k < count; k++)
          NoteElement.note(
            const Pitch(Step.d, octave: 3),
            NoteDuration.quarter,
            id: 'n${i++}',
          ),
      ]),
    ],
  );
}

List<String> _pattern(Score score, int count) {
  final states = playingStates(score);
  return [
    for (var i = 0; i < count; i++)
      states['n$i'] == PlayingState.pizzicato ? 'P' : 'A',
  ];
}

void main() {
  group('reading a printed marking', () {
    test('the forms engravers and other programs actually write', () {
      for (final t in ['pizz.', 'pizz', 'Pizzicato', 'PIZZ.', ' pizz. ']) {
        expect(playingStateFromMark(t), PlayingState.pizzicato, reason: t);
      }
      for (final t in ['arco', 'Arco', 'ARCO']) {
        expect(playingStateFromMark(t), PlayingState.arco, reason: t);
      }
    });

    test('ordinary staff text is not a playing state', () {
      expect(playingStateFromMark('Andante'), isNull);
      expect(playingStateFromMark('C7'), isNull);
      expect(playingStateFromMark(''), isNull);
    });
  });

  group('the state between the marks', () {
    test('an unmarked part is bowed throughout', () {
      expect(_pattern(_notes(4), 4), ['A', 'A', 'A', 'A']);
    });

    test('a mark holds until something countermands it', () {
      // This is the property that makes it a state rather than a note
      // decoration: ONE mark changes everything after it.
      final score = scoreWithPlayingState(
        _notes(4),
        fromElementId: 'n1',
        state: PlayingState.pizzicato,
      );
      expect(_pattern(score, 4), ['A', 'P', 'P', 'P']);
    });

    test('and arco takes it back', () {
      var score = scoreWithPlayingState(
        _notes(4),
        fromElementId: 'n1',
        state: PlayingState.pizzicato,
      );
      score = scoreWithPlayingState(
        score,
        fromElementId: 'n3',
        state: PlayingState.arco,
      );
      expect(_pattern(score, 4), ['A', 'P', 'P', 'A']);
    });

    test('the mark takes effect ON its note, not after it', () {
      final score = scoreWithPlayingState(
        _notes(2),
        fromElementId: 'n0',
        state: PlayingState.pizzicato,
      );
      expect(_pattern(score, 2), ['P', 'P']);
    });
  });

  group('what it refuses to write', () {
    test('re-stating a state already in force adds nothing', () {
      final plain = _notes(3);
      // Everything is arco already.
      expect(
        scoreWithPlayingState(
          plain,
          fromElementId: 'n1',
          state: PlayingState.arco,
        ).annotations,
        isEmpty,
        reason: 'an engraver would not print a mark that changes nothing',
      );
    });

    test('a LATER redundant mark of the same state is cleaned up', () {
      // Mark n2 pizz., then n0 pizz.: the n2 mark now says nothing new and
      // would print as a second "pizz." in the middle of a pizz. passage.
      var score = scoreWithPlayingState(
        _notes(4),
        fromElementId: 'n2',
        state: PlayingState.pizzicato,
      );
      score = scoreWithPlayingState(
        score,
        fromElementId: 'n0',
        state: PlayingState.pizzicato,
      );
      expect(_pattern(score, 4), ['P', 'P', 'P', 'P']);
      expect(
        score.annotations.where((a) => playingStateFromMark(a.text) != null),
        hasLength(1),
      );
    });

    test(
        'but a later mark of the OTHER state is kept — it still means something',
        () {
      // ⚠ The arco mark has to MEAN something before it can be kept, so the
      // passage is made pizz. first — marking arco on an already-arco score is
      // the documented no-op above, which is what my first version of this
      // test tripped over.
      var score = scoreWithPlayingState(
        _notes(4),
        fromElementId: 'n1',
        state: PlayingState.pizzicato,
      );
      score = scoreWithPlayingState(
        score,
        fromElementId: 'n2',
        state: PlayingState.arco,
      );
      expect(_pattern(score, 4), ['A', 'P', 'A', 'A']);

      // Now extend the pizz. back to the start: the n1 mark is newly redundant
      // and goes, the n2 arco still says something and stays.
      score = scoreWithPlayingState(
        score,
        fromElementId: 'n0',
        state: PlayingState.pizzicato,
      );
      expect(_pattern(score, 4), ['P', 'P', 'A', 'A']);
    });

    test('an unknown anchor changes nothing', () {
      final plain = _notes(2);
      expect(
        scoreWithPlayingState(
          plain,
          fromElementId: 'nope',
          state: PlayingState.pizzicato,
        ),
        same(plain),
      );
    });
  });

  test('it survives a MusicXML round trip — the reason it rides on Annotation',
      () {
    final score = scoreWithPlayingState(
      _notes(4),
      fromElementId: 'n1',
      state: PlayingState.pizzicato,
    );
    final xml = scoreToMusicXml(score);
    expect(xml, contains('pizz.'));

    // Re-import and ask the same question of the round-tripped score. Ids are
    // re-issued by the reader, so compare the PATTERN, not the ids.
    final back = scoreFromMusicXml(xml);
    final states = playingStates(back);
    final notes = [
      for (final m in back.measures)
        for (final e in m.elements)
          if (e is NoteElement && e.id != null) e.id!,
    ];
    expect(
      [
        for (final id in notes)
          states[id] == PlayingState.pizzicato ? 'P' : 'A',
      ],
      ['A', 'P', 'P', 'P'],
      reason: 'a part exported from here must still say pizz. when it comes '
          'back — from this app or any other',
    );
  });
}
