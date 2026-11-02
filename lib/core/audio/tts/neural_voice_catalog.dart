// neural_voice_catalog.dart — the vetted, SMALL neural narration voices the
// app offers, all run by CrispASR (libcrispasr) and fetched from CrispASR's
// published GGUF repos. Pure data, web-safe (no dart:io / ffi).
//
// Selection rules (maintainer, 2026-11):
//   • SMALL first: every Piper voice here is 10–57 MB (one self-contained GGUF,
//     phoneme map embedded). Kokoro is kept as the one LARGE option (~135 MB
//     model + a 0.5 MB voice pack) and is labelled as such.
//   • Licence: commercial-use OK only. CC0 / public domain need nothing; CC-BY
//     4.0 and the M-AILABS (BSD-style) voices need a credit, surfaced via
//     [NeuralVoice.attribution] on the attribution screen. NO non-commercial
//     voices (en_US-lessac — Blizzard research licence — is in CrispASR's
//     registry as the piper default but is deliberately NOT listed here; nor
//     are the CC BY-NC-SA ryan / hfc / pavoque voices). en_US-libritts_r is
//     also left out: its data is CC BY 4.0, but its model card says it was
//     FINE-TUNED FROM lessac, so the weights inherit that research licence.
//   • Must actually RUN on the libcrispasr we ship (0.8.49): thorsten-high,
//     thorsten_emotional and mls (all in cstr/piper-voices-GGUF) fail to load
//     there ("missing tensor flow.flows.*.enc.res_skip_layers") and then
//     CRASH the process natively — a worker isolate cannot contain that — so
//     they are left out until the shipped lib loads them (re-test with
//     test/crispasr_tts_smoke_test.dart before adding any voice).
//   • Sizes + licences verified against the HF file listings and the
//     cstr/piper-voices-GGUF + cstr/kokoro-voices-GGUF model cards.

/// Which CrispASR backend synthesises a voice.
enum NeuralVoiceEngine {
  /// Piper VITS (`--backend piper`), one GGUF per voice, 22.05 kHz.
  piper,

  /// Kokoro-82M (`--backend kokoro`): shared model GGUF + per-voice pack.
  kokoro,
}

/// A downloadable file of a voice (the model GGUF, or a Kokoro voice pack).
class NeuralVoiceFile {
  const NeuralVoiceFile({
    required this.filename,
    required this.url,
    required this.bytes,
  });

  /// File name inside CrispASR's cache dir (also the registry key).
  final String filename;

  /// Published download URL (CrispASR's HF repos).
  final String url;

  /// Exact size in bytes as published (used for the UI and to verify a
  /// download completed).
  final int bytes;
}

/// One selectable neural narration voice.
class NeuralVoice {
  const NeuralVoice({
    required this.id,
    required this.engine,
    required this.lang,
    required this.name,
    required this.license,
    required this.model,
    this.voicePack,
    this.attribution,
    this.region,
    this.female,
    this.speakerId,
  });

  /// Stable id (persisted in prefs) — never rename.
  final String id;
  final NeuralVoiceEngine engine;

  /// Base language: `de` or `en`.
  final String lang;

  /// Display name (a proper name, not translated).
  final String name;

  /// e.g. `GB`/`US` for English voices; null when not meaningful.
  final String? region;

  /// Voice gender if known (for a hint in the picker).
  final bool? female;

  /// Piper multi-speaker voices: which speaker to use (null = model default).
  final int? speakerId;

  /// Short licence label shown in the picker (SPDX-ish).
  final String license;

  /// Required credit line, or null when none is required (CC0 / PD).
  final String? attribution;

  /// The model GGUF (Piper: the whole voice; Kokoro: the shared backbone).
  final NeuralVoiceFile model;

  /// Kokoro only: the per-speaker voice pack.
  final NeuralVoiceFile? voicePack;

  /// All files this voice needs.
  List<NeuralVoiceFile> get files => [model, if (voicePack != null) voicePack!];

  /// Total download size.
  int get totalBytes => files.fold(0, (s, f) => s + f.bytes);

  /// "Large" = over the small-model budget (~70 MB).
  bool get isLarge => totalBytes > 70 * 1024 * 1024;
}

