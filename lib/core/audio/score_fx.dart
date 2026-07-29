// WS-X3 — an effect chain that belongs to a SCORE PART.
//
// Score was the last mode with no effect surface at all: the rack is hosted by
// Loop Studio, the Tracker and the Tab Workshop, and the Audio Editor has its
// own. What made Score different was not the UI — it was that Score had nowhere
// to PUT a chain. A tracker channel and a tab track are app objects with app
// JSON around them; a score part is a `Score` from crisp_notation, and the
// Workshop's only save path is MusicXML text (the Song Book stores the
// document's XML; the project codec wraps that same XML in a JSON envelope). A
// chain kept beside the score would therefore vanish the moment the part was
// saved, exported or copied to another project — the failure that makes a
// setting feel unreliable rather than absent.
//
// So the chain travels IN the part, through `ScoreMetadata.extras`
// (crisp_notation `ee7dbc9`), which MusicXML carries in its own
// `<miscellaneous-field>` slot, scoped per part. This file is the app's side of
// that: the key, the two conversions, and the render that actually applies it.
//
// Pure Dart — no widgets — so both faces (the Workshop rack and
// `bin/rendersong.dart`) sit on the same functions, and the audio can be
// asserted headlessly.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/fx/fx_chain.dart';
import 'package:comet_beat/core/audio/fx/fx_chain_codec.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:comet_beat/core/audio/score_instrument_render.dart';
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
// Like `score_instrument_render.dart`, this imports `crisp_notation_core`
// rather than the Flutter-facing package so `bin/rendersong.dart` can use it
// under plain `dart run`.
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerInstrument;
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show MultiPartScore, Score, ScoreMetadata;

/// The key an effect chain is stored under in [ScoreMetadata.extras].
///
/// Namespaced because extras are shared with every other application that ever
/// writes to the same score — the library asks for exactly this, and a bare
/// `fx` would be a collision waiting to happen.
const String kScoreFxKey = 'cometbeat.fx';

/// The chain string stored on [metadata], or null when the part has none.
String? scoreFxChainString(ScoreMetadata metadata) {
  final raw = metadata.extras[kScoreFxKey];
  return (raw == null || raw.trim().isEmpty) ? null : raw;
}

/// The effect chain stored on [metadata]; empty when the part has none.
///
/// Never throws. The value is text that may have been written by an older build
/// of this app, hand-edited in an XML file, or produced by another program that
/// happened to use the same key — so a chain that does not parse yields
/// whatever DID parse rather than an exception in the middle of a render.
List<FxSpec> scoreFxChain(ScoreMetadata metadata) {
  final source = scoreFxChainString(metadata);
  if (source == null) return const [];
  return parseFxChain(source).chain;
}

/// [metadata] with [chain] stored on it.
///
/// An EMPTY chain removes the key rather than storing an empty string, so a
/// part whose rack was opened and then cleared exports byte-identically to one
/// that never had a rack at all. Otherwise every score anyone glanced at would
/// carry a `<miscellaneous>` block forever.
ScoreMetadata withScoreFxChain(ScoreMetadata metadata, List<FxSpec> chain) {
  final extras = Map<String, String>.from(metadata.extras);
  if (chain.isEmpty) {
    extras.remove(kScoreFxKey);
  } else {
    extras[kScoreFxKey] = formatFxChain(chain);
  }
  return metadata.copyWith(extras: extras);
}

/// Whether storing [chain] on a part would lose anything.
///
/// The chain string has no syntax for per-param AUTOMATION, so a chain carrying
/// any is stored without it. The Workshop's rack cannot create automation, but
/// a chain pasted from the Audio Editor can — and silently dropping it would be
/// the kind of loss you only notice on the next open.
bool scoreFxIsLossless(List<FxSpec> chain) => fxChainStringIsLossless(chain);

/// [pcm] with the part's own chain applied. Returns [pcm] itself when there is
/// no chain, so a score without effects costs nothing.
Float64List applyScoreFx(
  Float64List pcm,
  ScoreMetadata metadata, {
  int sampleRate = kSampleRate,
}) {
  final chain = scoreFxChain(metadata);
  if (chain.isEmpty) return pcm;
  return applyFxChain(pcm, chain, sampleRate);
}

/// Render every part of [mp] through [inst], applying **each part's own** chain
/// before summing.
///
/// This is the whole reason the chain lives on the part rather than on the
/// document: parts are rendered separately and summed
/// ([renderMultiPartWithInstrument] already does), so a per-part chain costs one
/// call in the right place — and a rack that changed nothing when you pressed
/// play would be a control in name only.
Float64List renderMultiPartWithScoreFx(
  MultiPartScore mp,
  TrackerInstrument inst, {
  int quarterMs = 500,
  int sampleRate = kSampleRate,
}) {
  final parts = <Float64List>[
    for (final part in mp.parts)
      applyScoreFx(
        renderScoreWithInstrument(
          part,
          inst,
          quarterMs: quarterMs,
          sampleRate: sampleRate,
        ),
        part.metadata,
        sampleRate: sampleRate,
      ),
  ];
  return _sum(parts);
}

/// Render [score] through [inst] with its own chain applied.
Float64List renderScoreWithScoreFx(
  Score score,
  TrackerInstrument inst, {
  int quarterMs = 500,
  int sampleRate = kSampleRate,
}) =>
    applyScoreFx(
      renderScoreWithInstrument(
        score,
        inst,
        quarterMs: quarterMs,
        sampleRate: sampleRate,
      ),
      score.metadata,
      sampleRate: sampleRate,
    );

/// Sum buffers of differing length into one as long as the longest — parts of a
/// score need not end together.
///
/// ⚠️ Note what this does NOT buy: every effect in `applyFxChain` returns a
/// buffer the same length as its input, so a reverb or delay TAIL is cut at the
/// part's end rather than ringing past it. That is app-wide (the Tracker, Tab
/// and Loop racks share the engine), not a Score-side choice — measured, and
/// pinned in `score_fx_test.dart`.
Float64List _sum(List<Float64List> parts) {
  var len = 0;
  for (final part in parts) {
    if (part.length > len) len = part.length;
  }
  final out = Float64List(len);
  for (final part in parts) {
    for (var i = 0; i < part.length; i++) {
      out[i] += part[i];
    }
  }
  return out;
}
