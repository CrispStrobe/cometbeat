// lib/core/models/module_unlock.dart
//
// The module progression gate, as data. The core theory chain (note values →
// reading → measures → scales → chords → harmony → composition) opens one
// module at a time; the instrument corners, the Song Book and the other
// special-interest modules are `initiallyUnlocked` and never gate.
//
// It is an ENGAGEMENT gate, not a mastery gate: a module opens once the child
// has genuinely played in the one before it ([kModuleUnlockTracked] SRI items
// seen), not once they have aced it. A child stuck on one topic must still be
// able to move on — the review loop brings the weak items back.

import 'package:comet_beat/core/models/learning_module.dart';
import 'package:comet_beat/core/tuning.dart';

/// Where one module stands against its gate.
class ModuleUnlock {
  const ModuleUnlock({
    required this.unlocked,
    required this.tracked,
    required this.needed,
    this.requires,
  });

  final bool unlocked;

  /// SRI items seen so far in [requires] (0 when nothing gates this module).
  final int tracked;

  /// SRI items [requires] must reach (0 when nothing gates this module).
  final int needed;

  /// The module that has to be played first; null when nothing gates this one.
  final LearningModule? requires;

  /// Progress towards opening, 0..1 (1 when already open).
  double get fraction =>
      unlocked || needed == 0 ? 1 : (tracked / needed).clamp(0.0, 1.0);
}

/// The gate state of every module in [modules], keyed by module id.
/// [trackedIn] is the number of SRI-tracked items in a module; [unlockAll]
/// (the debug switch) opens everything.
Map<String, ModuleUnlock> moduleUnlocks(
  int Function(String moduleId) trackedIn, {
  bool unlockAll = false,
  List<LearningModule>? modules,
}) {
  modules ??= kLearningModules;
  final result = <String, ModuleUnlock>{};
  for (var i = 0; i < modules.length; i++) {
    final module = modules[i];
    if (unlockAll || module.initiallyUnlocked || i == 0) {
      // The first module has no predecessor to play; it can only be open.
      result[module.id] =
          const ModuleUnlock(unlocked: true, tracked: 0, needed: 0);
      continue;
    }
    final previous = modules[i - 1];
    final tracked = trackedIn(previous.id);
    result[module.id] = ModuleUnlock(
      unlocked: tracked >= kModuleUnlockTracked,
      tracked: tracked < kModuleUnlockTracked ? tracked : kModuleUnlockTracked,
      needed: kModuleUnlockTracked,
      requires: previous,
    );
  }
  return result;
}
