// "Open in Tracker" must not change how the groove sounds.
//
// The report was "we open from loop studio a voice for extended editing in
// tracker, it sounds not the same". It was neither a synthesis difference nor an
// approximation: `trackerSongFromMultiPart` hard-coded
// `kTrackerInstruments.first.build()` for every part, so whatever the loop track
// sounded like, it arrived as PIANO.
//
// The reason that is fixable exactly — rather than approximately — is that the
// two engines are not really separate here. The Tracker's `AdditiveInstrument`
// wraps the SAME `Instrument` enum the Loop engine's `MelodicPattern` carries,
// and both reach audio through `timbreFor` + `renderSegmentsRaw`. So the test
// worth writing is not "close enough" but "the same voice came out the other
// side".

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show AdditiveInstrument, kTrackerInstruments;
import 'package:comet_beat/features/games/composition/groove_notation.dart';
import 'package:comet_beat/features/games/composition/multipart_to_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

LoopEngine _engine() {
  final e = LoopEngine(tempoBpm: 120);
  e.enabled
    ..clear()
    ..addAll(['bass', 'melody', 'chords']);
  return e;
}

void main() {
  test('the engine can report the voice a track sounds through', () {
    final e = _engine();
    // Every pitched built-in has one; an unpitched track honestly has none.
    for (final id in ['bass', 'melody', 'chords']) {
      expect(e.instrumentFor(id), isNotNull, reason: '$id has no voice');
    }
    expect(e.instrumentFor('drums'), isNull);
    expect(e.instrumentFor('no-such-track'), isNull);
  });

  test('grooveParts reports which track each part came from', () {
    // Without this the caller has to re-derive the enabled/pitched filter, and
    // any future change to that loop would desync the two silently.
    final parts = grooveParts(_engine(), nameOf: (id) => id);
    expect(parts, isNotNull);
    expect(parts!.trackIds.length, parts.score.parts.length);
    expect(parts.trackIds.length, parts.partNames.length);
    for (final id in parts.trackIds) {
      expect(['bass', 'melody', 'chords'], contains(id));
    }
  });

  test('the loop voice survives the trip into the Tracker', () {
    final e = _engine();
    final parts = grooveParts(e, nameOf: (id) => id)!;
    final voices = [for (final id in parts.trackIds) e.instrumentFor(id)];

    final song = trackerSongFromMultiPart(parts.score, voices: voices);

    expect(song.channels.length, parts.trackIds.length);
    for (var i = 0; i < song.channels.length; i++) {
      final inst = song.channels[i].instrument;
      expect(
        inst,
        isA<AdditiveInstrument>(),
        reason: 'part $i is not an additive voice',
      );
      expect(
        (inst as AdditiveInstrument).instrument,
        voices[i],
        reason: 'part ${parts.trackIds[i]} changed voice on the way over',
      );
    }
  });

  test('a groove using more than one voice does not collapse to one', () {
    // The regression this guards is specifically the flattening: the old code
    // gave EVERY part the same instrument, so a test that only checked "it has
    // an instrument" would have passed throughout the bug.
    final e = _engine();
    final parts = grooveParts(e, nameOf: (id) => id)!;
    final voices = [for (final id in parts.trackIds) e.instrumentFor(id)];
    final distinct = voices.whereType<Instrument>().toSet();
    expect(
      distinct.length,
      greaterThan(1),
      reason: 'precondition: the default band uses more than one voice',
    );

    final song = trackerSongFromMultiPart(parts.score, voices: voices);
    final arrived = {
      for (final c in song.channels)
        if (c.instrument is AdditiveInstrument)
          (c.instrument as AdditiveInstrument).instrument,
    };
    expect(arrived, distinct);
  });

  test('a plain notation import with no voice keeps the old default', () {
    // Notation genuinely carries no synth voice, so that path must be
    // unchanged — this is what keeps score_router / project_bridge intact.
    final parts = grooveParts(_engine(), nameOf: (id) => id)!;
    final song = trackerSongFromMultiPart(parts.score);
    expect(song.channels.first.instrument.id, kTrackerInstruments.first.id);
  });

  test('a short voices list falls back rather than throwing', () {
    // Defensive: the caller builds this list from a parallel walk, and an
    // off-by-one there should degrade to the default voice, not crash the
    // conversion of a user's music.
    final parts = grooveParts(_engine(), nameOf: (id) => id)!;
    final song = trackerSongFromMultiPart(
      parts.score,
      voices: const [Instrument.cello],
    );
    expect(
      (song.channels.first.instrument as AdditiveInstrument).instrument,
      Instrument.cello,
    );
    expect(song.channels.last.instrument.id, kTrackerInstruments.first.id);
  });
}
