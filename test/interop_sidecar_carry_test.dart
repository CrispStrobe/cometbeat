// What the side-car is FOR: surviving the hop that cannot hold it.
//
// The point of `SymbolicAnnotations` is that a fact with no slot in the target
// model is not destroyed by passing through it — a score has no strings, a loop
// track has no strings, so the tuning rides alongside and is there again when
// something needs to rebuild a fretted instrument.
//
// It was not doing that. Only Tab → Tracker ever authored a side-car, and five
// of six hops dropped an incoming one on the floor, so a DADGAD tab that went
// through Score or Loop came back in standard tuning: the frets are preserved
// and every pitch is wrong. Nothing threw, and the report said nothing, because
// each converter was individually doing what it said it did.
//
// Two rules, and the second is the interesting one:
//
//   * `docMeta` travels. A tuning or a capo means the same thing in every mode.
//   * per-EVENT entries do NOT. They are keyed by an address the conversion has
//     just invalidated, so carrying them would attach a real fact to the wrong
//     note — worse than losing it, because it looks right.

import 'package:comet_beat/core/interop/annotation_codecs.dart'
    show tuningFromAnnotation, tuningToAnnotation;
import 'package:comet_beat/core/interop/project_bridge.dart';
import 'package:comet_beat/core/interop/symbolic_annotation.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A short tab in [tuning] — four quarter notes on the lowest string.
TabDocument _tab(Tuning tuning) {
  final doc = TabDocument.blank(tuning, initialColumns: 0);
  for (final fret in [0, 2, 3, 5]) {
    doc.columns.add(
      TabColumn(frets: {tuning.stringCount - 1: fret}),
    );
  }
  return doc;
}

/// The tuning [result] would have a later Tab rebuilt in, if any.
Tuning? _carriedTuning(ConversionResult result) =>
    tuningFromAnnotation(result.annotations.docMeta[AnnotationKeys.tuning]);

void main() {
  group('a tuning survives a mode that has no strings', () {
    for (final waypoint in [AppMode.score, AppMode.loop]) {
      test('Tab → ${waypoint.name} → Tab keeps DADGAD', () {
        final original = _tab(Tuning.dadgadGuitar);

        final out = ProjectBridge.convert(
          from: AppMode.tab,
          to: waypoint,
          document: original,
        );
        expect(out.document, isNotNull);
        expect(
          _carriedTuning(out)?.strings.map((p) => p.midiNumber),
          Tuning.dadgadGuitar.strings.map((p) => p.midiNumber),
          reason: 'the ${waypoint.name} hop did not record the tuning',
        );

        // Coming back WITHOUT naming a tuning: the side-car is the only thing
        // that can stop this defaulting to standard.
        final back = ProjectBridge.convert(
          from: waypoint,
          to: AppMode.tab,
          document: out.document!,
          annotations: out.annotations,
        );
        expect(back.document, isNotNull);
        expect(
          (back.document! as TabDocument).tuning.strings.map(
                (p) => p.midiNumber,
              ),
          Tuning.dadgadGuitar.strings.map((p) => p.midiNumber),
          reason: 'the tab came back in the wrong tuning',
        );
      });
    }

    test('with no side-car it still falls back to standard, as before', () {
      final out = ProjectBridge.convert(
        from: AppMode.tab,
        to: AppMode.score,
        document: _tab(Tuning.dadgadGuitar),
      );
      final back = ProjectBridge.convert(
        from: AppMode.score,
        to: AppMode.tab,
        document: out.document!,
      );
      expect(
        (back.document! as TabDocument).tuning.strings.map((p) => p.midiNumber),
        Tuning.standardGuitar.strings.map((p) => p.midiNumber),
        reason: 'without the side-car there is nothing to know it from',
      );
    });

    test('an explicit tuning still wins over a carried one', () {
      // The caller is looking at the instrument; the side-car only remembers an
      // earlier document.
      final out = ProjectBridge.convert(
        from: AppMode.tab,
        to: AppMode.score,
        document: _tab(Tuning.dadgadGuitar),
      );
      final back = ProjectBridge.convert(
        from: AppMode.score,
        to: AppMode.tab,
        document: out.document!,
        annotations: out.annotations,
        tuning: Tuning.dropDGuitar,
      );
      expect(
        (back.document! as TabDocument).tuning.strings.map((p) => p.midiNumber),
        Tuning.dropDGuitar.strings.map((p) => p.midiNumber),
      );
    });
  });

  group('carrying rules', () {
    test('an incoming docMeta fact survives a hop that authors nothing', () {
      final incoming = SymbolicAnnotations()
        ..docMeta[AnnotationKeys.tuning] =
            tuningToAnnotation(Tuning.dadgadGuitar);

      final tab = ProjectBridge.convert(
        from: AppMode.tab,
        to: AppMode.tracker,
        document: _tab(Tuning.dadgadGuitar),
      );
      final onward = ProjectBridge.convert(
        from: AppMode.tracker,
        to: AppMode.score,
        document: tab.document!,
        annotations: incoming,
      );
      expect(_carriedTuning(onward), isNotNull);
    });

    test("the route's own reading wins over the carried one", () {
      // Tab → Tracker reads the tuning off the document in front of it. A stale
      // one riding along must not overwrite that.
      final stale = SymbolicAnnotations()
        ..docMeta[AnnotationKeys.tuning] =
            tuningToAnnotation(Tuning.dropDGuitar);

      final out = ProjectBridge.convert(
        from: AppMode.tab,
        to: AppMode.tracker,
        document: _tab(Tuning.dadgadGuitar),
        annotations: stale,
      );
      expect(
        _carriedTuning(out)?.strings.map((p) => p.midiNumber),
        Tuning.dadgadGuitar.strings.map((p) => p.midiNumber),
        reason: 'a stale side-car overwrote what the document actually says',
      );
    });

    test('per-event entries are NOT carried across a conversion', () {
      // The deliberate limit. `EventAddress` is (track, step, voice) in the
      // SOURCE model; after a conversion those coordinates address a different
      // note, so carrying the entry would state a real fact about the wrong
      // one. Losing it is the honest outcome.
      const address = EventAddress(track: 0, step: 2);
      final incoming = SymbolicAnnotations()
        ..set(address, AnnotationKeys.velocity, 0.25);

      final out = ProjectBridge.convert(
        from: AppMode.tab,
        to: AppMode.score,
        document: _tab(Tuning.dadgadGuitar),
        annotations: incoming,
      );
      expect(
        out.annotations.get(address, AnnotationKeys.velocity),
        isNull,
        reason: 'an event annotation was carried onto a re-addressed document',
      );
      expect(
        out.annotations.docMeta[AnnotationKeys.tuning],
        isNotNull,
        reason: 'document-level facts should still travel',
      );
    });
  });
}
