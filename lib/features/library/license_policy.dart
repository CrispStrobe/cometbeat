// The license gate — the compliance spine of the library connector. Every item
// passes through `LicensePolicy` before it can be imported: a declared license
// string is classified, non-permissive licenses are blocked, and a human
// attribution line is produced for the ones we keep.
//
// **Default policy: TOTALLY FREE assets only** — Public Domain / CC0, i.e.
// licenses with NO conditions at all. Attribution licenses (CC BY, CC BY-SA)
// are permissive too, but they carry obligations (credit, and share-alike on
// derivatives), so they are OFF by default and must be opted into explicitly
// via `LicensePolicy(allowAttributionLicenses: true)`.
//
// Everything else — NC, ND, all-rights-reserved, unknown/absent — is always
// blocked. (Rationale + sources in docs/LIBRARIES_AND_TAB_SCOPING.md §1.5.)

import 'package:comet_beat/features/library/content_source.dart';

/// The classified license family of an item.
enum LicenseKind {
  publicDomain,
  cc0,
  mit,
  apache2,
  bsd,
  ccBy,
  ccBySa,
  ccByNc,
  ccByNd,
  allRightsReserved,
  unknown;

  /// "Totally free": no conditions at all (public domain / CC0).
  bool get isUnconditional => this == publicDomain || this == cc0;

  /// A permissive software-style license (MIT / Apache-2.0 / BSD): use for any
  /// purpose, the only duty is preserving the license/notice text. Treated as
  /// acceptable by default alongside CC0/PD (maintainer directive).
  bool get isPermissiveNotice => this == mit || this == apache2 || this == bsd;

  /// Permissive, but only if its conditions are honoured — credit for CC BY,
  /// credit + share-alike on derivatives for CC BY-SA.
  bool get needsAttribution => this == ccBy || this == ccBySa;

  /// A short label for the UI.
  String get label => switch (this) {
        publicDomain => 'Public Domain',
        cc0 => 'CC0',
        mit => 'MIT',
        apache2 => 'Apache-2.0',
        bsd => 'BSD',
        ccBy => 'CC BY',
        ccBySa => 'CC BY-SA',
        ccByNc => 'CC BY-NC',
        ccByNd => 'CC BY-ND',
        allRightsReserved => 'All rights reserved',
        unknown => 'Unknown license',
      };
}

/// Thrown by [LicensePolicy.gate] when an item's license is not on the
/// permissive allowlist. Carries the classified [kind] so the UI can explain.
class LicenseBlocked implements Exception {
  final LibraryItem item;
  final LicenseKind kind;
  const LicenseBlocked(this.item, this.kind);

  @override
  String toString() =>
      'LicenseBlocked(${item.title}: ${kind.label} is not permissive)';
}

/// Classifies declared-license text and gates imports. Pure + stateless, so it
/// is the highest-value unit test in the connector.
class LicensePolicy {
  /// Opt in to CC BY / CC BY-SA. Off by default: we start with **totally free**
  /// (Public Domain / CC0) assets only, so nothing we import carries a credit
  /// or share-alike obligation.
  final bool allowAttributionLicenses;

  const LicensePolicy({this.allowAttributionLicenses = false});

  /// Whether [kind] may be imported under this policy. Totally-free (CC0/PD) and
  /// permissive-notice (MIT/Apache/BSD) are always allowed; CC-BY/CC-BY-SA only
  /// when opted in.
  bool allows(LicenseKind kind) =>
      kind.isUnconditional ||
      kind.isPermissiveNotice ||
      (allowAttributionLicenses && kind.needsAttribution);

  /// Classifies a free-text declared license into a [LicenseKind]. Conservative:
  /// anything it can't confidently read as permissive falls through to
  /// [LicenseKind.unknown] (which the gate blocks). NC/ND are detected *before*
  /// the plain BY/BY-SA checks so "CC BY-NC" never reads as "CC BY".
  LicenseKind classify(String declared) {
    final s = declared.toLowerCase().replaceAll(RegExp(r'[\s_]+'), ' ').trim();
    if (s.isEmpty) return LicenseKind.unknown;

    final isCc = s.contains('cc') || s.contains('creative commons');
    final nc = s.contains('nc') ||
        s.contains('noncommercial') ||
        s.contains('non-commercial');
    final nd = s.contains('nd') || s.contains('noderiv');

    // Public domain / CC0 first (no conditions).
    if (s.contains('cc0') ||
        s.contains('publicdomain') ||
        s.contains('public domain') ||
        s == 'pd' ||
        s.contains('zero')) {
      return s.contains('cc0') || s.contains('zero')
          ? LicenseKind.cc0
          : LicenseKind.publicDomain;
    }

    // Permissive software licenses (before the CC / all-rights-reserved reads;
    // word-boundary matches so "mit"/"bsd" don't fire inside other words).
    if (!isCc) {
      if (s.contains('apache')) return LicenseKind.apache2;
      if (RegExp(r'\bmit\b').hasMatch(s)) return LicenseKind.mit;
      if (RegExp(r'\bbsd\b').hasMatch(s)) return LicenseKind.bsd;
    }

    if (isCc) {
      // Restrictive variants take priority over the permissive read.
      if (nc) return LicenseKind.ccByNc;
      if (nd) return LicenseKind.ccByNd;
      if (s.contains('by sa') || s.contains('by-sa') || s.contains('bysa')) {
        return LicenseKind.ccBySa;
      }
      if (s.contains('by')) return LicenseKind.ccBy;
      return LicenseKind.unknown; // "CC" with no recognisable clause
    }

    if (s.contains('all rights reserved') || s.contains('copyright')) {
      return LicenseKind.allRightsReserved;
    }
    return LicenseKind.unknown;
  }

  /// True if [item] may be imported under this policy.
  bool isAllowed(LibraryItem item) => allows(classify(item.declaredLicense));

  /// Throws [LicenseBlocked] if [item] is not allowed by this policy; otherwise
  /// returns the classified kind. Call this before any fetch/store.
  LicenseKind gate(LibraryItem item) {
    final kind = classify(item.declaredLicense);
    if (!allows(kind)) throw LicenseBlocked(item, kind);
    return kind;
  }

  /// The human attribution line stored with an imported work and shown on the
  /// "Sources & credits" screen. PD/CC0 need no credit but we still record the
  /// source; BY/BY-SA name the author + license.
  String attributionFor(LibraryItem item) {
    final kind = classify(item.declaredLicense);
    final who = item.composer.isEmpty ? '' : ' by ${item.composer}';
    return '“${item.title}”$who — ${kind.label}. Source: ${item.sourceName}.';
  }
}
