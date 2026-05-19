import 'package:flutter/material.dart';
import 'models.dart';
import 'project_model.dart';
import 'excel_service.dart';
import 'chart_screen.dart';

class DataEntryScreen extends StatefulWidget {
  final String projectName;
  final List<TaskEntry> initialEntries;
  final List<Project>? projects;
  final int initialProjectIndex;
  final ValueChanged<int>? onProjectSelected;
  final int Function()? onProjectAdded;
  final void Function(List<TaskEntry>)? onEntriesChanged;
  final void Function(List<TaskEntry>)? onEntriesSaved;
  const DataEntryScreen({
    super.key,
    this.projectName = '',
    this.initialEntries = const [],
    this.projects,
    this.initialProjectIndex = 0,
    this.onProjectSelected,
    this.onProjectAdded,
    this.onEntriesChanged,
    this.onEntriesSaved,
  });

  @override
  State<DataEntryScreen> createState() => _DataEntryScreenState();
}

class _DataEntryScreenState extends State<DataEntryScreen> {
  late final List<TaskEntry> _entries;
  final _taskController = TextEditingController();
  final _surnameController = TextEditingController();
  DateTime? _deadline;
  DateTime? _completionDate;

  @override
  void initState() {
    super.initState();
    _entries = List<TaskEntry>.from(widget.initialEntries);
  }

  @override
  void dispose() {
    _taskController.dispose();
    _surnameController.dispose();
    super.dispose();
  }

  void _notifyEntriesChanged() {
    widget.onEntriesChanged?.call(List<TaskEntry>.from(_entries));
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white38),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color.fromARGB(255, 217, 0, 255)),
      ),
    );
  }

  Future<DateTime?> _pickDate(BuildContext context, DateTime? initial) async {
    return showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color.fromARGB(255, 217, 0, 255),
              surface: Color.fromARGB(255, 40, 40, 40),
            ),
          ),
          child: child!,
        );
      },
    );
  }

  String _formatDate(DateTime? d) {
    if (d == null) return 'Не выбрано';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  void _addEntry() {
    if (_taskController.text.isEmpty ||
        _surnameController.text.isEmpty ||
        _deadline == null ||
        _completionDate == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Заполните все поля')));
      return;
    }

    setState(() {
      _entries.add(
        TaskEntry(
          task: _taskController.text.trim(),
          surname: _surnameController.text.trim(),
          deadline: _deadline!,
          completionDate: _completionDate!,
        ),
      );
      _taskController.clear();
      _surnameController.clear();
      _deadline = null;
      _completionDate = null;
    });
    _notifyEntriesChanged();
  }

  Future<void> _buildChart() async {
    if (_entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавьте хотя бы одну запись')),
      );
      return;
    }

    // Сохраняем в Excel
    try {
      final path = await ExcelService.saveToExcel(_entries);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Сохранено: $path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
      }
    }

    // Передаём данные обратно в проект
    final entries = List<TaskEntry>.from(_entries);
    widget.onEntriesChanged?.call(entries);
    widget.onEntriesSaved?.call(entries);

    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChartScreen(
            entries: entries,
            projectName: widget.projectName,
            projects: widget.projects,
            initialProjectIndex: widget.initialProjectIndex,
            onProjectSelected: widget.onProjectSelected,
            onProjectAdded: widget.onProjectAdded,
          ),
        ),
      );
    }
  }

  Widget _dateButton(String label, DateTime? value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white38),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, color: Colors.white70, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$label: ${_formatDate(value)}',
                style: TextStyle(
                  color: value != null ? Colors.white : Colors.white70,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ввод данных'),
        backgroundColor: const Color.fromARGB(255, 50, 50, 50),
        foregroundColor: const Color.fromARGB(255, 248, 220, 255),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Форма ввода
            TextField(
              controller: _taskController,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Задача'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _surnameController,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Фамилия'),
            ),
            const SizedBox(height: 12),
            _dateButton('Дедлайн', _deadline, () async {
              final d = await _pickDate(context, _deadline);
              if (d != null) setState(() => _deadline = d);
            }),
            const SizedBox(height: 12),
            _dateButton('Дата завершения', _completionDate, () async {
              final d = await _pickDate(context, _completionDate);
              if (d != null) setState(() => _completionDate = d);
            }),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _gradientButton(
                    icon: Icons.add,
                    label: 'Добавить запись',
                    onPressed: _addEntry,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _gradientButton(
                    icon: Icons.show_chart,
                    label: 'Построить график',
                    onPressed: _buildChart,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Таблица добавленных записей
            Expanded(
              child: _entries.isEmpty
                  ? const Center(
                      child: Text(
                        'Нет записей',
                        style: TextStyle(color: Colors.white38),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _entries.length,
                      itemBuilder: (context, i) {
                        final e = _entries[i];
                        return Card(
                          color: const Color.fromARGB(255, 45, 45, 45),
                          child: ListTile(
                            title: Text(
                              '${e.task} — ${e.surname}',
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              'Дедлайн: ${_formatDate(e.deadline)} | '
                              'Завершено: ${_formatDate(e.completionDate)} | '
                              'Δ: ${e.deltaDays} дн.',
                              style: const TextStyle(color: Colors.white54),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete,
                                color: Colors.white38,
                              ),
                              onPressed: () {
                                setState(() => _entries.removeAt(i));
                                _notifyEntriesChanged();
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gradientButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: [
            Color.fromARGB(255, 140, 33, 160),
            Color.fromARGB(255, 217, 0, 255),
            Color.fromARGB(255, 101, 43, 216),
          ],
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: const Color.fromARGB(255, 248, 220, 255),
                size: 18,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color.fromARGB(255, 248, 220, 255),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
