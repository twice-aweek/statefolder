import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'project_model.dart';

class StorageService {
  static const _fileName = 'statefolder_state.json';
  static Directory? documentsDirectoryOverride;

  static List<Project> defaultProjects() => [Project(name: 'Проект 1')];

  static Future<List<Project>> loadProjects() async {
    try {
      final file = await _stateFile();
      if (!await file.exists()) {
        return defaultProjects();
      }

      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return defaultProjects();
      }

      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        return defaultProjects();
      }

      final rawProjects = decoded['projects'];
      if (rawProjects is! List) {
        return defaultProjects();
      }

      final projects = <Project>[];
      for (final rawProject in rawProjects) {
        if (rawProject is! Map<String, dynamic>) continue;
        try {
          projects.add(Project.fromJson(rawProject));
        } catch (_) {
          continue;
        }
      }

      return projects.isEmpty ? defaultProjects() : projects;
    } catch (_) {
      return defaultProjects();
    }
  }

  static Future<void> saveProjects(List<Project> projects) async {
    final file = await _stateFile();
    await file.parent.create(recursive: true);
    final data = {
      'version': 1,
      'projects': projects.map((project) => project.toJson()).toList(),
    };
    await file.writeAsString(jsonEncode(data), flush: true);
  }

  static Future<File> _stateFile() async {
    final directory =
        documentsDirectoryOverride ?? await getApplicationDocumentsDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }
}
