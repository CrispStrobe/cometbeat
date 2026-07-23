// Acceptance for the symbolic tab labeler (gated on COMET_TABLABELER_DIR +
// TAB_LABELER_FIXTURE): does the model make arrangeTab finger more like a human
// than the heuristic? Arrange each held-out GuitarSet song both ways, score each
// against the human (string,fret), and require the model to not regress. Tab is a
// preference, so this asserts a floor (model ≥ heuristic), not bit-exactness.
//
// Run: COMET_TABLABELER_DIR=<dir with tab-labeler.onnx> \
//      TAB_LABELER_FIXTURE=<acceptance.json> flutter test test/tab_labeler_accept_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:comet_beat/features/games/composition/tab_arranger.dart';
import 'package:comet_beat/features/games/composition/tab_labeler.dart';
import 'package:crisp_notation/crisp_notation.dart' show Tuning;
import 'package:flutter_test/flutter_test.dart';

int? _anchor(Map<int, int> f) {
  int? lo;
  for (final v in f.values) {
    if (v > 0 && (lo == null || v < lo)) lo = v;
  }
  return lo;
}

({int match, int total, int move}) _score(
  List<Map<int, int>> arranged,
  List<List<List<int>>> human,
) {
  var match = 0, total = 0, move = 0;
  int? prev;
  for (var c = 0; c < arranged.length; c++) {
    final a = arranged[c];
    final h = {for (final p in human[c]) (p[0], p[1])};
    for (final e in a.entries) {
      if (h.contains((e.key, e.value))) match++;
    }
    total += h.length;
    final an = _anchor(a);
    if (prev != null && an != null) move += (prev - an).abs();
    if (an != null) prev = an;
  }
  return (match: match, total: total, move: move);
}

void main() {
  final dir = Platform.environment['COMET_TABLABELER_DIR'];
  final fixture = Platform.environment['TAB_LABELER_FIXTURE'];

  test('symbolic labeler ≥ heuristic on held-out human fingering', () async {
    if (dir == null || fixture == null) {
      // Not configured — skip (keeps CI green without the weights/fixture).
      return;
    }
    final songs = (jsonDecode(File(fixture).readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    final model = await TabLabeler.load(
      store: TabLabelerModelStore(cacheDirOverride: dir),
    );
    expect(model, isNotNull, reason: 'tab-labeler.onnx must be in $dir');
    final tuning = Tuning.standardGuitar;

    var hM = 0, hT = 0, hMove = 0, mM = 0, mT = 0, mMove = 0;
    for (final s in songs) {
      final columns =
          (s['columns'] as List).map((c) => (c as List).cast<int>()).toList();
      if (columns.isEmpty) continue;
      final human = (s['human'] as List)
          .map(
            (col) => (col as List).map((p) => (p as List).cast<int>()).toList(),
          )
          .toList();
      // Heuristic (no model), then the REAL app path: the model installed as
      // TabArranger.shared, arranged with no explicit args — so it picks up
      // TabArranger.sharedSpanCost (0.5), exactly what users get.
      TabArranger.shared = null;
      final h = _score(arrangeTab(columns, tuning), human);
      TabArranger.shared = model;
      final m = _score(arrangeTab(columns, tuning), human);
      TabArranger.shared = null;
      hM += h.match;
      hT += h.total;
      hMove += h.move;
      mM += m.match;
      mT += m.total;
      mMove += m.move;
    }
    final hAgree = hM / hT * 100, mAgree = mM / mT * 100;
    // ignore: avoid_print
    print('held-out songs ${songs.length}, positions $hT\n'
        'HEURISTIC agreement ${hAgree.toStringAsFixed(2)}%  movement $hMove\n'
        'MODEL     agreement ${mAgree.toStringAsFixed(2)}%  movement $mMove\n'
        'Δ agreement ${(mAgree - hAgree).toStringAsFixed(2)} pts, '
        'Δ movement ${mMove - hMove}');
    expect(
      mAgree,
      greaterThanOrEqualTo(hAgree),
      reason: 'the model should not finger worse than the heuristic',
    );
  });
}
