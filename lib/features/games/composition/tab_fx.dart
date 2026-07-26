// lib/features/games/composition/tab_fx.dart
//
// A6 — the Tab mode's guitar rig.
//
// Tab was the one authoring mode with NO effects at all: it rendered its band
// score with a bare instrument and played it dry, so the mode whose whole
// subject is electric and acoustic guitar was the only one that could not sound
// like one. Everything needed already existed — the shared FX rack (A1), the
// preset chains (A3/A6 in `fx/fx_presets.dart`) — so this file is just the
// wiring: render each audible track, run it through that track's chain, sum.
//
// PER TRACK, not per band, because that is the point: in a two-track tab the
// rhythm guitar wants crunch while the lead wants fuzz and a slapback. The old
// path collapsed every track into one `MultiPartScore` and rendered it in one
// go, which made a per-track chain impossible to express.
//
// Pure Dart — no Flutter, no AudioService — so the whole rig is headless-
// testable and the screen keeps only the "play this buffer" line.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/fx/fx_chain.dart';
import 'package:comet_beat/core/audio/fx/fx_presets.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:comet_beat/core/audio/score_instrument_render.dart'
    show renderMultiPartWithInstrument;
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerInstrument;
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:crisp_notation/crisp_notation.dart' show MultiPartScore;

// The rig's preset names are the shared ones — re-exported so a Tab screen has
// a single import for its effects rather than reaching into the audio layer.
export 'package:comet_beat/core/audio/fx/fx_presets.dart' show GuitarFxPreset;

/// Renders the audible tracks of [tracks] and applies each track's own
/// [TabTrack.fxChain] before summing.
///
/// Byte-identical to the old single-pass render when every chain is empty —
/// that is asserted in `tab_fx_test.dart`, because "adding effects" must not
/// quietly change how an existing tab sounds.
///
/// Muted/soloed handling comes from [audibleTracks], so it matches what the
/// user sees.
Float64List renderTabBandWithFx(
  List<TabTrack> tracks,
  TrackerInstrument instrument, {
  int quarterMs = 500,
  int capo = 0,
  int sampleRate = kSampleRate,
}) {
  final audible = audibleTracks(tracks).toList();
  if (audible.isEmpty) return Float64List(0);

  // Fast path: nothing to process, so render exactly the way it always was.
  if (audible.every((t) => t.fxChain.isEmpty)) {
    return renderMultiPartWithInstrument(
      MultiPartScore([for (final t in audible) t.doc.toScore(capo: capo)]),
      instrument,
      quarterMs: quarterMs,
      sampleRate: sampleRate,
    );
  }

  final rendered = <Float64List>[];
  for (final track in audible) {
    // One track at a time so its chain applies to ITS audio only. Wrapping the
    // single score in a MultiPartScore keeps the exact same render path (and
    // therefore the same timing/voicing) as the fast path above.
    var pcm = renderMultiPartWithInstrument(
      MultiPartScore([track.doc.toScore(capo: capo)]),
      instrument,
      quarterMs: quarterMs,
      sampleRate: sampleRate,
    );
    if (track.fxChain.isNotEmpty) {
      pcm = applyFxChain(pcm, track.fxChain, sampleRate);
    }
    rendered.add(pcm);
  }

  var length = 0;
  for (final pcm in rendered) {
    if (pcm.length > length) length = pcm.length;
  }
  final out = Float64List(length);
  for (final pcm in rendered) {
    for (var i = 0; i < pcm.length; i++) {
      out[i] += pcm[i];
    }
  }
  return out;
}

/// The chain a [preset] resolves to, ready to assign to [TabTrack.fxChain].
///
/// A thin re-export of `fx_presets.dart` so the Tab screen has one import for
/// its rig rather than reaching across into the audio layer's preset table.
List<FxSpec> tabRigChain(GuitarFxPreset preset) => fxForGuitarPreset(preset);

/// A short user-facing name for a rig preset.
String tabRigLabel(GuitarFxPreset preset) => switch (preset) {
      GuitarFxPreset.clean => 'Clean',
      GuitarFxPreset.crunch => 'Crunch',
      GuitarFxPreset.overdrive => 'Overdrive',
      GuitarFxPreset.fuzz => 'Fuzz',
      GuitarFxPreset.chorus => 'Chorus',
      GuitarFxPreset.springReverb => 'Spring reverb',
      GuitarFxPreset.slapback => 'Slapback',
    };
