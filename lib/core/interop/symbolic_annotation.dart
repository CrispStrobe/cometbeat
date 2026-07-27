// lib/core/interop/symbolic_annotation.dart
//
// C0 — the interop side-car.
//
// Every converter between two authoring modes hits the same wall: the target
// model cannot express everything the source model said. A tracker cell has no
// notion of "string 3, fret 5, played as a hammer-on"; a score has no notion of
// an effect-column command; a loop track has no chord diagram. Until now each
// converter simply DROPPED what it could not represent, silently, so a
// round-trip through another mode quietly destroyed the user's work.
//
// [SymbolicAnnotations] is where that information goes instead. It is a bag
// keyed by a stable [EventAddress] (track/step/voice) plus a document-level
// slot, carrying whatever the target could not hold. A converter writes it on
// the way out and reads it on the way back, which turns "how much did we lose?"
// into a testable property: with the side-car, a round-trip is IDENTITY; without
// it, the conversion is still valid, just best-effort.
//
// Deliberately untyped values (`Object?`) with typed accessors for the keys we
// know about: a converter that stores a key nobody else understands must not
// lose it, and a newer build must be able to add keys without breaking an older
// one. Pure Dart, JSON-round-trippable, no Flutter.

import 'dart:collection';

/// Where an annotation attaches: a track/channel/string/part index, a grid step
/// (row / column / tick index — whatever the source model counts in), and a
/// voice within that track.
///
/// Value equality, so it works as a map key across a serialisation round-trip.
class EventAddress {
  const EventAddress({required this.track, required this.step, this.voice = 0});

  /// The track, channel, string, or part index.
  final int track;

  /// The grid step: a tracker row, a tab column, a loop step.
  final int step;

  /// The voice within the track. 0 for every single-voice model.
  final int voice;

  @override
  bool operator ==(Object other) =>
      other is EventAddress &&
      other.track == track &&
      other.step == step &&
      other.voice == voice;

  @override
  int get hashCode => Object.hash(track, step, voice);

  @override
  String toString() => 't$track.s$step${voice == 0 ? '' : '.v$voice'}';

  /// `"track:step:voice"` — the map key used in [SymbolicAnnotations.toJson].
  String get key => '$track:$step:$voice';

  /// Parses a [key]; null when it is not three integers.
  static EventAddress? parseKey(String raw) {
    final parts = raw.split(':');
    if (parts.length != 3) return null;
    final track = int.tryParse(parts[0]);
    final step = int.tryParse(parts[1]);
    final voice = int.tryParse(parts[2]);
    if (track == null || step == null || voice == null) return null;
    return EventAddress(track: track, step: step, voice: voice);
  }
}

/// The well-known annotation keys. A converter may store anything, but these are
/// the ones the built-in converters agree on — using the constants rather than
/// string literals is what keeps two converters talking about the same thing.
abstract final class AnnotationKeys {
  /// Fretted-instrument placement.
  static const string = 'string';
  static const fret = 'fret';
  static const capo = 'capo';

  /// A whole column's placement as `[[string, fret], …]` — [string]/[fret] name
  /// ONE note, and a chord needs several. Stored per event so a model that
  /// keeps only pitch (a loop track) can hand the fretting back afterwards.
  static const fretting = 'fretting';

  /// A `List<String>` of `TabTechnique.name` values.
  static const techniques = 'techniques';

  /// Per-column playing state that is NOT a [TabTechnique] — `TabColumn` keeps
  /// these as their own flags, so they need their own keys or they travel with
  /// nothing.
  static const palmMute = 'palmMute';
  static const letRing = 'letRing';

  /// A `DynamicLevel.name`, and a `HairpinType.name` starting at this event.
  /// Named `dynamicLevel` because `dynamic` is a Dart keyword.
  static const dynamicLevel = 'dynamicLevel';
  static const hairpin = 'hairpin';

  /// A chord diagram, as [chordDiagramToAnnotation] writes it.
  static const chord = 'chord';

  /// Tracker effect-column command + parameter.
  static const fxCmd = 'fxCmd';
  static const fxParam = 'fxParam';

  /// Notation detail.
  static const duration = 'duration';
  static const tieToNext = 'tieToNext';

  /// A `[actual, normal]` pair, e.g. `[3, 2]` for an eighth triplet.
  static const tuplet = 'tuplet';
  static const lyric = 'lyric';
  static const articulation = 'articulation';
  static const velocity = 'velocity';

  /// Bar-level structure, anchored to a bar's first event.
  static const startRepeat = 'startRepeat';
  static const endRepeat = 'endRepeat';
  static const volta = 'volta';
  static const navigation = 'navigation';
  static const section = 'section';

  /// Document-level keys (stored in [SymbolicAnnotations.docMeta]).
  static const tuning = 'tuning';
  static const timeSignature = 'timeSignature';
  static const keySignature = 'keySignature';

  /// The mode a conversion came FROM, so a reverse conversion can tell whether
  /// the side-car it was handed actually belongs to this document.
  static const sourceMode = 'sourceMode';
}

/// The un-representable payload of one conversion: per-event annotations plus a
/// document-level [docMeta].
///
/// Mutable and small on purpose — a converter fills it while it walks the
/// document. [isEmpty] means the conversion was lossless without it.
class SymbolicAnnotations {
  SymbolicAnnotations({
    Map<String, Object?>? docMeta,
    Map<EventAddress, Map<String, Object?>>? events,
  })  : docMeta = docMeta ?? <String, Object?>{},
        _events = events ?? <EventAddress, Map<String, Object?>>{};

