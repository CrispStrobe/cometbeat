// lib/core/licensing/license_obligations.dart
//
// What the app OWES when licensed material ends up in something the user
// exports, saves or shares — the SA-PROPAGATION rule.
//
// docs/CORPUS_LICENSING.md holds Tier C (share-alike: CC BY-SA, ODbL) back from
// shipping with exactly one requirement: "once SA content enters an Editor
// (Audio Editor / Tracker / Workshop), export/save/share must affirm SA on the
// output." That needs a rule before it can need a UI, and this is the rule:
// pure, Flutter-free and testable, so every editor asks the same question and
// gets the same answer.
//
// **It classifies via `LicensePolicy.classify`, not its own string matching.**
// That classifier is already "the compliance spine of the library connector"
// and gets the awkward parts right (CC spelled out in full, ShareAlike checked
// before plain attribution, NC/ND taking priority). A second opinion about what
// a licence means is precisely the bug this file exists to prevent — the repo
// already carries scars from parallel implementations that drifted.
//
// What IS new here is propagation, which no existing code does:
//
//   * **Share-alike is infectious.** ONE share-alike contributor makes the
//     whole output share-alike. There is no "mostly permissive" mix.
//   * **Incompatible copyleft is a CONFLICT, not a choice.** ODbL is a database
//     licence and is not interchangeable with CC BY-SA; picking one silently
//     would be inventing permission we don't have.
//   * **The obligation lands on the OUTPUT**, not just in a credits list.

import 'package:comet_beat/features/library/license_policy.dart';

/// Tiers as defined in `docs/CORPUS_LICENSING.md`, derived from [LicenseKind]
/// so there is one classifier and one mapping, not two ladders.
enum LicenseTier {
  /// CC0 / public domain / MIT / Apache / BSD — no obligation.
  a,

  /// CC BY — attribution required.
  b,

  /// Share-alike (CC BY-SA, ODbL, GPL) — attribution AND the output inherits it.
  c,

  /// Non-commercial. Cannot ship.
  d,

  /// Unstated / all-rights-reserved / ND / anything unrecognised. Not
  /// shippable, because "unknown" has never meant "free".
  unknown,
}

extension LicenseTierX on LicenseTier {
  /// Whether material of this tier may be included in an exported work at all.
  bool get isShippable =>
      this == LicenseTier.a || this == LicenseTier.b || this == LicenseTier.c;

  /// Whether a credit has to appear.
  bool get requiresAttribution =>
      this == LicenseTier.b || this == LicenseTier.c;
}

const _policy = LicensePolicy(allowAttributionLicenses: true);

/// Classify a licence string into a tier.
///
/// Delegates to [LicensePolicy.classify] and only adds the copyleft families it
/// doesn't model (ODbL, GPL, CPDL), which are share-alike for our purposes.
LicenseTier licenseTierOf(String license) {
  // ODbL/GPL/CPDL aren't CC and aren't in LicenseKind; they're still copyleft.
  if (_nonCcShareAlikeFamily(license) != null) return LicenseTier.c;
  return switch (_policy.classify(license)) {
    LicenseKind.publicDomain ||
    LicenseKind.cc0 ||
    LicenseKind.mit ||
    LicenseKind.apache2 ||
    LicenseKind.bsd =>
      LicenseTier.a,
    LicenseKind.ccBy => LicenseTier.b,
    LicenseKind.ccBySa => LicenseTier.c,
    LicenseKind.ccByNc => LicenseTier.d,
    LicenseKind.ccByNd ||
    LicenseKind.allRightsReserved ||
    LicenseKind.unknown =>
      LicenseTier.unknown,
  };
}

/// One piece of licensed material that went into a document.
class LicensedWork {
  const LicensedWork({
    required this.title,
    required this.license,
    this.creator,
    this.source,
    this.url,
  });

  /// What it is (a song, a sample, an instrument).
  final String title;

  /// The licence exactly as the source states it — SPDX id or free text.
  final String license;

  /// The person the licence says to credit, when there is one.
  final String? creator;

  /// The collection it came from (e.g. "Kinder wollen singen").
  final String? source;

  final String? url;

  LicenseTier get tier => licenseTierOf(license);

  /// The credit line: title, creator, source, licence — skipping what we don't
  /// know rather than printing "null" at a user.
  String get creditLine => [
        title,
        if (creator != null && creator!.trim().isNotEmpty) creator!.trim(),
        if (source != null && source!.trim().isNotEmpty) source!.trim(),
        license.trim().isEmpty ? 'licence unstated' : license.trim(),
      ].join(' — ');

  @override
  bool operator ==(Object other) =>
      other is LicensedWork &&
      other.title == title &&
      other.license == license &&
      other.creator == creator &&
      other.source == source &&
      other.url == url;

  @override
  int get hashCode => Object.hash(title, license, creator, source, url);
}

/// Copyleft families. Material is only mutually relicensable WITHIN a family;
/// across families it's a conflict.
enum ShareAlikeFamily { ccBySa, odbl, gpl, other }

/// What an export/save/share has to do to be lawful.
class LicenseObligations {
  const LicenseObligations({
    required this.works,
    required this.strongestTier,
    required this.shareAlikeLicense,
    required this.conflicts,
    required this.blocking,
  });

  /// Every distinct contributing work, tier A included — a caller may want the
  /// full bill even when nothing is owed.
  final List<LicensedWork> works;

  /// The most restrictive tier present: what governs the output.
  final LicenseTier strongestTier;

