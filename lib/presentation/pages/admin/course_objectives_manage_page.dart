import 'dart:convert';
import 'dart:io' show File;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/error_handler.dart';
import '../../../data/local/achievement_dao.dart';
import '../../../data/local/course_dao.dart';
import '../../../data/models/course_model.dart';
import '../../../services/achievement/achievement_excel_service.dart';
import '../../../services/achievement_context.dart';
import '../../widgets/agent_chat_overlay.dart';

/// 课程目标管理页 — 管理员/教师对照表编辑器 + AI 智能分析入口
///
/// 支持：
/// - 多课程切换隔离
/// - 对照表编辑（插入行/列、全部字段编辑）
/// - docx 导入
/// - 智能体交互分析
/// - 自定义列（extra_columns_json）
class CourseObjectivesManagePage extends StatefulWidget {
  const CourseObjectivesManagePage({super.key});

  @override
  State<CourseObjectivesManagePage> createState() =>
      _CourseObjectivesManagePageState();
}

class _CourseObjectivesManagePageState
    extends State<CourseObjectivesManagePage> {
  final _dao = AchievementDao();
  final _courseDao = CourseDao();
  final _ctx = AchievementContext.instance;
  final _svc = AchievementExcelService.instance;

  List<Map<String, dynamic>> _objectives = [];
  List<CourseModel> _allCourses = [];
  String _courseName = '移动应用开发';
  bool _loading = true;
  bool _importing = false;
  bool _hasUnsaved = false;
  List<TextEditingController> _ctrls = [];

  List<String> get _fixedColumns => [
        'idx',
        'name',
        'indicator',
        'weight',
        'full_mark',
        'pingshi_ratio',
        'experiment_ratio',
        'exam_ratio',
      ];
  List<String> get _fixedLabels => [
        '序号',
        '课程目标',
        '指标点',
        '权重',
        '满分',
        '平时占比',
        '实验占比',
        '期末占比',
      ];
  List<String> _extraColumns = [];

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCourses() async {
    setState(() => _loading = true);
    try {
      final courses = await _courseDao.getAllCourses();
      _allCourses = courses;
      final activeCourse = await _courseDao.getActiveCourse();
      final active = activeCourse?.name.trim().isNotEmpty == true
          ? activeCourse!.name.trim()
          : _ctx.courseName;
      if (_allCourses.any((c) => c.name == active)) {
        _courseName = active;
      } else if (_allCourses.isNotEmpty) {
        _courseName = _allCourses.first.name;
      }
      _ctx.courseName = _courseName;
      await _loadObjectives();
    } catch (e, st) {
      swallowDebug(e, tag: 'CourseObjectives.loadCourses', stack: st);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadObjectives() async {
    try {
      _objectives = (await _dao.getCourseObjectives(_courseName))
          .map((o) => Map<String, dynamic>.from(o))
          .toList();
      _parseExtraColumns();
      _rebuildCtrls();
      _hasUnsaved = false;
    } catch (e, st) {
      swallowDebug(e, tag: 'CourseObjectives.loadObjectives', stack: st);
    }
  }

  void _parseExtraColumns() {
    final names = <String>{};
    for (final o in _objectives) {
      final json = (o['extra_columns_json'] ?? '{}').toString();
      if (json.trim().isEmpty) continue;
      try {
        final map = jsonDecode(json) as Map<String, dynamic>;
        names.addAll(map.keys);
      } catch (_) {}
    }
    _extraColumns = names.toList()..sort();
  }

  void _rebuildCtrls() {
    for (final c in _ctrls) {
      c.dispose();
    }
    _ctrls = [];
    for (final o in _objectives) {
      for (final col in _fixedColumns) {
        _ctrls.add(TextEditingController(text: (o[col] ?? '').toString()));
      }
      for (final col in [
        'description',
        'chapters',
        'experiments',
        'assess_content',
        'pingshi_standard',
        'experiment_standard'
      ]) {
        _ctrls.add(TextEditingController(text: (o[col] ?? '').toString()));
      }
      for (final col in _extraColumns) {
        final json = (o['extra_columns_json'] ?? '{}').toString();
        String val = '';
        if (json.trim().isNotEmpty) {
          try {
            val = (jsonDecode(json) as Map)[col]?.toString() ?? '';
          } catch (_) {}
        }
        _ctrls.add(TextEditingController(text: val));
      }
    }
  }

  void _readCtrls() {
    int ci = 0;
    for (var ri = 0; ri < _objectives.length; ri++) {
      for (final col in _fixedColumns) {
        final text = _ctrls[ci].text.trim();
        if (col == 'idx') {
          _objectives[ri][col] = int.tryParse(text) ?? ri + 1;
        } else if (col == 'weight' || col == 'full_mark') {
          _objectives[ri][col] = _parseNumber(text);
        } else if (const {
          'pingshi_ratio',
          'experiment_ratio',
          'exam_ratio',
        }.contains(col)) {
          _objectives[ri][col] = _parseRatio(text);
        } else {
          _objectives[ri][col] = text;
        }
        ci++;
      }
      final extraMap = <String, String>{};
      for (final col in [
        'description',
        'chapters',
        'experiments',
        'assess_content',
        'pingshi_standard',
        'experiment_standard'
      ]) {
        _objectives[ri][col] = _ctrls[ci].text;
        ci++;
      }
      for (final col in _extraColumns) {
        extraMap[col] = _ctrls[ci].text;
        ci++;
      }
      if (extraMap.isNotEmpty) {
        _objectives[ri]['extra_columns_json'] = jsonEncode(extraMap);
      }
    }
  }

  double get _weightSum {
    double s = 0;
    for (final o in _objectives) {
      s += _valueAsNumber(o['weight']);
    }
    return s;
  }

  double get _fullMarkSum {
    double s = 0;
    for (final o in _objectives) {
      s += _valueAsNumber(o['full_mark']);
    }
    return s;
  }

  Future<void> _save() async {
    _readCtrls();
    try {
      await _activateCourse(_courseName);
      await _dao.saveCourseObjectives(_courseName, _objectives);
      _ctx.courseName = _courseName;
      _hasUnsaved = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已保存 ${_objectives.length} 个课程目标'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'CourseObjectives.save', stack: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _addRow() async {
    _readCtrls();
    final nextIdx = _objectives.length + 1;
    _objectives.add({
      'idx': nextIdx,
      'name': '课程目标$nextIdx',
      'indicator': '',
      'weight': 0.0,
      'full_mark': 0.0,
      'pingshi_ratio': 0.20,
      'experiment_ratio': 0.30,
      'exam_ratio': 0.50,
      'description': '',
      'chapters': '',
      'experiments': '',
      'assess_content': '',
      'pingshi_standard': '',
      'experiment_standard': '',
      'extra_columns_json': '{}',
    });
    _rebuildCtrls();
    setState(() => _hasUnsaved = true);
  }

  Future<void> _addColumn() async {
    final nameCtrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加自定义列'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: '列名',
            hintText: '如：考核方式、评价标准',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
              child: const Text('添加')),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    _readCtrls();
    if (_extraColumns.contains(result)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('列 "$result" 已存在'), backgroundColor: Colors.orange),
        );
      }
      return;
    }
    _extraColumns.add(result);
    for (final o in _objectives) {
      final map = _parseExtraMap(o);
      map[result] = '';
      o['extra_columns_json'] = jsonEncode(map);
    }
    _rebuildCtrls();
    setState(() => _hasUnsaved = true);
  }

  Map<String, String> _parseExtraMap(Map<String, dynamic> row) {
    final json = (row['extra_columns_json'] ?? '{}').toString();
    if (json.trim().isEmpty) return {};
    try {
      return Map<String, String>.from((jsonDecode(json) as Map)
          .map((k, v) => MapEntry(k.toString(), v.toString())));
    } catch (_) {
      return {};
    }
  }

  Future<void> _importDocx() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['docx', 'md'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      final ext = (f.extension ?? '').toLowerCase();
      setState(() => _importing = true);
      String rawText;
      if (f.bytes != null) {
        rawText = _svc.syllabusRawText(f.bytes!, ext);
      } else if (f.path != null) {
        rawText = _svc.syllabusRawText(await File(f.path!).readAsBytes(), ext);
      } else {
        throw StateError('无法读取文件内容');
      }
      if (rawText.trim().isEmpty) throw StateError('大纲文本为空');
      if (mounted) setState(() => _importing = false);
      await _openAgentWithText(
        '以下是一份课程大纲原始文本。请重点识别“课程目标达成考核与评价方式及成绩评定对照表”，'
        '提取课程目标、权重、满分、指标点、平时/实验/期末占比、支撑章节、实验和考核内容。'
        '当前课程：$_courseName。\n\n$rawText',
      );
    } catch (e, st) {
      swallowDebug(e, tag: 'CourseObjectives.importDocx', stack: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _openAgentWithText(String text) async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AgentChatOverlay(
        initialAgentId: 'achievement',
        initialContext: text,
        onAgentResult: (_) {
          _loadObjectives().then((_) {
            if (mounted) setState(() {});
          });
        },
      ),
    );
    await _loadObjectives();
    if (mounted) setState(() {});
  }

  void _launchAgent() {
    _readCtrls();
    final rawText = _buildRawTextForAgent();
    _openAgentWithText(
      '请分析以下课程目标对照表草稿，检查权重、满分、指标点、支撑章节、实验和考核内容是否完整准确。'
      '如需要修正，请用 clarify_objective 工具更新；确认后用 submit_syllabus 保存。'
      '\n\n$rawText',
    );
  }

  String _buildRawTextForAgent() {
    final buf = StringBuffer('当前课程：$_courseName\n课程名称: $_courseName\n\n');
    for (final o in _objectives) {
      buf.writeln('目标${o['idx']}: ${o['name'] ?? ''}');
      buf.writeln('  权重: ${o['weight']}  满分: ${o['full_mark']}');
      buf.writeln('  指标点: ${o['indicator']}');
      buf.writeln('  描述: ${o['description']}');
      buf.writeln('  章节: ${o['chapters']}  实验: ${o['experiments']}');
      buf.writeln();
    }
    return buf.toString();
  }

  static double _valueAsNumber(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.trim().replaceAll('%', '')) ?? 0.0;
    }
    return 0.0;
  }

  static double _parseNumber(String text) => _valueAsNumber(text);

  static double _parseRatio(String text) {
    final value = _valueAsNumber(text);
    return value > 1 ? value / 100 : value;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('课程目标管理'),
        actions: [
          if (_hasUnsaved)
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('保存'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildToolbar(),
                const Divider(height: 1),
                Expanded(child: _buildEditor()),
              ],
            ),
    );
  }

  Widget _buildToolbar() {
    final sumOk = (_weightSum - 1.0).abs() < 0.001;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                initialValue: _allCourses.any((c) => c.name == _courseName)
                    ? _courseName
                    : null,
                decoration: const InputDecoration(
                  labelText: '课程',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                ),
                items: _allCourses.map((c) {
                  return DropdownMenuItem(value: c.name, child: Text(c.name));
                }).toList(),
                onChanged: (v) async {
                  if (v == null || v == _courseName) return;
                  if (_hasUnsaved) {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('未保存的更改'),
                        content: const Text('当前修改还未保存，切换课程将丢失。确定继续？'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('取消')),
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('确定')),
                        ],
                      ),
                    );
                    if (ok != true) return;
                  }
                  _courseName = v;
                  await _activateCourse(v);
                  _ctx.courseName = v;
                  await _loadObjectives();
                  setState(() {});
                },
              ),
            ),
            const SizedBox(width: 12),
            _ActionChip(
              icon: Icons.upload_file,
              label: '导入大纲',
              loading: _importing,
              onPressed: _importDocx,
            ),
            const SizedBox(width: 8),
            _ActionChip(
              icon: Icons.auto_awesome,
              label: '智能分析',
              onPressed: _launchAgent,
            ),
            const SizedBox(width: 8),
            _ActionChip(
              icon: Icons.playlist_add,
              label: '新增行',
              onPressed: _addRow,
            ),
            const SizedBox(width: 8),
            _ActionChip(
              icon: Icons.view_column,
              label: '新增列',
              onPressed: _addColumn,
            ),
            const SizedBox(width: 12),
            Text(
              '权重: ${_weightSum.toStringAsFixed(2)}',
              style: TextStyle(
                color: sumOk ? Colors.green : Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (!sumOk)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.warning_amber, color: Colors.red, size: 18),
              ),
            const SizedBox(width: 16),
            Text(
              '总分: ${_fullMarkSum.toStringAsFixed(0)}',
              style: TextStyle(
                color: (_fullMarkSum - 100).abs() < 0.5
                    ? Colors.green
                    : Colors.orange,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor() {
    if (_objectives.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_chart_outlined,
                size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('暂无课程目标数据',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            Text('导入大纲或手动添加行',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          ],
        ),
      );
    }
    final displayColumns = [
      ..._fixedLabels,
      '描述',
      '支撑章节',
      '支撑实验',
      '考核内容',
      '平时标准',
      '实验标准',
      ..._extraColumns,
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 12,
          horizontalMargin: 8,
          headingRowHeight: 40,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 80,
          columns: [
            for (final label in displayColumns)
              DataColumn(
                label: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
          ],
          rows: [
            for (var ri = 0; ri < _objectives.length; ri++)
              DataRow(
                cells: [
                  for (var ci = 0; ci < displayColumns.length; ci++)
                    DataCell(_buildCell(ri, ci)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCell(int ri, int ci) {
    final col = ci < _fixedLabels.length
        ? _fixedLabels[ci]
        : ci < _fixedLabels.length + 6
            ? [
                '描述',
                '支撑章节',
                '支撑实验',
                '考核内容',
                '平时标准',
                '实验标准'
              ][ci - _fixedLabels.length]
            : _extraColumns[ci - _fixedLabels.length - 6];
    final isNumeric = ['权重', '满分', '平时占比', '实验占比', '期末占比'].contains(col);
    final isReadonly = ['序号'].contains(col);
    final idx = ri * (_fixedColumns.length + 6 + _extraColumns.length) + ci;
    if (idx >= _ctrls.length) return const Text('');
    return Container(
      constraints: BoxConstraints(
        minWidth: isNumeric ? 70 : 120,
        maxWidth: isNumeric ? 90 : 200,
      ),
      child: isReadonly
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(_ctrls[idx].text,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            )
          : TextField(
              controller: _ctrls[idx],
              keyboardType: isNumeric
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              ),
              style: TextStyle(
                fontSize: 13,
                color: isNumeric ? Colors.blue.shade800 : null,
              ),
              onChanged: (_) {
                _hasUnsaved = true;
              },
              maxLines: null,
            ),
    );
  }

  Future<void> _activateCourse(String courseName) async {
    final matched = _allCourses.where((c) => c.name == courseName);
    if (matched.isEmpty) return;
    await _courseDao.setActiveCourse(matched.first.id);
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  const _ActionChip({
    required this.icon,
    required this.label,
    this.loading = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 18),
      label: Text(label),
      onPressed: loading ? null : onPressed,
    );
  }
}
