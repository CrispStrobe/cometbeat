// lib/core/audio/fx/fx_chain_codec.dart
//
// F1 — the CHAIN STRING: one line of text that is both a CLI argument and a
// copy/paste preset in the app.
//
//     highpass freq=120 | compressor ratio=4 thresholdDb=-22 | reverb mix=20%
//
// Why this exists. `fx_spec.dart` (what an effect IS) and `fx_params.dart` (what
// each param MEANS — range, unit, integer, choices) already describe the whole
// rack machine-readably, and the app's FX panel is generated from that pair. The
// CLI was not: `bin/fxproc.dart` hand-wrote flags for seven effects while the
// registry held thirty, so in practice a new effect never reached the command
// line and therefore never got the cheap headless test or the "hear it in one
// command" loop.
//
// This file closes that by making the registry ITSELF the parser and the
// printer. Adding an [FxType] now yields a CLI verb, `--list` documentation,
// range validation and a preset entry with no further work — the same way it
// already yields a slider.
//
// Design notes:
//
//   * **Never throws.** Both faces need to REPORT a bad chain rather than crash
//     on it: a CLI prints the errors and exits, the app shows them under the
//     text field while the user is still typing. So parsing returns an
//     [FxChainParse] carrying whatever it could build plus the problems.
//   * **Forgiving where it costs nothing.** Effect and param names match
//     case- and punctuation-insensitively (`peakingEq` = `peaking-eq` =
//     `Peaking EQ`), a choice param takes its label as well as its index
//     (`kind=fuzz`), and a 0..1 param takes a percentage (`mix=20%`). None of
//     that is ambiguous, and all of it removes a reason to consult a table.
//   * **Out-of-range CLAMPS and warns** rather than failing. `FxParamSpec.clamp`
//     is what the sliders enforce, so a typed chain lands in exactly the state
//     a dragged slider could reach — and the user still hears something.
//   * **Printing is minimal by default**: only params that differ from
//     [defaultFx], so a formatted chain reads as the user's intent rather than
//     a wall of defaults.
//
// Pure Dart. No Flutter, no IO — the CLI and the widget layer sit on top.

import 'package:comet_beat/core/audio/fx/fx_params.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';

/// The outcome of parsing a chain string: what could be built, plus what was
/// wrong with it.
class FxChainParse {
  const FxChainParse({
    required this.chain,
    this.errors = const [],
    this.warnings = const [],
  });

  /// The effects that parsed. A stage with an unknown effect name contributes
  /// nothing; a stage with a bad param still contributes the effect (with that
  /// param defaulted or clamped), because dropping a whole reverb over one
  /// mistyped key would be a worse answer than reporting it.
  final List<FxSpec> chain;

  /// Problems that mean the chain is not what was asked for.
  final List<String> errors;

  /// Things that were silently fixable — a clamped value, mostly.
  final List<String> warnings;

  bool get ok => errors.isEmpty;
  bool get isEmpty => chain.isEmpty;
}

