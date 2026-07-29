// lib/features/games/widgets/game_app_bar.dart
//
// A shared app bar for minigame screens: the title, the app-wide [SoundToggle],
// and an optional "?" [TutorialButton] that reopens the game's primer. A screen
// adopts it by swapping `appBar: AppBar(title: ...)` for
// `appBar: GameAppBar(title: ..., tutorial: myPrimer)`.
//
// Adopting it puts the sound toggle on that screen too (it's otherwise only on
// Home/Settings). Note the reopen "?" is ALSO provided app-wide by the overlay
// in tutorial_gate.dart, so passing `tutorial:` here is only needed if a screen
// wants the button in its bar rather than as the floating overlay.

import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/tutorial/tutorial.dart';
import 'package:comet_beat/shared/tutorial/tutorial_button.dart';
import 'package:comet_beat/shared/widgets/sound_toggle.dart';
import 'package:flutter/material.dart';

class GameAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GameAppBar({
    super.key,
    required this.title,
    this.tutorial,
    this.actions = const [],
  });

  /// The bar's title text.
  final String title;

  /// The primer to (re)open from the "?" action; null hides the button.
  final Tutorial Function(AppLocalizations)? tutorial;

  /// Screen-specific actions, placed before the sound toggle and "?".
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      // Ellipsize so a long title yields to the actions instead of overflowing
      // the app-bar row on a narrow phone (e.g. the Tracker on an iPhone SE).
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        // Screen actions SCROLL horizontally; the sound toggle and "?" do NOT.
        //
        // ⚠️ History worth knowing before touching this again: a previous
        // version wrapped EVERYTHING — actions, sound toggle and "?" — in a
        // `ConstrainedBox(maxWidth: 72% of screen)` plus a scroll view, and was
        // reverted (`ba96a26f`, "keep game app bar layout stable"). Two things
        // are deliberately different here:
        //   • the sound toggle and "?" stay OUTSIDE the scroll view, so they can
        //     never scroll out of reach — they are app-wide controls, not
        //     screen ones, and a mute button you have to go looking for is
        //     worse than no scroll at all;
        //   • `Flexible` replaces the guessed 72%, so the row takes exactly the
        //     space the title leaves rather than a fraction that is wrong on
        //     most widths.
        //
        // Without this the Tracker's action row overflows by ~370px on a phone
        // and those actions are simply unreachable — an overflowing Flex also
        // throws during layout, which is how it was found.
        if (actions.isNotEmpty)
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(mainAxisSize: MainAxisSize.min, children: actions),
            ),
          ),
        const SoundToggle(),
        if (tutorial != null) TutorialButton(builder: tutorial!),
      ],
    );
  }
}
