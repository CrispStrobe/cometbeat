import 'package:comet_beat/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('app boots and shows the module grid', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const CometBeatApp());
    await tester.pumpAndSettle();

    expect(find.text('CometBeat'), findsOneWidget);
    // English is the test default locale; two modules start unlocked.
    expect(find.text('Note Values'), findsOneWidget);
    expect(find.text('Reading Notes'), findsOneWidget);
    expect(find.text('Harmony'), findsOneWidget);
  });
}
