// WS-L5 — copying a pattern from one track to another.
//
// "Copy A to B, change one thing" is how sequencer users actually work. The
// Loop Studio could already copy a whole SECTION; the level below it — this
// track's notes onto that track — had no route at all, so every variation was
// built from nothing.
//
// The card asked to "duplicate a scene or a pattern", and the scene half turned
// out to be already shipped (a section IS a GrooveScene here). The pattern half
// looked blocked on a product decision, because a "pattern" is either an
// authored VARIANT — data, not an editable slot, so there is no B to copy into
// — or an override that replaces whichever variant is playing. This takes the
// second reading: copying writes an override onto the destination, which needs
// no new model and is the workflow the card actually described.
//
// Two things the tests below pin, both of which would be invisible bugs:
//
//   the copy is DEEP — `setTrackDrums` stores the object it is handed, so a
//   shallow copy leaves two tracks sharing one grid and editing either edits
//   both, which is the aliasing bug that already bit the track copy once;
//
//   the AUTHORED pattern is copied, not the sounding one — `cellsFor` returns
//   the four-bar resolved shape in progression mode, and writing that back as
//   a two-bar override is a length the renderer asserts on.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:flutter_test/flutter_test.dart';

LoopEngine _engine() {
  final e = LoopEngine(tempoBpm: 120);
  e.enabled
    ..clear()
    ..addAll(['drums', 'bass', 'melody']);
  return e;
}

