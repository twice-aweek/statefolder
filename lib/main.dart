import 'dart:async';

import 'package:flutter/material.dart';
import 'project_model.dart';
import 'models.dart';
import 'data_entry_screen.dart';
import 'excel_service.dart';
import 'chart_screen.dart';
import 'storage_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StateFolder',
      theme: ThemeData(
        scaffoldBackgroundColor: const Color.fromARGB(255, 30, 30, 30),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final List<Project> _projects = StorageService.defaultProjects();
  late TabController _tabController;
  int _currentIndex = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = _createTabController();
    unawaited(_loadProjects());
  }

  TabController _createTabController() {
    final controller = TabController(
      length: _projects.length,
      vsync: this,
      initialIndex: _safeIndex(_currentIndex),
    );
    controller.addListener(_handleTabChanged);
    return controller;
  }

  int _safeIndex(int index) {
    if (_projects.isEmpty) return 0;
    return index.clamp(0, _projects.length - 1).toInt();
  }

  void _handleTabChanged() {
    final nextIndex = _safeIndex(_tabController.index);
    if (_currentIndex != nextIndex) {
      setState(() => _currentIndex = nextIndex);
    }
  }

  void _selectProject(int index) {
    final nextIndex = _safeIndex(index);
    if (_currentIndex != nextIndex) {
      setState(() => _currentIndex = nextIndex);
    }
    if (_tabController.index != nextIndex) {
      _tabController.animateTo(nextIndex);
    }
  }

  Future<void> _loadProjects() async {
    final loadedProjects = await StorageService.loadProjects();
    if (!mounted) return;

    setState(() {
      _projects
        ..clear()
        ..addAll(
          loadedProjects.isEmpty
              ? StorageService.defaultProjects()
              : loadedProjects,
        );
      _currentIndex = _safeIndex(_currentIndex);
      _rebuildTabs();
      _isLoading = false;
    });
  }

  Future<void> _saveProjects() async {
    try {
      await StorageService.saveProjects(_projects);
    } catch (e, st) {
      debugPrint('Ошибка сохранения состояния: $e\n$st');
    }
  }

  void _rebuildTabs() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    _currentIndex = _safeIndex(_currentIndex);
    _tabController = _createTabController();
  }

  void _updateProjectEntries(Project project, List<TaskEntry> entries) {
    if (!mounted) return;
    setState(() {
      project.entries = entries;
    });
    unawaited(_saveProjects());
  }

  String _nextProjectName() {
    final usedNames = _projects.map((project) => project.name).toSet();
    var index = _projects.length + 1;
    while (usedNames.contains('Проект $index')) {
      index++;
    }
    return 'Проект $index';
  }

  int _addProject() {
    final newIndex = _projects.length;
    setState(() {
      _projects.add(Project(name: _nextProjectName()));
      _currentIndex = newIndex;
      _rebuildTabs();
      _tabController.animateTo(_currentIndex);
    });
    unawaited(_saveProjects());
    return newIndex;
  }

  void _removeProject(int index) {
    if (_projects.length <= 1) return;
    setState(() {
      _projects.removeAt(index);
      if (_currentIndex >= _projects.length) {
        _currentIndex = _projects.length - 1;
      }
      _rebuildTabs();
    });
    unawaited(_saveProjects());
  }

  void _renameProject(int index) {
    final controller = TextEditingController(text: _projects[index].name);
    unawaited(
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color.fromARGB(255, 45, 45, 50),
          title: const Text(
            'Переименовать проект',
            style: TextStyle(color: Colors.white70),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Название',
              labelStyle: const TextStyle(color: Colors.white54),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white38),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: Color.fromARGB(255, 217, 0, 255),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Отмена',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _projects[index].name = controller.text.trim().isEmpty
                      ? 'Проект ${index + 1}'
                      : controller.text.trim();
                });
                unawaited(_saveProjects());
                Navigator.pop(ctx);
              },
              child: const Text(
                'Сохранить',
                style: TextStyle(color: Color.fromARGB(255, 217, 0, 255)),
              ),
            ),
          ],
        ),
      ).whenComplete(controller.dispose),
    );
  }

  Future<void> _openFromExcel(Project project) async {
    try {
      final entries = await ExcelService.loadFromExcel();
      if (entries == null || entries.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Файл не выбран или пуст')),
          );
        }
        return;
      }
      setState(() {
        project.entries = entries;
      });
      unawaited(_saveProjects());
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChartScreen(
              entries: entries,
              projectName: project.name,
              projects: _projects,
              initialProjectIndex: _safeIndex(_projects.indexOf(project)),
              onProjectSelected: _selectProject,
              onProjectAdded: _addProject,
            ),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('Ошибка загрузки Excel: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_saveProjects());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_saveProjects());
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  Widget _gradientButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: 700,
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
              Icon(icon, color: const Color.fromARGB(255, 248, 220, 255)),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  color: Color.fromARGB(255, 248, 220, 255),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final project = _projects[_safeIndex(_currentIndex)];

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: const Color.fromARGB(255, 40, 40, 45),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  onTap: _selectProject,
                  isScrollable: true,
                  indicatorColor: const Color.fromARGB(255, 217, 0, 255),
                  labelColor: const Color.fromARGB(255, 248, 220, 255),
                  unselectedLabelColor: Colors.white38,
                  dividerColor: Colors.transparent,
                  tabAlignment: TabAlignment.start,
                  tabs: _projects.asMap().entries.map((kv) {
                    return Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () => _selectProject(kv.key),
                            onDoubleTap: () => _renameProject(kv.key),
                            child: Text(kv.value.name),
                          ),
                          if (_projects.length > 1) ...[
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => _removeProject(kv.key),
                              child: const Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.white38,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, color: Colors.white54, size: 20),
                tooltip: 'Новый проект',
                onPressed: () => _addProject(),
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color.fromARGB(255, 217, 0, 255),
              ),
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    project.name,
                    key: const ValueKey('currentProjectName'),
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  _gradientButton(
                    icon: Icons.add,
                    label: project.entries.isEmpty
                        ? 'Создать'
                        : 'Добавить данные',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DataEntryScreen(
                            projectName: project.name,
                            initialEntries: project.entries,
                            projects: _projects,
                            initialProjectIndex: _safeIndex(
                              _projects.indexOf(project),
                            ),
                            onProjectSelected: _selectProject,
                            onProjectAdded: _addProject,
                            onEntriesChanged: (entries) =>
                                _updateProjectEntries(project, entries),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _gradientButton(
                    icon: Icons.folder_open,
                    label: 'Открыть из Excel',
                    onPressed: () => _openFromExcel(project),
                  ),
                  if (project.entries.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _gradientButton(
                      icon: Icons.show_chart,
                      label: 'Показать график',
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChartScreen(
                              entries: project.entries,
                              projectName: project.name,
                              projects: _projects,
                              initialProjectIndex: _safeIndex(
                                _projects.indexOf(project),
                              ),
                              onProjectSelected: _selectProject,
                              onProjectAdded: _addProject,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
