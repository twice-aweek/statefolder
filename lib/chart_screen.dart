import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'models.dart';
import 'project_model.dart';
import 'summary_screen.dart';

enum ChartProjection { free3D, frontTaskDelta }

class ChartScreen extends StatefulWidget {
  final List<TaskEntry> entries;
  final String projectName;
  final List<Project>? projects;
  final int initialProjectIndex;
  final ValueChanged<int>? onProjectSelected;
  final int Function()? onProjectAdded;

  const ChartScreen({
    super.key,
    required this.entries,
    this.projectName = '',
    this.projects,
    this.initialProjectIndex = 0,
    this.onProjectSelected,
    this.onProjectAdded,
  });

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen>
    with SingleTickerProviderStateMixin {
  double _rotX = -0.5;
  double _rotY = 0.6;
  double _scale = 1.0;
  double _lastScale = 1.0;
  double _panX = 0; // смещение камеры в пикселях
  double _panY = 0;
  ChartProjection _projection = ChartProjection.free3D;

  // Для анимации проекций
  late AnimationController _animCtrl;
  double _sRotX = -0.5, _sRotY = 0.6;
  double _tRotX = -0.5, _tRotY = 0.6;

  // Режим: true = вращение, false = перемещение
  bool _rotateMode = true;

  // Выбранная точка
  TaskEntry? _selectedEntry;
  late int _projectIndex;

  bool get _hasProjectTabs =>
      widget.projects != null && widget.projects!.isNotEmpty;

  int _safeProjectIndex(int index) {
    final projects = widget.projects;
    if (projects == null || projects.isEmpty) return 0;
    return index.clamp(0, projects.length - 1).toInt();
  }

  List<TaskEntry> get _activeEntries {
    if (!_hasProjectTabs) return widget.entries;
    return widget.projects![_safeProjectIndex(_projectIndex)].entries;
  }

  String get _activeProjectName {
    if (!_hasProjectTabs) return widget.projectName;
    return widget.projects![_safeProjectIndex(_projectIndex)].name;
  }

  @override
  void initState() {
    super.initState();
    _projectIndex = _safeProjectIndex(widget.initialProjectIndex);
    _animCtrl =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 500),
        )..addListener(() {
          final t = Curves.easeInOut.transform(_animCtrl.value);
          setState(() {
            _rotX = _sRotX + (_tRotX - _sRotX) * t;
            _rotY = _sRotY + (_tRotY - _sRotY) * t;
          });
        });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _setProj(ChartProjection p) {
    if (_projection == p) return;
    _sRotX = _rotX;
    _sRotY = _rotY;
    switch (p) {
      case ChartProjection.free3D:
        _tRotX = -0.5;
        _tRotY = 0.6;
      case ChartProjection.frontTaskDelta:
        _tRotX = 0;
        _tRotY = 0;
    }
    setState(() => _projection = p);
    _animCtrl.forward(from: 0);
  }

  void _zoom(double d) => setState(() => _scale = (_scale + d).clamp(0.3, 3.0));

  void _selectProject(int index) {
    final nextIndex = _safeProjectIndex(index);
    if (_projectIndex == nextIndex) return;
    setState(() {
      _projectIndex = nextIndex;
      _selectedEntry = null;
    });
    widget.onProjectSelected?.call(nextIndex);
  }

  void _addProjectTab() {
    final addedIndex = widget.onProjectAdded?.call();
    if (addedIndex == null) return;
    setState(() {
      _projectIndex = _safeProjectIndex(addedIndex);
      _selectedEntry = null;
    });
  }

  static const _palette = [
    Color(0xFF42A5F5),
    Color(0xFFAB47BC),
    Color(0xFF26C6DA),
    Color(0xFF5C6BC0),
    Color(0xFF7E57C2),
    Color(0xFF29B6F6),
    Color(0xFFEC407A),
    Color(0xFF78909C),
    Color(0xFF8D6E63),
    Color(0xFF26A69A),
    Color(0xFF9575CD),
    Color(0xFF4DD0E1),
  ];

