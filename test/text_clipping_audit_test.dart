// App-wide audit for text that is CUT OFF without saying so.
//
// `layout_audit_test.dart` catches RenderFlex overflows. This catches the class
// it is structurally blind to, and the distinction is the whole point:
//
//   * an OVERFLOW is a widget asking for more room than it was given, and
//     Flutter reports it as an exception — so a test can catch it by pumping;
//   * CLIPPING is a widget being given less room than it laid out and having
//     the excess quietly painted away. Nothing is thrown, because clipping is
//     exactly what `Flexible` + `maxLines` inside a `Clip.antiAlias` ancestor
//     was ASKED to do. To a user it reads as "Fill the measure so" — a sentence
//     that stops mid-word with no ellipsis and no hint there is more.
//
// The home module cards shipped like that until someone LOOKED at the app, and
// no test could have found it. So the invariant has to be stated directly: no
// paragraph may lay out taller than the box it must paint inside.
//
// ⚠️ Ellipsis is FINE and must not be flagged. `didExceedMaxLines` means the
// text truncated VISIBLY, which is the designed behaviour — the audit only
// cares about height that gets silently cut.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/game_registry.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The narrowest supported phone — where text runs out of room if it is going
/// to. German because it is materially longer than English and is where this
/// class of bug actually bites.
const _size = Size(375, 667);

Widget _wrap(Widget child, Locale locale) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProvider(
          create: (_) => SriService(getNow: () => DateTime(2026, 8, 2)),
        ),
        Provider<AudioService>(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => ProgressService()),
        ChangeNotifierProvider(create: (_) => UserSongsService()),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('de')],
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: child,
        ),
      ),
    );

/// Every laid-out paragraph whose height exceeds the box it was given.
///
/// Walks the RENDER tree, not the widget tree: the question is about painted
/// geometry, and a `Text` widget cannot tell you whether it got sliced.
List<String> _clipped(WidgetTester tester) {
  final bad = <String>[];
  void visit(RenderObject node) {
    if (node is RenderParagraph) {
      final allowed = node.constraints.maxHeight;
      // ⚠️ Compare the height the paragraph WANTS, not the height it got.
      // A RenderBox is always sized WITHIN its constraints, so
      // `size.height > constraints.maxHeight` can never be true — a check
      // written that way silently never fires, and the audit passes vacuously.
      // `getMaxIntrinsicHeight` is what the text needs at this width (already
      // limited by its own maxLines), so exceeding the box is exactly the
      // "laid out taller than it can paint" condition.
      //
      // A 1px tolerance keeps sub-pixel rounding out of the findings.
      // Nothing to lose: an empty paragraph, or one painted at zero height
      // (collapsed, offstage, or mid-animation) is not text being cut off —
      // it is text that is not on screen at all.
      if (node.text.toPlainText().trim().isEmpty) return;
      if (!allowed.isFinite || node.size.width <= 0 || node.size.height <= 0) {
        return;
      }
      final wanted = node.getMaxIntrinsicHeight(node.size.width);
      // Three conditions, and all three are needed to avoid crying wolf:
      //   * the paragraph wants more height than the box allows;
      //   * the box it was actually PAINTED into is shorter than that (a
      //     constraint alone proves nothing — the widget may still have been
      //     given all the room it needed);
      //   * and it loses at least a whole line, so sub-pixel and half-line
      //     rounding do not drown the real findings.
      final lost = wanted - node.size.height;
      final lineish = wanted / (node.maxLines ?? 1).clamp(1, 8);
      if (wanted > allowed + 1.0 && lost > 1.0 && lost >= lineish * 0.9) {
        final text = node.text.toPlainText().replaceAll('\n', ' ');
        bad.add(
          '"${text.length > 44 ? '${text.substring(0, 44)}…' : text}" '
          '(needs ${wanted.toStringAsFixed(0)}px, '
          'has ${allowed.toStringAsFixed(0)}px)',
        );
      }
    }
    node.visitChildren(visit);
  }

  final root = tester.binding.rootElement?.renderObject;
  if (root != null) visit(root);
  return bad;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ⚠️ THE AUDIT MUST PROVE IT CAN SEE THE BUG, or "0 findings" means nothing.
  //
  // This matters more here than for the overflow audit, because the detector
  // only fires on text inside a HEIGHT-BOUNDED box: `RenderParagraph.constraints
  // .maxHeight` is `infinity` for text in an ordinary column, and unbounded text
  // that is too tall OVERFLOWS (a different audit's job) rather than being
  // clipped. Shrinking the surface therefore does NOT produce findings — which
  // is exactly how a vacuous audit looks like a passing one.
  testWidgets('the detector finds a known-bad layout', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(_size);
    await tester.pumpWidget(
      _wrap(
        const Center(
          // The exact shape the home cards had: a clipping ancestor, a bounded
          // box, and a Text asking for more lines than fit.
          child: SizedBox(
            height: 30,
            width: 200,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Flexible(
                    child: Text(
                      'A subtitle long enough to need two lines of room',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Locale('en'),
      ),
    );
    await tester.pump();
    tester.takeException();
    expect(
      _clipped(tester),
      isNotEmpty,
      reason: 'the audit cannot see the very bug it exists to find',
    );
  });

  testWidgets('no screen silently slices its text (EN + DE, 375x667)',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(_size);

    final findings = <String>[];
    final games = kGamesByModule.values.expand((g) => g).toList();

    for (final locale in const [Locale('en'), Locale('de')]) {
      for (final g in games) {
        await tester.pumpWidget(_wrap(Builder(builder: g.builder), locale));
        // Two frames: some screens only reveal their text after a post-frame
        // rebuild (auto-play, async load).
        for (var frame = 0; frame < 2; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        // Drain any exception so an unrelated overflow does not fail THIS
        // audit — that is `layout_audit_test`'s job, and two audits reporting
        // the same thing makes both harder to read.
        tester.takeException();
        for (final f in _clipped(tester)) {
          findings.add('${g.id} [${locale.languageCode}]: $f');
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      }
    }

    // ignore: avoid_print
    print('=== TEXT CLIPPING: ${findings.length} findings ===');
    for (final f in findings) {
      // ignore: avoid_print
      print('CLIPPED $f');
    }

    expect(
      findings,
      isEmpty,
      reason: 'text laid out taller than its box, so the excess is silently '
          'painted away:\n${findings.join('\n')}',
    );
  });
}
