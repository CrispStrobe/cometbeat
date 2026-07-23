// "Sources & credits" — the one place attribution travels with the app: every
// work imported from an external open-music library, AND every sample in the
// library whose licence obliges crediting (CC BY / BY-SA). CC0 / public-domain
// content creates no obligation, so it isn't listed here. Tapping a credit
// opens its source URL. Fulfils the compliance-checklist requirement in
// docs/LIBRARIES_AND_TAB_SCOPING.md §1.7.

import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/library/donation.dart';
import 'package:comet_beat/features/library/music_source_credits.dart';
import 'package:comet_beat/features/sound_lab/sample_clip_store.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class AttributionScreen extends StatelessWidget {
  /// Donation config for the optional "Support the developer" tile (off by
  /// default). Injectable for tests.
  final DonationConfig donation;

  /// The "My Samples" store, whose attribution-required clips are credited
  /// alongside imported songs. Injectable for tests.
  final SampleClipStore sampleStore;

  AttributionScreen({
    super.key,
    this.donation = kDonation,
    SampleClipStore? store,
  }) : sampleStore = store ?? SampleClipStore();

  void _open(String? url) {
    if (url == null) return;
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final service = context.watch<UserSongsService>();
    final songCredits =
        service.songs.where((s) => s.attribution != null).toList();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.librarySourcesCredits)),
      bottomNavigationBar: donation.isActive
          ? SafeArea(
              child: ListTile(
                leading: const Icon(Icons.local_cafe),
                title: Text(l10n.librarySupportDev),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => _open(donation.url),
              ),
            )
          : null,
      body: FutureBuilder<List<SampleClip>>(
        future: sampleStore.load(),
        builder: (context, snap) {
          final sampleCredits = (snap.data ?? const <SampleClip>[])
              .where((c) => c.needsAttribution)
              .toList();

          // Standing source-level credits (attribution-bearing catalogs) are
          // always shown, so browse-only users still satisfy the obligation.
          if (songCredits.isEmpty &&
              sampleCredits.isEmpty &&
              kMusicSourceCredits.isEmpty) {
            return _empty(context, l10n);
          }

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  l10n.libraryCreditsIntro,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (kMusicSourceCredits.isNotEmpty) ...[
                _sectionHeader(context, l10n.libraryCreditsMusicSources),
                for (final src in kMusicSourceCredits)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.library_music),
                      title: Text(src.name),
                      subtitle: Text(src.description),
                      isThreeLine: true,
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      onTap: () => _open(src.url),
                    ),
                  ),
              ],
              if (songCredits.isEmpty && sampleCredits.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    l10n.libraryNoCredits,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              if (songCredits.isNotEmpty) ...[
                _sectionHeader(context, l10n.libraryCreditsSongs),
                for (final song in songCredits)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.music_note),
                      title: Text(song.attribution!),
                      trailing: song.sourceUrl == null
                          ? null
                          : const Icon(Icons.open_in_new, size: 18),
                      onTap: song.sourceUrl == null
                          ? null
                          : () => _open(song.sourceUrl),
                    ),
                  ),
              ],
              if (sampleCredits.isNotEmpty) ...[
                _sectionHeader(context, l10n.libraryCreditsSamples),
                for (final clip in sampleCredits)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.graphic_eq),
                      title: Text(clip.name),
                      subtitle: Text(
                        [
                          if (clip.source != null) clip.source!,
                          if (clip.license != null) clip.license!,
                        ].join(' · '),
                      ),
                      trailing: clip.sourceUrl == null
                          ? null
                          : const Icon(Icons.open_in_new, size: 18),
                      onTap: clip.sourceUrl == null
                          ? null
                          : () => _open(clip.sourceUrl),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );

  Widget _empty(BuildContext context, AppLocalizations l10n) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            l10n.libraryNoCredits,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
}
