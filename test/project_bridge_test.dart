// test/project_bridge_test.dart
//
// C2 (Loop <-> Tab) + C3 (the ProjectBridge façade).
//
// The headline is the MATRIX: all 25 (from, to) pairs must either convert or
// say why not, and NONE may throw. That is the property that makes an "open
// in…" menu safe to build — a screen can offer every target without knowing
// which converter exists, and a pair that is not supported produces a sentence
// the user can read rather than a crash mid-tap.
//
// The second theme is honesty. Every lossy edge must NAME what it loses. A
// conversion that quietly drops fingering or velocity is worse than one that
// refuses, because the user only finds out later.

// The fixtures spell out every column's duration, including the ones that match
// the default — these tests are about what a conversion does to note LENGTHS,
// so leaving some implicit would hide the fixture.
// ignore_for_file: avoid_redundant_argument_values

import 'package:comet_beat/core/audio/loop_engine.dart' show PatternCell;
import 'package:comet_beat/core/audio/tracker_engine.dart' show TrackerTiming;
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/core/interop/loop_tab.dart';
import 'package:comet_beat/core/interop/project_bridge.dart';
import 'package:comet_beat/core/interop/symbolic_annotation.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

List<PatternCell> _loopTrack() => const [
      PatternCell(midis: [60], steps: 2),
      PatternCell(midis: [64, 67], steps: 2),
      PatternCell(steps: 2), // a rest
      PatternCell(midis: [62], steps: 2, velocity: 0.5),
    ];

TabDocument _tab() => TabDocument(
      tuning: Tuning.standardGuitar,
      columns: const [
        TabColumn(frets: {5: 3}, duration: NoteDuration.quarter),
        TabColumn(frets: {4: 5}, duration: NoteDuration.quarter),
      ],
    );

Object _documentFor(AppMode mode) => switch (mode) {
      AppMode.tab => _tab(),
      AppMode.loop => _loopTrack(),
      AppMode.tracker => TrackerSong(timing: const TrackerTiming(rows: 8)),
      AppMode.score => MultiPartScore([_tab().toScore()]),
      // Nothing symbolic to hand over; the bridge must reject it by MODE, not
      // by inspecting the document.
      AppMode.audio => const <int>[],
    };

