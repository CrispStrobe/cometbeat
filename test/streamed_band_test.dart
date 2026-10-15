import 'package:comet_beat/core/harmony/streamed_band.dart';
import 'package:flutter_test/flutter_test.dart';

/// BB-U3 — the live per-role mix rule.
void main() {
  test('levels pass through; mute silences one role', () {
    final mix = BandRoleMix()..setLevel(BandRole.bass, 0.5);
    expect(mix.volumeOf(BandRole.bass), 0.5);
    expect(mix.volumeOf(BandRole.comp), 1);
    mix.muted.add(BandRole.comp);
    expect(mix.volumeOf(BandRole.comp), 0);
    expect(mix.volumeOf(BandRole.drums), 1);
  });

  test('solo silences the others, and mute still wins on a soloed role', () {
    final mix = BandRoleMix()..soloed.add(BandRole.drums);
    expect(mix.volumeOf(BandRole.drums), 1);
    expect(mix.volumeOf(BandRole.comp), 0);
    expect(mix.volumeOf(BandRole.bass), 0);
    mix.soloed.add(BandRole.bass);
    expect(mix.volumeOf(BandRole.bass), 1);
    mix.muted.add(BandRole.drums);
    expect(mix.volumeOf(BandRole.drums), 0);
  });

  test('levels are clamped to a sane range', () {
    final mix = BandRoleMix()
      ..setLevel(BandRole.comp, 9)
      ..setLevel(BandRole.bass, -1);
    expect(mix.levelOf(BandRole.comp), 2);
    expect(mix.levelOf(BandRole.bass), 0);
  });
}
