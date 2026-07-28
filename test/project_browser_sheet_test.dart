// WS-W6 slice 1 — the projects browser, from the GUI.
//
// `project_store_test` proves a project survives being written and read. This
// proves a player can actually get at that: save the thing they are working on,
// see it in a list tomorrow, and open it back into the app.
//
// The behaviours worth pinning here are the destructive ones. Opening REPLACES
// what is loaded and deleting is not undoable, so both ask first — but only
// when there is something to lose, because a confirmation that appears every
// time stops being read, and then it is not protecting anything.

import 'package:comet_beat/core/audio/loop_engine.dart' show GrooveSpec;
import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/project/project.dart';
import 'package:comet_beat/core/services/project_service.dart';
import 'package:comet_beat/core/services/project_store.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/project_browser_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Project _project({String name = 'Song', String trackId = 'loop-1'}) => Project(
      name: name,
      tracks: [
        ProjectTrack(
          id: trackId,
          kind: AppMode.loop,
          document: const GrooveSpec(enabled: {'drums'}, tempoBpm: 111),
        ),
      ],
    );

/// Mounts a button that raises the sheet, and returns the service it drives.
Future<ProjectService> _open(
  WidgetTester tester, {
  required ProjectStore store,
  ProjectService? service,
}) async {
  final svc = service ?? ProjectService();
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: const Key('raise'),
            onPressed: () =>
                showProjectBrowserSheet(context, service: svc, store: store),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('raise')));
  await tester.pumpAndSettle();
  return svc;
}

Future<ProjectStore> _store() async =>
    ProjectStore(await SharedPreferences.getInstance());

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('an empty store says so rather than showing a blank list',
      (tester) async {
    await _open(tester, store: await _store());
    expect(find.byKey(const Key('project-save')), findsOneWidget);
    expect(find.textContaining('No saved projects'), findsOneWidget);
  });

  testWidgets('saving the current project puts it in the list', (tester) async {
    final store = await _store();
    final service = ProjectService(project: _project());
    await _open(tester, store: store, service: service);

    await tester.tap(find.byKey(const Key('project-save')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('project-name-field')),
      'Take 1',
    );
    await tester.tap(find.byKey(const Key('project-name-ok')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('project-row-Take 1')), findsOneWidget);
    expect(store.find('Take 1'), isNotNull);
    expect(
      service.name,
      'Take 1',
      reason: 'the project takes the name it was saved under, so the next '
          'save offers it rather than "Untitled"',
    );
  });

  testWidgets('opening one loads it into the app', (tester) async {
    final store = await _store();
    await store.save('Saved', _project(trackId: 'loop-9'));
    // An EMPTY project is not work, so opening must not stop to ask.
    final service = await _open(tester, store: store);

    await tester.tap(find.byKey(const Key('project-row-Saved')));
    await tester.pumpAndSettle();

    expect(service.tracks.single.id, 'loop-9');
    final groove = service.tracks.single.document! as GrooveSpec;
    expect(groove.tempoBpm, 111);
    expect(
      find.byKey(const Key('project-row-Saved')),
      findsNothing,
      reason: 'the sheet closes on open',
    );
  });

  testWidgets('opening over UNSAVED work asks first', (tester) async {
    final store = await _store();
    await store.save('Saved', _project(trackId: 'loop-9'));
    final service = await _open(
      tester,
      store: store,
      service: ProjectService(project: _project(trackId: 'in-progress')),
    );

    await tester.tap(find.byKey(const Key('project-row-Saved')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project-confirm-yes')), findsOneWidget);

    await tester.tap(find.byKey(const Key('project-confirm-no')));
    await tester.pumpAndSettle();
    expect(
      service.tracks.single.id,
      'in-progress',
      reason: 'saying no must change nothing',
    );

    await tester.tap(find.byKey(const Key('project-row-Saved')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('project-confirm-yes')));
    await tester.pumpAndSettle();
    expect(service.tracks.single.id, 'loop-9');
  });

  testWidgets('deleting asks first, and no means no', (tester) async {
    final store = await _store();
    await store.save('Doomed', _project());
    await _open(tester, store: store);

    await tester.tap(find.byKey(const Key('project-delete-Doomed')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('project-confirm-no')));
    await tester.pumpAndSettle();
    expect(store.find('Doomed'), isNotNull);

    await tester.tap(find.byKey(const Key('project-delete-Doomed')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('project-confirm-yes')));
    await tester.pumpAndSettle();
    expect(store.find('Doomed'), isNull);
    expect(find.byKey(const Key('project-row-Doomed')), findsNothing);
  });

  testWidgets('renaming works, and a clash is reported not swallowed',
      (tester) async {
    final store = await _store();
    await store.save('one', _project());
    await store.save('two', _project());
    await _open(tester, store: store);

    // A free name: it takes.
    await tester.tap(find.byKey(const Key('project-rename-one')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('project-name-field')),
      'three',
    );
    await tester.tap(find.byKey(const Key('project-name-ok')));
    await tester.pumpAndSettle();
    expect(store.find('three'), isNotNull);
    expect(store.find('one'), isNull);

    // A taken name: the store refuses rather than overwriting, and the sheet
    // says so instead of appearing to do nothing.
    await tester.tap(find.byKey(const Key('project-rename-three')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('project-name-field')), 'two');
    await tester.tap(find.byKey(const Key('project-name-ok')));
    await tester.pumpAndSettle();
    expect(find.textContaining('already taken'), findsOneWidget);
    expect(store.find('three'), isNotNull, reason: 'nothing was lost');
    expect(store.find('two'), isNotNull);
  });

  testWidgets('a project this build cannot read reports instead of blanking',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'projects_v1': '[{"name":"future","at":1,"p":"{\\"v\\":999}"}]',
    });
    final store = await _store();
    final service = await _open(tester, store: store);

    expect(find.byKey(const Key('project-row-future')), findsOneWidget);
    await tester.tap(find.byKey(const Key('project-row-future')));
    await tester.pumpAndSettle();
    expect(find.textContaining("couldn't open"), findsOneWidget);
    expect(service.tracks, isEmpty, reason: 'nothing was loaded over');
  });
}
