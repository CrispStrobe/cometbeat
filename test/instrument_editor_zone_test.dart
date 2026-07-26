// Multi-sample zone editor: velocity-range + non-sample zone replacement.
// The zone-mutation logic is extracted as pure functions (unit-tested here) and
// the editor delegates to them; a widget test drives the real controls.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/envelope.dart';
import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/features/games/composition/instrument_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

SampleInstrument _dc(String id, double v) => SampleInstrument(
      id,
      Float64List(4410)..fillRange(0, 4410, v),
      envelope: Envelope.none,
    );

void main() {
  group('pure zone-mutation helpers', () {
    test('replaceZoneInstrument assigns ANY instrument to a zone', () {
      final base = _dc('base', 1.0);
      const additive = AdditiveInstrument('piano', Instrument.piano);
      final multi = MultiSampleInstrument('m', {60: base, 72: base});

      final updated = replaceZoneInstrument(multi, 60, additive);
      expect(updated.zones[60], same(additive));
      // Untouched zone is preserved.
      expect(updated.zones[72], same(base));
    });

    test('replaceZoneInstrument keeps a matching velocity split coherent', () {
      final base = _dc('base', 1.0);
      const additive = AdditiveInstrument('cello', Instrument.cello);
      final multi = MultiSampleInstrument(
        'm',
        {60: base},
        velocityZones: [
          VelocityZone(note: 60, instrument: base, velHigh: 63),
        ],
      );
      final updated = replaceZoneInstrument(multi, 60, additive);
      expect(updated.velocityZones.single.instrument, same(additive));
    });

    test('setZoneVelocityRange upserts a split and full range clears it', () {
      final base = _dc('base', 1.0);
      final multi = MultiSampleInstrument('m', {60: base});

      final split = setZoneVelocityRange(multi, 60, 0, 63);
      expect(split.velocityZones, hasLength(1));
      expect(split.velocityZones.single.note, 60);
      expect(split.velocityZones.single.velLow, 0);
      expect(split.velocityZones.single.velHigh, 63);
      expect(split.velocityZones.single.instrument, same(base));

      // A full 0..127 range clears the split -> byte-identical to plain zone.
      final cleared = setZoneVelocityRange(split, 60, 0, 127);
      expect(cleared.velocityZones, isEmpty);
    });

    test('zonePickerCandidates dedupes and always offers the built-ins', () {
      final extra = _dc('extra', 1.0);
      final candidates = zonePickerCandidates([extra, extra]);
      final ids = candidates.map((c) => c.id).toList();
      expect(ids.where((id) => id == 'extra'), hasLength(1));
      expect(ids, contains('piano')); // a built-in voice
      // Nested multi-sample instruments are excluded.
      final nested = MultiSampleInstrument('nested', {60: extra});
      expect(
        zonePickerCandidates([nested]).map((c) => c.id),
        isNot(contains('nested')),
      );
    });
  });

  group('editor widget', () {
    testWidgets('replaces a zone with a non-sample instrument via the picker',
        (tester) async {
      const flute = AdditiveInstrument('flute', Instrument.flute);
      const multi = MultiSampleInstrument('m', {60: flute});
      TrackerInstrument? result;

      await pumpGame(
        tester,
        Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                result = await showInstrumentEditor(ctx, multi);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Open the zone-instrument picker and choose the built-in 'piano' voice.
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('piano').last);
      await tester.pumpAndSettle();

      // Close the editor; the returned instrument carries the replacement.
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      final edited = result as MultiSampleInstrument;
      expect(edited.zones[60], isA<AdditiveInstrument>());
      expect((edited.zones[60] as AdditiveInstrument).id, 'piano');
    });

    testWidgets('drags the velocity RangeSlider to create a split',
        (tester) async {
      const flute = AdditiveInstrument('flute', Instrument.flute);
      const multi = MultiSampleInstrument('m', {60: flute});
      TrackerInstrument? result;

      await pumpGame(
        tester,
        Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                result = await showInstrumentEditor(ctx, multi);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(RangeSlider), findsOneWidget);
      // Drag a thumb inward so the window is no longer full 0..127.
      await tester.drag(find.byType(RangeSlider), const Offset(60, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      final edited = result as MultiSampleInstrument;
      expect(
        edited.velocityZones,
        isNotEmpty,
        reason: 'dragging the range off full should author a split',
      );
      expect(edited.velocityZones.first.note, 60);
    });
  });
}