const _piperRepo = 'https://huggingface.co/cstr/piper-voices-GGUF/resolve/main';
const _kokoroModelRepo =
    'https://huggingface.co/cstr/kokoro-82m-GGUF/resolve/main';
const _kokoroVoiceRepo =
    'https://huggingface.co/cstr/kokoro-voices-GGUF/resolve/main';

NeuralVoiceFile _piper(String stem, int bytes) => NeuralVoiceFile(
      filename: 'piper-$stem-f16.gguf',
      url: '$_piperRepo/piper-$stem-f16.gguf',
      bytes: bytes,
    );

// Verified (Wayback copy of caito.de, the dataset's home): "Redistribution
// and use in any form, including any commercial use, … permitted provided …
// [redistributions] retain the above copyright notice"; no endorsement.
const _mailabs = 'trained on the M-AILABS Speech Dataset — Copyright (c) '
    '2017-2019 by the original creators @ M-AILABS.';

/// The catalog, in picker order (per language: best small voice first).
final List<NeuralVoice> kNeuralVoices = [
  // ── German ────────────────────────────────────────────────────────────────
  NeuralVoice(
    id: 'piper-de-thorsten-medium',
    engine: NeuralVoiceEngine.piper,
    lang: 'de',
    name: 'Thorsten',
    female: false,
    license: 'CC0',
    model: _piper('de_DE-thorsten-medium', 31418848),
  ),
  NeuralVoice(
    id: 'piper-de-kerstin-low',
    engine: NeuralVoiceEngine.piper,
    lang: 'de',
    name: 'Kerstin',
    female: true,
    license: 'CC0',
    model: _piper('de_DE-kerstin-low', 31370176),
  ),
  NeuralVoice(
    id: 'piper-de-eva_k-x_low',
    engine: NeuralVoiceEngine.piper,
    lang: 'de',
    name: 'Eva',
    female: true,
    license: 'BSD-style (M-AILABS)',
    attribution: 'Piper voice “eva_k” (de) — $_mailabs',
    model: _piper('de_DE-eva_k-x_low', 10089664),
  ),
  NeuralVoice(
    id: 'piper-de-ramona-low',
    engine: NeuralVoiceEngine.piper,
    lang: 'de',
    name: 'Ramona',
    female: true,
    license: 'BSD-style (M-AILABS)',
    attribution: 'Piper voice “ramona” (de) — $_mailabs',
    model: _piper('de_DE-ramona-low', 31370176),
  ),
  NeuralVoice(
    id: 'piper-de-karlsson-low',
    engine: NeuralVoiceEngine.piper,
    lang: 'de',
    name: 'Karlsson',
    female: false,
    license: 'BSD-style (M-AILABS)',
    attribution: 'Piper voice “karlsson” (de) — $_mailabs',
    model: _piper('de_DE-karlsson-low', 31370176),
  ),
  // ── English ───────────────────────────────────────────────────────────────
  NeuralVoice(
    id: 'piper-en-cori-medium',
    engine: NeuralVoiceEngine.piper,
    lang: 'en',
    region: 'GB',
    name: 'Cori',
    female: true,
    license: 'Public domain',
    model: _piper('en_GB-cori-medium', 31418816),
  ),
  const NeuralVoice(
    id: 'kokoro-en-af_heart',
    engine: NeuralVoiceEngine.kokoro,
    lang: 'en',
    region: 'US',
    name: 'Kokoro Heart',
    female: true,
    license: 'Apache-2.0',
    model: NeuralVoiceFile(
      filename: 'kokoro-82m-q8_0.gguf',
      url: '$_kokoroModelRepo/kokoro-82m-q8_0.gguf',
      bytes: 141322336,
    ),
    voicePack: NeuralVoiceFile(
      filename: 'kokoro-voice-af_heart.gguf',
      url: '$_kokoroVoiceRepo/kokoro-voice-af_heart.gguf',
      bytes: 522784,
    ),
  ),
];

/// The voice with [id], or null (unknown / removed from the catalog).
NeuralVoice? neuralVoiceById(String? id) {
  if (id == null) return null;
  for (final v in kNeuralVoices) {
    if (v.id == id) return v;
  }
  return null;
}

/// Voices for a base language (`de`/`en`), in picker order.
List<NeuralVoice> neuralVoicesFor(String lang) => [
      for (final v in kNeuralVoices)
        if (v.lang == lang) v,
    ];
