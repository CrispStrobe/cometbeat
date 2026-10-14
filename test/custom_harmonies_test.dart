// Loop Studio's custom-harmony list, without the screen.
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/features/games/composition/custom_progressions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('added harmonies get unique ids and are saved', () async {
    final h = CustomHarmonies();
    await h.load();
    final a = h.add(const [ChordDegree.i, ChordDegree.v]);
    final b = h.add(const [ChordDegree.iv, ChordDegree.i]);
    expect(a.id, isNot(b.id));
    expect(h.items, [a, b]);
    await h.saved;

    final again = CustomHarmonies();
    await again.load();
    expect(again.items.map((p) => p.degrees), [a.degrees, b.degrees]);
    // Loaded ids and new ids can never collide.
    final c = again.add(const [ChordDegree.v, ChordDegree.i]);
    expect(again.items.map((p) => p.id).toSet(), hasLength(3));
    expect(c.id, startsWith('custom-new-'));
  });

  test('removing one saves the rest', () async {
    final h = CustomHarmonies();
    await h.load();
    final a = h.add(const [ChordDegree.i, ChordDegree.v]);
    final b = h.add(const [ChordDegree.iv, ChordDegree.i]);
    h.remove(a.id);
    expect(h.items, [b]);
    await h.saved;
    final again = CustomHarmonies();
    await again.load();
    expect(again.items.single.degrees, b.degrees);
  });

  test('a harmony added before the saved ones load is kept', () async {
    final first = CustomHarmonies();
    await first.load();
    first.add(const [ChordDegree.i, ChordDegree.iv]);
    await first.saved;

    final h = CustomHarmonies();
    final early = h.add(const [ChordDegree.v, ChordDegree.i]);
    await h.load();
    expect(h.items.map((p) => p.degrees), [
      const [ChordDegree.i, ChordDegree.iv], // the stored one survived
      early.degrees,
    ]);
    await h.saved;
    final again = CustomHarmonies();
    await again.load();
    expect(again.items, hasLength(2));
  });
}
