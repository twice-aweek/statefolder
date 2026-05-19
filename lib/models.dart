class TaskEntry {
  String task;
  String surname;
  DateTime deadline;
  DateTime completionDate;

  TaskEntry({
    required this.task,
    required this.surname,
    required this.deadline,
    required this.completionDate,
  });

  /// Дельта в днях: completionDate - deadline.
  /// Положительное = опоздание, отрицательное = раньше срока.
  int get deltaDays => completionDate.difference(deadline).inDays;

  Map<String, dynamic> toJson() {
    return {
      'task': task,
      'surname': surname,
      'deadline': deadline.toIso8601String(),
      'completionDate': completionDate.toIso8601String(),
    };
  }

  factory TaskEntry.fromJson(Map<String, dynamic> json) {
    return TaskEntry(
      task: (json['task'] as String?)?.trim() ?? '',
      surname: (json['surname'] as String?)?.trim() ?? '',
      deadline: _parseDate(json['deadline']),
      completionDate: _parseDate(json['completionDate']),
    );
  }

  static DateTime _parseDate(Object? value) {
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw const FormatException('Некорректная дата записи');
  }
}
