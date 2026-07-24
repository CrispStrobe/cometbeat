import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/core/audio/tracker_song_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Tracker Semantics and Codec', () {
    test('TrackerCell.noteCut round trips through JSON codec', () {
      final song = TrackerSong();

      song.engine.setCell(0, 0, const TrackerCell(midi: 60));
      song.engine.setCell(0, 1, TrackerCell.noteCut);

      final json = trackerSongToJson(song);
      final decoded = trackerSongFromJson(json);

      expect(decoded.engine.channels[0].cells[0].midi, 60);
      expect(decoded.engine.channels[0].cells[1].isNoteCut, isTrue);
      expect(decoded.engine.channels[0].cells[1].midi, isNull);
    });
  });
}
