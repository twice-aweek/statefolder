import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'models.dart';

class ExcelService {
  /// Экспортирует сводку проекта в Excel.
  static Future<String?> exportSummary(
    List<TaskEntry> entries,
    String projectName,
  ) async {
    final excel = Excel.createExcel();

    // ── Лист: Общая статистика ──
    final statSheet = excel['Статистика'];
    statSheet.appendRow([
      TextCellValue('Проект'),
      TextCellValue(projectName.isNotEmpty ? projectName : 'Без названия'),
    ]);
    statSheet.appendRow([
      TextCellValue('Всего задач'),
      IntCellValue(entries.length),
    ]);
    final early = entries.where((e) => e.deltaDays < 0).length;
    final onTime = entries.where((e) => e.deltaDays == 0).length;
    final late_ = entries.where((e) => e.deltaDays > 0).length;
    statSheet.appendRow([TextCellValue('Раньше срока'), IntCellValue(early)]);
    statSheet.appendRow([TextCellValue('В срок'), IntCellValue(onTime)]);
    statSheet.appendRow([TextCellValue('Опоздание'), IntCellValue(late_)]);
    if (entries.isNotEmpty) {
      final avg =
          entries.map((e) => e.deltaDays).reduce((a, b) => a + b) /
          entries.length;
      statSheet.appendRow([
        TextCellValue('Среднее Δ'),
        TextCellValue(avg.toStringAsFixed(1)),
      ]);
    }

    // ── Лист: По исполнителям ──
    final personSheet = excel['По исполнителям'];
    personSheet.appendRow([
      TextCellValue('Исполнитель'),
      TextCellValue('Задач'),
      TextCellValue('В срок'),
      TextCellValue('Опоздание'),
      TextCellValue('Раньше срока'),
      TextCellValue('Среднее Δ'),
    ]);
    final byPerson = <String, List<TaskEntry>>{};
    for (final e in entries) {
      byPerson.putIfAbsent(e.surname, () => []).add(e);
    }
    for (final kv in byPerson.entries) {
      final tasks = kv.value;
      final avg =
          tasks.map((e) => e.deltaDays).reduce((a, b) => a + b) / tasks.length;
      personSheet.appendRow([
        TextCellValue(kv.key),
        IntCellValue(tasks.length),
        IntCellValue(tasks.where((e) => e.deltaDays == 0).length),
        IntCellValue(tasks.where((e) => e.deltaDays > 0).length),
        IntCellValue(tasks.where((e) => e.deltaDays < 0).length),
        TextCellValue(avg.toStringAsFixed(1)),
      ]);
    }

    // ── Лист: Все записи ──
    final dataSheet = excel['Все записи'];
    dataSheet.appendRow([
      TextCellValue('Задача'),
      TextCellValue('Фамилия'),
      TextCellValue('Дедлайн'),
      TextCellValue('Дата завершения'),
      TextCellValue('Дельта (дни)'),
    ]);
    for (final e in entries) {
      dataSheet.appendRow([
        TextCellValue(e.task),
        TextCellValue(e.surname),
        TextCellValue(_formatDate(e.deadline)),
        TextCellValue(_formatDate(e.completionDate)),
        IntCellValue(e.deltaDays),
      ]);
    }

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final safeName = projectName.isNotEmpty
        ? projectName.replaceAll(RegExp(r'[^\w\dа-яА-ЯёЁ\s\-]'), '_')
        : 'project';

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Сохранить сводку',
      fileName: 'summary_$safeName.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (savePath == null) return null;

    final path = savePath.endsWith('.xlsx') ? savePath : '$savePath.xlsx';
    final bytes = excel.encode();
    if (bytes != null) {
      await File(path).writeAsBytes(bytes);
    }
    return path;
  }

