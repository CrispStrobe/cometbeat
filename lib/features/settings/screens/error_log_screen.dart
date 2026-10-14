// lib/features/settings/screens/error_log_screen.dart
//
// Settings ▸ Debug ▸ Error log: what `ErrorLog` recorded, newest first, with
// copy-all (for a bug report) and clear.

import 'package:comet_beat/core/services/error_log.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ErrorLogScreen extends StatelessWidget {
  const ErrorLogScreen({super.key, this.log});

  /// Defaults to the app-wide log.
  final ErrorLog? log;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final log = this.log ?? ErrorLog.instance;
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) {
        final entries = log.entries;
        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.errorLogTitle),
            actions: [
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: l10n.errorLogCopy,
                onPressed: entries.isEmpty
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await Clipboard.setData(
                          ClipboardData(text: log.asText()),
                        );
                        messenger.showSnackBar(
                          SnackBar(content: Text(l10n.errorLogCopied)),
                        );
                      },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: l10n.errorLogClear,
                onPressed: entries.isEmpty ? null : log.clear,
              ),
            ],
          ),
          body: entries.isEmpty
              ? Center(child: Text(l10n.errorLogEmpty))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    return Card(
                      child: ExpansionTile(
                        title: Text(
                          e.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${e.time.toLocal()}'.split('.').first +
                              (e.source.isEmpty ? '' : ' · ${e.source}'),
                        ),
                        childrenPadding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        expandedAlignment: Alignment.centerLeft,
                        children: [
                          SelectableText(
                            e.stack.isEmpty
                                ? e.message
                                : '${e.message}\n\n${e.stack}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
