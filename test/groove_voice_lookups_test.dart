// grooveStyleById (loop_engine.dart) and the library-voice id helpers
// (voice_options.dart) — pure lookups / string transforms.
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/voice_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('grooveStyleById', () {
    test('finds every registered style by its id', () {
      for (final s in kGrooveStyles) {
        expect(grooveStyleById(s.id).id, s.id);
      }
    });

    test('an unknown id falls back to the first style', () {
      expect(grooveStyleById('__nope__').id, kGrooveStyles.first.id);
    });
  });

  group('library voice id ↔ name', () {
    test('id prefixes the name; name strips the prefix', () {
      expect(libraryVoiceId('Warm Pad'), 'lib:Warm Pad');
      expect(libraryVoiceName('lib:Warm Pad'), 'Warm Pad');
    });

    test('a non-library id has no library name', () {
      expect(libraryVoiceName('piano'), isNull);
    });

    test('round-trips any name, even one that looks prefixed', () {
      for (final n in ['x', 'Warm Pad', 'lib:tricky']) {
        expect(libraryVoiceName(libraryVoiceId(n)), n);
      }
    });
  });
}
