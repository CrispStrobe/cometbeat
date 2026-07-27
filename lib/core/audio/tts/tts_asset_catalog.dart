// tts_asset_catalog.dart — the vetted, downloadable TTS assets. Web-safe pure
// data (no platform imports). Every entry is ship-safe by licence:
//   • Piper CODE is MIT; these VOICE datasets are CC0 (kathleen, thorsten) —
//     no attribution required, commercial-OK. Verified against each voice's
//     MODEL_CARD on rhasspy/piper-voices.
// NOTHING NC / CC-BY-SA / espeak-derived is listed here (see CLAUDE.md licence
// notes). Kokoro is deliberately absent: it downloads through CrispASR's OWN
// model registry (no hand-rolled URLs — see kokoro_model_store.dart), so it is
// managed there, not by this static catalog.
//
// The `id` doubles as the cache key: a `models/`-rooted relative path that maps
// to the exact file PiperVoiceStore reads on native (piper/<base>.onnx), so a
// download through TtsModelManager transparently feeds native synthesis.

/// What a [TtsAsset] is, for grouping/UI.
enum TtsAssetKind {
  /// A neural voice model (`.onnx`).
  voiceModel,

  /// A voice model's config sidecar (`.onnx.json`).
  voiceConfig,
}

/// A downloadable TTS asset. `id` is the stable cache key (a relative path).
class TtsAsset {
  const TtsAsset({
    required this.id,
    required this.group,
    required this.kind,
    required this.url,
    required this.license,
    required this.langs,
    required this.minBytes,
    this.approxBytes,
  });

  /// Stable id AND cache key — a `models/`-rooted relative path.
  final String id;

  /// Grouping id (one voice = a model + its config); UI shows the group.
  final String group;

  final TtsAssetKind kind;

  /// HTTPS download URL.
  final String url;

  /// Human licence note (SPDX-ish + source), surfaced in the UI.
  final String license;

  /// Languages this asset serves, e.g. `['en']`.
  final List<String> langs;

  /// Sanity floor: a shorter download is treated as failed (offline/CORS/404
  /// pages are tiny). The manager rejects anything below this.
  final int minBytes;

  /// Rough download size, for a UI hint. Null if unknown.
  final int? approxBytes;
}

/// A voice = its model + config, grouped for the UI.
class TtsVoiceGroup {
  const TtsVoiceGroup({
    required this.id,
    required this.label,
    required this.langs,
    required this.license,
    required this.assets,
  });

  final String id;
  final String label;
  final List<String> langs;
  final String license;

  /// The assets that make up this voice (model + config).
  final List<TtsAsset> assets;

  /// Sum of the assets' approximate sizes, or null if any is unknown.
  int? get approxBytes {
    var total = 0;
    for (final a in assets) {
      if (a.approxBytes == null) return null;
      total += a.approxBytes!;
    }
    return total;
  }
}

const _piperBase = 'https://huggingface.co/rhasspy/piper-voices/resolve/main';

/// The flat list of all vetted downloadable assets.
const List<TtsAsset> kTtsAssetCatalog = [
  // ── en: kathleen (low, 16 kHz), CC0 ──────────────────────────────────────
  TtsAsset(
    id: 'piper/en_US-kathleen-low.onnx',
    group: 'piper-en',
    kind: TtsAssetKind.voiceModel,
    url: '$_piperBase/en/en_US/kathleen/low/en_US-kathleen-low.onnx',
    license: 'CC0 (dataset-voice-kathleen); Piper code MIT',
    langs: ['en'],
    minBytes: 1024 * 1024,
    approxBytes: 63 * 1024 * 1024,
  ),
  TtsAsset(
    id: 'piper/en_US-kathleen-low.onnx.json',
    group: 'piper-en',
    kind: TtsAssetKind.voiceConfig,
    url: '$_piperBase/en/en_US/kathleen/low/en_US-kathleen-low.onnx.json',
    license: 'CC0 (dataset-voice-kathleen); Piper code MIT',
    langs: ['en'],
    minBytes: 100,
    approxBytes: 4 * 1024,
  ),
  // ── de: thorsten (low, 16 kHz), CC0 ──────────────────────────────────────
  TtsAsset(
    id: 'piper/de_DE-thorsten-low.onnx',
    group: 'piper-de',
    kind: TtsAssetKind.voiceModel,
    url: '$_piperBase/de/de_DE/thorsten/low/de_DE-thorsten-low.onnx',
    license: 'CC0 (Thorsten-Voice); Piper code MIT',
    langs: ['de'],
    minBytes: 1024 * 1024,
    approxBytes: 63 * 1024 * 1024,
  ),
  TtsAsset(
    id: 'piper/de_DE-thorsten-low.onnx.json',
    group: 'piper-de',
    kind: TtsAssetKind.voiceConfig,
    url: '$_piperBase/de/de_DE/thorsten/low/de_DE-thorsten-low.onnx.json',
    license: 'CC0 (Thorsten-Voice); Piper code MIT',
    langs: ['de'],
    minBytes: 100,
    approxBytes: 4 * 1024,
  ),
];

/// The catalog grouped into voices (model + config), for the settings UI.
List<TtsVoiceGroup> ttsVoiceGroups() {
  final byGroup = <String, List<TtsAsset>>{};
  for (final a in kTtsAssetCatalog) {
    (byGroup[a.group] ??= []).add(a);
  }
  const labels = {
    'piper-en': 'English (kathleen)',
    'piper-de': 'Deutsch (thorsten)',
  };
  return [
    for (final entry in byGroup.entries)
      TtsVoiceGroup(
        id: entry.key,
        label: labels[entry.key] ?? entry.key,
        langs: entry.value.first.langs,
        license: entry.value.first.license,
        assets: entry.value,
      ),
  ];
}

/// The catalog asset with this [id], or null.
TtsAsset? ttsAssetById(String id) {
  for (final a in kTtsAssetCatalog) {
    if (a.id == id) return a;
  }
  return null;
}
