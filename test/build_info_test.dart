// BuildInfo: the version label appends the baked-in commit when present, else
// shows the version alone. (Tests run without the --dart-defines, so commit is
// empty — the fallback path.)

import 'package:comet_beat/core/build_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('versionLabel falls back to the bare version without a commit', () {
    // No --dart-define in the test runner → commit is empty.
    expect(BuildInfo.hasCommit, isFalse);
    expect(BuildInfo.versionLabel('1.0.0+3'), '1.0.0+3');
  });
}