  // ── Вычисляем экранные позиции точек для hit-test ──
  List<_ScreenDot> _computeScreenDots(Size chartSize) {
    final entries = _activeEntries;
    if (entries.isEmpty) return [];

    final cx = chartSize.width / 2 + _panX;
    final cy = chartSize.height / 2 + _panY;

    final tasks = entries.map((e) => e.task).toSet().toList()..sort();
    final surnames = entries.map((e) => e.surname).toSet().toList()..sort();
    final deltas = entries.map((e) => e.deltaDays).toList();
    final minD = deltas.reduce(min);
    final maxD = deltas.reduce(max);
    final dRange = (maxD - minD).abs();
    final sc = min(chartSize.width, chartSize.height) * 0.28 * _scale;

    final cosY = cos(_rotY), sinY = sin(_rotY);
    final cosX = cos(_rotX), sinX = sin(_rotX);

    Offset proj(double x, double y, double z) {
      final x1 = x * cosY - z * sinY;
      final z1 = x * sinY + z * cosY;
      final y1 = y * cosX - z1 * sinX;
      return Offset(cx + x1, cy - y1);
    }

    double tx(int i) =>
        tasks.length <= 1 ? 0.0 : (i / (tasks.length - 1) * 2 - 1) * sc;
    double sz(int i) =>
        surnames.length <= 1 ? 0.0 : (i / (surnames.length - 1) * 2 - 1) * sc;
    double dy(int d) => dRange == 0 ? 0.0 : ((d - minD) / dRange * 2 - 1) * sc;

    final dots = <_ScreenDot>[];
    for (final e in entries) {
      final ti = tasks.indexOf(e.task);
      final si = surnames.indexOf(e.surname);
      dots.add(
        _ScreenDot(entry: e, pos: proj(tx(ti), dy(e.deltaDays), sz(si))),
      );
    }
    return dots;
  }