  /// The licence the OUTPUT must carry, or null when nothing is share-alike.
  /// Mixed CC BY-SA versions resolve to the NEWEST, because BY-SA permits
  /// relicensing an adaptation under a later version.
  final String? shareAlikeLicense;

  /// Incompatible copyleft found together. Non-empty means the combination
  /// cannot lawfully be exported as one work.
  final List<String> conflicts;

  /// Works that may not be included at all (NC, ND, unstated).
  final List<LicensedWork> blocking;

  bool get isClear =>
      !requiresAttribution && !requiresShareAlike && !hasProblem;

  bool get requiresAttribution => works.any((w) => w.tier.requiresAttribution);

  bool get requiresShareAlike => shareAlikeLicense != null;

  /// Something must be resolved before this can be exported.
  bool get hasProblem => conflicts.isNotEmpty || blocking.isNotEmpty;

  /// The works that must be credited, in input order so a notice is stable.
  List<LicensedWork> get attributable => [
        for (final w in works)
          if (w.tier.requiresAttribution) w,
      ];

  /// The notice to embed in / show alongside the export. Empty when nothing is
  /// owed, so callers check `isEmpty` instead of re-deriving the rule.
  String noticeText() {
    if (!requiresAttribution && !requiresShareAlike) return '';
    final lines = <String>[
      if (requiresShareAlike)
        'This work contains share-alike material, so the whole of it is '
            'licensed $shareAlikeLicense.'
      else
        'This work contains material that must be credited:',
      if (requiresShareAlike && attributable.isNotEmpty) 'It contains:',
      for (final w in attributable)
        '• ${w.creditLine}${w.url == null ? '' : ' <${w.url}>'}',
    ];
    return lines.join('\n');
  }
}

/// Copyleft families [LicenseKind] doesn't model.
ShareAlikeFamily? _nonCcShareAlikeFamily(String license) {
  final s = license.toLowerCase();
  if (s.contains('odbl') || s.contains('open database')) {
    return ShareAlikeFamily.odbl;
  }
  if (RegExp(r'\bl?gpl\b').hasMatch(s) || s.contains('gnu general public')) {
    return ShareAlikeFamily.gpl;
  }
  if (s.contains('cpdl')) return ShareAlikeFamily.other;
  return null;
}

ShareAlikeFamily _familyOf(String license) =>
    _nonCcShareAlikeFamily(license) ?? ShareAlikeFamily.ccBySa;

/// Work out what [works] collectively oblige.
///
/// Duplicates collapse (one sample used twice is credited once), input order is
/// preserved so a notice reads the same every time, and problems are NAMED
/// rather than resolved silently.
LicenseObligations obligationsFor(Iterable<LicensedWork> works) {
  final unique = <LicensedWork>[];
  for (final w in works) {
    if (!unique.contains(w)) unique.add(w);
  }

  var strongest = LicenseTier.a;
  final blocking = <LicensedWork>[];
  final families = <ShareAlikeFamily, List<LicensedWork>>{};

  for (final w in unique) {
    final tier = w.tier;
    if (_severity(tier) > _severity(strongest)) strongest = tier;
    if (!tier.isShippable) blocking.add(w);
    if (tier == LicenseTier.c) {
      (families[_familyOf(w.license)] ??= []).add(w);
    }
  }

  final conflicts = <String>[];
  String? saLicense;
  if (families.length > 1) {
    final names = families.keys.map(_familyName).toList()..sort();
    conflicts.add(
      'Incompatible share-alike licences in one work: ${names.join(' and ')}. '
      'These cannot be combined into a single export.',
    );
  } else if (families.length == 1) {
    final entry = families.entries.single;
    saLicense = _resolveShareAlike(entry.key, entry.value);
  }

  return LicenseObligations(
    works: unique,
    strongestTier: strongest,
    shareAlikeLicense: saLicense,
    conflicts: conflicts,
    blocking: blocking,
  );
}

/// Within one family, the licence the output must carry. For CC BY-SA that's
/// the NEWEST version present: BY-SA permits relicensing an adaptation under a
/// later version, so 3.0 + 4.0 ships as 4.0 — claiming 3.0 would under-license
/// the 4.0 material.
String _resolveShareAlike(ShareAlikeFamily family, List<LicensedWork> works) {
  if (family != ShareAlikeFamily.ccBySa) {
    return family == ShareAlikeFamily.odbl
        ? 'ODbL'
        : works.first.license.trim();
  }
  var best = '';
  for (final w in works) {
    final v = RegExp(r'(\d+\.\d+)').firstMatch(w.license)?.group(1);
    if (v == null) continue;
    if (best.isEmpty || _compareVersions(v, best) > 0) best = v;
  }
  return best.isEmpty ? 'CC BY-SA' : 'CC BY-SA $best';
}

int _compareVersions(String a, String b) {
  final pa = a.split('.').map(int.tryParse).toList();
  final pb = b.split('.').map(int.tryParse).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final x = pa[i] ?? 0;
    final y = pb[i] ?? 0;
    if (x != y) return x.compareTo(y);
  }
  return pa.length.compareTo(pb.length);
}

String _familyName(ShareAlikeFamily f) => switch (f) {
      ShareAlikeFamily.ccBySa => 'CC BY-SA',
      ShareAlikeFamily.odbl => 'ODbL',
      ShareAlikeFamily.gpl => 'GPL',
      ShareAlikeFamily.other => 'another share-alike licence',
    };

/// Ordering for "most restrictive wins".
int _severity(LicenseTier t) => switch (t) {
      LicenseTier.a => 0,
      LicenseTier.b => 1,
      LicenseTier.c => 2,
      LicenseTier.d => 3,
      LicenseTier.unknown => 4,
    };
