// test/highway_instrument_test.dart
//
// Instrument preparation — the step that turns pitch into *how you play it*.
// A guitar chart must come out with a string and a fret per note that really
// do sound that pitch on that tuning, and a cello chart with a string and a
// finger; a piano chart must come out untouched.

import 'package:comet_beat/core/games/highway/highway_chart.dart';
import 'package:comet_beat/core/games/highway/highway_instrument.dart';
import 'package:comet_beat/core/games/highway/highway_lanes.dart';
import 'package:comet_beat/core/games/highway/highway_library.dart';
import 'package:flutter_test/flutter_test.dart';

const _riff = HighwayChart(
  name: 'riff',
  bpm: 90,
  events: [
    HighwayEvent(startBeat: 0, beats: 1, midi: 40), // E2, open low E
    HighwayEvent(startBeat: 1, beats: 1, midi: 55), // G3
    HighwayEvent(startBeat: 2, beats: 1, midi: 64), // E4
  ],
);

void main() {
  group('guitar', () {
    final profile = HighwayInstrumentProfile.of(HighwayInstrument.guitar);

    test('every note gets a string and a fret that really sound it', () {
      final prepared = profile.prepare(_riff);
      expect(prepared.events.length, _riff.events.length);
      for (final e in prepared.events) {
        expect(e.lane, isNotNull, reason: 'no string for ${e.midi}');
        expect(e.caption, isNotNull);
        final open = profile.tuning!.strings[e.lane!].midiNumber;
        final fret = int.parse(e.caption!);
        expect(open + fret, e.midi, reason: 'string+fret must sound the pitch');
        expect(fret, inInclusiveRange(0, profile.maxFret));
      }
    });

    test('an open string is fret 0, not a stopped note somewhere else', () {
      final prepared = profile.prepare(_riff);
      final lowE = prepared.events.firstWhere((e) => e.midi == 40);
      expect(lowE.caption, '0');
      expect(lowE.lane, 5); // the bottom string of the tuning
    });

    test('the timing and the pitches survive the arrangement untouched', () {
      final prepared = profile.prepare(_riff);
      expect(
        prepared.events.map((e) => (e.startBeat, e.midi)),
        _riff.events.map((e) => (e.startBeat, e.midi)),
      );
      expect(prepared.bpm, _riff.bpm);
    });

    test('a chord keeps one note per string', () {
      const chord = HighwayChart(
        name: 'Em',
        bpm: 90,
        events: [
          HighwayEvent(startBeat: 0, beats: 1, midi: 40),
          HighwayEvent(startBeat: 0, beats: 1, midi: 47),
          HighwayEvent(startBeat: 0, beats: 1, midi: 52),
          HighwayEvent(startBeat: 0, beats: 1, midi: 55),
          HighwayEvent(startBeat: 0, beats: 1, midi: 59),
          HighwayEvent(startBeat: 0, beats: 1, midi: 64),
        ],
      );
      final prepared = profile.prepare(chord);
      final lanes = prepared.events.map((e) => e.lane).toSet();
      expect(lanes.length, 6, reason: 'six notes must use six strings');
    });

    test('a strummed chord is tagged as one, with the hand direction', () {
      // Four beats of the same open chord: down on the beat, up off it — the
      // alternation is half of learning a strumming pattern, so it is DATA,
      // not something the view invents.
      const strummed = HighwayChart(
        name: 'strum',
        bpm: 90,
        events: [
          HighwayEvent(startBeat: 0, beats: 0.9, midi: 40),
          HighwayEvent(startBeat: 0, beats: 0.9, midi: 47),
          HighwayEvent(startBeat: 0, beats: 0.9, midi: 52),
          HighwayEvent(startBeat: 0.5, beats: 0.4, midi: 40),
          HighwayEvent(startBeat: 0.5, beats: 0.4, midi: 47),
          HighwayEvent(startBeat: 0.5, beats: 0.4, midi: 52),
        ],
      );
      final prepared = profile.prepare(strummed);
      final onBeat =
          prepared.events.where((e) => e.startBeat == 0).map((e) => e.strum);
      final offBeat =
          prepared.events.where((e) => e.startBeat == 0.5).map((e) => e.strum);
      expect(onBeat, everyElement(HighwayStrum.down));
      expect(offBeat, everyElement(HighwayStrum.up));
    });

    test('two notes together are a double stop, not a strum', () {
      const dyad = HighwayChart(
        name: 'dyad',
        bpm: 90,
        events: [
          HighwayEvent(startBeat: 0, beats: 1, midi: 52),
          HighwayEvent(startBeat: 0, beats: 1, midi: 59),
        ],
      );
      expect(
        profile.prepare(dyad).events.map((e) => e.strum),
        everyElement(HighwayStrum.none),
        reason: 'an arrow over every two-note shape would be noise',
      );
    });

    test('a pitch the instrument cannot reach keeps its note but gets no lane',
        () {
      const tooLow = HighwayChart(
        name: 'low',
        bpm: 90,
        events: [HighwayEvent(startBeat: 0, beats: 1, midi: 24)],
      );
      final prepared = profile.prepare(tooLow);
      expect(prepared.events.single.midi, 24);
      expect(prepared.events.single.lane, isNull);
      // …and the lane map then simply does not draw it.
      expect(
        StringLaneMap(profile.tuning!).slotFor(prepared.events.single),
        isNull,
      );
    });
  });

  group('cello', () {
    final profile = HighwayInstrumentProfile.of(HighwayInstrument.cello);

    test('notes get a string and a finger, not a fret', () {
      const walk = HighwayChart(
        name: 'walk',
        bpm: 60,
        events: [
          HighwayEvent(startBeat: 0, beats: 1, midi: 50), // D3, open D
          HighwayEvent(startBeat: 1, beats: 1, midi: 52), // E3
          HighwayEvent(startBeat: 2, beats: 1, midi: 55), // G3
        ],
      );
      final prepared = profile.prepare(walk);
      expect(profile.captionStyle, HighwayCaptionStyle.finger);
      for (final e in prepared.events) {
        expect(e.lane, isNotNull);
        final finger = int.parse(e.caption!);
        expect(finger, inInclusiveRange(0, 4));
      }
      final openD = prepared.events.firstWhere((e) => e.midi == 50);
      expect(openD.caption, '0', reason: 'an open string needs no finger');
    });
  });

  group('piano and pads', () {
    test('need no preparation at all — the pitch IS the position', () {
      final piano = HighwayInstrumentProfile.of(HighwayInstrument.piano);
      final prepared = piano.prepare(_riff);
      expect(prepared.events, same(_riff.events));
      expect(piano.laneMapFor(prepared), isA<KeyboardLaneMap>());
    });

    test('the pad map is chosen for the pads instrument', () {
      final pads = HighwayInstrumentProfile.of(HighwayInstrument.pads);
      expect(pads.laneMapFor(_riff), isA<PadLaneMap>());
    });
  });

  group('voices', () {
    test('each instrument has its own timbre — a guitar is not a piano', () {
      final piano = HighwayInstrumentProfile.of(HighwayInstrument.piano);
      final guitar = HighwayInstrumentProfile.of(HighwayInstrument.guitar);
      final cello = HighwayInstrumentProfile.of(HighwayInstrument.cello);
      expect(guitar.timbre.decay, greaterThan(piano.timbre.decay));
      expect(cello.timbre.attackMs, greaterThan(guitar.timbre.attackMs));
    });
  });

  group('the built-in library', () {
    test('every piece prepares cleanly on every instrument it claims', () {
      for (final piece in HighwayLibrary.pieces) {
        for (final instrument in piece.instruments) {
          final profile = HighwayInstrumentProfile.of(instrument);
          final prepared = profile.prepare(piece.chart);
          expect(
            prepared.events.length,
            piece.chart.events.length,
            reason: '${piece.id} on $instrument lost notes',
          );
          // Every note must be drawable, or the piece is not really playable.
          final map = profile.laneMapFor(prepared);
          for (final e in prepared.events) {
            expect(
              map.slotFor(e),
              isNotNull,
              reason: '${piece.id}: ${e.midi} is unreachable on $instrument',
            );
          }
        }
      }
    });

    test('each instrument has something to play', () {
      for (final instrument in HighwayInstrument.values) {
        expect(
          HighwayLibrary.forInstrument(instrument),
          isNotEmpty,
          reason: 'nothing to play on $instrument',
        );
      }
    });
  });
}
