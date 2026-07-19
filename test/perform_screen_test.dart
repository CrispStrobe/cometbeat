// Live Looper "Perform" (S1) — stack/mute/undo/redo layers + a summed mix.

import 'package:comet_beat/features/games/composition/perform_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

PerformTester _perform(WidgetTester tester) =>
    tester.state<State<PerformScreen>>(find.byType(PerformScreen))
        as PerformTester;

Widget _wrap(Widget home) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('de')],
      home: home,
    );

double _peak(List<double> x) =>
    x.fold(0.0, (m, v) => v.abs() > m ? v.abs() : m);

void main() {
  testWidgets('stack layers, mute/undo/redo, and the mix reflects it',
      (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    expect(p.layerCount, 0);
    expect(p.debugMix().every((v) => v == 0), isTrue); // silence when empty

    p.addSeed('beat');
    await tester.pump();
    p.addSeed('bass');
    await tester.pump();
    expect(p.layerCount, 2);
    expect(_peak(p.debugMix()), greaterThan(0.0)); // the jam makes sound

    // Muting a layer changes the mix; unmuting restores it.
    final full = _peak(p.debugMix());
    p.toggleMute(0);
    await tester.pump();
    expect(p.isMuted(0), isTrue);
    final muted = _peak(p.debugMix());
    expect(muted, lessThan(full)); // one layer removed → quieter/different
    p.toggleMute(0);
    await tester.pump();
    expect(p.isMuted(0), isFalse);

    // Undo drops the newest layer; redo brings it back.
    p.undoLayer();
    await tester.pump();
    expect(p.layerCount, 1);
    expect(p.canRedo, isTrue);
    p.redoLayer();
    await tester.pump();
    expect(p.layerCount, 2);

    // Clear wipes everything.
    p.clearAll();
    await tester.pump();
    expect(p.layerCount, 0);
    expect(p.canUndo, isFalse);
  });

  testWidgets('play-in a melody becomes a new layer', (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    p.startPlayIn();
    await tester.pump();
    expect(p.isPlayingIn, isTrue);

    // Tap a little C-major run.
    for (final midi in [60, 64, 67, 72]) {
      p.playInNote(midi);
    }
    p.finishPlayIn();
    await tester.pump();

    expect(p.isPlayingIn, isFalse);
    expect(p.layerCount, 1); // the played melody is now a layer
    expect(p.layerLabel(0), 'melody');
    expect(_peak(p.debugMix()), greaterThan(0.0)); // and it makes sound

    // Cancel discards without adding a layer.
    p.startPlayIn();
    p.playInNote(62);
    p.cancelPlayIn();
    await tester.pump();
    expect(p.layerCount, 1); // still just the first melody
  });

  testWidgets('play/stop toggles and does not crash without audio',
      (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    p.play(); // no layers yet → stays stopped
    expect(p.isPlaying, isFalse);

    p.addSeed('melody');
    await tester.pump();
    p.play();
    expect(p.isPlaying, isTrue);
    p.stop();
    expect(p.isPlaying, isFalse);
  });
}
