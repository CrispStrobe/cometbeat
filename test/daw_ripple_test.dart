// D1 — ripple delete and insert: editing TIME, not just clips.
//
// The distinction these tests exist to protect is the one between rippling and
// the range verbs that were already there. `silenceRange` cuts audio out and
// leaves a hole, so everything later keeps the time it was recorded at.
// `rippleDelete` removes the time itself, so the arrangement closes up behind
// it. Both are wanted; confusing them silently ruins an arrangement, because
// the damage is a timing shift you notice bars later.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A one-second clip at [startMs] on [track].
void _addClip(DawService daw, int track, double startMs) {
  daw.addClip(
    SampleSource(Float64List(kDawSampleRate)),
    track: track,
  );
  final index = daw.timeline.tracks[track].clips.length - 1;
  daw.moveClip(track, index, startMs);
}

List<double> _starts(DawService daw, int track) =>
    [for (final c in daw.timeline.tracks[track].clips) c.startMs]..sort();

void main() {
  group('ripple delete closes the gap', () {
    test('later clips slide back by exactly what was removed', () {
      final daw = DawService();
      _addClip(daw, 0, 0); // 0 … 1000
      _addClip(daw, 0, 2000); // 2000 … 3000
      _addClip(daw, 0, 4000); // 4000 … 5000

      // Remove 1000 ms of empty time between the first and second clips.
      daw.rippleDelete(1000, 2000);

      expect(_starts(daw, 0), [0, 1000, 3000]);
    });

    test('a clip inside the range is removed, not just moved', () {
      final daw = DawService();
      _addClip(daw, 0, 0);
      _addClip(daw, 0, 2000);
      _addClip(daw, 0, 4000);

      daw.rippleDelete(1900, 3100);

      expect(daw.clipCount, 2);
      expect(_starts(daw, 0), [0, 2800]);
    });

    test('EVERY lane ripples, not just one', () {
      // A ripple on some lanes and not others slides the arrangement out of
      // sync with itself, which is never what anyone means.
      final daw = DawService();
      _addClip(daw, 0, 3000);
      _addClip(daw, 1, 3000);

      daw.rippleDelete(0, 1000);

      expect(_starts(daw, 0), [2000]);
      expect(_starts(daw, 1), [2000]);
    });

    test('it is NOT silenceRange — that one leaves the hole', () {
      // The distinction, asserted side by side so neither can drift into the
      // other.
      final rippled = DawService();
      _addClip(rippled, 0, 0);
      _addClip(rippled, 0, 2000);
      rippled.rippleDelete(1000, 2000);

      final silenced = DawService();
      _addClip(silenced, 0, 0);
      _addClip(silenced, 0, 2000);
      silenced.silenceRange([0], 1000, 2000);

      expect(_starts(rippled, 0), [0, 1000]);
      expect(_starts(silenced, 0), [0, 2000]);
    });

    test('it is undoable', () {
      final daw = DawService();
      _addClip(daw, 0, 0);
      _addClip(daw, 0, 2000);
      daw.rippleDelete(1000, 2000);
      expect(_starts(daw, 0), [0, 1000]);
      daw.undo();
      expect(_starts(daw, 0), [0, 2000]);
    });

    test('a range too short to matter does nothing', () {
      final daw = DawService();
      _addClip(daw, 0, 2000);
      expect(daw.rippleDelete(100, 101), 0);
      expect(_starts(daw, 0), [2000]);
    });
  });

  group('ripple insert opens time', () {
    test('everything from the point onward slides later', () {
      final daw = DawService();
      _addClip(daw, 0, 0);
      _addClip(daw, 0, 2000);

      daw.rippleInsert(2000, 500);

      expect(_starts(daw, 0), [0, 2500]);
    });

    test('a clip straddling the point is SPLIT, not relocated', () {
      // Moving it whole would silently relocate audio the user did not select
      // — the edit would appear to work and be wrong.
      final daw = DawService();
      _addClip(daw, 0, 0); // 0 … 1000

      daw.rippleInsert(500, 1000);

      expect(daw.clipCount, 2);
      final starts = _starts(daw, 0);
      expect(starts.first, 0);
      // The second half moved by the inserted amount.
      expect(starts.last, closeTo(1500, 1));
    });

    test('clips before the point do not move', () {
      final daw = DawService();
      _addClip(daw, 0, 0);
      daw.rippleInsert(5000, 1000);
      expect(_starts(daw, 0), [0]);
    });

    test('insert then delete of the same span is a round trip', () {
      final daw = DawService();
      _addClip(daw, 0, 0);
      _addClip(daw, 0, 3000);

      daw.rippleInsert(2000, 1000);
      expect(_starts(daw, 0), [0, 4000]);
      daw.rippleDelete(2000, 3000);
      expect(_starts(daw, 0), [0, 3000]);
    });

    test('a zero-length insert does nothing', () {
      final daw = DawService();
      _addClip(daw, 0, 1000);
      daw.rippleInsert(0, 0);
      expect(_starts(daw, 0), [1000]);
    });
  });

  group('markers ripple with the music', () {
    test('a marker after the cut moves back with it', () {
      // A marker is a position in TIME. Leaving one pointing at a bar that has
      // moved is worse than not having it.
      final daw = DawService();
      _addClip(daw, 0, 0);
      daw.addMarker(5000, 'chorus');
      daw.rippleDelete(1000, 2000);
      expect(daw.timeline.markers.single.ms, 4000);
      expect(daw.timeline.markers.single.label, 'chorus');
    });

    test('a marker before the cut stays put', () {
      final daw = DawService();
      _addClip(daw, 0, 0);
      daw.addMarker(500, 'intro');
      daw.rippleDelete(1000, 2000);
      expect(daw.timeline.markers.single.ms, 500);
    });

    test('a marker INSIDE the removed range is dropped', () {
      // It pointed at something that no longer exists; sliding it to the seam
      // would invent a cue the user never placed.
      final daw = DawService();
      _addClip(daw, 0, 0);
      daw.addMarker(1500, 'gone');
      daw.addMarker(5000, 'kept');
      daw.rippleDelete(1000, 2000);
      expect(daw.timeline.markers.map((m) => m.label), ['kept']);
    });

    test('an insert pushes later markers along', () {
      final daw = DawService();
      _addClip(daw, 0, 0);
      daw.addMarker(3000, 'drop');
      daw.rippleInsert(2000, 1000);
      expect(daw.timeline.markers.single.ms, 4000);
    });

    test('markers stay sorted after a ripple', () {
      final daw = DawService();
      _addClip(daw, 0, 0);
      daw.addMarker(1000);
      daw.addMarker(6000);
      daw.rippleDelete(4000, 5000);
      final positions = daw.timeline.markers.map((m) => m.ms).toList();
      expect(positions, orderedEquals([...positions]..sort()));
    });
  });
}
