// lib/features/home/screens/home_screen.dart
//
// The home screen: the Continue card (the curriculum's next step), the review
// button, and one card per learning module from the registry.

import 'dart:async';

import 'package:comet_beat/core/curriculum/curriculum.dart';
import 'package:comet_beat/core/models/learning_module.dart';
import 'package:comet_beat/core/models/module_unlock.dart';
import 'package:comet_beat/core/services/debug_service.dart';
import 'package:comet_beat/core/services/profile_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/project_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/curriculum/next_step.dart';
import 'package:comet_beat/features/games/composition/advanced_tracker_screen.dart';
import 'package:comet_beat/features/games/composition/daw_screen.dart';
import 'package:comet_beat/features/games/composition/loop_studio_screen.dart';
import 'package:comet_beat/features/games/composition/tab_workshop_screen.dart';
import 'package:comet_beat/features/games/screens/module_screen.dart';
import 'package:comet_beat/features/progress/screens/progress_screen.dart';
import 'package:comet_beat/features/recital/recital_screen.dart';
import 'package:comet_beat/features/review/review_router.dart';
import 'package:comet_beat/features/settings/screens/learners_card.dart';
import 'package:comet_beat/features/settings/screens/settings_screen.dart';
import 'package:comet_beat/features/textbook/textbook_screen.dart';
import 'package:comet_beat/features/workshop/screens/composition_workshop_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/project_browser_sheet.dart';
import 'package:comet_beat/shared/widgets/sound_toggle.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// "Who is playing?" — one tap per learner.
  Future<void> _switchLearner(
    BuildContext context,
    ProfileService profiles,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                l10n.learnerSwitchTitle,
                style: Theme.of(sheet).textTheme.titleMedium,
              ),
            ),
            for (final profile in profiles.profiles)
              ListTile(
                key: Key('home-learner-${profile.id}'),
                leading: Icon(
                  profile.id == profiles.active.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(learnerDisplayName(l10n, profile)),
                onTap: () {
                  Navigator.of(sheet).pop();
                  profiles.switchTo(profile.id);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sri = context.watch<SriService>();
    final progress = context.watch<ProgressService>();
    final debugUnlockAll = context.watch<DebugService>().unlockAll;
    final studioMode = context.watch<SettingsService>().studioMode;
    final profiles = context.watch<ProfileService?>();
    final dueCount = sri.getAvailableReviewCount();
    // What the review button opens (features/review/review_router.dart); null
    // when nothing due can be reviewed, in which case there is no button.
    final review = planReview(sri);
    // The one-tap answer to "what should I do now?": the curriculum's
    // recommended level, opening on its least-ready topic.
    final next =
        nextStep(kCurricula.first, progress.starsFor, sri.masteryUnder);

    // The progression gate (core/models/module_unlock.dart). Debug mode opens
    // everything.
    final breakdown = sri.getDetailedBreakdown();
    final gates = moduleUnlocks(
      (moduleId) => (breakdown[moduleId] ?? const {})
          .values
          .fold(0, (sum, s) => sum + s.tracked),
      unlockAll: debugUnlockAll,
    );

    return Scaffold(
      appBar: AppBar(
        title: const _DebugTapTitle(),
        centerTitle: true,
        actions: [
          const SoundToggle(),
          // Studio tools — off by default on a new install (Settings ▸ Studio
          // tools). Home is the learning app first.
          if (studioMode) ...[
            // WS-W6 slice 1 — the projects browser. On the home bar rather than
            // inside an authoring surface: a project spans all of them, so it
            // does not belong to any one, and the alternative was editing four
            // screens that other agents are live in.
            IconButton(
              key: const Key('home-projects'),
              icon: const Icon(Icons.folder_open),
              tooltip: l10n.projectBrowser,
              onPressed: () => showProjectBrowserSheet(
                context,
                service: context.read<ProjectService>(),
              ),
            ),
            // Authoring: one menu exposes the five product modes. Legacy
            // Perform/Drumkit/Transcribe screens remain internal integration
            // surfaces while their workflows move into Loop Studio and Audio.
            PopupMenuButton<int>(
              icon: const Icon(Icons.piano),
              tooltip: l10n.workshopTitle,
              onSelected: (v) => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => switch (v) {
                    1 => const AdvancedTrackerScreen(),
                    2 => const TabWorkshopScreen(),
                    3 => const LoopStudioScreen(),
                    8 => const DawScreen(),
                    _ => const CompositionWorkshopScreen(),
                  },
                ),
              ),
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 0,
                  child: Row(
                    children: [
                      const Icon(Icons.edit_note, size: 20),
                      const SizedBox(width: 12),
                      Text(l10n.workshopModeScore),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 1,
                  child: Row(
                    children: [
                      const Icon(Icons.grid_view, size: 20),
                      const SizedBox(width: 12),
                      Text(l10n.workshopModeTracker),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 2,
                  child: Row(
                    children: [
                      const Icon(Icons.straighten, size: 20),
                      const SizedBox(width: 12),
                      Text(l10n.workshopModeTab),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 3,
                  child: Row(
                    children: [
                      const Icon(Icons.queue_music, size: 20),
                      const SizedBox(width: 12),
                      Text(l10n.workshopModeLoopStudio),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 8,
                  child: Row(
                    children: [
                      const Icon(Icons.view_agenda, size: 20),
                      const SizedBox(width: 12),
                      Text(l10n.dawTitle),
                    ],
                  ),
                ),
                // WS-W5's project mixer used to sit here as a SIXTH entry beside
                // the five authoring modes. It is not a mode: you mix while you
                // arrange, and making it a separate destination meant leaving the
                // thing you were mixing to move a fader. It is now an overlay
                // inside Loop Studio and the Audio Editor
                // (`showMixerConsoleSheet`), where the arrangement stays visible
                // behind it.
              ],
            ),
          ],
          IconButton(
            icon: const Icon(Icons.menu_book),
            tooltip: l10n.textbookTitle,
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const TextbookScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: l10n.progressTitle,
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ProgressScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: l10n.settingsTitle,
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(
                l10n.homeTagline,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
            // Only once there is someone to tell apart: a single-learner
            // install never sees this.
            if (profiles != null && profiles.profiles.length > 1)
              Center(
                child: ActionChip(
                  key: const Key('home-learner'),
                  avatar: const Icon(Icons.person, size: 18),
                  label: Text(learnerDisplayName(l10n, profiles.active)),
                  tooltip: l10n.learnerSwitchTitle,
                  onPressed: () => _switchLearner(context, profiles),
                ),
              ),
            if (progress.currentStreak > 0)
              _StreakBar(progress: progress, l10n: l10n),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: dueCount > 0 && review != null
                  ? Center(
                      child: FilledButton.tonalIcon(
                        icon: const Icon(Icons.replay),
                        label: Text(l10n.dueForReview(dueCount)),
                        onPressed: () =>
                            Navigator.of(context).push(review.open(sri)),
                      ),
                    )
                  : Text(
                      l10n.dueForReview(dueCount),
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
            ),
            if (next != null) _ContinueCard(next: next, l10n: l10n),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 280,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  // ⚠️ Was 1.05, which left a two-column phone card ~165 pt tall
                  // against ~162 pt of content — so a module whose TITLE wrapped
                  // to two lines had its subtitle sliced through the glyphs
                  // ("Fill the measure so…" with no ellipsis). Taller cards let
                  // the two-line titles keep their subtitle instead of trading
                  // one for the other.
                  childAspectRatio: 0.92,
                ),
                itemCount: kLearningModules.length,
                itemBuilder: (context, index) {
                  final module = kLearningModules[index];
                  return _ModuleCard(
                    module: module,
                    l10n: l10n,
                    gate: gates[module.id]!,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The app-bar title. Seven taps within a couple of seconds turn on debug
/// mode (all modules unlocked) — matching the sibling apps.
class _DebugTapTitle extends StatefulWidget {
  const _DebugTapTitle();

  @override
  State<_DebugTapTitle> createState() => _DebugTapTitleState();
}

class _DebugTapTitleState extends State<_DebugTapTitle> {
  int _taps = 0;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _onTap() {
    final debug = context.read<DebugService>();
    if (debug.menuEnabled) return; // already revealed
    _resetTimer?.cancel();
    _taps++;
    if (_taps >= 7) {
      _taps = 0;
      debug.enableMenu();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.debugModeEnabled),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      _resetTimer = Timer(const Duration(seconds: 2), () => _taps = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      // The 7-tap debug reveal is a hidden dev gesture, not a user control:
      // keep it off the semantics tree so a screen reader announces the title
      // as a heading, not an undersized "button" (a11y tap-target guideline).
      excludeFromSemantics: true,
      child: Text(AppLocalizations.of(context)!.appTitle),
    );
  }
}

/// The home screen's primary action: continue the curriculum where the child
/// left off. Opens the recommended level as a short mixed session, least-ready
/// topic first, with each new game's tutorial in front of it.
class _ContinueCard extends StatelessWidget {
  final NextStep next;
  final AppLocalizations l10n;

  const _ContinueCard({required this.next, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Card(
        key: const Key('home-continue'),
        color: scheme.primaryContainer,
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Text(next.level.badge, style: const TextStyle(fontSize: 30)),
          title: Text(
            l10n.homeContinueTitle,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.onPrimaryContainer,
                ),
          ),
          subtitle: Text(
            l10n.homeContinueSubtitle(
              next.level.name(l10n),
              next.topic.title(l10n),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onPrimaryContainer),
          ),
          trailing: Icon(
            Icons.play_circle_fill,
            size: 40,
            color: scheme.primary,
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => RecitalScreen(
                program: next.program,
                title: l10n.homeContinueTitle,
                showTutorials: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StreakBar extends StatelessWidget {
  final ProgressService progress;
  final AppLocalizations l10n;

  const _StreakBar({required this.progress, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final today = progress.today;
    final days = [
      for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i)),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      // One announcement — "3-day streak" — instead of a flame and seven
      // anonymous dots.
      child: Semantics(
        label: l10n.streakDays(progress.currentStreak),
        excludeSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.local_fire_department,
                  color: Colors.deepOrange,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.streakDays(progress.currentStreak),
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final d in days)
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: progress.practicedOn(d)
                          ? Colors.deepOrange
                          : Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final LearningModule module;
  final AppLocalizations l10n;
  final ModuleUnlock gate;

  bool get unlocked => gate.unlocked;

  const _ModuleCard({
    required this.module,
    required this.l10n,
    required this.gate,
  });

  /// What to do about the lock — and, once the child has started on the
  /// module before it, how far along they are.
  String _lockedHint() {
    final requires = gate.requires;
    if (requires == null) return l10n.locked;
    return gate.tracked == 0
        ? l10n.unlockHint(requires.title(l10n))
        : l10n.unlockHintProgress(
            requires.title(l10n),
            gate.tracked,
            gate.needed,
          );
  }

  /// Opens the module, or — locked — says what unlocks it.
  void _open(BuildContext context) {
    if (unlocked) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ModuleScreen(module: module)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_lockedHint()),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        // One node per card: "Scales, <subtitle>", or — locked — the title
        // plus what opens it. Without it a screen reader meets an unnamed lock
        // and has to set off the snackbar to learn why.
        button: true,
        label: unlocked
            ? '${module.title(l10n)}, ${module.subtitle(l10n)}'
            : '${module.title(l10n)}, ${l10n.locked}. ${_lockedHint()}',
        excludeSemantics: true,
        onTap: () => _open(context),
        child: InkWell(
          onTap: () => _open(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The lock wears its own progress: a ring that fills as the
                // child plays the module before this one, so "locked" reads as
                // "nearly there" rather than as a wall. Same footprint as the
                // open avatar — the card is height-critical (see below).
                Stack(
                  alignment: Alignment.center,
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: module.color.withValues(
                        alpha: unlocked ? 1.0 : 0.3,
                      ),
                      child: Icon(
                        unlocked ? module.icon : Icons.lock,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    if (!unlocked)
                      SizedBox(
                        width: 52,
                        height: 52,
                        child: CircularProgressIndicator(
                          key: Key('unlock-progress-${module.id}'),
                          value: gate.fraction,
                          strokeWidth: 4,
                          color: module.color,
                          backgroundColor: Colors.transparent,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  module.title(l10n),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: unlocked ? null : Colors.grey,
                      ),
                ),
                const SizedBox(height: 4),
                // ⚠️ This used to be a plain `Flexible` + `maxLines: 2`, and the
                // comment on it said the subtitle would "clip instead of
                // overflowing". It does — but clipping a Text does NOT ellipsize
                // it: `maxLines: 2` means the widget still LAYS OUT two lines, and
                // when Flexible hands it room for one and a half, the Card's
                // `Clip.antiAlias` slices the second line through the middle of
                // the glyphs. On a 390-wide phone that reads as "Fill the measure
                // so" simply cut off — no ellipsis, no indication there is more.
                //
                // It is invisible to `layout_audit_test` because nothing
                // overflows: the text is clipped, which is exactly what the widget
                // was asked to do. Only looking at it catches this.
                //
                // So ask for the number of lines that actually FIT, and let Text
                // ellipsize within that. A title that wraps to two lines leaves
                // room for one subtitle line; a short title leaves room for two.
                Flexible(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final style =
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: unlocked ? null : Colors.grey,
                              );
                      // Measure a real line rather than guessing from fontSize:
                      // `TextStyle.height` is usually null, so the true line box
                      // comes from the font's own metrics.
                      final probe = TextPainter(
                        text: TextSpan(text: 'Xg', style: style),
                        textDirection: Directionality.of(context),
                        maxLines: 1,
                      )..layout();
                      final lines = constraints.maxHeight.isFinite
                          ? (constraints.maxHeight / probe.height).floor()
                          : 2;
                      // No room for even ONE line: draw nothing. `maxLines: 1`
                      // would not help — a one-line Text cannot be shorter than a
                      // line, so it would be clipped through the glyphs again.
                      // A missing subtitle reads as "this card has no subtitle";
                      // a half-sliced one reads as broken.
                      if (lines < 1) return const SizedBox.shrink();
                      return Text(
                        module.subtitle(l10n),
                        style: style,
                        maxLines: lines > 2 ? 2 : lines,
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