void main() {
  group('what can be copied onto what', () {
    test('pitched to pitched, drums to drums', () {
      final e = _engine();
      expect(e.canCopyPattern('bass', 'melody'), isTrue);
      expect(e.canCopyPattern('melody', 'bass'), isTrue);
      expect(e.canCopyPattern('drums', 'beat'), isFalse, reason: 'no beat yet');
    });

    test('a drum grid is refused on a melody track, and the reverse', () {
      // Not a transposition problem: the rows are kick, snare and hat, not
      // pitches. Copying either way is meaningless rather than merely odd.
      final e = _engine();
      expect(e.canCopyPattern('drums', 'bass'), isFalse);
      expect(e.canCopyPattern('bass', 'drums'), isFalse);
    });

    test('a track cannot be copied onto itself', () {
      expect(_engine().canCopyPattern('bass', 'bass'), isFalse);
    });

    test('unknown ids are refused, not crashed on', () {
      final e = _engine();
      expect(e.canCopyPattern('tuba', 'bass'), isFalse);
      expect(e.canCopyPattern('bass', 'tuba'), isFalse);
      expect(e.copyPattern('tuba', 'bass'), isFalse);
    });

    test('an AUDIO track has no pattern in either direction', () {
      final e = _engine();
      final audio = e.addAudioTrack(_silence());
      expect(e.canCopyPattern(audio, 'bass'), isFalse);
      expect(e.canCopyPattern('bass', audio), isFalse);
      expect(e.copyPattern('bass', audio), isFalse);
    });

    test('the offered targets are exactly the compatible ones', () {
      final e = _engine();
      final targets = e.copyTargetsFor('bass');
      expect(targets, contains('melody'));
      expect(targets, isNot(contains('bass')), reason: 'not itself');
      expect(targets, isNot(contains('drums')), reason: 'not a drum track');
    });
  });

  group('the copy lands', () {
    test('a pitched pattern is heard on the destination', () {
      final e = _engine();
      final before = e.cellsFor('melody');
      expect(e.copyPattern('bass', 'melody'), isTrue);
      final after = e.cellsFor('melody');
      expect(after, isNot(before));
      expect(
        after!.map((c) => c.midis),
        e.cellsFor('bass')!.map((c) => c.midis),
      );
    });

    test('a drum grid is heard on the destination', () {
      final e = _engine();
      e.setUserBeatTrack(
        DrumRowsPattern({Drum.kick: stepRow('x...............')}),
      );
      expect(e.copyPattern('drums', 'beat'), isTrue);
      expect(
        e.drumRowsFor('beat')!.rows[Drum.kick],
        e.drumRowsFor('drums')!.rows[Drum.kick],
      );
    });

    test('it changes the RENDER, not just the model', () {
      final e = _engine();
      e.enabled
        ..clear()
        ..add('melody');
      final before = e.renderLoop();
      expect(e.copyPattern('bass', 'melody'), isTrue);
      expect(e.renderLoop(), isNot(orderedEquals(before)));
    });

    test('the source is left alone', () {
      final e = _engine();
      final sourceBefore = e.cellsFor('bass')!.map((c) => c.midis).toList();
      e.copyPattern('bass', 'melody');
      expect(e.cellsFor('bass')!.map((c) => c.midis), sourceBefore);
    });

    test('copying an edited pattern copies the EDIT, not the original', () {
      final e = _engine();
      e.setTrackCells('bass', const [
        PatternCell(midis: [48], steps: 8),
        PatternCell(midis: [55], steps: 8),
      ]);
      expect(e.copyPattern('bass', 'melody'), isTrue);
      expect(e.trackCellsOverride('melody')!.first.midis, [48]);
    });
  });

  group('the copy is DEEP — the aliasing trap', () {
    test('editing the copy does not edit the source (drums)', () {
      // `setTrackDrums` stores the object it is handed, so a shallow copy
      // leaves both tracks sharing one grid. This is the same bug that bit the
      // track copy, one level down, and it is invisible until someone edits.
      final e = _engine();
      e.setUserBeatTrack(
        DrumRowsPattern({Drum.kick: stepRow('x...............')}),
      );
      expect(e.copyPattern('drums', 'beat'), isTrue);

      final sourceBefore =
          List<bool>.of(e.drumRowsFor('drums')!.rows[Drum.kick]!);
      final copied = e.drumRowsFor('beat')!;
      e.setTrackDrums(
        'beat',
        DrumRowsPattern({
          for (final row in copied.rows.entries)
            row.key: [for (var i = 0; i < row.value.length; i++) i == 3],
        }),
      );
      expect(e.drumRowsFor('drums')!.rows[Drum.kick], sourceBefore);
    });

    test('the two grids are not the same LIST', () {
      final e = _engine();
      e.setUserBeatTrack(
        DrumRowsPattern({Drum.kick: stepRow('x...............')}),
      );
      e.copyPattern('drums', 'beat');
      expect(
        identical(
          e.drumRowsFor('beat')!.rows[Drum.kick],
          e.drumRowsFor('drums')!.rows[Drum.kick],
        ),
        isFalse,
        reason: 'a shared row is a shared edit',
      );
    });

    test('ghost velocities come across, and are copied too', () {
      final e = _engine();
      e.setUserBeatTrack(
        DrumRowsPattern({Drum.kick: stepRow('x...............')}),
      );
      e.setTrackDrums(
        'drums',
        DrumRowsPattern(
          {Drum.kick: stepRow('x.x.............')},
          velocities: {
            Drum.kick: [1.0, 0, 0.4, ...List.filled(13, 0.0)],
          },
        ),
      );
      expect(e.copyPattern('drums', 'beat'), isTrue);
      final copied = e.drumRowsFor('beat')!;
      expect(copied.velocities?[Drum.kick]?[2], 0.4);
      expect(
        identical(
          copied.velocities?[Drum.kick],
          e.drumRowsFor('drums')!.velocities?[Drum.kick],
        ),
        isFalse,
      );
    });

    test('the pitched copy is a separate list too', () {
      final e = _engine();
      e.copyPattern('bass', 'melody');
      expect(
        identical(e.trackCellsOverride('melody'), e.trackCellsOverride('bass')),
        isFalse,
      );
    });
  });

  group('it copies the AUTHORED pattern, not the sounding one', () {
    test('in progression mode the override is still 2 bars', () {
      // `cellsFor` resolves to four bars under a progression. Writing that back
      // would be a pattern of the wrong length, which the render asserts on —
      // so the copy must take the authored shape.
      final e = _engine();
      e.progression = kProgressions.first;
      expect(e.cellsFor('bass')!.length, greaterThan(0));
      expect(e.copyPattern('bass', 'melody'), isTrue);
      final override = e.trackCellsOverride('melody')!;
      expect(
        override.fold<int>(0, (sum, c) => sum + c.steps),
        kPatternSteps,
        reason: 'an override must fill the 2-bar grid exactly',
      );
      // And it still renders, which is the assertion the length protects.
      expect(e.renderLoop().length, greaterThan(44));
    });

    test('the copy survives a share token, like any other edit', () {
      final e = _engine();
      e.copyPattern('bass', 'melody');
      final back = LoopEngine(tempoBpm: 120)
        ..applySpec(decodeGrooveToken(encodeGrooveToken(e.spec))!);
      expect(
        back.trackCellsOverride('melody')!.map((c) => c.midis),
        e.trackCellsOverride('melody')!.map((c) => c.midis),
      );
    });
  });
}

Float64List _silence() => Float64List(4410);
