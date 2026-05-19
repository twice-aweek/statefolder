import 'models.dart';

class Project {
  String name;
  List<TaskEntry> entries;

  Project({required this.name, List<TaskEntry>? entries})
    : entries = entries ?? [];

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'entries': entries.map((entry) => entry.toJson()).toList(),
    };
  }

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : 'Проект',
      entries: _entriesFromJson(json['entries']),
    );
  }

  static List<TaskEntry> _entriesFromJson(Object? rawEntries) {
    if (rawEntries is! List) return [];

    final entries = <TaskEntry>[];
    for (final rawEntry in rawEntries) {
      if (rawEntry is! Map<String, dynamic>) continue;
      try {
        entries.add(TaskEntry.fromJson(rawEntry));
      } catch (_) {
        continue;
      }
    }
    return entries;
  }
}
