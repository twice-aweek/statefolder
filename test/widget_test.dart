import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:statefolder/chart_screen.dart';
import 'package:statefolder/main.dart';
import 'package:statefolder/models.dart';
import 'package:statefolder/project_model.dart';
import 'package:statefolder/storage_service.dart';

void main() {
  late Directory tempDirectory;

  setUp(() {
    tempDirectory = Directory.systemTemp.createTempSync('statefolder_test_');
    StorageService.documentsDirectoryOverride = tempDirectory;
  });

  tearDown(() {
    StorageService.documentsDirectoryOverride = null;
    if (tempDirectory.existsSync()) {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
  }

  test('Project state serializes and restores entries', () {
    final project = Project(
      name: 'Проект 1',
      entries: [
        TaskEntry(
          task: 'Задача',
          surname: 'Иванов',
          deadline: DateTime(2026, 5, 20),
          completionDate: DateTime(2026, 5, 21),
        ),
      ],
    );

    final restored = Project.fromJson(project.toJson());

    expect(restored.name, 'Проект 1');
    expect(restored.entries, hasLength(1));
    expect(restored.entries.single.task, 'Задача');
    expect(restored.entries.single.surname, 'Иванов');
    expect(restored.entries.single.deltaDays, 1);
  });

  testWidgets('Home screen shows project actions', (WidgetTester tester) async {
    await pumpApp(tester);

    expect(find.text('Проект 1'), findsWidgets);
    expect(find.text('Создать'), findsOneWidget);
    expect(find.text('Открыть из Excel'), findsOneWidget);
    expect(find.byTooltip('Новый проект'), findsOneWidget);
  });

  testWidgets('Project tabs can be added', (WidgetTester tester) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Новый проект'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Проект 2'), findsWidgets);
    expect(find.byIcon(Icons.close), findsNWidgets(2));
  });

  testWidgets('Project tabs switch the current project', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Новый проект'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('currentProjectName')))
          .data,
      'Проект 2',
    );

    await tester.tap(find.text('Проект 1').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('currentProjectName')))
          .data,
      'Проект 1',
    );
  });

  testWidgets('Chart project tabs can create a new project', (
    WidgetTester tester,
  ) async {
    final projects = [Project(name: 'Проект 1')];

    await tester.pumpWidget(
      MaterialApp(
        home: ChartScreen(
          entries: const [],
          projectName: 'Проект 1',
          projects: projects,
          onProjectAdded: () {
            projects.add(Project(name: 'Проект ${projects.length + 1}'));
            return projects.length - 1;
          },
        ),
      ),
    );

    expect(find.text('Проект 1'), findsWidgets);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    expect(find.text('Проект 2'), findsWidgets);
    expect(projects, hasLength(2));
  });
}
