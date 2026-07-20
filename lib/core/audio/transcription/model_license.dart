// lib/core/audio/transcription/model_license.dart
//
// Non-permissive model-weight gate. Most neural weights we ship are MIT /
// Apache-2.0 (no gate). A few carry a NON-COMMERCIAL / restrictive licence —
// notably the BTC chord weights (CC-BY-NC-SA-4.0: the BTC *code* is MIT, but the
// released weights are trained on Isophonics annotations, which are
// CC-BY-NC-SA). Those must be EXPLICITLY accepted before the store downloads or
// loads them — auto-download is intentionally NOT sufficient.
//
// Accept via user consent (`acceptModelLicense`, e.g. after a consent dialog),
// or for CLI/tests via the `COMET_ACCEPT_LICENSES` env (comma/space-separated
// SPDX ids, or `all`). Mirrors the CrispASR / CrispEmbed acceptance gate.
library;

import 'dart:io';

/// Thrown when a restrictive-licence model is used without explicit acceptance.
class ModelLicenseNotAccepted implements Exception {
  const ModelLicenseNotAccepted(this.model, this.spdx);

  final String model;
  final String spdx;

  @override
  String toString() =>
      '$model ships under $spdx (non-commercial / restrictive) and will not '
      'download or load until you accept it. Accept via a consent prompt '
      '(acceptModelLicense("$spdx")) or set COMET_ACCEPT_LICENSES="$spdx" (or '
      '"all"). Auto-download is intentionally not sufficient.';
}

final Set<String> _accepted = <String>{};

/// Record explicit user consent for [spdx] (e.g. after a consent dialog). Pass
/// `all` to accept every restrictive licence.
void acceptModelLicense(String spdx) =>
    _accepted.add(spdx.trim().toLowerCase());

/// Clear all programmatic acceptances (for tests).
void resetModelLicenseAcceptance() => _accepted.clear();

/// Whether [spdx] has been explicitly accepted — via [acceptModelLicense] or the
/// `COMET_ACCEPT_LICENSES` env (comma/space-separated SPDX ids, or `all`).
bool modelLicenseAccepted(String spdx, {Map<String, String>? env}) {
  final k = spdx.trim().toLowerCase();
  if (_accepted.contains(k) || _accepted.contains('all')) return true;
  final raw = (env ?? Platform.environment)['COMET_ACCEPT_LICENSES'] ?? '';
  final set = raw
      .split(RegExp(r'[,\s]+'))
      .map((s) => s.trim().toLowerCase())
      .where((s) => s.isNotEmpty)
      .toSet();
  return set.contains('all') || set.contains(k);
}

/// Throws [ModelLicenseNotAccepted] unless [spdx] is accepted. Call BEFORE any
/// download or load of restrictive-licence weights.
void requireModelLicense(String model, String spdx) {
  if (!modelLicenseAccepted(spdx)) {
    throw ModelLicenseNotAccepted(model, spdx);
  }
}