/// Parse [source] into an FX chain.
///
/// Stages are separated by `|`, `;` or a newline (a multi-line preset in a text
/// field is the same thing as a one-line CLI argument). Within a stage the first
/// token is the effect and the rest are `key=value`. A leading `!` bypasses the
/// stage — it stays in the chain, with [FxSpec.enabled] false, exactly like the
/// rack's power button, so a chain can be pasted around with a stage parked.
FxChainParse parseFxChain(String source) {
  final chain = <FxSpec>[];
  final errors = <String>[];
  final warnings = <String>[];

  final stages = source
      .split(RegExp(r'[|;\n]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty);

  for (final stage in stages) {
    final tokens = stage.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    if (tokens.isEmpty) continue;
    var name = tokens.first;
    var enabled = true;
    if (name.startsWith('!')) {
      enabled = false;
      name = name.substring(1);
    }
    if (name.isEmpty) {
      errors.add('"$stage": no effect name');
      continue;
    }

    final type = fxTypeFromName(name);
    if (type == null) {
      final suggestion = _closestTypeNames(name);
      errors.add(
        'Unknown effect "$name"'
        '${suggestion.isEmpty ? '' : ' — did you mean ${suggestion.join(' or ')}?'}',
      );
      continue;
    }

    final defaults = defaultFx(type);
    final params = Map<String, double>.from(defaults.params);

    for (final token in tokens.skip(1)) {
      final eq = token.indexOf('=');
      if (eq <= 0) {
        errors.add(
          '"$token" in "${type.name}" is not key=value'
          '${token.contains('=') ? '' : ' (missing "=")'}',
        );
        continue;
      }
      final rawKey = token.substring(0, eq);
      final rawValue = token.substring(eq + 1);
      final key = _matchKey(type, rawKey);
      if (key == null) {
        errors.add(
          'Unknown "${type.name}" parameter "$rawKey" — '
          'try ${defaults.params.keys.join(', ')}',
        );
        continue;
      }
      final spec = fxParamSpec(type, key);
      final value = _parseValue(rawValue, spec);
      if (value == null) {
        errors.add('"$rawKey=$rawValue": not a number${_choiceHint(spec)}');
        continue;
      }
      final clamped = spec.clamp(value);
      if ((clamped - value).abs() > 1e-9) {
        warnings.add(
          '${type.name} $key=$value is outside ${_rangeText(spec)} — '
          'using $clamped',
        );
      }
      params[key] = clamped;
    }

    chain.add(FxSpec(type: type, enabled: enabled, params: params));
  }

  return FxChainParse(chain: chain, errors: errors, warnings: warnings);
}

/// Print [chain] as a chain string that [parseFxChain] reads back identically.
///
/// Only params that differ from [defaultFx] are written, so the result reads as
/// the intent rather than the full state; pass [verbose] to write them all.
///
/// ⚠ Per-param AUTOMATION is not representable in a chain string and is dropped
/// here — ask [fxChainStringIsLossless] first when that matters.
String formatFxChain(List<FxSpec> chain, {bool verbose = false}) =>
    chain.map((fx) {
      final defaults = defaultFx(fx.type).params;
      final parts = <String>[
        if (!fx.enabled) '!${fx.type.name}' else fx.type.name,
      ];
      for (final entry in fx.params.entries) {
        final def = defaults[entry.key];
        if (!verbose && def != null && (def - entry.value).abs() < 1e-9) {
          continue;
        }
        parts.add('${entry.key}=${_num(entry.value)}');
      }
      return parts.join(' ');
    }).join(' | ');

/// Whether [formatFxChain] can represent [chain] without losing anything — false
/// when any effect carries automation, which the string form has no syntax for.
bool fxChainStringIsLossless(List<FxSpec> chain) =>
    chain.every((fx) => fx.automation.isEmpty);

/// The [FxType] called [name], matched case- and punctuation-insensitively
/// against both the enum name and the human label (`peakingEq` = `peaking-eq` =
/// `Peaking EQ`). Null when nothing matches.
FxType? fxTypeFromName(String name) {
  final want = _slug(name);
  if (want.isEmpty) return null;
  for (final type in FxType.values) {
    if (_slug(type.name) == want) return type;
  }
  for (final type in FxType.values) {
    if (_slug(fxTypeLabel(type)) == want) return type;
  }
  return null;
}

// --- introspection: the same table, as help text ---------------------------

/// One line per effect: `name  Label (category)  param=default[range unit] …`.
///
/// This is what `--list` prints, and it is generated from the registry rather
/// than maintained, so it cannot fall behind the rack.
String fxCatalogText({FxType? only}) {
  final buffer = StringBuffer();
  if (only != null) {
    _describeType(buffer, only);
    return buffer.toString();
  }
  final category = <FxCategory>{};
  for (final type in _byCategory()) {
    final c = fxCategory(type);
    if (category.add(c)) {
      buffer.writeln('\n${fxCategoryLabel(c).toUpperCase()}');
    }
    final params = defaultFx(type).params.keys.join(' ');
    buffer.writeln(
      '  ${type.name.padRight(18)}${fxTypeLabel(type).padRight(21)} '
      '${params.isEmpty ? '' : '($params)'}',
    );
  }
  return buffer.toString();
}

void _describeType(StringBuffer buffer, FxType type) {
  final fx = defaultFx(type);
  buffer.writeln(
    '${type.name} — ${fxTypeLabel(type)} '
    '(${fxCategoryLabel(fxCategory(type))})',
  );
  if (fx.params.isEmpty) {
    buffer.writeln('  (no parameters)');
    return;
  }
  for (final entry in fx.params.entries) {
    final spec = fxParamSpec(type, entry.key);
    final choices = spec.choices;
    buffer.writeln(
      '  ${entry.key.padRight(14)}'
      'default ${_num(entry.value).padRight(8)}'
      '${_rangeText(spec).padRight(22)}'
      '${choices == null ? fxParamLabel(entry.key) : choices.join(' | ')}',
    );
  }
}

/// Every [FxType], grouped by [fxCategory] in enum order — the picker's order,
/// reused so the CLI listing and the GUI menu agree.
List<FxType> _byCategory() => [
      for (final category in FxCategory.values)
        for (final type in FxType.values)
          if (fxCategory(type) == category) type,
    ];

// --- internals --------------------------------------------------------------

/// Lowercased, stripped of everything that is not a letter or digit — so
/// `peakingEq`, `peaking-eq`, `Peaking EQ` and `PEAKING_EQ` are one name.
String _slug(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// The real param key of [type] that [raw] names, or null.
String? _matchKey(FxType type, String raw) {
  final keys = defaultFx(type).params.keys;
  final want = _slug(raw);
  for (final key in keys) {
    if (_slug(key) == want) return key;
  }
  return null;
}

/// A value for [spec]: a plain number, a percentage of a 0..1 param, or the
/// label of a choice param.
double? _parseValue(String raw, FxParamSpec spec) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  if (text.endsWith('%')) {
    final percent = double.tryParse(text.substring(0, text.length - 1));
    if (percent == null) return null;
    // A percentage means "of the range" — which for the 0..1 params that carry
    // most mixes is the obvious reading, and stays sensible for the rest.
    return spec.min + (spec.max - spec.min) * percent / 100;
  }
  final number = double.tryParse(text);
  if (number != null) return number;
  final choices = spec.choices;
  if (choices != null) {
    final want = _slug(text);
    for (var i = 0; i < choices.length; i++) {
      if (_slug(choices[i]) == want) return i.toDouble();
    }
  }
  return null;
}

String _choiceHint(FxParamSpec spec) {
  final choices = spec.choices;
  return choices == null ? '' : ' (or one of: ${choices.join(', ')})';
}

String _rangeText(FxParamSpec spec) =>
    '${_num(spec.min)}..${_num(spec.max)}${spec.unit.isEmpty ? '' : ' ${spec.unit}'}';

/// A compact number that still round-trips EXACTLY.
///
/// A whole value drops its `.0` (`freq=120`, not `freq=120.0`); anything else
/// uses Dart's shortest representation that parses back to the same double.
/// Fixed-decimal formatting was the obvious first cut and is wrong: rounding to
/// four places turns a slider's 3.53025 into 3.5302, so printing a chain and
/// reading it back would quietly move the user's setting.
String _num(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) {
    return v.toInt().toString();
  }
  return v.toString();
}

/// Effect names close enough to [name] to be what was meant — a shared prefix
/// (`comp` → `compressor`) or a small edit distance (`revrb` → `reverb`).
/// Typos and half-remembered names are the two ways this goes wrong, so both
/// are covered; anything further away is not guessed at.
List<String> _closestTypeNames(String name) {
  final want = _slug(name);
  if (want.isEmpty) return const [];
  final scored = <(int, String)>[];
  for (final type in FxType.values) {
    final slug = _slug(type.name);
    final label = _slug(fxTypeLabel(type));
    if (slug.startsWith(want) ||
        want.startsWith(slug) ||
        label.contains(want)) {
      scored.add((0, type.name));
      continue;
    }
    final distance = _editDistance(want, slug);
    // Allow one edit per four characters, up to two — enough for a slip, tight
    // enough that a genuinely different word is not "corrected" into nonsense.
    final budget = want.length >= 8 ? 2 : (want.length >= 4 ? 1 : 0);
    if (budget > 0 && distance <= budget) scored.add((distance, type.name));
  }
  scored.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final (_, name) in scored.take(3)) name];
}

/// Edit distance counting an adjacent TRANSPOSITION as one edit (optimal string
/// alignment), three rows at a time.
///
/// Plain Levenshtein charges 2 for a swap, which is wrong for the purpose:
/// typing `chorsu` for `chorus` is one slip of the fingers and by far the
/// commonest way an effect name comes out wrong, so it has to fit inside a
/// one-edit budget or the hint never appears where it is most wanted.
int _editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty || b.isEmpty) return a.length + b.length;
  var twoBack = List<int>.filled(b.length + 1, 0);
  var previous = List<int>.generate(b.length + 1, (i) => i);
  var current = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final substitute = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      final delete = previous[j] + 1;
      final insert = current[j - 1] + 1;
      var best = substitute < delete
          ? (substitute < insert ? substitute : insert)
          : (delete < insert ? delete : insert);
      if (i > 1 &&
          j > 1 &&
          a[i - 1] == b[j - 2] &&
          a[i - 2] == b[j - 1] &&
          twoBack[j - 2] + 1 < best) {
        best = twoBack[j - 2] + 1;
      }
      current[j] = best;
    }
    final spare = twoBack;
    twoBack = previous;
    previous = current;
    current = spare;
  }
  return previous[b.length];
}
