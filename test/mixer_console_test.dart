// WS-W5 — the mixer console.
//
// The assertion that matters most is not "a slider moves". It is that
// `ProjectTrackMix` is now READ AND WRITTEN by the app at all: level, pan, mute
// and solo existed since WS-W1 and nothing outside `project.dart` and its codec
// ever touched them. This is the screen that makes them real.

import 'package:comet_beat/core/audio/loop_engine.dart' show GrooveSpec;
import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/project/project.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/project_service.dart';
import 'package:comet_beat/features/games/composition/mixer_console_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

MixerConsoleTester _mixer(WidgetTester tester) =>
    tester.state<State<MixerConsoleScreen>>(find.byType(MixerConsoleScreen))
        as MixerConsoleTester;

Future<void> _pump(WidgetTester tester, ProjectService projects) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ProjectService>.value(value: projects),
        Provider<AudioService>(create: (_) => AudioService()),
      ],
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
  group('WS-W5c — Play renders the project, and says what it could not', () {
    testWidgets('playing a loop track produces actual samples', (tester) async {
      // The point of the whole WS-W5 arc: the faders are audible, not
      // decorative. Asserting on the mixdown rather than on the tap is what
      // makes that claim mean something.
      final projects = ProjectService()
        ..addTrack(
          kind: AppMode.loop,
          document: const GrooveSpec(enabled: {'drums'}),
          name: 'Beat',
        );
      await _pump(tester, projects);

      final mix = await _mixer(tester).playMix();
      expect(mix.isSilent, isFalse);
      expect(mix.left.length, mix.right.length);
      expect(mix.skipped, isEmpty);
    });

    testWidgets('the mixer values reach the played mix', (tester) async {
      final projects = ProjectService();
      final id = projects.addTrack(
        kind: AppMode.loop,
        document: const GrooveSpec(enabled: {'drums'}),
      );
      await _pump(tester, projects);
      final loud = await _mixer(tester).playMix();

      // Mute it through the SCREEN, then play again.
      await tester.tap(find.byKey(ValueKey('mixer-mute-$id')));
      await tester.pump();
      final muted = await _mixer(tester).playMix();

      expect(loud.isSilent, isFalse);
      expect(
        muted.isSilent,
        isTrue,
        reason: 'the mute button silenced the mix',
      );
    });

    testWidgets('a track it cannot sound is NAMED, not swallowed', (
      tester,
    ) async {
      // The renderer reports skipped tracks on purpose; a Play button that hid
      // that would leave the user hearing a mix quietly missing a part.
      final projects = ProjectService()
        ..addTrack(
          kind: AppMode.loop,
          document: const GrooveSpec(enabled: {'drums'}),
        )
        ..addTrack(kind: AppMode.tab, document: 'a tab', name: 'Gtr');
      await _pump(tester, projects);

      await _mixer(tester).playMix();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('mixer-skipped')), findsOneWidget);
      expect(find.textContaining('has no sound yet'), findsOneWidget);
      expect(
        find.textContaining('instrument'),
        findsOneWidget,
        reason: 'the REASON is shown, not just a count',
      );
    });

    testWidgets('nothing is reported before Play is pressed', (tester) async {
      final projects = ProjectService()
        ..addTrack(kind: AppMode.tab, document: 'a tab');
      await _pump(tester, projects);
      expect(find.byKey(const ValueKey('mixer-skipped')), findsNothing);
    });

    testWidgets('Play is disabled with no tracks', (tester) async {
      await _pump(tester, ProjectService());
      final button = tester.widget<IconButton>(
        find.byKey(const ValueKey('mixer-play')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('an all-muted project does not enter the playing state', (
      tester,
    ) async {
      final projects = ProjectService()
        ..addTrack(
          kind: AppMode.loop,
          document: const GrooveSpec(enabled: {'drums'}),
          name: 'Beat',
        );
      await _pump(tester, projects);
      final id = projects.tracks.single.id;
      await tester.tap(find.byKey(ValueKey('mixer-mute-$id')));
      await tester.pump();

      final mix = await _mixer(tester).playMix();
      expect(mix.isSilent, isTrue);
      expect(
        _mixer(tester).isPlaying,
        isFalse,
        reason: 'a stop button on a silent mix would be a lie',
      );
    });
  });

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
