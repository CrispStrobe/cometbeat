// The module progression gate: the theory chain opens one module at a time on
// engagement; the special-interest modules never gate.
import 'package:comet_beat/core/models/learning_module.dart';
import 'package:comet_beat/core/models/module_unlock.dart';
import 'package:comet_beat/core/tuning.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a new learner: entry and special-interest modules open, chain locked',
      () {
    final gates = moduleUnlocks((_) => 0);
    for (final m in kLearningModules) {
      expect(gates[m.id]!.unlocked, m.initiallyUnlocked, reason: m.id);
    }
    // The chain is real: something is actually gated.
    expect(gates.values.where((g) => !g.unlocked), isNotEmpty);
    final measures = gates['measures']!;
    expect(measures.requires!.id, 'note_reading');
    expect(measures.needed, kModuleUnlockTracked);
    expect(measures.fraction, 0);
  });

  test('progress in the previous module fills the gate, then opens it', () {
    var seen = kModuleUnlockTracked ~/ 2;
    int tracked(String id) => id == 'note_reading' ? seen : 0;

    var gate = moduleUnlocks(tracked)['measures']!;
    expect(gate.unlocked, isFalse);
    expect(gate.tracked, seen);
    expect(gate.fraction, closeTo(0.5, 0.01));

    seen = kModuleUnlockTracked + 10;
    gate = moduleUnlocks(tracked)['measures']!;
    expect(gate.unlocked, isTrue);
    expect(gate.fraction, 1);
    // Only the NEXT link opens — the one after it has its own gate.
    expect(moduleUnlocks(tracked)['scales']!.unlocked, isFalse);
  });

  test('the debug switch opens everything', () {
    final gates = moduleUnlocks((_) => 0, unlockAll: true);
    expect(gates.values.every((g) => g.unlocked), isTrue);
  });
}
