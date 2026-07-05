import 'package:flutter/material.dart';

import '../../../core/design/noir_tokens.dart';
import '../../../core/error_handler.dart';
import '../../../data/local/achievement_dao.dart';
import '../../../data/local/ordinary_score_dao.dart';
import '../../../services/auth_service.dart';
import '../../../services/course_context_service.dart';

class OrdinaryScoreTab extends StatefulWidget {
  const OrdinaryScoreTab({super.key});

  @override
  State<OrdinaryScoreTab> createState() => _OrdinaryScoreTabState();
}

class _OrdinaryScoreTabState extends State<OrdinaryScoreTab> {
  final _ordinaryDao = OrdinaryScoreDao();
  final _achievementDao = AchievementDao();
  final _authService = AuthService();
  final _studentFilterCtrl = TextEditingController();

  OrdinaryScoreSnapshot? _snapshot;
  OrdinaryScoreSettings? _settings;
  List<Map<String, dynamic>> _batches = [];
  int? _selectedBatchId;
  bool _loading = true;
  bool _savingSettings = false;
  bool _syncing = false;
  bool _creatingBatch = false;
  bool _totalSortAscending = false;
  String _studentFilter = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _studentFilterCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final snapshot = await _ordinaryDao.loadSnapshot();
      final batches = await _achievementDao.getBatches();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _settings = snapshot.settings;
        _batches = batches;
        if (_selectedBatchId == null && batches.isNotEmpty) {
          _selectedBatchId = batches.first['id'] as int?;
        } else if (_selectedBatchId != null &&
            !batches.any((b) => b['id'] == _selectedBatchId)) {
          _selectedBatchId =
              batches.isNotEmpty ? batches.first['id'] as int? : null;
        }
        _loading = false;
      });
    } catch (e, st) {
      swallowDebug(e, tag: 'OrdinaryScoreTab.loadData', stack: st);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _saveSettings() async {
    final settings = _settings;
    if (settings == null || _savingSettings) return;
    setState(() => _savingSettings = true);
    try {
      await _ordinaryDao.saveSettings(settings);
      await _loadData();
      _showSnack('指标设置已保存');
    } catch (e, st) {
      swallowDebug(e, tag: 'OrdinaryScoreTab.saveSettings', stack: st);
      _showSnack('保存失败：$e');
    } finally {
      if (mounted) setState(() => _savingSettings = false);
    }
  }

  Future<void> _resetSettings() async {
    final courseId =
        _snapshot?.courseId ?? CourseContextService.defaultCourseId;
    setState(() => _settings = OrdinaryScoreSettings.defaults(courseId));
  }

  Future<void> _createBatch() async {
    if (_creatingBatch) return;
    final snapshot = _snapshot;
    setState(() => _creatingBatch = true);
    try {
      final now = DateTime.now();
      final name =
          '${snapshot?.courseName ?? '课程'}平时成绩 ${now.year}-${_two(now.month)}-${_two(now.day)}';
      final id = await _achievementDao.addBatch(
        batchName: name,
        courseName: snapshot?.courseName ?? '当前课程',
        teacherId: _authService.currentUser?.userId ?? '',
      );
      final batches = await _achievementDao.getBatches();
      if (!mounted) return;
      setState(() {
        _batches = batches;
        _selectedBatchId = id;
      });
      _showSnack('已创建达成度批次');
    } catch (e, st) {
      swallowDebug(e, tag: 'OrdinaryScoreTab.createBatch', stack: st);
      _showSnack('创建批次失败：$e');
    } finally {
      if (mounted) setState(() => _creatingBatch = false);
    }
  }

  Future<void> _syncToAchievement() async {
    final snapshot = _snapshot;
    if (snapshot == null || _syncing) return;
    if (snapshot.rows.isEmpty) {
      _showSnack('暂无学生平时成绩可同步');
      return;
    }
    if (_selectedBatchId == null) {
      await _createBatch();
      if (_selectedBatchId == null) return;
    }

    setState(() => _syncing = true);
    try {
      final rows =
          snapshot.rows.map((row) => row.toPingshiComponentRow()).toList();
      final count = await _achievementDao.importPlatformPingshiScores(
          _selectedBatchId!, rows);
      await _loadData();
      _showSnack('已同步$count名学生的平时成绩');
    } catch (e, st) {
      swallowDebug(e, tag: 'OrdinaryScoreTab.sync', stack: st);
      _showSnack('同步失败：$e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _snapshot == null) {
      return const Center(
        child: CircularProgressIndicator(color: NoirTokens.accent),
      );
    }
    if (_error != null && _snapshot == null) {
      return Center(
        child: _emptyState(Icons.error_outline, '平时成绩加载失败', _error!),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: NoirTokens.accent,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          _buildToolbar(),
          const SizedBox(height: 12),
          _buildSummaryGrid(),
          const SizedBox(height: 12),
          _buildSettingsPanel(),
          const SizedBox(height: 12),
          _buildScoreTable(),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    final snapshot = _snapshot;
    return _panel(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('平时成绩', style: NoirTokens.title(color: NoirTokens.paper)),
                const SizedBox(height: 4),
                Text(
                  snapshot?.courseName ?? '当前课程',
                  style: TextStyle(
                    color: NoirTokens.paper.withValues(alpha: 0.58),
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          SizedBox(
            width: 280,
            child: _batchDropdown(),
          ),
          OutlinedButton.icon(
            onPressed: _creatingBatch ? null : _createBatch,
            icon: _creatingBatch
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
            label: const Text('新建批次'),
          ),
          FilledButton.icon(
            onPressed: _syncing ? null : _syncToAchievement,
            icon: _syncing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file),
            label: const Text('同步达成度'),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _loadData,
            icon: const Icon(Icons.refresh),
            color: NoirTokens.paper,
          ),
        ],
      ),
    );
  }

  Widget _batchDropdown() {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: NoirTokens.paper.withValues(alpha: 0.16)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _selectedBatchId,
          isExpanded: true,
          dropdownColor: NoirTokens.inkDeep,
          iconEnabledColor: NoirTokens.paper,
          hint: Text(
            '选择达成度批次',
            style: TextStyle(color: NoirTokens.paper.withValues(alpha: 0.58)),
          ),
          style: const TextStyle(color: NoirTokens.paper, fontSize: 13),
          items: _batches.map((batch) {
            final id = batch['id'] as int?;
            return DropdownMenuItem<int>(
              value: id,
              child: Text(
                batch['batch_name']?.toString() ?? '批次#$id',
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: (value) => setState(() => _selectedBatchId = value),
        ),
      ),
    );
  }

  Widget _buildSummaryGrid() {
    final snapshot = _snapshot;
    final settings = _settings ?? snapshot?.settings;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final itemWidth = width >= 980
            ? (width - 36) / 4
            : width >= 640
                ? (width - 12) / 2
                : width;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _metricCard(
              width: itemWidth,
              icon: Icons.groups_outlined,
              label: '学生数',
              value: '${snapshot?.studentCount ?? 0}',
              caption: '活跃学生名单',
            ),
            _metricCard(
              width: itemWidth,
              icon: Icons.record_voice_over_outlined,
              label: '课堂表现',
              value:
                  '${_fmt(snapshot?.averageClassroomScore ?? 0)}/${_fmt(settings?.classroomWeight ?? 20)}',
              caption: '课堂积分、签到、回答',
            ),
            _metricCard(
              width: itemWidth,
              icon: Icons.quiz_outlined,
              label: '期间测验',
              value:
                  '${_fmt(snapshot?.averageQuizScore ?? 0)}/${_fmt(settings?.quizWeight ?? 30)}',
              caption: '教学测验平均表现',
            ),
            _metricCard(
              width: itemWidth,
              icon: Icons.self_improvement_outlined,
              label: '课外学习',
              value:
                  '${_fmt(snapshot?.averageExtraScore ?? 0)}/${_fmt(settings?.extraWeight ?? 50)}',
              caption: '课件、AI、扩展、推荐',
            ),
          ],
        );
      },
    );
  }

  Widget _metricCard({
    required double width,
    required IconData icon,
    required String label,
    required String value,
    required String caption,
  }) {
    return SizedBox(
      width: width,
      child: _panel(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: NoirTokens.accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: NoirTokens.accent, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                        color: NoirTokens.paper.withValues(alpha: 0.64),
                        fontSize: 12,
                      )),
                  const SizedBox(height: 3),
                  Text(value,
                      style: const TextStyle(
                        color: NoirTokens.paper,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      )),
                  const SizedBox(height: 2),
                  Text(caption,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: NoirTokens.paper.withValues(alpha: 0.45),
                        fontSize: 11,
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsPanel() {
    final settings = _settings;
    if (settings == null) return const SizedBox.shrink();

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, color: NoirTokens.accent, size: 20),
              const SizedBox(width: 8),
              Text('指标设置', style: NoirTokens.title(color: NoirTokens.paper)),
              const Spacer(),
              TextButton.icon(
                onPressed: _resetSettings,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('默认'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _savingSettings ? null : _saveSettings,
                icon: _savingSettings
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('保存'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 760;
              final children = [
                _weightSlider(
                  label: '课堂表现',
                  value: settings.classroomWeight,
                  onChanged: (v) =>
                      _updateSettings(settings.copyWith(classroomWeight: v)),
                ),
                _weightSlider(
                  label: '期间测验',
                  value: settings.quizWeight,
                  onChanged: (v) =>
                      _updateSettings(settings.copyWith(quizWeight: v)),
                ),
                _weightSlider(
                  label: '课外学习',
                  value: settings.extraWeight,
                  onChanged: (v) =>
                      _updateSettings(settings.copyWith(extraWeight: v)),
                ),
              ];
              if (narrow) {
                return Column(children: children);
              }
              return Row(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    Expanded(child: children[i]),
                    if (i != children.length - 1) const SizedBox(width: 12),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 4),
          Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
              expansionTileTheme: ExpansionTileThemeData(
                iconColor: NoirTokens.paper.withValues(alpha: 0.8),
                collapsedIconColor: NoirTokens.paper.withValues(alpha: 0.55),
              ),
            ),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                '细项权重',
                style: TextStyle(
                  color: NoirTokens.paper.withValues(alpha: 0.82),
                  fontWeight: FontWeight.w700,
                ),
              ),
              children: [
                _subWeightGroup('课堂表现', [
                  _subWeightSlider(
                      '课堂积分',
                      settings.classroomPointsRatio,
                      (v) => _updateSettings(
                            settings.copyWith(classroomPointsRatio: v),
                          )),
                  _subWeightSlider(
                      '签到',
                      settings.classroomCheckinRatio,
                      (v) => _updateSettings(
                            settings.copyWith(classroomCheckinRatio: v),
                          )),
                  _subWeightSlider(
                      '回答',
                      settings.classroomAnswerRatio,
                      (v) => _updateSettings(
                            settings.copyWith(classroomAnswerRatio: v),
                          )),
                ]),
                _subWeightGroup('期间测验', [
                  _subWeightSlider(
                      '测验均分',
                      settings.quizAverageRatio,
                      (v) => _updateSettings(
                            settings.copyWith(quizAverageRatio: v),
                          )),
                  _subWeightSlider(
                      '完成次数',
                      settings.quizCompletionRatio,
                      (v) => _updateSettings(
                            settings.copyWith(quizCompletionRatio: v),
                          )),
                ]),
                _subWeightGroup('课外学习', [
                  _subWeightSlider(
                      '课件学习',
                      settings.extraCoursewareRatio,
                      (v) => _updateSettings(
                            settings.copyWith(extraCoursewareRatio: v),
                          )),
                  _subWeightSlider(
                      'AI 自主学习',
                      settings.extraAiRatio,
                      (v) =>
                          _updateSettings(settings.copyWith(extraAiRatio: v))),
                  _subWeightSlider(
                      '扩展资源',
                      settings.extraExtendedRatio,
                      (v) => _updateSettings(
                            settings.copyWith(extraExtendedRatio: v),
                          )),
                  _subWeightSlider(
                      '推荐学习',
                      settings.extraRecommendRatio,
                      (v) => _updateSettings(
                            settings.copyWith(extraRecommendRatio: v),
                          )),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _weightSlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NoirTokens.paper.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NoirTokens.paper.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: NoirTokens.paper,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text('${_fmt(value)}分',
                  style: const TextStyle(
                    color: NoirTokens.accent,
                    fontWeight: FontWeight.w800,
                  )),
            ],
          ),
          Slider(
            value: value.clamp(0, 100).toDouble(),
            min: 0,
            max: 100,
            divisions: 100,
            activeColor: NoirTokens.accent,
            inactiveColor: NoirTokens.paper.withValues(alpha: 0.16),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _subWeightGroup(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Text(
              title,
              style: TextStyle(
                color: NoirTokens.paper.withValues(alpha: 0.66),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth >= 820
                  ? (constraints.maxWidth - 24) / 3
                  : constraints.maxWidth >= 520
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  for (final child in children)
                    SizedBox(width: itemWidth, child: child),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _subWeightSlider(
      String label, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 82,
          child: Text(
            label,
            style: TextStyle(
              color: NoirTokens.paper.withValues(alpha: 0.76),
              fontSize: 12,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0, 100).toDouble(),
            min: 0,
            max: 100,
            divisions: 100,
            activeColor: NoirTokens.accent,
            inactiveColor: NoirTokens.paper.withValues(alpha: 0.16),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            _fmt(value),
            textAlign: TextAlign.right,
            style: const TextStyle(color: NoirTokens.paper, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildScoreTable() {
    final snapshot = _snapshot;
    final settings = _settings ?? snapshot?.settings;
    if (snapshot == null || settings == null) {
      return const SizedBox.shrink();
    }
    if (snapshot.rows.isEmpty) {
      return _panel(
        child: _emptyState(
          Icons.school_outlined,
          '暂无学生数据',
          '请先在班级管理中添加学生',
        ),
      );
    }
    final rows = _visibleScoreRows(snapshot.rows);

    return _panel(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 220,
                child: Row(
                  children: [
                    const Icon(Icons.table_chart_outlined,
                        color: NoirTokens.accent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '学生平时成绩明细',
                        style: NoirTokens.title(color: NoirTokens.paper),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 260,
                height: 40,
                child: TextField(
                  controller: _studentFilterCtrl,
                  style: const TextStyle(color: NoirTokens.paper, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '按学号/姓名筛选',
                    hintStyle: TextStyle(
                      color: NoirTokens.paper.withValues(alpha: 0.42),
                    ),
                    prefixIcon: Icon(Icons.search,
                        size: 18,
                        color: NoirTokens.paper.withValues(alpha: 0.56)),
                    suffixIcon: _studentFilter.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除筛选',
                            icon: const Icon(Icons.close, size: 18),
                            color: NoirTokens.paper.withValues(alpha: 0.62),
                            onPressed: () {
                              _studentFilterCtrl.clear();
                              setState(() => _studentFilter = '');
                            },
                          ),
                    isDense: true,
                    filled: true,
                    fillColor: NoirTokens.paper.withValues(alpha: 0.04),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: NoirTokens.paper.withValues(alpha: 0.14)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: NoirTokens.paper.withValues(alpha: 0.14)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                      borderSide: BorderSide(color: NoirTokens.accent),
                    ),
                  ),
                  onChanged: (value) => setState(
                    () => _studentFilter = value.trim().toLowerCase(),
                  ),
                ),
              ),
              SizedBox(
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: () => setState(
                      () => _totalSortAscending = !_totalSortAscending),
                  icon: Icon(_totalSortAscending
                      ? Icons.arrow_upward
                      : Icons.arrow_downward),
                  label: Text(_totalSortAscending ? '总分升序' : '总分降序'),
                ),
              ),
              SizedBox(
                height: 40,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '班均 ${_fmt(snapshot.averageTotalScore)}/100 · 显示 ${rows.length}/${snapshot.rows.length} 人',
                    style: const TextStyle(
                      color: NoirTokens.accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            _emptyState(Icons.search_off, '没有匹配学生', '请调整学号或姓名筛选条件')
          else
            LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        dataTableTheme: DataTableThemeData(
                          headingTextStyle: TextStyle(
                            color: NoirTokens.paper.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                          dataTextStyle: const TextStyle(
                              color: NoirTokens.paper, fontSize: 12),
                          headingRowColor: WidgetStatePropertyAll(
                            NoirTokens.paper.withValues(alpha: 0.06),
                          ),
                          dataRowColor:
                              WidgetStateProperty.resolveWith((states) {
                            return states.contains(WidgetState.hovered)
                                ? NoirTokens.accent.withValues(alpha: 0.08)
                                : null;
                          }),
                          dividerThickness: 0.4,
                        ),
                      ),
                      child: DataTable(
                        sortColumnIndex: 11,
                        sortAscending: _totalSortAscending,
                        columnSpacing: 18,
                        horizontalMargin: 8,
                        columns: [
                          const DataColumn(label: Text('排名')),
                          const DataColumn(label: Text('学号')),
                          const DataColumn(label: Text('姓名')),
                          const DataColumn(label: Text('课堂表现')),
                          const DataColumn(label: Text('期间测验')),
                          const DataColumn(label: Text('课外学习')),
                          const DataColumn(label: Text('课堂积分')),
                          const DataColumn(label: Text('测验')),
                          const DataColumn(label: Text('课件')),
                          const DataColumn(label: Text('AI')),
                          const DataColumn(label: Text('扩展/推荐')),
                          DataColumn(
                            numeric: true,
                            label: const Text('总分'),
                            onSort: (_, ascending) =>
                                setState(() => _totalSortAscending = ascending),
                          ),
                        ],
                        rows: [
                          for (var i = 0; i < rows.length; i++)
                            _studentRow(i, rows[i], settings),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  List<OrdinaryStudentScore> _visibleScoreRows(
      List<OrdinaryStudentScore> source) {
    final filtered = source.where((row) {
      if (_studentFilter.isEmpty) return true;
      return row.studentId.toLowerCase().contains(_studentFilter) ||
          row.studentName.toLowerCase().contains(_studentFilter);
    }).toList();
    filtered.sort((a, b) {
      final byTotal = _totalSortAscending
          ? a.totalScore.compareTo(b.totalScore)
          : b.totalScore.compareTo(a.totalScore);
      if (byTotal != 0) return byTotal;
      return a.studentId.compareTo(b.studentId);
    });
    return filtered;
  }

  DataRow _studentRow(
    int index,
    OrdinaryStudentScore row,
    OrdinaryScoreSettings settings,
  ) {
    final m = row.metrics;
    return DataRow(
      cells: [
        DataCell(Text('${index + 1}')),
        DataCell(Text(row.studentId)),
        DataCell(Text(row.studentName)),
        DataCell(_scoreCell(
          row.classroomScore,
          settings.classroomWeight,
          row.classroomPercent,
        )),
        DataCell(
            _scoreCell(row.quizScore, settings.quizWeight, row.quizPercent)),
        DataCell(
            _scoreCell(row.extraScore, settings.extraWeight, row.extraPercent)),
        DataCell(Text(
          '${_fmt(m.earnedClassroomPoints)}分 · ${m.rollCallCorrectCount}/${m.rollCallCount}次',
        )),
        DataCell(Text(
          m.quizAttempts == 0
              ? '0次'
              : '${_fmt(m.quizAverage)}均 · ${m.quizAttempts}次',
        )),
        DataCell(Text(
          '${m.coursewareRecords}条 · ${_fmt(m.coursewareMinutes)}分钟',
        )),
        DataCell(Text('${m.aiRequests}次 · ${m.aiActiveDays}天')),
        DataCell(Text(
          '${m.extendedRecords}扩展 · ${m.recommendRecords + m.recommendFavorites}推荐',
        )),
        DataCell(Text(
          _fmt(row.totalScore),
          style: const TextStyle(
            color: NoirTokens.accent,
            fontWeight: FontWeight.w800,
          ),
        )),
      ],
    );
  }

  Widget _scoreCell(double score, double full, double percent) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${_fmt(score)}/${_fmt(full)}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(
          '${_fmt(percent)}%',
          style: TextStyle(
            color: NoirTokens.paper.withValues(alpha: 0.48),
            fontSize: 11,
          ),
        ),
      ],
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

  Widget _emptyState(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: NoirTokens.paper.withValues(alpha: 0.45), size: 42),
          const SizedBox(height: 10),
          Text(title,
              style: const TextStyle(
                color: NoirTokens.paper,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 4),
          Text(subtitle,
              style: TextStyle(
                color: NoirTokens.paper.withValues(alpha: 0.52),
                fontSize: 12,
              )),
        ],
      ),
    );
  }

  void _updateSettings(OrdinaryScoreSettings settings) {
    setState(() => _settings = settings);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  static String _fmt(num value) {
    final v = value.toDouble();
    if ((v - v.round()).abs() < 0.05) return v.round().toString();
    return v.toStringAsFixed(1);
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
