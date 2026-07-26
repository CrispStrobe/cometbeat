// The retained-scan store: save/load/delete a photo by song id, and make sure a
// hostile id can't write outside the store dir. Native (dart:io) only — the web
// stub keeps nothing, which the app relies on to hide the re-run button.
import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/features/games/songs/import/omr_source_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('omr_src_test');
    debugOmrSourcesDirOverride = () => tmp.path;
  });

  tearDown(() {
    debugOmrSourcesDirOverride = null;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('saves, loads and deletes a retained scan by song id', () async {
    final bytes = Uint8List.fromList(List.generate(64, (i) => i));
    expect(await loadOmrSource('song1'), isNull); // nothing yet
    expect(await saveOmrSource('song1', bytes), isTrue);
    expect(await loadOmrSource('song1'), bytes);
    await deleteOmrSource('song1');
    expect(await loadOmrSource('song1'), isNull);
  });

  test('a hostile id is sanitised and cannot escape the store dir', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    await saveOmrSource('../evil', bytes);
    // No file appeared next to the store dir.
    expect(File('${tmp.parent.path}/evil').existsSync(), isFalse);
    // ...and it still round-trips under its sanitised name.
    expect(await loadOmrSource('../evil'), bytes);
  });

  test('a zero-length file reads back as absent', () async {
    await saveOmrSource('empty', Uint8List(0));
    expect(await loadOmrSource('empty'), isNull);
  });
}