  /// Document-level facts the target model has no slot for — a tuning, a key
  /// signature, the source mode.
  final Map<String, Object?> docMeta;

  final Map<EventAddress, Map<String, Object?>> _events;

  /// The per-event annotations, read-only. Use [set] / [put] to write.
  UnmodifiableMapView<EventAddress, Map<String, Object?>> get events =>
      UnmodifiableMapView(_events);

  bool get isEmpty => docMeta.isEmpty && _events.isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// The number of annotated events (not the number of keys).
  int get eventCount => _events.length;

  /// Everything annotated at [at], or an empty map.
  Map<String, Object?> at(EventAddress address) =>
      _events[address] ?? const <String, Object?>{};

  /// One value, or null when absent.
  Object? get(EventAddress address, String key) => _events[address]?[key];

  /// Stores [value] under [key] at [address]. A null [value] REMOVES the key,
  /// so a converter can write unconditionally without polluting the bag with
  /// nulls — an empty entry is then dropped entirely, keeping [isEmpty]
  /// meaningful.
  void set(EventAddress address, String key, Object? value) {
    if (value == null) {
      final existing = _events[address];
      if (existing == null) return;
      existing.remove(key);
      if (existing.isEmpty) _events.remove(address);
      return;
    }
    (_events[address] ??= <String, Object?>{})[key] = value;
  }

  /// Stores several keys at once, skipping null values (see [set]).
  void put(EventAddress address, Map<String, Object?> values) {
    for (final entry in values.entries) {
      set(address, entry.key, entry.value);
    }
  }

  /// Everything annotated on [track], re-addressed to track 0.
  ///
  /// Used when a multi-track conversion hands one track to a single-track
  /// converter — without the re-addressing the callee would look up track 0 and
  /// find nothing.
  SymbolicAnnotations restrictToTrack(int track) {
    final out = SymbolicAnnotations(docMeta: Map.of(docMeta));
    for (final entry in _events.entries) {
      if (entry.key.track != track) continue;
      final rebased = EventAddress(
        track: 0,
        step: entry.key.step,
        voice: entry.key.voice,
      );
      out._events[rebased] = Map.of(entry.value);
    }
    return out;
  }

  /// This bag plus [other]. Keys in [other] win on collision.
  SymbolicAnnotations merge(SymbolicAnnotations other) {
    final out = SymbolicAnnotations(docMeta: Map.of(docMeta));
    for (final entry in _events.entries) {
      out._events[entry.key] = Map.of(entry.value);
    }
    out.docMeta.addAll(other.docMeta);
    for (final entry in other._events.entries) {
      (out._events[entry.key] ??= <String, Object?>{}).addAll(entry.value);
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
        if (docMeta.isNotEmpty) 'doc': docMeta,
        if (_events.isNotEmpty)
          'events': {
            for (final entry in _events.entries) entry.key.key: entry.value,
          },
      };

  /// Rebuilds from [toJson]. Malformed input yields an EMPTY bag rather than
  /// throwing — a corrupt side-car should cost the extra fidelity, not the
  /// document.
  static SymbolicAnnotations fromJson(Object? raw) {
    if (raw is! Map) return SymbolicAnnotations();
    final out = SymbolicAnnotations();
    final doc = raw['doc'];
    if (doc is Map) {
      for (final entry in doc.entries) {
        if (entry.key is String) out.docMeta[entry.key as String] = entry.value;
      }
    }
    final events = raw['events'];
    if (events is Map) {
      for (final entry in events.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String || value is! Map) continue;
        final address = EventAddress.parseKey(key);
        if (address == null) continue;
        for (final field in value.entries) {
          if (field.key is String) {
            out.set(address, field.key as String, field.value);
          }
        }
      }
    }
    return out;
  }
}

/// What a conversion could not carry across, in the user's terms.
///
/// Every converter returns one. [lossless] is the honest answer to "can I edit
/// this over there and come back unharmed?" — the UI shows [lost] and
/// [approximated] before the user commits to the conversion.
class ConversionReport {
  ConversionReport({
    List<String>? lost,
    List<String>? approximated,
  })  : lost = lost ?? <String>[],
        approximated = approximated ?? <String>[];

  /// Information that is GONE in the target document — recoverable only from
  /// the side-car.
  final List<String> lost;

  /// Information that survived in a changed form (a bend rendered as a pitch
  /// slide, a triplet quantized onto the grid).
  final List<String> approximated;

  /// Stable localization keys for the reason MESSAGES above, keyed by the
  /// English text. Pure Dart, so a report cannot localize itself — a UI layer
  /// with a [BuildContext] maps the key to the user's language, falling back to
  /// the English message when a reason carries no key (a dynamic/one-off one).
  /// Additive: reasons added without a key still render (in English).
  final Map<String, String> reasonKeys = {};

  /// The l10n key for a reason [message], or null to show it verbatim.
  String? keyFor(String message) => reasonKeys[message];

  bool get lossless => lost.isEmpty && approximated.isEmpty;

  void addLost(String what, [String? key]) {
    if (!lost.contains(what)) lost.add(what);
    if (key != null) reasonKeys[what] = key;
  }

  void addApproximated(String what, [String? key]) {
    if (!approximated.contains(what)) approximated.add(what);
    if (key != null) reasonKeys[what] = key;
  }

  @override
  String toString() => lossless
      ? 'lossless'
      : [
          if (lost.isNotEmpty) 'lost: ${lost.join(", ")}',
          if (approximated.isNotEmpty)
            'approximated: ${approximated.join(", ")}',
        ].join('; ');
}
