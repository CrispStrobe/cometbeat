// OPL2 / AdLib as a pickable app voice: the kOplPresets patches are exposed as
// InstrumentOptions in kTrackerInstruments (so they appear in the voice picker,
// settings, and as a tab/score voice) and resolve like every other built-in.
//
// Two claims: the presets render audible sound (a real patch, not a blank one),
// and resolveVoiceSync/isBuiltInVoiceId treat them as built-in voices.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/opl_voice.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_instrument_codec.dart';
import 'package:comet_beat/core/audio/voice_options.dart';
import 'package:flutter_test/flutter_test.dart';

const _timing = TrackerTiming(tempoBpm: 60, rows: 4, stepsPerBeat: 1);

List<TrackerCell> _note() => <TrackerCell>[
      const TrackerCell(midi: 60),
      TrackerCell.empty,
      TrackerCell.empty,
      TrackerCell.empty,
    ];

double _rms(Float64List b) {
  var s = 0.0;
  for (final v in b) {
    s += v * v;
  }
  return sqrt(s / b.length);
}

void main() {
  test('every OPL preset is a real (non-blank) patch that renders sound', () {
    expect(kOplPresets, isNotEmpty);
    for (final e in kOplPresets.entries) {
      final inst = OplInstrument(e.key, e.value);
      expect(inst.isBlank, isFalse, reason: '${e.key} is blank');
      final pcm = inst.renderChannel(_note(), _timing);
      expect(_rms(pcm), greaterThan(1e-4), reason: '${e.key} is silent');
    }
  });

  test(
      'OPL presets are exposed in kTrackerInstruments and build an OplInstrument',
      () {
    for (final id in kOplPresets.keys) {
      final option = kTrackerInstruments.where((o) => o.id == id).firstOrNull;
      expect(option, isNotNull, reason: '$id missing from the voice list');
      expect(option!.build(), isA<OplInstrument>());
    }
  });

  test('OPL voices resolve as built-in procedural voices', () {
    for (final id in kOplPresets.keys) {
      expect(isBuiltInVoiceId(id), isTrue, reason: '$id not built-in');
      final resolved = resolveVoiceSync(id);
      expect(resolved.voice, isA<OplInstrument>());
    }
  });

  test('an OPL instrument survives a codec round-trip and renders identically',
      () {
    for (final e in kOplPresets.entries) {
      final original = OplInstrument(e.key, e.value);
      expect(isSerializableInstrument(original), isTrue);
      final twin = instrumentFromJson(instrumentToJson(original));
      expect(twin, isA<OplInstrument>());
      final a = original.renderChannel(_note(), _timing);
      final b = twin.renderChannel(_note(), _timing);
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(b[i], a[i], reason: '${e.key} sample $i');
      }
    }
  });
}
