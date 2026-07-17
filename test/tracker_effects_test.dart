// Per-note effect DSP — the contract/spec for renderNoteWithEffect. Pure Dart;
// the effects agent implements tracker_effects.dart to make these pass.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/core/audio/tracker_effects.dart';
import 'package:flutter_test/flutter_test.dart';

double _peak(Float64List b) {
  var p = 0.0;
  for (final v in b) {
    if (v.abs() > p) p = v.abs();
  }
  return p;
}

bool _finite(Float64List b) => b.every((v) => v.isFinite);
bool _same(Float64List a, Float64List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  const ms = 400;
  const expectedLen = (ms * kSampleRate) ~/ 1000;

  test('a plain note is audible and correctly sized', () {
    final b = renderNoteWithEffect(60, ms, TrackerEffect.none);
    expect(b.length, expectedLen);
    expect(_finite(b), isTrue);
    expect(_peak(b), greaterThan(0.0));
  });

  test('every effect yields finite, audible output of the right length', () {
    for (final fx in TrackerEffect.values) {
      final b = renderNoteWithEffect(60, ms, fx);
      expect(b.length, expectedLen, reason: '$fx length');
      expect(_finite(b), isTrue, reason: '$fx finite');
      expect(_peak(b), greaterThan(0.0), reason: '$fx silent');
    }
  });

  test('each modulation actually changes the waveform vs. a plain note', () {
    final plain = renderNoteWithEffect(60, ms, TrackerEffect.none);
    for (final fx in [
      TrackerEffect.arpeggio,
      TrackerEffect.vibrato,
      TrackerEffect.slideUp,
      TrackerEffect.slideDown,
    ]) {
      expect(
        _same(renderNoteWithEffect(60, ms, fx), plain),
        isFalse,
        reason: '$fx should differ from none',
      );
    }
  });

  test('slide up and slide down differ from each other', () {
    final up = renderNoteWithEffect(60, ms, TrackerEffect.slideUp);
    final down = renderNoteWithEffect(60, ms, TrackerEffect.slideDown);
    expect(_same(up, down), isFalse);
  });

  test('honours a supplied timbre', () {
    final piano = renderNoteWithEffect(
      60,
      ms,
      TrackerEffect.vibrato,
      timbre: timbreFor(Instrument.piano),
    );
    final cello = renderNoteWithEffect(
      60,
      ms,
      TrackerEffect.vibrato,
      timbre: timbreFor(Instrument.cello),
    );
    expect(_same(piano, cello), isFalse);
  });
}
