// Voice Lab — the transform chain (pure) + the screen driving it via an
// injected clip (no microphone).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/voice_fx.dart';
import 'package:comet_beat/features/sound_lab/voice_lab_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

Float64List _tone(int n) => Float64List.fromList([
      for (var i = 0; i < n; i++) 0.5 * math.sin(2 * math.pi * 220 * i / 44100),
    ]);

VoiceLabTester _lab(WidgetTester tester) =>
    tester.state<State<VoiceLabScreen>>(find.byType(VoiceLabScreen))
        as VoiceLabTester;

void main() {
  group('voiceLabProcess', () {
    final clip = _tone(8820); // 0.2 s

    test('a no-op chain returns audio of the same length', () {
      final out = voiceLabProcess(clip);
      expect(out.length, clip.length);
    });

    test('speed (time-stretch) changes the length', () {
      final slower = voiceLabProcess(clip, speed: 1.5);
      expect(slower.length, greaterThan(clip.length));
      final faster = voiceLabProcess(clip, speed: 0.5);
      expect(faster.length, lessThan(clip.length));
    });

    test('a character preset changes the samples', () {
      final robot = voiceLabProcess(clip, effect: VoiceEffect.robot);
      expect(robot, isNot(clip));
    });

    test('empty clip stays empty', () {
      expect(voiceLabProcess(Float64List(0), reverb: 0.5), isEmpty);
    });

    test('tremolo is an identity at depth 0', () {
      expect(tremoloFx(clip, 0), same(clip));
    });
  });

  testWidgets('screen processes an injected clip and reacts to controls',
      (tester) async {
    await pumpGame(tester, const VoiceLabScreen());
    final lab = _lab(tester);

    expect(lab.output, isNull); // no clip yet
    lab.debugSetClip(_tone(4410));
    await tester.pump();
    expect(lab.output, isNotEmpty);

    lab.setEffect(VoiceEffect.chipmunk);
    await tester.pump();
    expect(lab.effect, VoiceEffect.chipmunk);

    final before = lab.output!.length;
    lab.setParam('speed', 1.5);
    await tester.pump();
    expect(lab.output!.length, greaterThan(before)); // slower = longer
  });
}
