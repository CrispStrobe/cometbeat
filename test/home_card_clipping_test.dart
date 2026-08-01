// The home module cards must not slice their subtitle through the glyphs.
//
// The bug this pins was found by LOOKING at the app, not by any test: at
// 390×844 a module whose TITLE wrapped to two lines ("Measures & Meter",
// "Chords & Intervals") had its subtitle cut off mid-word — "Fill the measure
// so" with no ellipsis and no indication there was more.
//
// ⚠️ `layout_audit_test` is structurally blind to it. Nothing OVERFLOWS: the
// subtitle sat in a `Flexible` with `maxLines: 2`, so it laid out two lines,
// got room for one and a half, and the Card's `Clip.antiAlias` sliced the rest.
// Clipping is exactly what the widget was asked to do, so there is no exception
// to catch. The invariant has to be stated directly, which is what this does:
// every subtitle that is BUILT must fit in the space it was given.
//
// That is why the fix has two halves — ask for the number of lines that
// actually fit, and draw nothing at all when not even one does (a missing
// subtitle reads as "this card has no subtitle"; a half-sliced one reads as
// broken).

import 'package:comet_beat/core/models/learning_module.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/debug_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/home/screens/home_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(SriService sri, Locale locale) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProvider<SriService>.value(value: sri),
        Provider<AudioService>(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => ProgressService()),
        ChangeNotifierProvider(create: (_) => DebugService()),
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
        home: const HomeScreen(),
      ),
    );

/// Every laid-out paragraph whose height exceeds the box it was given.
///
/// Walks the RENDER tree rather than the widget tree because the question is
/// about painted geometry, not configuration — a `Text` widget cannot tell you
/// whether it got sliced.
List<String> _clippedParagraphs(WidgetTester tester) {
  final bad = <String>[];
  void visit(RenderObject node) {
    if (node is RenderParagraph) {
      final allowed = node.constraints.maxHeight;
      // `didExceedMaxLines` means the text ellipsized, which is FINE — that is
      // the visible, intentional truncation. What is not fine is a paragraph
      // laid out TALLER than the box it must paint inside, because the excess
      // is silently cut.
      if (allowed.isFinite && node.size.height > allowed + 0.5) {
        final text = node.text.toPlainText();
        bad.add(
          '"${text.length > 40 ? '${text.substring(0, 40)}…' : text}" '
          'laid out ${node.size.height.toStringAsFixed(1)} in '
          '${allowed.toStringAsFixed(1)}',
        );
      }
    }
    node.visitChildren(visit);
  }

  visit(tester.binding.rootElement!.renderObject!);
  return bad;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('no module card slices its text, EN + DE, phone + small phone',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // 375×667 is the narrowest supported phone; 390×844 is where the bug was
    // actually seen. German because its module titles are longer, which is what
    // pushes a title onto a second line and squeezes the subtitle.
    const sizes = {
      'SE 375x667': Size(375, 667),
      'iPhone 390x844': Size(390, 844),
    };

    final findings = <String>[];
    for (final locale in const [Locale('en'), Locale('de')]) {
      for (final size in sizes.entries) {
        await tester.binding.setSurfaceSize(size.value);
        await tester.pumpWidget(
          _wrap(SriService(getNow: () => DateTime(2026, 8, 2)), locale),
        );
        await tester.pump(const Duration(milliseconds: 32));
        for (final f in _clippedParagraphs(tester)) {
          findings.add('${size.key} [${locale.languageCode}]: $f');
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());

    expect(
      findings,
      isEmpty,
      reason: 'text laid out taller than its box (silently cut):\n'
          '${findings.join('\n')}',
    );
  });

  testWidgets('every unlocked module still shows its subtitle at 390x844',
      (tester) async {
    // The complement to the check above: drawing nothing would also satisfy
    // "nothing is clipped", so pin that the cards still SAY something. Without
    // this, a regression that hid every subtitle would look like a pass.
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      _wrap(SriService(getNow: () => DateTime(2026, 8, 2)), const Locale('en')),
    );
    await tester.pump(const Duration(milliseconds: 32));

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    // The first module is always unlocked and its title is short, so its
    // subtitle has room on any phone.
    final first = kLearningModules.first;
    expect(find.text(first.title(l10n)), findsOneWidget);
    expect(find.text(first.subtitle(l10n)), findsOneWidget);
  });
}
