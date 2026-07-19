// Live-looper S0 — the pure LoopStack summing renderer.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/loop_record.dart';
import 'package:comet_beat/core/audio/loop_stack_render.dart';
import 'package:flutter_test/flutter_test.dart';

Float64List _const(double v, int n) => Float64List.fromList(List.filled(n, v));

void main() {
  test('no layers → an empty loop', () {
    expect(renderLoopStack(const []), isEmpty);
  });

  test('one layer passes through (below the limiter knee)', () {
    final layer = _const(0.1, 8);
    final out = renderLoopStack([layer]);
    expect(out, hasLength(8));
    for (final v in out) {
      expect(v, closeTo(0.1, 1e-3)); // tanh(0.1) ≈ 0.0997
    }
  });

  test('two same-length layers sum sample-for-sample', () {
    final out = renderLoopStack([_const(0.2, 4), _const(0.3, 4)], limit: false);
    for (final v in out) {
      expect(v, closeTo(0.5, 1e-12));
    }
  });

  test('a shorter layer is tiled under the longest (loop stays in phase)', () {
    // A 2-sample layer under a 6-sample layer: it repeats 3×.
    final short = Float64List.fromList([1.0, 0.0]);
    final long = _const(0.0, 6);
    final out = renderLoopStack([long, short], limit: false);
    expect(out, hasLength(6)); // the longest layer sets the loop length
    expect(out.toList(), [1.0, 0.0, 1.0, 0.0, 1.0, 0.0]);
  });

  test('loopSamples overrides the loop length', () {
    final out = renderLoopStack([_const(1.0, 3)], loopSamples: 5, limit: false);
    expect(out.toList(), [1.0, 1.0, 1.0, 1.0, 1.0]); // tiled to 5
  });

  test('the sum is soft-limited so many hot layers never clip', () {
    final out = renderLoopStack([for (var i = 0; i < 10; i++) _const(0.5, 4)]);
    for (final v in out) {
      expect(v.abs(), lessThanOrEqualTo(1.0)); // tanh keeps it in [-1, 1]
      expect(v, greaterThan(0.9)); // …but the 10× stack is loud (compressed)
    }
  });

  test('renders a LoopStack — a muted layer drops out of the mix', () {
    final stack = LoopStack<Float64List>()
      ..add(_const(0.3, 4))
      ..add(_const(0.4, 4));
    // Both active: 0.3 + 0.4 = 0.7.
    expect(
      renderLoopStack(stack.activeLayers, limit: false).first,
      closeTo(0.7, 1e-12),
    );
    stack.toggleMute(1); // mute the second layer
    expect(
      renderLoopStack(stack.activeLayers, limit: false).first,
      closeTo(0.3, 1e-12),
    );
    // Undo removes the second layer entirely — same mix, one fewer layer.
    stack.toggleMute(1);
    stack.undo();
    expect(
      renderLoopStack(stack.activeLayers, limit: false).first,
      closeTo(0.3, 1e-12),
    );
  });
}
