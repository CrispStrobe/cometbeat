// WS-W5 — the mixer console.
//
// The assertion that matters most is not "a slider moves". It is that
// `ProjectTrackMix` is now READ AND WRITTEN by the app at all: level, pan, mute
// and solo existed since WS-W1 and nothing outside `project.dart` and its codec
// ever touched them. This is the screen that makes them real.

import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/project/project.dart';
import 'package:comet_beat/core/services/project_service.dart';
import 'package:comet_beat/features/games/composition/mixer_console_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Future<void> _pump(WidgetTester tester, ProjectService projects) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<ProjectService>.value(
      value: projects,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MixerConsoleScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an empty project explains itself instead of showing nothing', (
    tester,
  ) async {
    await _pump(tester, ProjectService());
    expect(find.textContaining('No tracks yet'), findsOneWidget);
  });

  testWidgets('one strip per track, whatever KIND it is', (tester) async {
    // The point of a workstation mixer: a tracker pattern, a loop and a tab sit
    // side by side, because the mix belongs to the project rather than to
    // whichever editor made the track.
    final projects = ProjectService();
    final a = projects.addTrack(
      kind: AppMode.tracker,
      document: null,
      name: 'Drums',
    );
    final b = projects.addTrack(
      kind: AppMode.loop,
      document: null,
      name: 'Bass',
    );
    final c = projects.addTrack(kind: AppMode.tab, document: null, name: 'Gtr');
    await _pump(tester, projects);

    for (final id in [a, b, c]) {
      expect(find.byKey(ValueKey('mixer-strip-$id')), findsOneWidget);
    }
    expect(find.text('Drums'), findsOneWidget);
    expect(find.text('Tracker'), findsOneWidget);
    expect(find.text('Loop Studio'), findsOneWidget);
    expect(find.text('Tab'), findsOneWidget);
  });

  testWidgets('mute and solo write through to the project', (tester) async {
    final projects = ProjectService();
    final id = projects.addTrack(kind: AppMode.loop, document: null);
    await _pump(tester, projects);

    expect(projects.track(id)!.mix.muted, isFalse);
    await tester.tap(find.byKey(ValueKey('mixer-mute-$id')));
    await tester.pump();
    expect(projects.track(id)!.mix.muted, isTrue);

    await tester.tap(find.byKey(ValueKey('mixer-solo-$id')));
    await tester.pump();
    expect(projects.track(id)!.mix.soloed, isTrue);
  });

  testWidgets('more than one track can be soloed at once', (tester) async {
    // Deliberate: `soloed` is per-track and "solo these three" is a real
    // request. Exclusivity would be a data-model decision made for the wrong
    // reason.
    final projects = ProjectService();
    final a = projects.addTrack(kind: AppMode.loop, document: null);
    final b = projects.addTrack(kind: AppMode.loop, document: null);
    await _pump(tester, projects);

    await tester.tap(find.byKey(ValueKey('mixer-solo-$a')));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('mixer-solo-$b')));
    await tester.pump();

    expect(projects.track(a)!.mix.soloed, isTrue);
    expect(projects.track(b)!.mix.soloed, isTrue);
  });

  testWidgets('level and pan write through, and the OTHER value survives', (
    tester,
  ) async {
    // A strip that reset pan every time the fader moved would be worse than no
    // strip at all, and `copyWith` makes that mistake easy.
    final projects = ProjectService();
    final id = projects.addTrack(kind: AppMode.score, document: null);
    projects.updateTrack(
      id,
      projects.track(id)!.copyWith(mix: const ProjectTrackMix(pan: 0.5)),
    );
    await _pump(tester, projects);

    await tester.drag(
      find.byKey(ValueKey('mixer-level-$id')),
      const Offset(-200, 0),
    );
    await tester.pump();

    expect(projects.track(id)!.mix.level, lessThan(1.0));
    expect(
      projects.track(id)!.mix.pan,
      0.5,
      reason: 'moving the fader must not reset the pan',
    );
  });

  testWidgets('the strip follows the project, not its own state', (
    tester,
  ) async {
    // Another surface changing the mix has to show up here; a strip holding
    // local state would silently disagree with the project.
    final projects = ProjectService();
    final id = projects.addTrack(kind: AppMode.tracker, document: null);
    await _pump(tester, projects);

    projects.updateTrack(
      id,
      projects.track(id)!.copyWith(mix: const ProjectTrackMix(muted: true)),
    );
    await tester.pump();

    final button = tester.widget<IconButton>(
      find.byKey(ValueKey('mixer-mute-$id')),
    );
    expect(button.color, isNotNull, reason: 'a muted strip is lit');
  });

  testWidgets('a track added later appears without a rebuild by hand', (
    tester,
  ) async {
    final projects = ProjectService();
    await _pump(tester, projects);
    expect(find.textContaining('No tracks yet'), findsOneWidget);

    final id = projects.addTrack(kind: AppMode.loop, document: null);
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('mixer-strip-$id')), findsOneWidget);
  });
}
