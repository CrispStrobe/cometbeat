// Repeatable native profile workloads, not a debug timing benchmark.
import 'dart:async';
import 'dart:io';

import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/transport_service.dart';
import 'package:comet_beat/features/games/composition/advanced_tracker_screen.dart';
import 'package:comet_beat/features/games/composition/daw_screen.dart';
import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:comet_beat/features/games/tutorial_gate.dart';
import 'package:comet_beat/features/home/screens/home_screen.dart';
import 'package:comet_beat/features/workshop/screens/composition_workshop_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/main.dart' as app;
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/composition_profiler.dart';

Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'profile four composition editors',
    (tester) async {
      final profiler = CompositionProfiler();
      final failures = <String>[];
      final audioWarnings = <String>[];
      final originalPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null &&
            (message.contains('unavailable') ||
                message.contains('Exception'))) {
          audioWarnings.add(message);
        }
        originalPrint(message, wrapWidth: wrapWidth);
      };
      addTearDown(() => debugPrint = originalPrint);
      SharedPreferences.setMockInitialValues({});
      autoShowTutorials = false;
      await app.main();
      await _wait(2000);
      final home = tester.element(find.byType(HomeScreen));
      await home.read<SettingsService>().setLocale(const Locale('en'));
      final transport = home.read<TransportService>();
      final navigator = Navigator.of(home);
      final metadata = <String, Object?>{
        'mode': kProfileMode ? 'profile' : 'NOT_PROFILE',
        'os': Platform.operatingSystemVersion,
        'dart': Platform.version,
        'pid': pid,
        'revision': const String.fromEnvironment('PROFILE_REVISION'),
        'run_id': const String.fromEnvironment('PROFILE_RUN_ID'),
        'contention':
            'Exploratory; other agents/tests may be active. Rerun uncontended before comparison.',
        'frame_policy': 'fullyLive; real wall-clock waits, no synthetic ticks',
        'view_physical_size': tester.view.physicalSize.toString(),
        'device_pixel_ratio': tester.view.devicePixelRatio,
        'cpu_source':
            'Darwin clock(3) process CPU, all threads; CLOCKS_PER_SEC=1000000',
        'allocation_source':
            'VM getAllocationProfile snapshots outside timing window; no GC/reset',
        'audio':
            'Real plugins, no mocks; transport assertions do not prove speaker output',
        'workloads': {
          'workshop':
              '64 eighth notes, C major ABC, 4/4, quarter=120, synth; normal highlighting transport',
          'daw':
              'Built-in demo beat + demo tune on two tracks; looping enabled',
          'loop_mixer':
              'Default starter groove; drums, bass and chords enabled; no frozen seams',
          'advanced_tracker':
              'Built-in demo song; follow-play and oscilloscope enabled; song playback',
        },
        'phase_definition':
            'idle=2s after setup; start=play plus 2s (render/native startup); playback=6s after startup',
        'failures': failures,
        'audio_warnings': audioWarnings,
      };

      Future<void> workshopToggle() async {
        var button =
            find.byIcon(transport.isPlaying ? Icons.stop : Icons.play_arrow);
        if (button.evaluate().isEmpty) {
          final l10n = AppLocalizations.of(
            tester.element(find.byType(CompositionWorkshopScreen)),
          )!;
          await tester.tap(find.byTooltip(l10n.workshopMoreActions));
          await _wait(400);
          button =
              find.byIcon(transport.isPlaying ? Icons.stop : Icons.play_arrow);
        }
        await tester.ensureVisible(button.first);
        await tester.tap(button.first);
      }

      const selectedEditor = String.fromEnvironment('PROFILE_EDITOR');
      for (final name in [
        'workshop',
        'daw',
        'loop_mixer',
        'advanced_tracker',
      ].where(
        (name) => selectedEditor.isEmpty || name == selectedEditor,
      )) {
        try {
          late Widget screen;
          switch (name) {
            case 'workshop':
              final notes = List.filled(8, 'C D E F G A B c |').join(' ');
              screen = CompositionWorkshopScreen(
                initialScore: multiPartScoreFromAbc(
                  'X:1\nT:Profile fixture\nM:4/4\nL:1/8\nQ:1/4=120\nK:C\n$notes',
                ),
              );
            case 'daw':
              screen = const DawScreen();
            case 'loop_mixer':
              screen = const LoopMixerScreen();
            case 'advanced_tracker':
              screen = const AdvancedTrackerScreen();
          }
          // Route under the REAL app providers, without perturbing the home UI.
          unawaited(
            navigator.push(MaterialPageRoute<void>(builder: (_) => screen)),
          );
          await _wait(1500);
          if (find.byType(BottomSheet).evaluate().isNotEmpty) {
            navigator.pop(); // first-run primer, if this surface opens its own
            await _wait(400);
          }
          late Future<void> Function() start;
          late Future<void> Function() stop;
          late bool Function() playing;
          switch (name) {
            case 'workshop':
              final editor = tester.state<State<CompositionWorkshopScreen>>(
                find.byType(CompositionWorkshopScreen),
              ) as CompositionWorkshopTester;
              expect(editor.noteCount, 64);
              start = workshopToggle;
              stop = workshopToggle;
              playing = () => transport.isPlaying;
            case 'daw':
              final editor = tester
                  .state<State<DawScreen>>(find.byType(DawScreen)) as DawTester;
              editor.clear();
              editor.addDemoBeat();
              editor.addDemoTune();
              expect(editor.clipCount, 2);
              if (!editor.loopOn) editor.toggleLoop();
              start = () async => editor.play();
              stop = () async => editor.stop();
              playing = () => editor.isPlaying;
            case 'loop_mixer':
              final editor = tester.state<State<LoopMixerScreen>>(
                find.byType(LoopMixerScreen),
              ) as LoopMixerTester;
              if (editor.isPlaying) editor.pauseOrResume();
              for (final id in ['drums', 'bass', 'chords']) {
                if (!editor.enabledTracks.contains(id)) editor.toggleTrack(id);
              }
              if (editor.isPlaying) editor.pauseOrResume();
              start = () async => editor.pauseOrResume();
              stop = () async => editor.stopAll();
              playing = () => editor.isPlaying;
            case 'advanced_tracker':
              final editor = tester.state<State<AdvancedTrackerScreen>>(
                find.byType(AdvancedTrackerScreen),
              ) as AdvancedTrackerTester;
              editor.loadDemo();
              editor.setFollowPlay(true);
              if (!editor.showScope) editor.toggleScope();
              expect(editor.noteCount, greaterThan(0));
              start = () async => editor.playSong();
              stop = () async => editor.stop();
              playing = () => editor.isPlaying;
          }
          await _wait(1000);
          await profiler.measure(name, 'idle', () => _wait(2000));
          await profiler.measure(name, 'start', () async {
            await start();
            await _wait(2000);
          });
          expect(playing(), isTrue, reason: '$name did not start');
          final before = transport.positionMs;
          await profiler.measure(name, 'playback', () => _wait(6000));
          expect(playing(), isTrue, reason: '$name stopped during workload');
          expect(
            transport.positionMs,
            isNot(before),
            reason: '$name clock did not advance',
          );
          await stop();
          await _wait(300);
          expect(playing(), isFalse, reason: '$name did not stop');
        } catch (error, stack) {
          failures.add('$name: $error\n$stack');
        } finally {
          await profiler.save(metadata);
          navigator.popUntil((r) => r.isFirst);
          await _wait(600);
        }
      }
      binding.reportData = {
        'profile_artifact': await profiler.save(metadata),
        'failures': failures,
      };
      expect(failures, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
