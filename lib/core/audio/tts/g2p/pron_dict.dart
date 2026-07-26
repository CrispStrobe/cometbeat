// pron_dict.dart — pronunciation-dictionary tier for the G2P phonemizer.
//
// LICENSE / DATA PROVENANCE
//   Code: MIT (this project). The LTS rules and ARPAbet→IPA mapping are ported
//   from our own MIT repo CrispASR.
//   Bundled English dict ([bundledEnDict]): derived from CMUdict, which is
//   PUBLIC DOMAIN (Carnegie Mellon). ARPAbet is converted to IPA with OUR OWN
//   mapping ([arpabetToIpa]) — no espeak data is used or shipped.
//   Bundled German dict ([bundledDeDict]): derived from OLaPh, which is MIT.
//   NOT shipped: espeak-ng-generated dicts (GPLv3 grey area) and open-dict-data
//   (CC-BY-SA copyleft). Those are used, if at all, only as a *test oracle*
//   (measuring accuracy), never bundled or redistributed.
//
// Pure Dart: no dart:io / dart:ffi / Flutter. Bundled data lives in const
// strings ([bundled_dict_en.dart] / [bundled_dict_de.dart]) parsed in-memory.
// A caller may also DOWNLOAD a fuller dict at runtime (its own I/O) and inject
// it — see [kEnDictDownloadUrl] / [kDeDictDownloadUrl] and the parser factories.

import 'package:comet_beat/core/audio/tts/g2p/bundled_dict_de.dart';
import 'package:comet_beat/core/audio/tts/g2p/bundled_dict_en.dart';
import 'package:comet_beat/core/audio/tts/g2p/g2p_en.dart';

/// Documented download sources for the FULL clean-licensed dicts, so a TTS
/// backend can fetch + cache them at runtime for maximum coverage, then inject
/// via [PronunciationDictionary.fromCmudict] / [PronunciationDictionary.fromTsv].
///
/// English — CMUdict (public domain), ARPAbet; convert with [arpabetToIpa].
const String kEnDictDownloadUrl =
    'https://huggingface.co/datasets/cstr/g2p-dicts/resolve/main/cmudict.dict';

/// German — OLaPh (MIT), already IPA in `word\t/ipa/` form.
const String kDeDictDownloadUrl =
    'https://huggingface.co/datasets/cstr/g2p-dicts/resolve/main/olaph_de.txt';

/// An injectable word→IPA pronunciation dictionary (lowercase keys).
class PronunciationDictionary {
  PronunciationDictionary(this._entries);

  final Map<String, String> _entries;

  int get length => _entries.length;

  bool contains(String word) => _entries.containsKey(word.toLowerCase());

  /// IPA for [word], or null if absent. Case-insensitive (Unicode-aware).
  String? lookup(String word) => _entries[word.toLowerCase()];

  /// Parse a `word<TAB>ipa` TSV. When [slashWrapped] the IPA is expected as
  /// `/ipa/` (optionally comma-separated variants — the first is kept), the
  /// format used by espeak/OLaPh dumps. First entry per word wins; a leading
  /// `word\tipa` header row is skipped.
  factory PronunciationDictionary.fromTsv(
    String tsv, {
    bool slashWrapped = false,
  }) {
    final map = <String, String>{};
    for (final line in tsv.split('\n')) {
      if (line.isEmpty) continue;
      final tab = line.indexOf('\t');
      if (tab <= 0) continue;
      final word = line.substring(0, tab).toLowerCase();
      if (word == 'word') continue; // header
      var ipa = line.substring(tab + 1);
      if (slashWrapped) {
        // Take the first variant, strip surrounding slashes/space.
        final comma = ipa.indexOf(',');
        if (comma >= 0) ipa = ipa.substring(0, comma);
        ipa = ipa.replaceAll('/', '').trim();
      }
      if (ipa.isEmpty || map.containsKey(word)) continue;
      map[word] = ipa;
    }
    return PronunciationDictionary(map);
  }

  /// Parse a CMUdict-format text (`WORD  AH0 B AW1 T`, `;;;` comments,
  /// `WORD(2)` variants) into IPA via [arpabetToIpa]. Public-domain input →
  /// clean-room IPA. First pronunciation per word wins.
  factory PronunciationDictionary.fromCmudict(String text) {
    final map = <String, String>{};
    for (final raw in text.split('\n')) {
      if (raw.isEmpty || raw.startsWith(';;;')) continue;
      // Word is the first whitespace-delimited token.
      var sp = raw.indexOf(' ');
      if (sp < 0) sp = raw.indexOf('\t');
      if (sp <= 0) continue;
      var word = raw.substring(0, sp);
      // Drop a "(2)" variant marker; keep only the first pronunciation.
      final paren = word.indexOf('(');
      if (paren >= 0) word = word.substring(0, paren);
      word = word.toLowerCase();
      if (map.containsKey(word)) continue;
      final rest = raw.substring(sp + 1).trim();
      if (rest.isEmpty) continue;
      final phones = rest.split(RegExp(r'\s+'));
      final ipa = arpabetToIpa(phones);
      if (ipa.isNotEmpty) map[word] = ipa;
    }
    return PronunciationDictionary(map);
  }
}

PronunciationDictionary? _bundledEn;
PronunciationDictionary? _bundledDe;

/// Bundled high-frequency English dict (CMUdict-derived, public domain).
/// Lazily parsed once. Excludes the eval set so accuracy numbers stay honest.
PronunciationDictionary bundledEnDict() =>
    _bundledEn ??= PronunciationDictionary.fromTsv(kBundledEnDictTsv);

/// Bundled high-frequency German dict (OLaPh-derived, MIT). Lazily parsed once.
PronunciationDictionary bundledDeDict() =>
    _bundledDe ??= PronunciationDictionary.fromTsv(kBundledDeDictTsv);
