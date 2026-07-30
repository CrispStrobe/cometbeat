// WS-W6 slice 2 — the templates tab.
//
// Slice 1 made a project survive the app closing, and left the browser's first
// impression as an empty list with a Save button: a player who has never saved
// anything opens it and there is nothing there, so the panel reads as broken
// rather than empty. That is what these fix.
//
// The parts worth pinning are not "the list has four entries". They are:
//
//   * every template BUILDS A FRESH PROJECT — hand out a shared instance and
//     two opens edit the same object;
//   * a template that carries a groove must carry one the engine will actually
//     accept, including a tempo inside the sample-integrality set the whole
//     loop engine rests on;
//   * starting from one obeys the same confirm-only-when-there-is-work rule as
//     opening a saved project, because it destroys just as much;
//   * and every template has a NAME, which is the failure a `switch` with a
//     fallback hides — the row still renders, so nothing looks wrong.

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/project/project_templates.dart';
import 'package:comet_beat/core/services/project_service.dart';
import 'package:comet_beat/core/services/project_store.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/project_browser_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(ProjectService, ProjectStore)> _mount(
  WidgetTester tester, {
  bool withWork = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = ProjectStore(prefs);
  final service = ProjectService();
  if (withWork) {
    service.addTrack(
      kind: AppMode.loop,
      name: 'In progress',
      document: const GrooveSpec(enabled: {'bass'}),
    );
  }
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showProjectBrowserSheet(
                context,
                service: service,
                store: store,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (service, store);
}

/// Switches to the templates tab.
Future<void> _templatesTab(WidgetTester tester) async {
  await tester.tap(find.text('Templates'));
  await tester.pumpAndSettle();
}

void main() {
  group('the templates themselves', () {
    test('each build() returns a FRESH project', () {
      // A shared instance would mean two opens editing the same object. Project
      // is deeply immutable today, which makes that safe — and this is what
      // keeps it safe when it stops being.
      for (final template in kProjectTemplates) {
        final a = template.build();
        final b = template.build();
        expect(identical(a, b), isFalse, reason: template.id);
      }
    });

    test('every template is findable by its id, and an unknown one is not', () {
      for (final template in kProjectTemplates) {
        expect(projectTemplateById(template.id), isNotNull);
      }
      expect(projectTemplateById('no-such-template'), isNull);
    });

    test('ids are unique — they are used as widget keys', () {
      final ids = kProjectTemplates.map((t) => t.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('the blank one really is blank', () {
      final project = projectTemplateById('empty')!.build();
      expect(project.tracks, isEmpty);
    });

    test('the groove templates carry a GrooveSpec the engine accepts', () {
      // A template whose document the engine refuses would open to silence,
      // which looks like a broken template rather than a broken document.
      for (final id in ['beat', 'band', 'slow']) {
        final track = projectTemplateById(id)!.build().tracks.single;
        expect(track.kind, AppMode.loop, reason: id);
        final spec = track.document! as GrooveSpec;
        expect(spec.enabled, isNotEmpty, reason: id);
        final engine = LoopEngine()..applySpec(spec);
        expect(
          engine.enabled,
          spec.enabled,
          reason: '$id: the engine kept every track the template asked for',
        );
      }
    });

    test('every tempo stays in the sample-integral set', () {
      // 75/100/120 are the tempos whose eighth-steps are integral in BOTH ms
      // and samples — the invariant that keeps stems aligned and the loop seam
      // click-free. A template is exactly the kind of place a stray 90 would
      // slip in, since it looks like a harmless preset.
      for (final template in kProjectTemplates) {
        for (final track in template.build().tracks) {
          if (track.document case final GrooveSpec spec) {
            expect(
              const [75, 100, 120],
              contains(spec.tempoBpm),
              reason: template.id,
            );
          }
        }
      }
    });
  });

  group('the browser tab', () {
    testWidgets('templates are listed, and named', (tester) async {
      // The `switch` in the sheet falls back to the raw id for an unnamed
      // template, so the row still renders and nothing LOOKS wrong. This is
      // what catches a template added without an ARB entry.
      await _mount(tester);
      await _templatesTab(tester);

      for (final template in kProjectTemplates) {
        final row = find.byKey(Key('project-template-${template.id}'));
        expect(row, findsOneWidget, reason: template.id);
        expect(
          find.descendant(of: row, matching: find.text(template.id)),
          findsNothing,
          reason: '${template.id} shows its raw id — no ARB entry for it',
        );
      }
    });

    testWidgets('the projects tab is what opens first', (tester) async {
      // A returning player is the common case; templates are one tap away.
      await _mount(tester);
      expect(find.byKey(const Key('project-template-band')), findsNothing);
    });

    testWidgets('tapping one loads it, with no confirmation on an empty desk',
        (tester) async {
      final (service, _) = await _mount(tester);
      expect(service.tracks, isEmpty);

      await _templatesTab(tester);
      await tester.tap(find.byKey(const Key('project-template-band')));
      await tester.pumpAndSettle();

      expect(service.tracks, hasLength(1));
      expect(service.tracks.single.document, isA<GrooveSpec>());
      expect(
        find.byKey(const Key('project-template-band')),
        findsNothing,
        reason: 'the sheet closed behind it',
      );
    });

    testWidgets('but it ASKS when there is work to lose', (tester) async {
      // Same rule as opening a saved project, because it destroys just as much.
      final (service, _) = await _mount(tester, withWork: true);
      await _templatesTab(tester);
      await tester.tap(find.byKey(const Key('project-template-beat')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('project-confirm-yes')), findsOneWidget);
      await tester.tap(find.byKey(const Key('project-confirm-no')));
      await tester.pumpAndSettle();

      expect(
        service.tracks.single.name,
        'In progress',
        reason: 'declining kept the work',
      );
    });

    testWidgets('and accepting replaces it', (tester) async {
      final (service, _) = await _mount(tester, withWork: true);
      await _templatesTab(tester);
      await tester.tap(find.byKey(const Key('project-template-beat')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('project-confirm-yes')));
      await tester.pumpAndSettle();

      expect(service.tracks, hasLength(1));
      expect(service.tracks.single.name, isNot('In progress'));
    });

    testWidgets('the blank template clears a project that had work',
        (tester) async {
      // The one template whose whole job is to leave nothing behind — easy to
      // mistake for a no-op and skip.
      final (service, _) = await _mount(tester, withWork: true);
      await _templatesTab(tester);
      await tester.tap(find.byKey(const Key('project-template-empty')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('project-confirm-yes')));
      await tester.pumpAndSettle();

      expect(service.tracks, isEmpty);
    });

    testWidgets('switching back shows saved projects, not templates',
        (tester) async {
      final (service, store) = await _mount(tester);
      await store.save('Yesterday', service.project);
      await _templatesTab(tester);
      await tester.tap(find.text('Projects'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('project-template-band')), findsNothing);
    });
  });
}
