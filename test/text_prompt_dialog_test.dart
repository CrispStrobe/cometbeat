import 'package:comet_beat/shared/widgets/text_prompt_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shared one-field prompt. The point of it is the controller's lifetime:
/// it must survive the dialog's exit animation (the old per-call-site shape
/// disposed it as the await returned, mid-animation).
void main() {
  Future<Future<String?> Function()> harness(
    WidgetTester tester, {
    bool Function(String)? accept,
  }) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    return () => showTextPrompt(
          ctx,
          title: 'Name',
          initial: 'Groove',
          cancelLabel: 'Cancel',
          confirmLabel: 'Save',
          accept: accept,
          fieldKey: const Key('field'),
        );
  }

  testWidgets('returns what was typed, through the whole exit animation',
      (tester) async {
    final open = await harness(tester);
    String? result;
    final done = open().then((v) => result = v);
    await tester.pumpAndSettle();
    expect(find.text('Groove'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('field')), 'My loop');
    await tester.tap(find.text('Save'));
    // Every exit frame rebuilds the field; none may throw.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await done;
    expect(result, 'My loop');
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel returns null', (tester) async {
    final open = await harness(tester);
    final future = open();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await future, isNull);
  });

  testWidgets('accept keeps the dialog open until it passes', (tester) async {
    final open = await harness(
      tester,
      accept: (t) => int.tryParse(t) != null,
    );
    final future = open();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save')); // "Groove" is not a number
    await tester.pumpAndSettle();
    expect(find.text('Name'), findsOneWidget, reason: 'still open');
    await tester.enterText(find.byKey(const Key('field')), '64');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(await future, '64');
  });
}
