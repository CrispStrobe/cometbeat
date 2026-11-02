// Regression: the Progress screen showed "0 von 0" on module cards because
// items recorded under namespaces that are not module ids (reading.*, pitch.*,
// voice.* ...) never reached any card, and untouched modules had no fallback.

import 'package:comet_beat/core/models/learning_module.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/progress/screens/progress_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

int _tracked(Map<String, SkillStat> m) =>
    m.values.fold(0, (a, s) => a + s.tracked);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('aliased namespaces land on their module card', () {
    SharedPreferences.setMockInitialValues({});
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    sri.recordResponse('reading.clef.treble', true);
    sri.recordResponse('pitch.hear.asc', true);
    sri.recordResponse('voice.sing_along.x', true);
    sri.recordResponse('note_reading.treble.g4', true);
    final b = sri.getDetailedBreakdown();

    // Before the fix, only the exact-id bucket was read: 1 for note_reading
    // and 0 ("0 von 0") for scales and songs.
    expect(_tracked(moduleSkills(b, 'note_reading')), 2);
    expect(_tracked(moduleSkills(b, 'scales')), 1);
    expect(_tracked(moduleSkills(b, 'songs')), 1);
    expect(_tracked(moduleSkills(b, 'drums')), 0);
  });

  test('every alias targets a real module', () {
    final ids = kLearningModules.map((m) => m.id).toSet();
    for (final target in kSriNamespaceModule.values) {
      expect(ids, contains(target));
    }
  });
}
