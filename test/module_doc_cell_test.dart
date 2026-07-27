// DocCell value semantics in the neutral tracker model. The many round-trip
// suites build DocCells but never assert isEmpty / == / hashCode directly;
// these underpin pattern de-duplication and change detection, so pin them.
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DocCell.isEmpty', () {
    test('the default / empty cell is empty', () {
      expect(const DocCell().isEmpty, isTrue);
      expect(DocCell.empty.isEmpty, isTrue);
    });

    test('a key-off cell is NOT empty (it stops the ringing note)', () {
      expect(const DocCell.off().isEmpty, isFalse);
    });

    test('any populated field makes a cell non-empty', () {
      expect(const DocCell(note: 60).isEmpty, isFalse);
      expect(const DocCell(instrument: 1).isEmpty, isFalse);
      expect(const DocCell(volume: 32).isEmpty, isFalse);
      expect(const DocCell(effect: 1).isEmpty, isFalse);
      expect(const DocCell(effectParam: 5).isEmpty, isFalse);
      expect(const DocCell(nativeEffect: 3).isEmpty, isFalse);
      expect(const DocCell(nativeInstrument: 2).isEmpty, isFalse);
      expect(const DocCell(nativeNote: 40).isEmpty, isFalse);
      expect(const DocCell(nativeVolpan: 10).isEmpty, isFalse);
    });
  });

  group('DocCell value equality', () {
    test('identical cells are equal with equal hashCodes', () {
      const a = DocCell(note: 60, instrument: 3, volume: 48, effect: 1);
      const b = DocCell(note: 60, instrument: 3, volume: 48, effect: 1);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a difference in any field breaks equality', () {
      const base = DocCell(note: 60, instrument: 3, volume: 48, effect: 1);
      expect(
        base,
        isNot(const DocCell(note: 61, instrument: 3, volume: 48, effect: 1)),
      );
      expect(
        base,
        isNot(const DocCell(note: 60, instrument: 4, volume: 48, effect: 1)),
      );
      expect(
        base,
        isNot(const DocCell(note: 60, instrument: 3, volume: 49, effect: 1)),
      );
      expect(
        base,
        isNot(const DocCell(note: 60, instrument: 3, volume: 48, effect: 2)),
      );
      expect(
        base,
        isNot(
          const DocCell(
            note: 60,
            instrument: 3,
            volume: 48,
            noteOff: true,
          ),
        ),
      );
    });

    test('an empty cell differs from a key-off cell', () {
      expect(const DocCell(), isNot(const DocCell.off()));
    });
  });
}
