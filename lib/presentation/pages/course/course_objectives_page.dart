import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/design/noir_tokens.dart';
import '../../../data/local/achievement_dao.dart';
import '../../../services/auth_service.dart';
import '../../../services/achievement_context.dart';
import '../../../services/course_context_service.dart';
import '../../widgets/noir_page_shell.dart';
import '../admin/course_objectives_manage_page.dart';

/// 课程目标展示页 — 从 course_objectives 表动态读取数据。
/// 学生只读查看；教师/管理员看到编辑按钮跳转到管理页。
class CourseObjectivesPage extends StatefulWidget {
  const CourseObjectivesPage({super.key});

  @override
  State<CourseObjectivesPage> createState() => _CourseObjectivesPageState();
}

class _CourseObjectivesPageState extends State<CourseObjectivesPage> {
  final _dao = AchievementDao();
  final _ctx = AchievementContext.instance;
  final _auth = AuthService();
  final _courseContext = CourseContextService();
  List<Map<String, dynamic>> _objectives = [];
  String _courseName = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _ctx.addListener(_onCourseChanged);
  }

  @override
  void dispose() {
    _ctx.removeListener(_onCourseChanged);
    super.dispose();
  }

  void _onCourseChanged() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _courseName = await _courseContext.activeCourseName(
        fallback: CourseContextService.defaultCourseName,
      );
      _ctx.courseName = _courseName;
      _objectives = (await _dao.getCourseObjectives(_courseName))
          .where((o) => _asInt(o['idx']) >= 1)
          .toList();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  static const _intro =
      '通过本课程的学习，掌握移动应用开发的多元技术体系（原生/混合/小程序/多端），理解不同开发模式的适用场景，熟悉主流跨平台开发框架及 AI 编程工具的使用，具备跨平台应用系统分析、设计和开发能力，能够运用 RESTful API 实现移动端与后端的数据交互，培养学生科学思维、创新意识和良好的职业道德，为从事移动开发工作及毕业设计奠定基础。';

  @override
  Widget build(BuildContext context) {
    final canManage = _auth.isTeacher || _auth.isAdmin;
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return NoirPageShell(
      title: '课程目标',
      eyebrow: 'COURSE OBJECTIVES',
      showBackdrop: false,
      actions: [
        Text(_courseName,
            style: TextStyle(
                color: NoirTokens.paper.withValues(alpha: 0.6), fontSize: 12)),
        if (canManage)
          IconButton(
            tooltip: '管理课程目标',
            icon: const Icon(Icons.edit_note_outlined),
            onPressed: _openManager,
          ),
      ],
      body: _objectives.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.flag_outlined,
                      size: 64, color: NoirTokens.paper.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text('暂无课程目标数据',
                      style: TextStyle(
                          color: NoirTokens.paper.withValues(alpha: 0.5))),
                  if (canManage) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _openManager,
                      icon: const Icon(Icons.edit_note_outlined),
                      label: const Text('管理课程目标'),
                    ),
                  ],
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
              children: [
                _panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('二、课程目标及其对毕业要求的支撑',
                          style: NoirTokens.title(color: NoirTokens.paper)),
                      const SizedBox(height: 12),
                      Text(
                        _intro,
                        style: TextStyle(
                          color: NoirTokens.paper.withValues(alpha: 0.82),
                          fontSize: 13,
                          height: 1.7,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildSupportTable(context),
                const SizedBox(height: 12),
                _buildAchievementTable(context),
                const SizedBox(height: 12),
                ..._objectives.map(_buildObjectiveCard),
              ],
            ),
    );
  }

  Future<void> _openManager() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CourseObjectivesManagePage()),
    );
    await _load();
  }

  Widget _buildSupportTable(BuildContext context) {
    final columns = ['序号', '课程目标', '支撑的毕业要求'];
    return _panel(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('课程目标与毕业要求支撑关系',
              style: NoirTokens.title(color: NoirTokens.paper)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Theme(
              data: Theme.of(context).copyWith(
                dataTableTheme: _darkTableTheme(),
              ),
              child: DataTable(
                columnSpacing: 22,
                horizontalMargin: 8,
                columns: [
                  for (final c in columns) DataColumn(label: Text(c)),
                ],
                rows: [
                  for (final o in _objectives)
                    DataRow(cells: [
                      DataCell(Text('${o['idx']}')),
                      DataCell(SizedBox(
                        width: 420,
                        child: Text(o['description'] ?? o['name'] ?? ''),
                      )),
                      DataCell(SizedBox(
                        width: 460,
                        child: Text(o['indicator'] ?? ''),
                      )),
                    ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementTable(BuildContext context) {
    final extraColumns = _collectExtraColumnNames();
    final columns = [
      '课程目标',
      '权重',
      '毕业要求',
      '平时',
      '实验',
      '考核',
      ...extraColumns,
    ];
    return _panel(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('课程目标达成考核与评价方式及成绩评定对照表',
              style: NoirTokens.title(color: NoirTokens.paper)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Theme(
              data: Theme.of(context).copyWith(
                dataTableTheme: _darkTableTheme(),
              ),
              child: DataTable(
                columnSpacing: 24,
                horizontalMargin: 8,
                columns: [
                  for (final c in columns) DataColumn(label: Text(c)),
                ],
                rows: [
                  ..._objectives.map((o) {
                    final w = _asDouble(o['weight']);
                    final fm = _asDouble(o['full_mark']);
                    final pr = _asRatio(o['pingshi_ratio']);
                    final er = _asRatio(o['experiment_ratio']);
                    final exr = _asRatio(o['exam_ratio']);
                    final extra = _parseExtraMap(o);
                    return DataRow(cells: [
                      DataCell(Text(o['name'] ?? '目标${o['idx']}')),
                      DataCell(Text(w.toStringAsFixed(2))),
                      DataCell(Text(o['indicator'] ?? '')),
                      DataCell(Text(
                          '${fm.toStringAsFixed(0)}（${(pr * 100).toStringAsFixed(0)}%）')),
                      DataCell(Text(
                          '${fm.toStringAsFixed(0)}（${(er * 100).toStringAsFixed(0)}%）')),
                      DataCell(Text(
                          '${fm.toStringAsFixed(0)}（${(exr * 100).toStringAsFixed(0)}%）')),
                      for (final c in extraColumns)
                        DataCell(Text(extra[c] ?? '')),
                    ]);
                  }),
                  DataRow(cells: [
                    const DataCell(Text('合计',
                        style: TextStyle(fontWeight: FontWeight.w800))),
                    DataCell(Text(
                      _objectives
                          .fold<double>(0, (s, o) => s + _asDouble(o['weight']))
                          .toStringAsFixed(2),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    )),
                    const DataCell(Text('')),
                    DataCell(Text(
                      '${_objectives.fold<double>(0, (s, o) => s + _asDouble(o['full_mark'])).toStringAsFixed(0)}（100%）',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    )),
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                    for (final _ in extraColumns) const DataCell(Text('')),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _collectExtraColumnNames() {
    final names = <String>{};
    for (final o in _objectives) {
      final map = _parseExtraMap(o);
      names.addAll(map.keys);
    }
    return names.toList()..sort();
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

  Widget _buildObjectiveCard(Map<String, dynamic> o) {
    final idx = _asInt(o['idx'], 1);
    final colors = [
      const Color(0xFFE53935),
      const Color(0xFF1E88E5),
      const Color(0xFF43A047),
      const Color(0xFFFF9800),
      const Color(0xFF9C27B0),
      const Color(0xFF00BCD4),
    ];
    final color = colors[(idx - 1).clamp(0, colors.length - 1)];
    final w = _asDouble(o['weight']);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NoirTokens.paper.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NoirTokens.paper.withValues(alpha: 0.10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 90,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text(
                  '目标$idx',
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '权重${w.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: NoirTokens.paper.withValues(alpha: 0.62),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  o['description'] ?? o['name'] ?? '',
                  style: const TextStyle(
                    color: NoirTokens.paper,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '支撑毕业要求 ${o['indicator'] ?? ''} · 考核：${o['assess_content'] ?? ''}',
                  style: TextStyle(
                    color: NoirTokens.paper.withValues(alpha: 0.64),
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '章节：${o['chapters'] ?? ''}    实验：${o['experiments'] ?? ''}',
                  style: TextStyle(
                    color: color.withValues(alpha: 0.86),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  DataTableThemeData _darkTableTheme() {
    return DataTableThemeData(
      headingTextStyle: TextStyle(
        color: NoirTokens.paper.withValues(alpha: 0.86),
        fontWeight: FontWeight.w800,
        fontSize: 13,
      ),
      dataTextStyle: TextStyle(
        color: NoirTokens.paper.withValues(alpha: 0.82),
        fontSize: 13,
        height: 1.4,
      ),
      headingRowColor: WidgetStatePropertyAll(
        NoirTokens.paper.withValues(alpha: 0.06),
      ),
      dividerThickness: 0.4,
    );
  }

  Widget _panel({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: NoirTokens.paper.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NoirTokens.paper.withValues(alpha: 0.10)),
      ),
      child: child,
    );
  }

  static int _asInt(Object? value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  static double _asDouble(Object? value, [double fallback = 0]) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final text = value.trim().replaceAll('%', '');
      return double.tryParse(text) ?? fallback;
    }
    return fallback;
  }

  static double _asRatio(Object? value, [double fallback = 0]) {
    final ratio = _asDouble(value, fallback);
    return ratio > 1 ? ratio / 100 : ratio;
  }
}