void main() {
  group('C2 — loop <-> tab', () {
    test('pitches survive a round trip', () {
      final cells = _loopTrack();
      final toTab = tabDocumentFromLoopCells(cells, Tuning.standardGuitar);
      final back = loopCellsFromTabDocument(
        toTab.doc,
        annotations: toTab.annotations,
      );
      expect(back.cells, hasLength(cells.length));
      for (var i = 0; i < cells.length; i++) {
        expect(back.cells[i].midis, cells[i].midis, reason: 'cell $i');
      }
    });

    test('step lengths survive a round trip', () {
      final cells = _loopTrack();
      final toTab = tabDocumentFromLoopCells(cells, Tuning.standardGuitar);
      final back = loopCellsFromTabDocument(toTab.doc);
      for (var i = 0; i < cells.length; i++) {
        expect(back.cells[i].steps, cells[i].steps, reason: 'cell $i');
      }
    });

    test('velocity survives via the side-car — a tab has no dynamics', () {
      final cells = _loopTrack();
      final toTab = tabDocumentFromLoopCells(cells, Tuning.standardGuitar);
      expect(
        toTab.report.lost.any((s) => s.contains('velocity')),
        isTrue,
        reason: 'the loss must be reported, not silent',
      );
      final back = loopCellsFromTabDocument(
        toTab.doc,
        annotations: toTab.annotations,
      );
      expect(back.cells[3].velocity, 0.5);
    });

    test('without the side-car velocity is gone, as reported', () {
      final toTab = tabDocumentFromLoopCells(
        _loopTrack(),
        Tuning.standardGuitar,
      );
      final back = loopCellsFromTabDocument(toTab.doc);
      expect(back.cells[3].velocity, 1.0);
    });

    test('the fretting is playable, not just correct in pitch', () {
      // It routes through the real arranger, so a chord lands on distinct
      // strings within reach rather than "lowest fret for each note".
      final toTab = tabDocumentFromLoopCells(
        _loopTrack(),
        Tuning.standardGuitar,
      );
      final chord = toTab.doc.columns[1];
      expect(chord.frets, hasLength(2));
      expect(
        chord.frets.keys.toSet(),
        hasLength(2),
        reason: 'two notes landed on one string',
      );
      final frets = chord.frets.values.toList();
      expect(
        (frets.first - frets.last).abs(),
        lessThanOrEqualTo(5),
        reason: 'the shape is out of hand span',
      );
    });

    test('a rest stays a rest in both directions', () {
      final toTab = tabDocumentFromLoopCells(
        _loopTrack(),
        Tuning.standardGuitar,
      );
      expect(toTab.doc.columns[2].frets, isEmpty);
      final back = loopCellsFromTabDocument(toTab.doc);
      expect(back.cells[2].midis, isNull);
    });

    test('a chord in a tab column becomes one multi-pitch loop cell', () {
      final doc = TabDocument(
        tuning: Tuning.standardGuitar,
        columns: const [
          TabColumn(frets: {0: 0, 1: 1, 2: 0}, duration: NoteDuration.quarter),
        ],
      );
      final back = loopCellsFromTabDocument(doc);
      expect(back.cells.single.midis, hasLength(3));
      // Sorted low to high, so a caller can rely on the order.
      final midis = back.cells.single.midis!;
      expect(midis, orderedEquals([...midis]..sort()));
    });

    test('a tab that does not fill whole bars says so', () {
      final doc = TabDocument(
        tuning: Tuning.standardGuitar,
        columns: const [
          TabColumn(frets: {5: 3}, duration: NoteDuration.quarter),
        ],
      );
      final back = loopCellsFromTabDocument(doc);
      expect(
        back.report.approximated.any((s) => s.contains('whole bars')),
        isTrue,
      );
    });

    test('an empty loop track converts to an empty tab without throwing', () {
      final out = tabDocumentFromLoopCells(const [], Tuning.standardGuitar);
      expect(out.doc.columns, isEmpty);
      expect(out.report.lossless, isTrue);
    });
  });

  group('C3 — the conversion matrix', () {
    test('all 25 pairs either convert or explain themselves, and none throw',
        () {
      for (final from in AppMode.values) {
        for (final to in AppMode.values) {
          final result = ProjectBridge.convert(
            from: from,
            to: to,
            document: _documentFor(from),
          );
          if (result.isUnsupported) {
            expect(
              result.unsupportedReason,
              isNotEmpty,
              reason: '$from -> $to gave no reason',
            );
            expect(result.document, isNull, reason: '$from -> $to');
          } else {
            expect(
              result.document,
              isNotNull,
              reason: '$from -> $to claimed success with no document',
            );
          }
        }
      }
    });

    test('an identity conversion returns the same document, losslessly', () {
      for (final mode in AppMode.values) {
        final document = _documentFor(mode);
        final result = ProjectBridge.convert(
          from: mode,
          to: mode,
          document: document,
        );
        expect(result.document, same(document), reason: '$mode');
        expect(result.lossless, isTrue, reason: '$mode');
      }
    });

    test('every supported lossy edge NAMES what it costs', () {
      // A conversion that silently drops fingering or velocity is worse than
      // one that refuses — the user only finds out later.
      for (final from in AppMode.values) {
        if (from == AppMode.audio) continue;
        for (final to in AppMode.values) {
          if (to == from || to == AppMode.audio) continue;
          final result = ProjectBridge.convert(
            from: from,
            to: to,
            document: _documentFor(from),
          );
          if (result.isUnsupported || result.lossless) continue;
          expect(
            [...result.report.lost, ...result.report.approximated],
            isNotEmpty,
            reason: '$from -> $to is lossy but says nothing',
          );
        }
      }
    });

    test('the document type matches the TARGET mode', () {
      final expected = <AppMode, Matcher>{
        AppMode.tracker: isA<TrackerSong>(),
        AppMode.tab: isA<TabDocument>(),
        AppMode.score: isA<MultiPartScore>(),
        AppMode.loop: isA<List<PatternCell>>(),
      };
      for (final from in expected.keys) {
        for (final to in expected.keys) {
          if (from == to) continue;
          final result = ProjectBridge.convert(
            from: from,
            to: to,
            document: _documentFor(from),
          );
          if (result.isUnsupported) continue;
          expect(result.document, expected[to], reason: '$from -> $to');
        }
      }
    });

    test('Audio is one-way on purpose', () {
      // Everything can bounce out; coming back is transcription, which is a
      // guess from a waveform and should not masquerade as a peer route.
      for (final mode in AppMode.values) {
        if (mode == AppMode.audio) continue;
        expect(ProjectBridge.canConvert(mode, AppMode.audio), isTrue);
        expect(ProjectBridge.canConvert(AppMode.audio, mode), isFalse);
      }
      final back = ProjectBridge.convert(
        from: AppMode.audio,
        to: AppMode.tab,
        document: const <int>[],
      );
      expect(back.isUnsupported, isTrue);
      expect(back.unsupportedReason, contains('Transcribe'));
    });

    test('targetsFrom lists exactly the reachable modes', () {
      for (final from in AppMode.values) {
        final targets = ProjectBridge.targetsFrom(from);
        expect(targets, isNot(contains(from)));
        for (final to in AppMode.values) {
          if (to == from) continue;
          expect(
            targets.contains(to),
            ProjectBridge.canConvert(from, to),
            reason: '$from -> $to',
          );
        }
      }
    });

    test('every edge has a one-line description for a menu subtitle', () {
      for (final from in AppMode.values) {
        for (final to in AppMode.values) {
          expect(
            ProjectBridge.describeEdge(from, to),
            isNotEmpty,
            reason: '$from -> $to has no description',
          );
        }
      }
    });

    test('a wrong document type is reported, not thrown', () {
      // A programming error must not crash a menu action mid-tap.
      final result = ProjectBridge.convert(
        from: AppMode.tab,
        to: AppMode.tracker,
        document: 'not a tab',
      );
      expect(result.isUnsupported, isTrue);
      expect(result.unsupportedReason, contains('TabDocument'));
      expect(result.unsupportedReason, contains('String'));
    });

    test('a bare Score is accepted where a MultiPartScore is expected', () {
      final result = ProjectBridge.convert(
        from: AppMode.score,
        to: AppMode.tab,
        document: _tab().toScore(),
      );
      expect(result.isUnsupported, isFalse);
      expect(result.document, isA<TabDocument>());
    });
  });

  group('C3 — routing keeps what the direct converters keep', () {
    test('tab -> tracker still puts one channel per string', () {
      final result = ProjectBridge.convert(
        from: AppMode.tab,
        to: AppMode.tracker,
        document: _tab(),
      );
      final song = result.document! as TrackerSong;
      expect(song.channels, hasLength(6));
      expect(song.channels[5].cells[0].midi, 43); // low E, fret 3
    });

    test('tab -> tracker -> tab round-trips through the bridge', () {
      final doc = _tab();
      final out = ProjectBridge.convert(
        from: AppMode.tab,
        to: AppMode.tracker,
        document: doc,
      );
      final back = ProjectBridge.convert(
        from: AppMode.tracker,
        to: AppMode.tab,
        document: out.document!,
        annotations: out.annotations,
      );
      final recovered = back.document! as TabDocument;
      expect(recovered.columns, hasLength(doc.columns.length));
      for (var i = 0; i < doc.columns.length; i++) {
        expect(recovered.columns[i].frets, doc.columns[i].frets);
        expect(recovered.columns[i].duration, doc.columns[i].duration);
      }
    });

    test('a composed route reports BOTH converters findings', () {
      // loop -> tracker goes via tab; the second leg's losses must not be
      // dropped just because it ran last.
      final result = ProjectBridge.convert(
        from: AppMode.loop,
        to: AppMode.tracker,
        document: _loopTrack(),
      );
      expect(result.isUnsupported, isFalse);
      expect(
        result.report.lost.any((s) => s.contains('velocity')),
        isTrue,
        reason: 'the loop -> tab leg lost velocity and did not say so',
      );
    });

    test('a side-car from a composed route is merged, not replaced', () {
      final result = ProjectBridge.convert(
        from: AppMode.loop,
        to: AppMode.tracker,
        document: _loopTrack(),
      );
      // The loop -> tab leg recorded velocity; the tab -> tracker leg recorded
      // durations. Both must be present.
      expect(result.annotations.isNotEmpty, isTrue);
      final hasVelocity = result.annotations.events.values
          .any((m) => m.containsKey(AnnotationKeys.velocity));
      final hasDuration = result.annotations.events.values
          .any((m) => m.containsKey(AnnotationKeys.duration));
      expect(hasVelocity, isTrue, reason: 'the first leg was overwritten');
      expect(hasDuration, isTrue, reason: 'the second leg was dropped');
    });
  });
}