  /// Сохраняет записи в Excel-файл рядом с исполняемым файлом.
  static Future<String> saveToExcel(List<TaskEntry> entries) async {
    final excel = Excel.createExcel();
    final sheet = excel['Данные'];

    // Заголовки
    sheet.appendRow([
      TextCellValue('Задача'),
      TextCellValue('Фамилия'),
      TextCellValue('Дедлайн'),
      TextCellValue('Дата завершения'),
      TextCellValue('Дельта (дни)'),
    ]);

    for (final e in entries) {
      sheet.appendRow([
        TextCellValue(e.task),
        TextCellValue(e.surname),
        TextCellValue(_formatDate(e.deadline)),
        TextCellValue(_formatDate(e.completionDate)),
        IntCellValue(e.deltaDays),
      ]);
    }

    // Удаляем дефолтный лист Sheet1 если он есть
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final dir = File(Platform.resolvedExecutable).parent.path;
    final path = '$dir/data.xlsx';
    final bytes = excel.encode();
    if (bytes != null) {
      await File(path).writeAsBytes(bytes);
    }
    return path;
  }

  /// Открывает Excel-файл через диалог выбора файла.
  static Future<List<TaskEntry>?> loadFromExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (result == null || result.files.isEmpty) return null;
    final filePath = result.files.first.path;
    if (filePath == null) return null;

    final bytes = await File(filePath).readAsBytes();
    final excel = Excel.decodeBytes(bytes);

    if (excel.sheets.isEmpty) return [];
    final sheet = excel.sheets.values.first;
    final entries = <TaskEntry>[];

    for (int i = 1; i < sheet.maxRows; i++) {
      try {
        final row = sheet.row(i);
        if (row.length < 4) continue;
        final task = row[0]?.value?.toString().trim() ?? '';
        final surname = row[1]?.value?.toString().trim() ?? '';
        final deadline = _parseCellDate(row[2]?.value);
        final completion = _parseCellDate(row[3]?.value);
        if (task.isEmpty || surname.isEmpty) continue;
        if (deadline == null || completion == null) continue;
        entries.add(
          TaskEntry(
            task: task,
            surname: surname,
            deadline: deadline,
            completionDate: completion,
          ),
        );
      } catch (e) {
        // ignore: avoid_print
        print('Ошибка чтения строки $i: $e');
        continue;
      }
    }
    return entries;
  }

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// Универсальный парсер дат из Excel: поддерживает DateCellValue,
  /// DateTimeCellValue, числовые серийные даты Excel и текстовые форматы.
  static DateTime? _parseCellDate(dynamic value) {
    if (value == null) return null;

    try {
      // 1. DateCellValue / DateTimeCellValue из пакета excel
      if (value is DateCellValue) {
        return DateTime(value.year, value.month, value.day);
      }
      if (value is DateTimeCellValue) {
        return value.asDateTimeLocal();
      }

      // 2. Числовая серийная дата Excel
      if (value is IntCellValue) {
        return _excelSerialToDate(value.value.toDouble());
      }
      if (value is DoubleCellValue) {
        return _excelSerialToDate(value.value);
      }
    } catch (_) {
      // если внутреннее представление не такое, как ожидаем — упадём в строковый парсинг
    }

    // 3. Строковые форматы
    final s = value.toString().trim();
    if (s.isEmpty) return null;

    // dd.MM.yyyy или dd/MM/yyyy или dd-MM-yyyy
    final dotMatch = RegExp(
      r'^(\d{1,2})[.\-/](\d{1,2})[.\-/](\d{4})',
    ).firstMatch(s);
    if (dotMatch != null) {
      return DateTime(
        int.parse(dotMatch.group(3)!),
        int.parse(dotMatch.group(2)!),
        int.parse(dotMatch.group(1)!),
      );
    }

    // ISO: yyyy-MM-dd[ HH:mm:ss[.ms]]
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;

    // Чистое число в строке (на всякий случай)
    final num = double.tryParse(s);
    if (num != null) return _excelSerialToDate(num);

    return null;
  }

  /// Excel хранит даты как кол-во дней от 1899-12-30 (с учётом бага 1900г.)
  static DateTime _excelSerialToDate(double serial) {
    final base = DateTime(1899, 12, 30);
    final days = serial.floor();
    final fracMs = ((serial - days) * 24 * 60 * 60 * 1000).round();
    return base.add(Duration(days: days, milliseconds: fracMs));
  }
}
