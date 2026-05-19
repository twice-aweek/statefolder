import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models.dart';
import 'excel_service.dart';

class SummaryScreen extends StatelessWidget {
  final List<TaskEntry> entries;
  final String projectName;
  const SummaryScreen({
    super.key,
    required this.entries,
    this.projectName = '',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          projectName.isNotEmpty ? 'Сводка: $projectName' : 'Сводка по проекту',
        ),
        backgroundColor: const Color.fromARGB(255, 50, 50, 50),
        foregroundColor: const Color.fromARGB(255, 248, 220, 255),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Выгрузить в Excel',
            onPressed: () => _exportSummary(context),
          ),
        ],
      ),
      body: entries.isEmpty
          ? const Center(
              child: Text(
                'Нет данных',
                style: TextStyle(color: Colors.white38, fontSize: 16),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOverallStats(),
                  const SizedBox(height: 24),
                  _buildBarChart(),
                  const SizedBox(height: 24),
                  _sectionTitle('По исполнителям'),
                  const SizedBox(height: 8),
                  _buildPersonTable(),
                  const SizedBox(height: 24),
                  _sectionTitle('По задачам'),
                  const SizedBox(height: 8),
                  _buildTaskTable(),
                  const SizedBox(height: 24),
                  _sectionTitle('Все записи'),
                  const SizedBox(height: 8),
                  _buildFullTable(),
                ],
              ),
            ),
    );
  }

  // ── Общая статистика ──
  Widget _buildOverallStats() {
    final total = entries.length;
    final early = entries.where((e) => e.deltaDays < 0).length;
    final onTime = entries.where((e) => e.deltaDays == 0).length;
    final late_ = entries.where((e) => e.deltaDays > 0).length;
    final avgDelta = entries.isEmpty
        ? 0.0
        : entries.map((e) => e.deltaDays).reduce((a, b) => a + b) / total;
    final maxLate = entries.isEmpty
        ? 0
        : entries.map((e) => e.deltaDays).reduce((a, b) => a > b ? a : b);
    final maxEarly = entries.isEmpty
        ? 0
        : entries.map((e) => e.deltaDays).reduce((a, b) => a < b ? a : b);

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _statCard('Всего задач', '$total', Colors.white70, Icons.assignment),
        _statCard(
          'Раньше срока',
          '$early',
          Colors.greenAccent,
          Icons.check_circle_outline,
        ),
        _statCard('В срок', '$onTime', Colors.amberAccent, Icons.access_time),
        _statCard('Опоздание', '$late_', Colors.redAccent, Icons.warning_amber),
        _statCard(
          'Среднее \u0394',
          '${avgDelta.toStringAsFixed(1)} дн.',
          Colors.white70,
          Icons.analytics,
        ),
        _statCard(
          'Макс. опоздание',
          '$maxLate дн.',
          Colors.redAccent,
          Icons.trending_up,
        ),
        _statCard(
          'Макс. опережение',
          '${maxEarly.abs()} дн.',
          Colors.greenAccent,
          Icons.trending_down,
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, Color color, IconData icon) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 40, 40, 45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ── Горизонтальный Bar chart по исполнителям ──
  Widget _buildBarChart() {
    final byPerson = <String, List<TaskEntry>>{};
    for (final e in entries) {
      byPerson.putIfAbsent(e.surname, () => []).add(e);
    }
    final sortedNames = byPerson.keys.toList()..sort((a, b) => a.compareTo(b));

    final maxAbsDelta = entries
        .map((e) => e.deltaDays.abs())
        .fold(1, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 35, 35, 40),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Среднее отклонение по исполнителям'),
          const SizedBox(height: 12),
          for (final name in sortedNames) ...[
            _barRow(name, byPerson[name]!, maxAbsDelta),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          // Легенда
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendDot(Colors.greenAccent, 'Раньше'),
              const SizedBox(width: 16),
              _legendDot(Colors.amberAccent, 'В срок'),
              const SizedBox(width: 16),
              _legendDot(Colors.redAccent, 'Опоздание'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _barRow(String name, List<TaskEntry> tasks, int maxAbsDelta) {
    final avg =
        tasks.map((e) => e.deltaDays).reduce((a, b) => a + b) / tasks.length;
    final color = avg > 0.5
        ? Colors.redAccent
        : avg < -0.5
        ? Colors.greenAccent
        : Colors.amberAccent;
    final fraction = maxAbsDelta == 0 ? 0.0 : avg.abs() / maxAbsDelta;

    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            name,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final barWidth = constraints.maxWidth * fraction.clamp(0.02, 1.0);
              return Stack(
                children: [
                  Container(
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  Container(
                    height: 22,
                    width: barWidth,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 70,
          child: Text(
            '${avg >= 0 ? '+' : ''}${avg.toStringAsFixed(1)} дн.',
            style: TextStyle(color: color, fontSize: 12),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _legendDot(Color c, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }

  // ── Таблица по исполнителям ──
  Widget _buildPersonTable() {
    final byPerson = <String, List<TaskEntry>>{};
    for (final e in entries) {
      byPerson.putIfAbsent(e.surname, () => []).add(e);
    }

    return _styledTable(
      columns: const [
        'Исполнитель',
        'Задач',
        'В срок',
        'Опозд.',
        'Раньше',
        'Сред. \u0394',
      ],
      rows: byPerson.entries.map((kv) {
        final name = kv.key;
        final tasks = kv.value;
        final onTime = tasks.where((e) => e.deltaDays == 0).length;
        final late_ = tasks.where((e) => e.deltaDays > 0).length;
        final early = tasks.where((e) => e.deltaDays < 0).length;
        final avg =
            tasks.map((e) => e.deltaDays).reduce((a, b) => a + b) /
            tasks.length;
        return [
          name,
          '${tasks.length}',
          '$onTime',
          '$late_',
          '$early',
          avg.toStringAsFixed(1),
        ];
      }).toList(),
    );
  }

  // ── Таблица по задачам ──
  Widget _buildTaskTable() {
    final byTask = <String, List<TaskEntry>>{};
    for (final e in entries) {
      byTask.putIfAbsent(e.task, () => []).add(e);
    }

    return _styledTable(
      columns: const [
        'Задача',
        'Исполн.',
        'В срок',
        'Опозд.',
        'Раньше',
        'Сред. \u0394',
      ],
      rows: byTask.entries.map((kv) {
        final task = kv.key;
        final tasks = kv.value;
        final onTime = tasks.where((e) => e.deltaDays == 0).length;
        final late_ = tasks.where((e) => e.deltaDays > 0).length;
        final early = tasks.where((e) => e.deltaDays < 0).length;
        final avg =
            tasks.map((e) => e.deltaDays).reduce((a, b) => a + b) /
            tasks.length;
        return [
          task,
          '${tasks.length}',
          '$onTime',
          '$late_',
          '$early',
          avg.toStringAsFixed(1),
        ];
      }).toList(),
    );
  }

  // ── Полная таблица всех записей ──
  Widget _buildFullTable() {
    final df = DateFormat('dd.MM.yyyy');
    return _styledTable(
      columns: const [
        'Задача',
        'Исполнитель',
        'Дедлайн',
        'Сдано',
        '\u0394 дней',
      ],
      rows: entries.map((e) {
        return [
          e.task,
          e.surname,
          df.format(e.deadline),
          df.format(e.completionDate),
          '${e.deltaDays > 0 ? '+' : ''}${e.deltaDays}',
        ];
      }).toList(),
    );
  }

  Widget _styledTable({
    required List<String> columns,
    required List<List<String>> rows,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 35, 35, 40),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            const Color.fromARGB(255, 50, 50, 60),
          ),
          dataRowColor: WidgetStateProperty.all(Colors.transparent),
          columns: columns
              .map(
                (c) => DataColumn(
                  label: Text(
                    c,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
              .toList(),
          rows: rows
              .map(
                (r) => DataRow(
                  cells: r.asMap().entries.map((cell) {
                    final isLast = cell.key == r.length - 1;
                    Color textColor = Colors.white60;
                    if (isLast && columns.last.contains('\u0394')) {
                      final val = double.tryParse(cell.value) ?? 0;
                      textColor = val > 0
                          ? Colors.redAccent
                          : val < 0
                          ? Colors.greenAccent
                          : Colors.amberAccent;
                    }
                    return DataCell(
                      Text(
                        cell.value,
                        style: TextStyle(color: textColor, fontSize: 12),
                      ),
                    );
                  }).toList(),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  // ── Выгрузка в Excel ──
  Future<void> _exportSummary(BuildContext context) async {
    try {
      final path = await ExcelService.exportSummary(entries, projectName);
      if (path == null) return;
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Сводка сохранена: $path')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }
}
