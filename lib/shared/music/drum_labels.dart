// The one place a [Drum] gets a user-facing name.
//
// This mapping used to live as a private `_drumLabel` inside the Drum Kit
// screen, so every other surface that needed to name a drum either reached for
// the three `performPad*` keys (kick/snare/hat only) or named nothing at all.
// The Loop Studio's beat grid did the latter, which is part of why its extended
// kit lanes were invisible: there was no name to put beside them.
//
// Exhaustive on purpose — no `_ =>` default. `Drum` grows by APPENDING (see the
// enum's own note), and a default arm would let a newly added voice ship with
// silently wrong or missing text; the switch failing to compile is the point.

import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/l10n/app_localizations.dart';

String drumLabel(AppLocalizations l10n, Drum d) => switch (d) {
      Drum.kick => l10n.drumkitKick,
      Drum.snare => l10n.drumkitSnare,
      Drum.hat => l10n.drumkitHat,
      Drum.openHat => l10n.drumkitOpenHat,
      Drum.clap => l10n.drumkitClap,
      Drum.tom => l10n.drumkitTom,
      Drum.rim => l10n.drumkitRim,
      Drum.cowbell => l10n.drumkitCowbell,
      Drum.crash => l10n.drumkitCrash,
      Drum.ride => l10n.drumkitRide,
      Drum.lowTom => l10n.drumkitLowTom,
      Drum.highTom => l10n.drumkitHighTom,
    };
