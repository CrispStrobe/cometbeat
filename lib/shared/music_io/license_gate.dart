// The shared export-time licence gate.
//
// `docs/CORPUS_LICENSING.md` requires that once share-alike content enters an
// Editor, export/save/share affirms SA on the output. Each editor knows what
// material it holds; this is the one place that turns those obligations into a
// decision, so the Audio Editor, Tracker and Workshop can't drift into three
// slightly different answers about the same licence.
//
// Call it BEFORE writing anything:
//
//   if (!await confirmLicenseObligations(context, obligations)) return;
//
// It returns false when the export must not happen — either because the
// combination is unlawful (incompatible copyleft, NC/unstated material) or
// because the user declined the share-alike terms.

import 'package:comet_beat/core/licensing/license_obligations.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Show what an export owes and get a decision.
///
/// * Nothing owed → returns true immediately, no dialog. The common case must
///   not grow a click.
/// * Blocking problem → explains and returns false. There is no "export
///   anyway": the point of computing obligations is that they can refuse.
/// * Attribution / share-alike → states the terms (share-alike phrased as
///   governing the WHOLE output, which is the requirement) and lets the user
///   continue or cancel.
Future<bool> confirmLicenseObligations(
  BuildContext context,
  LicenseObligations obligations,
) async {
  if (obligations.isClear) return true;
  final l10n = AppLocalizations.of(context)!;

  final blocked = obligations.hasProblem;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(
          blocked ? l10n.licenseCannotExport : l10n.licenseTermsTitle,
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final conflict in obligations.conflicts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      conflict,
                      style: TextStyle(
                        color: scheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                for (final work in obligations.blocking)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${l10n.licenseCannotInclude}: ${work.creditLine}',
                      style: TextStyle(
                        color: scheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (obligations.noticeText().isNotEmpty)
                  Text(obligations.noticeText()),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(blocked ? l10n.dawClose : l10n.dawCancel),
          ),
          if (!blocked)
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.licenseAgreeAndExport),
            ),
        ],
      );
    },
  );
  return ok ?? false;
}
