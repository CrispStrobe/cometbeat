// Value semantics of the XM / S3M / IT format structs. The parse/round-trip
// suites build these but never assert the format-exception messages, the
// empty/identity factories, or the per-format cell isEmpty/==/hashCode — the
// coverage map flagged each around 55-62%. Pin them here.
import 'package:comet_beat/core/audio/mod/it_module.dart';
import 'package:comet_beat/core/audio/mod/s3m_module.dart';
import 'package:comet_beat/core/audio/mod/xm_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('format exceptions carry a named message', () {
    test('XM / S3M / IT toString', () {
      expect(
        const XmFormatException('bad sig').toString(),
        'XmFormatException: bad sig',
      );
      expect(
        const S3mFormatException('too short').toString(),
        'S3mFormatException: too short',
      );
      expect(
        const ItFormatException('no IMPM').toString(),
        'ItFormatException: no IMPM',
      );
    });
  });

  group('empty sample factories build a zero-length sample', () {
    test('XmSample / S3mSample / ItSample .empty()', () {
      expect(XmSample.empty().pcm, isEmpty);
      expect(S3mSample.empty().pcm, isEmpty);
      expect(ItSample.empty().pcm, isEmpty);
    });
  });

  group('XmCell', () {
    test('default is empty; a pitch makes it non-empty', () {
      expect(const XmCell().isEmpty, isTrue);
      expect(const XmCell(note: 49).isEmpty, isFalse);
      expect(const XmCell(instrument: 1).isEmpty, isFalse);
    });
    test('equality and hashCode', () {
      const a = XmCell(note: 49, instrument: 2, volume: 40, effect: 1);
      const b = XmCell(note: 49, instrument: 2, volume: 40, effect: 1);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const XmCell(note: 50, instrument: 2, volume: 40)));
      expect(a, isNot(const XmCell(note: 49, instrument: 2, volume: 40)));
    });
  });

  group('S3mCell', () {
    test('default is empty; a pitch makes it non-empty', () {
      expect(const S3mCell().isEmpty, isTrue);
      expect(const S3mCell(note: 60).isEmpty, isFalse);
      expect(const S3mCell(command: 1).isEmpty, isFalse);
    });
    test('equality and hashCode', () {
      const a = S3mCell(note: 60, instrument: 3, volume: 48, command: 1);
      const b = S3mCell(note: 60, instrument: 3, volume: 48, command: 1);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const S3mCell(note: 61, instrument: 3, volume: 48)));
    });
  });

  group('ItCell', () {
    test('default is empty; a pitch makes it non-empty', () {
      expect(const ItCell().isEmpty, isTrue);
      expect(const ItCell(note: 60).isEmpty, isFalse);
      expect(const ItCell(volpan: 32).isEmpty, isFalse);
    });
    test('equality and hashCode', () {
      const a = ItCell(note: 60, instrument: 3, volpan: 32, command: 1);
      const b = ItCell(note: 60, instrument: 3, volpan: 32, command: 1);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const ItCell(note: 60, instrument: 3, volpan: 33)));
    });
  });

  group('ItInstrument.identity', () {
    test('builds an identity key/note map over 120 notes', () {
      final id = ItInstrument.identity();
      expect(id.keymap.length, 120);
      expect(id.noteMap.length, 120);
      expect(id.noteMap.first, 0);
      expect(id.noteMap.last, 119);
    });
  });
}