  TaskEntry? _hitTest(Offset tap, Size chartSize) {
    final dots = _computeScreenDots(chartSize);
    const hitRadius = 16.0;
    double bestDist = hitRadius;
    TaskEntry? best;
    for (final d in dots) {
      final dist = (d.pos - tap).distance;
      if (dist < bestDist) {
        bestDist = dist;
        best = d.entry;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _activeEntries;
    final projectName = _activeProjectName;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          projectName.isNotEmpty ? '3D График: $projectName' : '3D График',
        ),
        backgroundColor: const Color.fromARGB(255, 50, 50, 50),
        foregroundColor: const Color.fromARGB(255, 248, 220, 255),
        bottom: _hasProjectTabs
            ? PreferredSize(
                preferredSize: const Size.fromHeight(46),
                child: _projectTabStrip(),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.summarize),
            tooltip: 'Сводка по проекту',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      SummaryScreen(entries: entries, projectName: projectName),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Кнопки проекций
          Container(
            color: const Color.fromARGB(255, 40, 40, 40),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _projBtn(
                    ChartProjection.free3D,
                    'Свободный 3D',
                    Icons.threed_rotation,
                  ),
                  const SizedBox(width: 8),
                  _projBtn(
                    ChartProjection.frontTaskDelta,
                    'Задача / Δ дней',
                    Icons.view_agenda,
                  ),
                  const SizedBox(width: 16),
                  // Переключатель режима
                  _modeToggle(),
                ],
              ),
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? const Center(
                    child: Text(
                      'В проекте нет данных',
                      style: TextStyle(color: Colors.white38, fontSize: 16),
                    ),
                  )
                : Row(
                    children: [
                      // ── График ──
                      Expanded(
                        child: LayoutBuilder(
                          builder: (ctx, constraints) {
                            final chartSize = Size(
                              constraints.maxWidth,
                              constraints.maxHeight,
                            );
                            return Stack(
                              children: [
                                Positioned.fill(
                                  child: Listener(
                                    onPointerSignal: (e) {
                                      if (e is PointerScrollEvent) {
                                        _zoom(-e.scrollDelta.dy * 0.001);
                                      }
                                    },
                                    child: GestureDetector(
                                      onScaleStart: (_) => _lastScale = _scale,
                                      onScaleUpdate: (d) {
                                        setState(() {
                                          if (d.pointerCount >= 2) {
                                            _scale = (_lastScale * d.scale)
                                                .clamp(0.3, 3.0);
                                          } else if (!_rotateMode) {
                                            _panX += d.focalPointDelta.dx;
                                            _panY += d.focalPointDelta.dy;
                                          } else {
                                            _projection =
                                                ChartProjection.free3D;
                                            _rotY +=
                                                d.focalPointDelta.dx * 0.01;
                                            _rotX +=
                                                d.focalPointDelta.dy * 0.01;
                                            _rotX = _rotX.clamp(
                                              -pi / 2,
                                              pi / 2,
                                            );
                                          }
                                        });
                                      },
                                      onTapUp: (d) {
                                        final hit = _hitTest(
                                          d.localPosition,
                                          chartSize,
                                        );
                                        setState(() => _selectedEntry = hit);
                                      },
                                      child: CustomPaint(
                                        painter: _Chart3DPainter(
                                          entries: entries,
                                          rotX: _rotX,
                                          rotY: _rotY,
                                          scale: _scale,
                                          panX: _panX,
                                          panY: _panY,
                                          projection: _projection,
                                          palette: _palette,
                                          selectedEntry: _selectedEntry,
                                        ),
                                        size: Size.infinite,
                                      ),
                                    ),
                                  ),
                                ),
                                // Зум
                                Positioned(
                                  right: 12,
                                  bottom: 12,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _zoomBtn(Icons.add, () => _zoom(0.15)),
                                      const SizedBox(height: 6),
                                      _zoomBtn(
                                        Icons.remove,
                                        () => _zoom(-0.15),
                                      ),
                                      const SizedBox(height: 6),
                                      _zoomBtn(Icons.center_focus_strong, () {
                                        setState(() {
                                          _panX = 0;
                                          _panY = 0;
                                          _scale = 1.0;
                                        });
                                        _setProj(ChartProjection.free3D);
                                      }),
                                    ],
                                  ),
                                ),
                                // Статус точек
                                Positioned(
                                  left: 12,
                                  top: 8,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _statusDot(
                                        Colors.greenAccent,
                                        'Раньше срока',
                                      ),
                                      _statusDot(Colors.amberAccent, 'В срок'),
                                      _statusDot(Colors.redAccent, 'Опоздание'),
                                    ],
                                  ),
                                ),
                                // ── Всплывающая карточка по клику ──
                                if (_selectedEntry != null)
                                  Positioned(
                                    left: 12,
                                    bottom: 12,
                                    child: _buildTooltipCard(_selectedEntry!),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                      // ── Легенда ──
                      Container(
                        width: 230,
                        color: const Color.fromARGB(255, 35, 35, 35),
                        child: _buildLegend(),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ── Карточка выбранной точки ──
  Widget _buildTooltipCard(TaskEntry e) {
    final df = DateFormat('dd.MM.yyyy');
    final surnames = _activeEntries.map((e) => e.surname).toSet().toList()
      ..sort();
    final si = surnames.indexOf(e.surname);
    final sColor = _palette[si % _palette.length];
    final statusColor = e.deltaDays > 0
        ? Colors.redAccent
        : e.deltaDays < 0
        ? Colors.greenAccent
        : Colors.amberAccent;
    final statusText = e.deltaDays > 0
        ? 'Опоздание на ${e.deltaDays} дн.'
        : e.deltaDays < 0
        ? 'Раньше на ${-e.deltaDays} дн.'
        : 'Точно в срок';

    return Material(
      color: const Color.fromARGB(230, 45, 45, 55),
      borderRadius: BorderRadius.circular(12),
      elevation: 8,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _selectedEntry = null),
        child: Container(
          padding: const EdgeInsets.all(14),
          constraints: const BoxConstraints(maxWidth: 300),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Фамилия
              Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: sColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    e.surname,
                    style: TextStyle(
                      color: sColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.close, color: Colors.white30, size: 16),
                ],
              ),
              const SizedBox(height: 8),
              // Задача
              Text(
                'Задача: ${e.task}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 4),
              // Дедлайн
              Text(
                'Дедлайн: ${df.format(e.deadline)}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              // Дата сдачи
              Text(
                'Сдано: ${df.format(e.completionDate)}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 6),
              // Статус
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  '$statusText (Δ ${e.deltaDays > 0 ? '+' : ''}${e.deltaDays})',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    final surnames = _activeEntries.map((e) => e.surname).toSet().toList()
      ..sort();
    final tasks = _activeEntries.map((e) => e.task).toSet().toList()..sort();
    final map = <String, List<TaskEntry>>{};
    for (final e in _activeEntries) {
      map.putIfAbsent(e.surname, () => []).add(e);
    }
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'Фамилии',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        for (int i = 0; i < surnames.length; i++)
          _legendSurname(surnames[i], i, map[surnames[i]] ?? []),
        const Divider(color: Colors.white12, height: 20),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'Задачи',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        for (final t in tasks)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              t,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _projectTabStrip() {
    final projects = widget.projects!;
    return Container(
      height: 46,
      color: const Color.fromARGB(255, 40, 40, 45),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemCount: projects.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final project = projects[index];
                final active = index == _safeProjectIndex(_projectIndex);
                return Material(
                  color: active
                      ? const Color.fromARGB(255, 100, 54, 160)
                      : const Color.fromARGB(255, 58, 58, 64),
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _selectProject(index),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.folder,
                            size: 16,
                            color: active
                                ? const Color.fromARGB(255, 248, 220, 255)
                                : Colors.white54,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            project.name,
                            style: TextStyle(
                              color: active
                                  ? const Color.fromARGB(255, 248, 220, 255)
                                  : Colors.white60,
                              fontSize: 13,
                              fontWeight: active
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                            ),
                          ),
                          if (project.entries.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              '${project.entries.length}',
                              style: TextStyle(
                                color: active ? Colors.white70 : Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (widget.onProjectAdded != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Material(
                color: const Color.fromARGB(255, 58, 58, 64),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _addProjectTab,
                  child: const SizedBox(
                    width: 36,
                    height: 34,
                    child: Icon(
                      Icons.add,
                      size: 20,
                      color: Color.fromARGB(255, 248, 220, 255),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _legendSurname(String name, int idx, List<TaskEntry> tasks) {
    final c = _palette[idx % _palette.length];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    color: c,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          for (final t in tasks)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 2),
              child: Text(
                '${t.task}: ${t.deltaDays > 0 ? '+' : ''}${t.deltaDays}д',
                style: TextStyle(
                  color: t.deltaDays > 0
                      ? Colors.redAccent.withValues(alpha: 0.8)
                      : t.deltaDays < 0
                      ? Colors.greenAccent.withValues(alpha: 0.8)
                      : Colors.amberAccent.withValues(alpha: 0.8),
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusDot(Color c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white54, width: 1),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    ),
  );

  Widget _projBtn(ChartProjection proj, String label, IconData icon) {
    final a = _projection == proj;
    return Material(
      color: a
          ? const Color.fromARGB(255, 120, 60, 180)
          : const Color.fromARGB(255, 60, 60, 60),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _setProj(proj),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: a ? Colors.white : Colors.white54),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: a ? Colors.white : Colors.white70,
                  fontSize: 13,
                  fontWeight: a ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 55, 55, 55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modeBtn(Icons.threed_rotation, 'Вращение', true),
          _modeBtn(Icons.open_with, 'Перемещение', false),
        ],
      ),
    );
  }

  Widget _modeBtn(IconData icon, String label, bool isRotate) {
    final active = _rotateMode == isRotate;
    return Material(
      color: active
          ? const Color.fromARGB(255, 90, 50, 150)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _rotateMode = isRotate),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: active ? Colors.white : Colors.white54,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : Colors.white60,
                  fontSize: 12,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _zoomBtn(IconData icon, VoidCallback onTap) => Material(
    color: const Color.fromARGB(200, 60, 60, 60),
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(icon, color: Colors.white70, size: 22),
      ),
    ),
  );
}

// ── Вспомогательный класс ──
class _ScreenDot {
  final TaskEntry entry;
  final Offset pos;
  _ScreenDot({required this.entry, required this.pos});
}

// ════════════════════ PAINTER ════════════════════

class _Chart3DPainter extends CustomPainter {
  final List<TaskEntry> entries;
  final double rotX, rotY, scale, panX, panY;
  final ChartProjection projection;
  final List<Color> palette;
  final TaskEntry? selectedEntry;

  _Chart3DPainter({
    required this.entries,
    required this.rotX,
    required this.rotY,
    required this.scale,
    required this.panX,
    required this.panY,
    required this.projection,
    required this.palette,
    this.selectedEntry,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.isEmpty) return;

    final cx = size.width / 2 + panX;
    final cy = size.height / 2 + panY;

    final tasks = entries.map((e) => e.task).toSet().toList()..sort();
    final surnames = entries.map((e) => e.surname).toSet().toList()..sort();
    final deltas = entries.map((e) => e.deltaDays).toList();
    final minD = deltas.reduce(min);
    final maxD = deltas.reduce(max);
    final dRange = (maxD - minD).abs();

    final sc = min(size.width, size.height) * 0.28 * scale;

    final cosY = cos(rotY), sinY = sin(rotY);
    final cosX = cos(rotX), sinX = sin(rotX);

    Offset proj(double x, double y, double z) {
      final x1 = x * cosY - z * sinY;
      final z1 = x * sinY + z * cosY;
      final y1 = y * cosX - z1 * sinX;
      return Offset(cx + x1, cy - y1);
    }

    double tx(int i) =>
        tasks.length <= 1 ? 0.0 : (i / (tasks.length - 1) * 2 - 1) * sc;
    double sz(int i) =>
        surnames.length <= 1 ? 0.0 : (i / (surnames.length - 1) * 2 - 1) * sc;
    double dy(int d) => dRange == 0 ? 0.0 : ((d - minD) / dRange * 2 - 1) * sc;

    final bool showSurnames = projection != ChartProjection.frontTaskDelta;
    final bool showSurnameLines = projection == ChartProjection.free3D;

    // Оси значительно длиннее данных
    final al = sc * 1.5;

    // ── Сетка ──
    final gridP = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;

    for (int i = 0; i < tasks.length; i++) {
      canvas.drawLine(proj(tx(i), -sc, 0), proj(tx(i), sc, 0), gridP);
    }
    if (showSurnames) {
      for (int i = 0; i < surnames.length; i++) {
        canvas.drawLine(proj(0, -sc, sz(i)), proj(0, sc, sz(i)), gridP);
      }
    }
    if (dRange > 0) {
      final step = _niceStep(dRange.toDouble(), 6);
      final start = (minD / step).floor() * step;
      for (double d = start; d <= maxD + step * 0.5; d += step) {
        final di = d.round();
        if (di < minD || di > maxD) continue;
        final y = dy(di);
        canvas.drawLine(proj(-sc, y, 0), proj(sc, y, 0), gridP);
        if (showSurnames) {
          canvas.drawLine(proj(0, y, -sc), proj(0, y, sc), gridP);
        }
      }
    }

    // ── Оси — толстые, длинные ──
    final axP = Paint()
      ..color = Colors.white54
      ..strokeWidth = 2;

    canvas.drawLine(proj(-al, 0, 0), proj(al, 0, 0), axP);
    canvas.drawLine(proj(0, -al, 0), proj(0, al, 0), axP);
    if (showSurnames) {
      canvas.drawLine(proj(0, 0, -al), proj(0, 0, al), axP);
    }

    // Стрелки на концах осей
    _drawArrow(canvas, proj(al, 0, 0), proj(al - 12, 0, 0), axP);
    _drawArrow(canvas, proj(0, al, 0), proj(0, al - 12, 0), axP);
    if (showSurnames) {
      _drawArrow(canvas, proj(0, 0, al), proj(0, 0, al - 12), axP);
    }

    // ── Подписи осей — крупные, яркие, с фоном ──
    _labelBg(canvas, proj(al + 30, 0, 0), 'ЗАДАЧА', Colors.white, 13);
    _labelBg(canvas, proj(0, al + 30, 0), 'Δ ДНЕЙ', Colors.white, 13);
    if (showSurnames) {
      _labelBg(canvas, proj(0, 0, al + 30), 'ФАМИЛИЯ', Colors.white, 13);
    }

    // ── Тики ──
    final tickP = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1;

    for (int i = 0; i < tasks.length; i++) {
      final x = tx(i);
      final p = proj(x, 0, 0);
      canvas.drawLine(p, p + const Offset(0, 8), tickP);
      _labelRotated(
        canvas,
        p + const Offset(2, 12),
        tasks[i],
        Colors.white70,
        10,
        -pi / 4,
      );
    }

    if (showSurnames) {
      for (int i = 0; i < surnames.length; i++) {
        final z = sz(i);
        final p = proj(0, 0, z);
        canvas.drawLine(p, p + const Offset(0, 8), tickP);
        _labelRotated(
          canvas,
          p + const Offset(2, 12),
          surnames[i],
          palette[i % palette.length],
          10,
          -pi / 4,
        );
      }
    }

    if (dRange > 0) {
      final step = _niceStep(dRange.toDouble(), 6);
      final start = (minD / step).floor() * step;
      for (double d = start; d <= maxD + step * 0.5; d += step) {
        final di = d.round();
        if (di < minD || di > maxD) continue;
        final y = dy(di);
        final p = proj(0, y, 0);
        canvas.drawLine(p, p + const Offset(-8, 0), tickP);
        _label(canvas, p + const Offset(-22, 0), '$di', Colors.white60, 10);
      }
    }

    // ── Карта точек ──
    final ptMap = <String, List<double>>{};
    for (final e in entries) {
      final ti = tasks.indexOf(e.task);
      final si = surnames.indexOf(e.surname);
      ptMap['${ti}_$si'] = [tx(ti), dy(e.deltaDays), sz(si)];
    }

    // ── Линии по фамилиям ──
    final lp = Paint()
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (int si = 0; si < surnames.length; si++) {
      final pts = <List<double>>[];
      for (int ti = 0; ti < tasks.length; ti++) {
        final k = '${ti}_$si';
        if (ptMap.containsKey(k)) pts.add(ptMap[k]!);
      }
      if (pts.length > 1) {
        lp.color = _col(si).withValues(alpha: 0.7);
        for (int i = 0; i < pts.length - 1; i++) {
          canvas.drawLine(
            proj(pts[i][0], pts[i][1], pts[i][2]),
            proj(pts[i + 1][0], pts[i + 1][1], pts[i + 1][2]),
            lp,
          );
        }
      }
    }

    // ── Линии по задачам ──
    if (showSurnameLines) {
      for (int ti = 0; ti < tasks.length; ti++) {
        final pts = <List<double>>[];
        for (int si = 0; si < surnames.length; si++) {
          final k = '${ti}_$si';
          if (ptMap.containsKey(k)) pts.add(ptMap[k]!);
        }
        if (pts.length > 1) {
          lp.color = Colors.white.withValues(alpha: 0.2);
          for (int i = 0; i < pts.length - 1; i++) {
            canvas.drawLine(
              proj(pts[i][0], pts[i][1], pts[i][2]),
              proj(pts[i + 1][0], pts[i + 1][1], pts[i + 1][2]),
              lp,
            );
          }
        }
      }
    }

    // ── Тени в 2D ──
    if (projection == ChartProjection.frontTaskDelta) {
      final shP = Paint()
        ..color = Colors.white.withValues(alpha: 0.1)
        ..strokeWidth = 0.5;
      for (final e in entries) {
        final ti = tasks.indexOf(e.task);
        final si = surnames.indexOf(e.surname);
        final x = tx(ti), y = dy(e.deltaDays), z = sz(si);
        canvas.drawLine(proj(x, y, z), proj(x, 0, z), shP);
      }
    }

    // ── Точки ──
    for (final e in entries) {
      final ti = tasks.indexOf(e.task);
      final si = surnames.indexOf(e.surname);
      final x = tx(ti), y = dy(e.deltaDays), z = sz(si);
      final p = proj(x, y, z);

      final dotC = e.deltaDays > 0
          ? Colors.redAccent
          : e.deltaDays < 0
          ? Colors.greenAccent
          : Colors.amberAccent;
      final sColor = _col(si);

      final isSelected =
          selectedEntry != null &&
          selectedEntry!.surname == e.surname &&
          selectedEntry!.task == e.task;

      final radius = isSelected ? 10.0 : 7.0;

      // Подсветка выбранной
      if (isSelected) {
        canvas.drawCircle(
          p,
          14,
          Paint()..color = Colors.white.withValues(alpha: 0.15),
        );
      }

      canvas.drawCircle(p, radius, Paint()..color = dotC);
      canvas.drawCircle(
        p,
        radius,
        Paint()
          ..color = sColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 3.5 : 2.5,
      );

      final sign = e.deltaDays > 0 ? '+' : '';
      _label(
        canvas,
        p + const Offset(14, -12),
        '$sign${e.deltaDays}д',
        Colors.white70,
        10,
      );
    }
  }

  void _drawArrow(Canvas c, Offset tip, Offset back, Paint p) {
    final dir = tip - back;
    final len = dir.distance;
    if (len == 0) return;
    final norm = dir / len;
    final perp = Offset(-norm.dy, norm.dx);
    const w = 5.0; // ширина основания треугольника
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(back.dx + perp.dx * w, back.dy + perp.dy * w)
      ..lineTo(back.dx - perp.dx * w, back.dy - perp.dy * w)
      ..close();
    c.drawPath(path, Paint()..color = p.color);
  }

  double _niceStep(double range, int maxTicks) {
    if (range <= 0) return 1;
    final rough = range / maxTicks;
    final mag = pow(10, (log(rough) / ln10).floor()).toDouble();
    final norm = rough / mag;
    final nice = norm <= 1.5
        ? 1.0
        : norm <= 3
        ? 2.0
        : norm <= 7
        ? 5.0
        : 10.0;
    return (nice * mag).clamp(1, double.infinity);
  }

  void _label(Canvas c, Offset pos, String text, Color color, double fs) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fs),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, pos - Offset(tp.width / 2, tp.height / 2));
  }

  /// Подпись оси с полупрозрачным фоном
  void _labelBg(Canvas c, Offset pos, String text, Color color, double fs) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fs,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = Rect.fromCenter(
      center: pos,
      width: tp.width + 12,
      height: tp.height + 6,
    );
    c.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = const Color.fromARGB(180, 40, 40, 50),
    );
    tp.paint(c, pos - Offset(tp.width / 2, tp.height / 2));
  }

  void _labelRotated(
    Canvas c,
    Offset anchor,
    String text,
    Color color,
    double fs,
    double angle,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fs),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    c.save();
    c.translate(anchor.dx, anchor.dy);
    c.rotate(angle);
    tp.paint(c, Offset.zero);
    c.restore();
  }

  Color _col(int i) => palette[i % palette.length];

  @override
  bool shouldRepaint(covariant _Chart3DPainter o) =>
      o.rotX != rotX ||
      o.rotY != rotY ||
      o.scale != scale ||
      o.panX != panX ||
      o.panY != panY ||
      o.projection != projection ||
      o.selectedEntry != selectedEntry;
}
