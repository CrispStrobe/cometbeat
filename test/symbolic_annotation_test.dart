// test/symbolic_annotation_test.dart
//
// C0 — the interop side-car. Its whole job is to not lose things, so the tests
// are about exactly that: an address survives serialisation as a map key,
// unknown keys written by a newer build survive untouched, and a corrupt bag
// costs fidelity rather than the document.

import 'package:comet_beat/core/interop/symbolic_annotation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EventAddress', () {
    test('is a value type — equal addresses are the same map key', () {
      const a = EventAddress(track: 1, step: 4);
      const b = EventAddress(track: 1, step: 4);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      final map = {a: 'x'};
      expect(map[b], 'x');
    });

    test('voice participates in identity', () {
      const a = EventAddress(track: 1, step: 4);
      const b = EventAddress(track: 1, step: 4, voice: 1);
      expect(a, isNot(b));
    });

    test('round-trips through its string key', () {
      const a = EventAddress(track: 3, step: 17, voice: 2);
      expect(EventAddress.parseKey(a.key), a);
    });

    test('a malformed key parses to null, it does not throw', () {
      expect(EventAddress.parseKey(''), isNull);
      expect(EventAddress.parseKey('1:2'), isNull);
      expect(EventAddress.parseKey('a:b:c'), isNull);
      expect(EventAddress.parseKey('1:2:3:4'), isNull);
    });
  });

  group('SymbolicAnnotations', () {
    test('starts empty, and empty means "the conversion lost nothing"', () {
      final notes = SymbolicAnnotations();
      expect(notes.isEmpty, isTrue);
      expect(notes.eventCount, 0);
      expect(notes.at(const EventAddress(track: 0, step: 0)), isEmpty);
    });

    test('a null value removes the key and prunes an emptied entry', () {
      // A converter writes unconditionally; nulls must not leave debris behind,
      // or isEmpty stops meaning anything.
      final notes = SymbolicAnnotations();
      const at = EventAddress(track: 0, step: 0);
      notes.set(at, AnnotationKeys.fret, 5);
      expect(notes.eventCount, 1);
      notes.set(at, AnnotationKeys.fret, null);
      expect(notes.eventCount, 0);
      expect(notes.isEmpty, isTrue);
    });

    test('put skips nulls but keeps the rest', () {
      final notes = SymbolicAnnotations();
      const at = EventAddress(track: 2, step: 8);
      notes.put(at, {
        AnnotationKeys.fret: 7,
        AnnotationKeys.capo: null,
        AnnotationKeys.section: 'Chorus',
      });
      expect(
        notes.at(at).keys,
        unorderedEquals([AnnotationKeys.fret, AnnotationKeys.section]),
      );
    });

    test('round-trips through JSON, keeping value types', () {
      final notes = SymbolicAnnotations()
        ..docMeta[AnnotationKeys.tuning] = [64, 59, 55, 50, 45, 40]
        ..docMeta[AnnotationKeys.capo] = 2;
      notes.put(const EventAddress(track: 1, step: 4, voice: 1), {
        AnnotationKeys.techniques: ['slide', 'vibrato'],
        AnnotationKeys.velocity: 0.8,
        AnnotationKeys.tieToNext: true,
      });

      final back = SymbolicAnnotations.fromJson(notes.toJson());
      expect(back.docMeta[AnnotationKeys.capo], 2);
      expect(back.docMeta[AnnotationKeys.tuning], [64, 59, 55, 50, 45, 40]);
      const at = EventAddress(track: 1, step: 4, voice: 1);
      expect(back.at(at)[AnnotationKeys.techniques], ['slide', 'vibrato']);
      expect(back.at(at)[AnnotationKeys.velocity], 0.8);
      expect(back.at(at)[AnnotationKeys.tieToNext], true);
    });

    test('a key this build does not know survives a round-trip untouched', () {
      // The forward-compatibility guarantee: a newer converter can annotate
      // something we have no constant for, and we must hand it back intact.
      final notes = SymbolicAnnotations();
      notes.set(
        const EventAddress(track: 0, step: 0),
        'someFutureThing',
        {'nested': 42},
      );
      final back = SymbolicAnnotations.fromJson(notes.toJson());
      expect(
        back.at(const EventAddress(track: 0, step: 0))['someFutureThing'],
        {'nested': 42},
      );
    });

    test('a corrupt bag yields an empty one rather than throwing', () {
      expect(SymbolicAnnotations.fromJson(null).isEmpty, isTrue);
      expect(SymbolicAnnotations.fromJson('nope').isEmpty, isTrue);
      expect(
        SymbolicAnnotations.fromJson({'events': 'not a map'}).isEmpty,
        isTrue,
      );
      // Well-formed entries survive alongside malformed ones.
      final mixed = SymbolicAnnotations.fromJson({
        'events': {
          'garbage': {'fret': 1},
          '0:0:0': {'fret': 9},
        },
      });
      expect(mixed.eventCount, 1);
      expect(mixed.at(const EventAddress(track: 0, step: 0))['fret'], 9);
    });

    test('restrictToTrack re-addresses to track 0', () {
      // Without the re-addressing, a single-track callee looks up track 0 and
      // finds nothing.
      final notes = SymbolicAnnotations()..docMeta['x'] = 1;
      notes.set(const EventAddress(track: 0, step: 1), 'a', 1);
      notes.set(const EventAddress(track: 2, step: 5), 'b', 2);
      notes.set(const EventAddress(track: 2, step: 9), 'c', 3);

      final only2 = notes.restrictToTrack(2);
      expect(only2.eventCount, 2);
      expect(only2.at(const EventAddress(track: 0, step: 5))['b'], 2);
      expect(only2.at(const EventAddress(track: 0, step: 9))['c'], 3);
      expect(only2.docMeta['x'], 1);
      // The original is untouched.
      expect(notes.eventCount, 3);
    });

    test('merge combines both, with the other side winning collisions', () {
      final a = SymbolicAnnotations()..docMeta['k'] = 'a';
      a.set(const EventAddress(track: 0, step: 0), 'shared', 'a');
      a.set(const EventAddress(track: 0, step: 0), 'onlyA', 1);
      final b = SymbolicAnnotations()..docMeta['k'] = 'b';
      b.set(const EventAddress(track: 0, step: 0), 'shared', 'b');
      b.set(const EventAddress(track: 0, step: 1), 'onlyB', 2);

      final merged = a.merge(b);
      expect(merged.docMeta['k'], 'b');
      const at = EventAddress(track: 0, step: 0);
      expect(merged.at(at)['shared'], 'b');
      expect(merged.at(at)['onlyA'], 1);
      expect(merged.at(const EventAddress(track: 0, step: 1))['onlyB'], 2);
      // Neither input mutated.
      expect(a.at(at)['shared'], 'a');
      expect(a.eventCount, 1);
      expect(b.eventCount, 2);
    });
  });

  group('ConversionReport', () {
    test('lossless only when nothing was lost or approximated', () {
      final report = ConversionReport();
      expect(report.lossless, isTrue);
      report.addApproximated('tuplets quantized');
      expect(report.lossless, isFalse);
    });

    test('deduplicates — a per-event loop must not repeat itself 400 times',
        () {
      final report = ConversionReport();
      for (var i = 0; i < 400; i++) {
        report.addLost('chord diagrams');
        report.addApproximated('techniques approximated');
      }
      expect(report.lost, ['chord diagrams']);
      expect(report.approximated, ['techniques approximated']);
    });

    test('reads as something a user could be shown', () {
      final report = ConversionReport()
        ..addLost('chord diagrams')
        ..addApproximated('bends become pitch slides');
      expect(report.toString(), contains('chord diagrams'));
      expect(report.toString(), contains('bends become pitch slides'));
      expect(ConversionReport().toString(), 'lossless');
    });
  });
}
