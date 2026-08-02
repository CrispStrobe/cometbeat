// lib/core/harmony/chart_share.dart
//
// BB-D4b — a chart you can hand to someone.
//
// There is no hosted index and there never will be (decision 4), so sharing is
// a STRING: you paste it into a message and the other person pastes it back.
// That is the whole mechanism, and it is deliberately the same one the groove
// engine already uses — `KU1.` + base64 of the spec's JSON — so there is one
// idea to learn rather than two.
//
// ⚠️ THE HARD PART IS EVERYTHING THAT HAPPENS TO A STRING IN TRANSIT, not the
// encoding. A token gets wrapped by a mail client, surrounded by quote markers,
// autocorrected into a smart-quoted "CB1.", and pasted with a trailing newline.
// `decodeChartToken` therefore repairs what it safely can and refuses the rest
// — but it NEVER guesses at the payload itself: a token that does not decode to
// a chart returns null rather than a partial one.
library;

import 'dart:convert';

import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_codec.dart';

/// The share-token prefix. Versioned like the codec so a later format can
/// coexist rather than break every token already in someone's messages.
const String kChartTokenPrefix = 'CB1.';

/// [chart] as a share token.
String encodeChartToken(Chart chart) =>
    '$kChartTokenPrefix${base64UrlEncode(utf8.encode(chartToJsonString(chart)))}';

/// A share token back to a chart; null for anything that is not one.
///
/// Never throws on foreign input — this is fed straight from a paste buffer,
/// which contains whatever the user copied.
Chart? decodeChartToken(String token) {
  for (final candidate in _candidates(token)) {
    final chart = _tryDecode(candidate);
    if (chart != null) return chart;
  }
  return null;
}

/// True when [text] looks like it contains a chart token at all.
///
/// For a paste handler deciding whether to offer "open this chart?" — cheap,
/// and deliberately not a full decode.
bool looksLikeChartToken(String text) => _candidates(text).isNotEmpty;

Chart? _tryDecode(String payload) {
  try {
    final json = utf8.decode(base64Url.decode(base64Url.normalize(payload)));
    return chartFromJsonString(json);
  } catch (_) {
    return null;
  }
}

/// The payloads worth trying, most trustworthy first.
///
/// ⚠️ REPAIR ONLY WHEN THE PLAIN READING FAILS. The obvious implementation —
/// skip whitespace so a wrapped token rejoins — is WRONG, and the tests caught
/// it: `CB1.abc what do you think?` absorbs "what", "do" and "you", because
/// those are all valid base64. So the contiguous run is tried FIRST, and the
/// line-rejoining repair is only reached when that run does not decode. A
/// token that arrived intact can never be corrupted by the repair path.
List<String> _candidates(String text) {
  // Smart quotes first: a token pasted from a messaging app often arrives as
  // “CB1.…”, and the curly characters are not base64.
  final s = text
      .replaceAll('\u201c', '"')
      .replaceAll('\u201d', '"')
      .replaceAll('\u2018', "'")
      .replaceAll('\u2019', "'");

  final start = s.indexOf(kChartTokenPrefix);
  if (start < 0) return const [];
  final rest = s.substring(start + kChartTokenPrefix.length);

  final out = <String>[];

  // 1. The contiguous run: what an intact paste looks like.
  final contiguous = StringBuffer();
  for (final rune in rest.runes) {
    final c = String.fromCharCode(rune);
    if (!_isBase64Url(c)) break;
    contiguous.write(c);
  }
  if (contiguous.isNotEmpty) out.add(contiguous.toString());

  // 2. Rejoined across line breaks and reply quotes, for a wrapped token.
  //    Whitespace is skipped ONLY at the start of a line — a space in the
  //    middle of a line is a sentence, not a wrap.
  final rejoined = StringBuffer();
  var atLineStart = false;
  for (final rune in rest.runes) {
    final c = String.fromCharCode(rune);
    if (c == '\n' || c == '\r') {
      atLineStart = true;
      continue;
    }
    if (atLineStart && (c == ' ' || c == '\t' || c == '>')) continue;
    if (_isBase64Url(c)) {
      rejoined.write(c);
      atLineStart = false;
      continue;
    }
    break;
  }
  final joined = rejoined.toString();
  if (joined.isNotEmpty && joined != out.firstOrNull) out.add(joined);

  return out;
}

bool _isBase64Url(String c) =>
    (c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39) || // 0-9
    (c.codeUnitAt(0) >= 0x41 && c.codeUnitAt(0) <= 0x5A) || // A-Z
    (c.codeUnitAt(0) >= 0x61 && c.codeUnitAt(0) <= 0x7A) || // a-z
    c == '-' ||
    c == '_' ||
    c == '=';
