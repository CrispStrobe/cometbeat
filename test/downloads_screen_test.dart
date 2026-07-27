// DownloadsScreen — the "what's cached on disk" settings screen. Previously
// untested; a smoke test confirms it builds, resolves its scan future and
// renders (list or empty state) without throwing.
import 'package:comet_beat/features/settings/screens/downloads_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('builds and resolves its scan without throwing', (tester) async {
    await pumpGame(tester, const DownloadsScreen());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(DownloadsScreen), findsOneWidget);
  });
}
